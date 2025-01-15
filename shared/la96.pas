{Audio compression library}
unit la96;

{$MODE delphi}

{

  LA96 will eventually support the following modes

  16LR Truely lossless                  1.2:1
  16JS Nearly lossless                  2.2:1
  8JS  Sounds ok for 'retro' music      6.0:1

  Mono can be stored as joint, with very little overhead.
  Optional LZ4 layer should be around 8:1 on 8JS

  Todo:
    - decompress to 8bit audio in memory (mixer needs to support this)
    - formally define the 'frame' codes
    - add support for full byte packing (only 5%, maybe skip this)
    - support lossless modes
    - add support for a LZ4 compress layer (should be 30%, so worth it)
}

interface

uses
  debug,
  test,
  utils,
  types,
  lz4,
  dos,
  go32,
  sysInfo,
  timer,
  stats,
  list,
  sound,
  csv,
  audioFilter,
  keyboard, {stub: remove}
  stream;

type

  {fast uLaw calculations via a lookup table}
  {settings bits to 0 gives identity transform}
  tULawLookup = class
    encodeTable: tIntList;
    decodeTable: tIntList;
    constructor create(bits: byte; log2Mu: byte);
    function encode(x: int32): int32; inline;
    function decode(x: int32): int32; inline;
  end;

  tAudioCompressionProfile = record
    tag: string;
    quantBits: byte; // number of bits to remove 0..16 (0=off)
    ulawBits: byte;  // number of ulaw bits, (0 = off).
    log2mu: byte;    // log2 of mu parameter (if ulaw is active)
    filter: byte;    // frequency of low pass filter (in khz) = (0 off).
  end;

  tAudioStreamProcessor = class
    x, prevX, y, prevY: int32;
    xPrime: int32; {what our decoder will produce}
    function lastError: int32;
    procedure encode(newX: int32); virtual;
    procedure reset(initialValue: int32=0); virtual;
  end;

  {encode the difference between samples}
  tASPDelta = class(tAudioStreamProcessor)
    procedure encode(newX: int32); override;
  end;

  tASPULaw = class(tAudioStreamProcessor)
    lut: tULawLookup;
    log2Mu: byte;
    uLawBits: byte;
    constructor create(uLawBits: byte=8;log2Mu: byte=8);
    destructor destroy(); override;
    procedure encode(newX: int32); override;
  end;

  {delta on uLaw}
  tASPULawDelta = class(tASPULaw)
    prevU: int32;
    procedure reset(initialValue: int32=0); override;
    procedure encode(newX: int32); override;
  end;

function decodeLA96(s: tStream): tSoundEffect;
function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile): tStream;

const
  ACP_VERYLOW: tAudioCompressionProfile  = (tag:'verylow'; quantBits:7;ulawBits:5;log2Mu:7;filter:16);
  ACP_LOW: tAudioCompressionProfile      = (tag:'low';     quantBits:6;ulawBits:6;log2Mu:7;filter:16);
  ACP_MEDIUM: tAudioCompressionProfile   = (tag:'medium';  quantBits:5;ulawBits:7;log2Mu:7;filter:0);
  ACP_HIGH: tAudioCompressionProfile     = (tag:'high';    quantBits:3;ulawBits:8;log2Mu:8;filter:0);
  ACP_Q10: tAudioCompressionProfile      = (tag:'q10';     quantBits:7;ulawBits:0;log2Mu:0;filter:0);
  ACP_Q12: tAudioCompressionProfile      = (tag:'q12';     quantBits:5;ulawBits:0;log2Mu:0;filter:0);
  ACP_Q16: tAudioCompressionProfile      = (tag:'q16';     quantBits:1;ulawBits:0;log2Mu:0;filter:0);
  ACP_LOSSLESS: tAudioCompressionProfile = (tag:'lossless';quantBits:0;ulawBits:0;log2Mu:0;filter:0);

var
  LA96_ENABLE_STATS: boolean = false;

implementation

const
  VER_SMALL = 1;
  VER_BIG = 0;
  FRAME_SIZE = 1024;

{-------------------------------------------------------}

type

  tLA96FrameHeader = record
    offset: dword;
    startMid, startDif: int16;
  end;

  tLA96FileHeader = packed record
    tag: array[1..4] of char;
    versionSmall, versionBig: word;
    format, compressionMode: byte;
    numFrames: dWord;
    numSamples: dWord;
    frameSize: word;
    log2mu: byte;
    postFilter: byte;
  end;

  {todo: make a LA96Writer aswell (for progressive save)}
  tLA96Reader = class
    fs: tStream;
    header: tLA96FileHeader;
    frames: array of tLA96FrameHeader;
    constructor create(filename: string);
    destructor destroy(); override;
    procedure close();
    function  readSfx(): tSoundEffect;
    procedure readFrame(frameId: integer;sfx: tSoundEffect;sfxOffset: dword);
  end;

{
How this will work.

SFX will store compressed in memory via LA96Reader.
Mixer will request SFX to decompress frame by frame via readFrame
}

constructor tLA96Reader.create(filename: string);
var
  f: file;
begin

  {first read header, and make sure everything is ok}
  system.assign(f, filename);
  system.reset(f, 1);
  system.blockread(f, header, sizeof(header));
  system.close(f);

  if header.tag <> 'LA96' then raise ValueError.create('Not a LA96 file.');
  if (header.versionSmall <> VER_SMALL) or (header.versionBig <> VER_BIG) then
    raise ValueError.create(format('Expecting v%d.%d, but found v%d.%d', [VER_SMALL, VER_BIG, header.versionSmall, header.versionBig]));
  if header.format <> 0 then raise ValueError.create(format('Format type %d not supported', [header.format]));
  if header.compressionMode <> 0 then raise ValueError.create('Compression not supported');
  if header.frameSize <> 1024 then raise ValueError.create('Framesize must be 1024');

  {load entire file into stream}
  {process header etc}
  {also load our ulaw tables here}
  {we just need 5-7,6-7,7-7,8-8}
end;

destructor tLA96Reader.destroy();
begin
  close();
  inherited destroy();
end;

procedure tLA96Reader.close();
begin
  if assigned(fs) then begin
    fs.free;
    fs := nil;
  end;
  frames := nil;
  fillchar(header, sizeof(header), 0);
end;

{read entire SFX out and return it uncompressed}
function tLA96Reader.readSFX(): tSoundEffect;
var
  i: integer;
begin
  {just loop through all frames}
  result := tSoundEffect.create(AF_16_STEREO, header.numSamples);
  for i := 0 to length(frames)-1 do
    readFrame(i, result, i*header.frameSize);
end;

{decodes a single frame into sfx at given sample position.
 can be used to stream music compressed in memory.}
procedure tLA96Reader.readFrame(frameId: integer;sfx: tSoundEffect;sfxOffset: dword);
begin
  {todo: this should be super fast, like maybe MMX fast}
  {get initial values}
  {read frame header}
  {read frame}
  {processs}
end;

{-------------------------------------------------------}

{input is -32k..32k, output is -1..1}
function uLaw(x: int32; mu: int32): single;
begin
  result := sign(x)*(ln(1.0+abs(mu*x/(32*1024)))/ln(1+mu));
end;

{input is -1..1, output is -32k..32k}
function uLawInv(y: single; mu: int32): int32;
begin
  result := round(sign(y)*32*1024/mu*(power(1+mu, abs(y))-1));
end;

{--------------}

constructor tULawLookup.create(bits: byte; log2Mu: byte);
var
  i: int32;
  codeSize: int32;
  mu: int32;
begin
  mu := 1 shl log2Mu;
  codeSize := (1 shl bits);
  decodeTable := tIntList.create(codeSize+1); {0..codesize (inclusive)}
  encodeTable := tIntList.create(32*1024+1);
  for i := 0 to 32*1024 do
    encodeTable[i] := round(uLaw(i, mu) * codeSize);
  for i := 0 to codeSize do
    decodeTable[i] := uLawInv(i / codeSize, mu);

end;

{ input is -2^bits..2^bits, output is -32k...32k }
function tULawLookup.decode(x: int32): int32; inline;
begin
  result := decodeTable[abs(x)];
  if x < 0 then result := -result;
end;

{input is -32k to 32k, output is -2^bits..2^bits}
function tULawLookup.encode(x: int32): int32; inline;
begin
  if abs(x) > 32*1024 then exit(encodeTable[32*1024]);
  result := encodeTable[abs(x)];
  if x < 0 then result := -result;
end;

{-------------------------------------------------------}

procedure tAudioStreamProcessor.reset(initialValue: int32=0);
begin
  x := initialValue;
  y := initialValue;
  prevX := 0;
  prevY := 0;
  xPrime := 0;
end;

{returns the value the decode will produce for x}
function tAudioStreamProcessor.lastError: int32;
begin
  result := x-xPrime;
end;

procedure tAudioStreamProcessor.encode(newX: int32);
begin
  prevX := x;
  prevY := y;
  x := newX;
  y := newX;
  xPrime := newX;
end;

{------}

procedure tASPDelta.encode(newX: int32);
begin
  prevX := x;
  prevY := y;
  y := newX - prevX;
  x := newX;
  xPrime := newX;
end;

{------}

constructor tASPULaw.create(uLawBits: byte=8;log2Mu: byte=8);
begin
  inherited create();
  assert(log2MU <= 16);
  assert(uLawBits <= 16);
  self.uLawBits := uLawBits;
  self.log2Mu := log2Mu;
  lut := tULawLookup.create(uLawBits, log2Mu);
end;

destructor tASPULaw.destroy();
begin
  lut.free;
  inherited destroy();
end;

procedure tASPULaw.encode(newX: int32);
begin
  prevX := x;
  prevY := y;
  y := lut.encode(newX);
  x := newX;
  xPrime := lut.decode(y);
end;

{------}

procedure tASPULawDelta.encode(newX: int32);
var
  thisU: int32;
  ax: int32;
begin
  prevX := x;
  prevY := y;
  //thisU := lut.encode(newX);
  //self inline... :(
  ax := abs(newX);
  if ax > 32*1024 then ax := 32*1024;
  thisU := lut.encodeTable.data[ax];
  if newX < 0 then thisU := -thisU;

  y := thisU - prevU;
  x := newX;
  prevU := thisU;
  xPrime := lut.decodeTable.data[abs(thisU)];
  if thisU < 0 then xPrime := -xPrime;
end;

procedure tASPULawDelta.reset(initialValue: int32=0);
begin
  inherited reset(initialValue);
  prevU := 0;
end;

{-------------------------------------------------------}

function decodeLA96(s: tStream): tSoundEffect;
begin
  result := tSoundEffect.create();
  {todo: implement decode}
end;

function quant(x: int32;shiftAmount: byte): int32; inline; pascal;
asm
  push cx
  mov cl, [shiftAmount]
  mov eax, [x]
  sar eax, cl
  pop cx
  end;

function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile): tStream;
var
  i,j,k: int32;

  samplePtr: pAudioSample;

  thisMidValue, thisDifValue: int32;

  {note: we write FRAME_SIZE-1 deltas, which is FRAME_SIZE samples when including
   the initial value}
  midCodes: array[0..(FRAME_SIZE-1)-1] of dword;
  difCodes: array[0..(FRAME_SIZE-1)-1] of dword;
  midSignBits: array[0..(FRAME_SIZE-1)-1] of dword;
  difSignBits: array[0..(FRAME_SIZE-1)-1] of dword;

  fs: tStream;  // our file stream
  midSigns, difSigns: tStream;

  counter: int32;
  numFrames: int32;
  framePtr: tDwords;
  frameSizes: tDwords;
  maxSamplePtr: pointer;
  aspMid, aspDif: tAudioStreamProcessor;
  midSignCounter, difSignCounter: integer;
  currentMidSign, currentDifSign: integer;

  cMid, cDif: int32; {centers}
  tmp: int32;
  header: tLA96FileHeader;

  fullStats, frameStats: tCSVWriter;

  midFrameSize, difFrameSize: int32;

  midXStats, difXStats,
  midYStats, difYStats: tStats;

begin

  assert(profile.quantBits >= 0);
  assert(profile.quantBits <= 16);

  if sfx.length = 0 then exit(nil);

  if LA96_ENABLE_STATS then begin
    fullStats := tCSVWriter.create(removeExtension(sfx.tag)+'_full.csv');
    fullStats.writeHeader('frame,sample,mid_true,mid,mid_code,mid_ema,dif_true,dif,dif_code,dif_ema');
    frameStats := tCSVWriter.create(removeExtension(sfx.tag)+'_frame.csv');
    frameStats.writeHeader(
      'frame,'+
      'midFrameSize,difFrameSize,'+
      'midTrueMin,midTrueMax,midTrueMean,midTrueVar,'+
      'midMin,midMax,midMean,midVar,'+
      'difTrueMin,difTrueMax,difTrueMean,difTrueVar,'+
      'difMin,difMax,difMean,difVar'
      );
  end else begin
    fullStats := nil;
    frameStats := nil;
  end;

  // Setup out output stream
  {guess that we'll need 2 bytes per sample, i.e 4:1 compression vs 16bit stereo}
  fs := tStream.create(2*sfx.length);
  result := fs;

  startTimer('LA96');

  counter := 0;
  samplePtr := sfx.data;
  maxSamplePtr := pointer(dword(samplePtr) + (sfx.length * 4));
  numFrames := (sfx.length + (FRAME_SIZE-1)) div FRAME_SIZE;

  midSigns := tStream.create();
  difSigns := tStream.create();

  framePtr := nil;

  if profile.ulawBits > 0 then begin
    aspMid := tASPULawDelta.create(profile.ulawBits, profile.log2mu);
    aspDif := tASPULawDelta.create(profile.ulawBits, profile.log2mu);
  end else begin
    aspMid := tASPDelta.create();
    aspDif := tASPDelta.create();
  end;

  // -------------------------
  // Write Header

  header.tag := 'LA96';
  header.versionSmall := VER_SMALL;
  header.versionBig := VER_BIG;
  header.format := 0;
  header.compressionMode := 0;
  header.numFrames := numFrames;
  header.numSamples := sfx.length;
  header.frameSize := 1024;
  header.log2mu := profile.log2mu;
  header.postFilter := profile.filter;

  fs.writeBlock(header, sizeof(header));

  {write reserved header space}
  if fs.pos > 128 then raise Exception.create('Header length exceeds 128 bytes');
  while fs.pos < 128 do
    fs.writeByte(0);

  // -------------------------
  // Write Frames

  midXStats.init();
  difXStats.init();
  midYStats.init();
  difYStats.init();

  for i := 0 to numFrames-1 do begin

    //stub:
    if keyDown(key_esc) then break;

    aspMid.reset(quant(samplePtr^.left+samplePtr^.right, profile.quantBits));
    aspDif.reset(quant(samplePtr^.left-samplePtr^.right, profile.quantBits));
    if samplePtr < maxSamplePtr then inc(samplePtr);

    midSignCounter := 0;
    difSignCounter := 0;

    midSigns.softReset();
    difSigns.softReset();

    fillchar(midSignBits, sizeof(midSignBits), 0);
    fillchar(difSignBits, sizeof(difSignBits), 0);
    currentMidSign := 1;
    currentDifSign := 1;

    midXStats.init(false);
    difXStats.init(false);
    midYStats.init(false);
    difYStats.init(false);

    cMid := (aspMid.xPrime div 256) * 256;
    cDif := (aspDif.xPrime div 256) * 256;

    {write frame header (one for each channel)}
    framePtr.append(fs.pos);
    fs.writeByte(profile.quantBits + profile.ulawBits*16);
    fs.writeByte(profile.quantBits + profile.ulawBits*16);
    fs.writeByte(min(negEncode(aspMid.y), 255));
    fs.writeByte(min(negEncode(aspDif.y), 255));

    startTimer('LA96_process');
    for j := 0 to (FRAME_SIZE-1)-1 do begin

      aspMid.encode(quant(samplePtr^.left+samplePtr^.right-cMid, profile.quantBits));
      aspDif.encode(quant(samplePtr^.left-samplePtr^.right-cDif, profile.quantBits));
      if samplePtr < maxSamplePtr then inc(samplePtr);

      {xPrime is decoders quant(decoded-cMid)}
      cMid := ((aspMid.xPrime shl profile.quantBits) + cMid) div 256 * 256;
      cDif := ((aspMid.xPrime shl profile.quantBits) + cDif) div 256 * 256;

      {stats}
      midXStats.addValue(aspMid.x);
      difXStats.addValue(aspDif.x);
      midYStats.addValue(aspMid.y);
      difYStats.addValue(aspDif.y);

      midCodes[j] := abs(aspMid.y);
      difCodes[j] := abs(aspDif.y);

      if (sign(aspMid.y) * currentMidSign) < 0 then begin
        midSigns.writeVLC(midSignCounter);
        midSignCounter := 0;
        currentMidSign *= -1;
      end else
        inc(midSignCounter);

      if (sign(aspDif.y) * currentDifSign) < 0 then begin
        difSigns.writeVLC(difSignCounter);
        difSignCounter := 0;
        currentDifSign *= -1;
      end else
        inc(difSignCounter);

      if aspMid.y < 0 then midSignBits[j] := 1;
      if aspDif.y < 0 then difSignBits[j] := 1;

      if assigned(fullStats) then
        fullStats.writeRow([
          i, i*FRAME_SIZE+j,
          aspMid.x,
          aspMid.x+aspMid.lastError,
          aspMid.y,
          midXStats.ema,
          aspDif.x,
          aspDif.x+aspMid.lastError,
          aspDif.y,
          difXStats.ema
        ]);

    end;
    stopTimer('LA96_process');

    {write out frame}
    startTimer('LA96_segments');
    midFrameSize := fs.writeVLCSegment(midCodes, PACK_BEST);
    difFrameSize := fs.writeVLCSegment(difCodes, PACK_BEST);
    stopTimer('LA96_segments');

    {write signs}
    {if it's more efficent to just write out the bits then do that
     instead}
    if midSigns.len > (FRAME_SIZE div 8) then
      fs.writeVLCSegment(midSignBits)
    else
      fs.writeBytes(midSigns.asBytes);
    if midSigns.len > (FRAME_SIZE div 8) then
      fs.writeVLCSegment(difSignBits)
    else
      fs.writeBytes(difSigns.asBytes);

    if assigned(frameStats) then
      frameStats.writeRow([
        i,
        midFrameSize,
        difFrameSize,
        midXStats.minValue,
        midXStats.maxValue,
        midXStats.mean,
        midXStats.variance,
        midYStats.minValue,
        midYStats.maxValue,
        midYStats.mean,
        midYStats.variance,
        difXStats.minValue,
        difXStats.maxValue,
        difXStats.mean,
        difXStats.variance,
        difYStats.minValue,
        difYStats.maxValue,
        difYStats.mean,
        difYStats.variance
      ]);


    write('.');

  end;

  // -------------------------
  // Write Footer
  fs.writeVLCSegment(framePtr, PACK_BEST);

  {clean up}
  midSigns.free;
  difSigns.free;

  aspMid.free;
  aspDif.free;

  if assigned(fullStats) then fullStats.free;
  if assigned(frameStats) then frameStats.free;

  stopTimer('LA96');

  note(format('Encoded size %fKB Original %fKB',[fs.len/1024, 4*sfx.length/1024]));
end;

{--------------------------------------------------------}

type
  tLA96Test = class(tTestSuite)
    procedure run; override;
  end;

procedure tLA96Test.run();
var
  lut: tULawLookup;
  i: int32;
const
  mu = 256;
  bits = 6;
  codeSize = 1 shl bits;
begin
  {test lookups}
  lut := tULawLookup.create(bits, round(log2(mu)));
  for i := -codeSize to codeSize do
    assertEqual(lut.decode(i), uLawInv(i/codeSize, mu));
  for i := -1024 to 1024 do begin
    {check all values -1k..-1k, and also samples from whole range}
    assertEqual(lut.encode(32*i), round(uLaw(32*i, mu) * codeSize));
    assertEqual(lut.encode(i), round(uLaw(i, mu) * codeSize));
  end;
end;

{--------------------------------------------------------}

initialization
  tLA96Test.create('LA96');
finalization

end.


