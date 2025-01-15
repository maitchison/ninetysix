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
  list,
  sound,
  audioFilter,
  stream;

type

  {fast uLaw calculations via a lookup table}
  tULawLookup = class
    encodeTable: tIntList;
    decodeTable: tIntList;
    constructor create(bits: byte; log2Mu: byte);
    function encode(x: int32): int32; inline;
    function decode(x: int32): int32; inline;
  end;

  tAudioCompressionProfile = record
    quantBits: byte; // number of bits to remove 0..16 (0=off)
    ulawBits: byte;  // number of ulaw bits, (0 = off).
    log2mu: byte;    // log2 of mu parameter (if ulaw is active)
    filter: byte;    // frequency of low pass filter (in khz) = (0 off).
  end;

  tAudioStreamProcessor = class
    x, prevX, y, prevY: int32;
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
    destructor destroy();
    procedure encode(newX: int32); override;
  end;

  {uLaw on deltas}
  tASPDeltaULaw = class(tASPULaw)
    currentError: int32;  // to track drift
    procedure encode(newX: int32); override;
  end;

  {delta on uLaw}
  tASPULawDelta = class(tASPULaw)
    prevU: int32;
    procedure encode(newX: int32); override;
  end;

function decodeLA96(s: tStream): tSoundEffect;
function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile;useLZ4: boolean=false): tStream;

const
  ACP_VERYLOW: tAudioCompressionProfile  = (quantBits:10;ulawBits:5;log2Mu:7;filter:16);
  ACP_LOW: tAudioCompressionProfile      = (quantBits:11;ulawBits:6;log2Mu:7;filter:16);
  ACP_MEDIUM: tAudioCompressionProfile   = (quantBits:12;ulawBits:7;log2Mu:7;filter:0);
  ACP_HIGH: tAudioCompressionProfile     = (quantBits:14;ulawBits:8;log2Mu:8;filter:0);
  ACP_Q10: tAudioCompressionProfile      = (quantBits:10;ulawBits:0;log2Mu:0;filter:0);
  ACP_Q12: tAudioCompressionProfile      = (quantBits:12;ulawBits:0;log2Mu:0;filter:0);
  ACP_Q16: tAudioCompressionProfile      = (quantBits:16;ulawBits:0;log2Mu:0;filter:0);
  ACP_LOSSLESS: tAudioCompressionProfile = (quantBits:17;ulawBits:0;log2Mu:0;filter:0);

implementation

const
  VER_SMALL = 1;
  VER_BIG = 0;

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
end;

procedure tAudioStreamProcessor.encode(newX: int32);
begin
  prevX := x;
  prevY := y;
  x := newX;
  y := newX;
end;

{------}

procedure tASPDelta.encode(newX: int32);
begin
  prevX := x;
  prevY := y;
  y := newX - prevX;
  x := newX;
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
end;

{------}

procedure tASPDeltaULaw.encode(newX: int32);
var
  delta: int32;
  yInv: int32;
  mu: int32;
begin

  mu := (1 shl log2Mu);

  prevX := x;
  prevY := y;

  x := newX;

  delta := clamp16(x - prevX);
  y := round(ulaw(delta, mu) * (1 shl uLawBits));
  yInv := uLawInv(y / (1 shl uLawBits), mu);
  currentError := (prevX+yInv) - x;
  if currentError > abs(y) then dec(y);
  if currentError < -abs(y) then inc(y);

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
end;

{-------------------------------------------------------}

function decodeLA96(s: tStream): tSoundEffect;
begin
  result := tSoundEffect.create();
  {todo: implement decode}
end;

function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile;useLZ4: boolean=false): tStream;
var
  i,j,k: int32;

  samplePtr: pAudioSample;

  thisMidValue, thisDifValue: int32;

  {note: we write 1023 deltas, which is 1024 samples when including
   the initial value}
  midCodes: array[0..1023-1] of dword;
  difCodes: array[0..1023-1] of dword;
  midSignBits: array[0..1023-1] of dword;
  difSignBits: array[0..1023-1] of dword;

  fs: tStream;  // our file stream
  ds: tStream;  // our data stream.
  midSigns, difSigns: tStream;

  counter: int32;
  numFrames: int32;
  startPos: int32;
  shiftAmount: byte;
  framePtr, frameMid, frameDif: tDwords;
  maxSamplePtr: pointer;
  aspMid, aspDif: tAudioStreamProcessor;
  midSignCounter, difSignCounter: integer;
  currentMidSign, currentDifSign: integer;


  function quant(x: int32;shiftAmount: byte): int32; inline; pascal;
  asm
    push cx
    mov cl, [shiftAmount]
    mov eax, [x]
    sar eax, cl
    pop cx
    end;

  procedure incPtr(); inline;
  begin
    {once we reach end just write out the last value repeatedly}
    if samplePtr < maxSamplePtr then
      inc(samplePtr);
  end;

  procedure writeFrameData(data: array of dword);
  var
    bytes: tBytes;
    tokens: tDwords;
    i,j: integer;
  begin
    {bpe preprocessing method...}
    setLength(bytes, length(data));
    for j := 0 to length(data)-1 do
      bytes[j] := data[j];

    bytes := lz4.doBPE(bytes, 10);

    {annoying}
    tokens := nil;
    for j := 0 to length(bytes)-1 do
      tokens.append(bytes[j]);

    {simplest method, just write VLC codes}
    ds.writeVLCSegment(tokens, PACK_BEST);
  end;

begin

  assert(profile.quantBits >= 0);
  assert(profile.quantBits <= 16);

  if sfx.length = 0 then exit(nil);

  // Setup out output stream
  {guess that we'll need 2 bytes per sample, i.e 4:1 compression vs 16bit stereo}
  fs := tStream.create(2*sfx.length);
  result := fs;

  startTimer('LA96');

  // Initialize variables
  if useLZ4 then
    {must defer writes as LZ4 doesn't work with streaming yet}
    ds := tStream.create()
  else
    {no compression means we can write directly to the file stream}
    ds := fs;
  counter := 0;
  samplePtr := sfx.data;
  maxSamplePtr := pointer(dword(samplePtr) + (sfx.length * 4));
  numFrames := (sfx.length + 1023) div 1024;

  midSigns := tStream.create();
  difSigns := tStream.create();

  framePtr := nil;
  frameMid := nil;
  frameDif := nil;

  aspMid := tASPULawDelta.create(profile.ulawBits, profile.log2mu);
  aspDif := tASPULawDelta.create(profile.ulawBits, profile.log2mu);

  // -------------------------
  // Write Header

  {write header}
  startPos := fs.pos;
  fs.writeChars('LA96');
  fs.writebyte(VER_SMALL);
  fs.writebyte(VER_BIG);
  fs.writeByte($00);    {joint 16bit-stereo}
  fs.writeByte(byte(useLZ4)); {LZ4 compression}
  fs.writeDWord(numFrames);
  fs.writeDWord(sfx.length); // samples might be different if length is not multiple of 1024

  {write reserved header space}
  while fs.pos < startPos+128 do
    fs.writeByte(0);

  // -------------------------
  // Write Frames

  for i := 0 to numFrames-1 do begin

    {unfortunately we can not encode any final partial block}
    aspMid.reset(quant(samplePtr^.left+samplePtr^.right, shiftAmount));
    aspDif.reset(quant(samplePtr^.left-samplePtr^.right, shiftAmount));
    incPtr();

    framePtr.append(fs.pos);
    frameMid.append(negEncode(aspMid.y));
    frameDif.append(negEncode(aspDif.y));

    midSignCounter := 0;
    difSignCounter := 0;

    midSigns.softReset();
    difSigns.softReset();

    fillchar(midSignBits, sizeof(midSignBits), 0);
    fillchar(difSignBits, sizeof(difSignBits), 0);
    currentMidSign := 1;
    currentDifSign := 1;


    startTimer('LA96_process');
    for j := 0 to 1023-1 do begin

      aspMid.encode(quant(samplePtr^.left+samplePtr^.right, shiftAmount));
      aspDif.encode(quant(samplePtr^.left-samplePtr^.right, shiftAmount));

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

      incPtr();
    end;
    stopTimer('LA96_process');

    {stub:}
    {
    if i mod 4 = 0 then begin
      for k := 0 to 20 do
        write(midCodes[k], ' ');
      writeln('!!');
    end;
    }

    {write frame header}
    {todo:}



    {write out frame}
    startTimer('LA96_segments');
    writeFrameData(midCodes);
    writeFrameData(difCodes);
    stopTimer('LA96_segments');

    {write signs}
    {if it's more efficent to just write out the bits then do that
     instead}
    if midSigns.len > (1024 div 8) then
      ds.writeVLCSegment(midSignBits)
    else
      ds.writeBytes(midSigns.asBytes);
    if midSigns.len > (1024 div 8) then
      ds.writeVLCSegment(difSignBits)
    else
      ds.writeBytes(difSigns.asBytes);

    write('.');

    {when using compression every 128k or so write out the compressed data}
    if useLZ4 and (ds.len > 128*1024) then begin
      writeln('Compressing ',ds.len,' bytes');
      startTimer('LA96_compress');
      fs.writeBytes(LZ4Compress(ds.asBytes));
      ds.reset();
      stopTimer('LA96_compress');
      printTimers();
    end;
  end;

  if useLZ4 then begin
    startTimer('LA96_compress');
    fs.writeBytes(LZ4Compress(ds.asBytes));
    ds.free;
    stopTimer('LA96_compress');
  end;

  // -------------------------
  // Write Footer
  fs.writeVLCSegment(frameMid, PACK_BEST);
  fs.writeVLCSegment(frameDif, PACK_BEST);
  fs.writeVLCSegment(framePtr, PACK_BEST);

  midSigns.free;
  difSigns.free;

  aspMid.free;
  aspDif.free;

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


