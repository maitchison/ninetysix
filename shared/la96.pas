{Audio compression library}
unit la96;

{$MODE delphi}

{

  LA96 supports the following formats

  note: quality is subjective quality
  -------------------------------------------------
   5 = I can not tell the difference
   4 = I can only tell the difference if I listen carefully
   3 = I can tell the difference but it's not distracting
   2 = Difference is annoying.
   1 = Difference is very annoying.

  Profile   Quality   Ratio
  LOSSLESS  5         1.2x
  VERY_LOW  2         5x
  MEDIUM    4         4x
  HIGH      5         3x
  Q10       5         2.7x  (10bit audio)


  Decompression speed is very fast. Currently at 20x realtime on P166 MMX
  An ASM/MMX decoder should get this to 30x.

  There are also some compression improvements to be made. I think we'll probably
  get VERY_LOW=7x, MEDIUM=5x and HIGH=4x. For the moment you can just zip them
  for some extra compression.

  Pending features
  -------------------------------------------------
  Sign bit compression (should be +5% or so)
  ASM Decoder (should be 25x realtime)
  MMX Decoder (should be 35x realtime)
  lowpass post filter - to help with VERY_LOW quality setting.
  variable bit-rate (hoping for medium level with 5x compression)

  -------------------------------------------------
  How it all works (x? means x is optional via config settings)

  (LEFT,RIGHT) -> [clip protection] -> MID,DIF -> CENTERING? -> QUANTIZE?
    -> ULAW? -> DELTA -> SIGN_EXTRACT


  and unwind

  process_REF
  SIGN_ADD -> INVDELTA ->
  generate_sample
  INVULAW -> INVQUANT -> INVCENTER -> INV MID,DIF -> (LEFT,RIGHT)

}

interface

uses
  debug,
  test,
  utils,
  sysTypes,
  filesystem,
  lz4,
  dos,
  go32,
  sysInfo,
  timer,
  stats,
  list,
  sound,
  csv,
  vlc,
  audioFilter,
  stream;

const
  ENABLE_POST_PROCESS = false; {doesn't really help right now, need a better noise gate}

type

  {fast uLaw calculations via a lookup table}
  {settings bits to 0 gives identity transform}
  tULawLookup = record
    table: tIntList;
    procedure initEncode(bits: byte; log2Mu: byte);
    procedure initDecode(bits: byte; log2Mu: byte);
    function lookup(x: int32): int32; inline;
  end;
  pULawLookup = ^tULawLookup;

  tAudioCompressionProfile = record
    tag: string;
    quantBits: byte; // number of bits to remove 0..15 (0=off)
    ulawBits: byte;  // number of ulaw bits, 0..15 (0 = off).
    log2mu: byte;    // log2 of mu parameter (if ulaw is active)
    filter: byte;    // frequency of low pass filter (in khz) = (0 off).
  end;

  tLA96FileHeader = packed record
    tag: array[1..4] of char;
    versionSmall, versionBig: word;
    format, compressionMode: byte;
    numFrames: dWord;
    numSamples: dWord;
    frameSize: word;
    log2mu: byte;
    postFilter: byte; {requested post processing highpass filter in KHZ}
    centering: byte;  {0=off, 8=on with 256 resolution}
    function verStr: string;
  end;

  tFrameFrameGenProc = procedure(frameOn: int32; samplePtr: pAudioSample16S; frameLength: int32);

  {todo: make a LA96Writer aswell (for progressive save)}
  tLA96Reader = class
  private
    fs: tStream;
    ownsStream: boolean;
    header: tLA96FileHeader;
  protected
    ulawTable: array[1..8] of tULawLookup;
    midCodes, difCodes: tDwords;
    midSigns, difSigns: tDwords;
    framePtr: tInt32s; {will be filled with -1 if no frame pointers}
    frameOn: int32;
    cLeft, cRight: single; {used for EMA}
  protected
    function  getULAW(bits: byte): pULawLookup;
    procedure loadHeader();
  public
    looping: boolean;
    frameGenHook: tFrameFrameGenProc;
  public
    constructor create();
    function  isLoaded: boolean;
    function  frameSize: integer;
    procedure seek(frameNumber: integer);
    procedure load(filename: string); overload;
    procedure load(aStream: tStream); overload;
    destructor destroy(); override;
    procedure close();
    function  readSFX(): tSoundEffect;
    procedure nextFrame(sfx: tSoundEffect;sfxOffset: dword);
  end;

function decodeLA96(s: tStream): tSoundEffect;
function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile;verbose: boolean=false): tStream;

const
  {note: low sounds very noisy, but I think we can fix this with some post filtering}
  ACP_LOW: tAudioCompressionProfile      = (tag:'low';     quantBits:6;ulawBits:7;log2Mu:6;filter:0);
  ACP_MEDIUM: tAudioCompressionProfile   = (tag:'medium';  quantBits:6;ulawBits:8;log2Mu:7;filter:0);
  ACP_HIGH: tAudioCompressionProfile     = (tag:'high';    quantBits:4;ulawBits:8;log2Mu:8;filter:0);
  ACP_VERYHIGH: tAudioCompressionProfile = (tag:'veryhigh';quantBits:2;ulawBits:8;log2Mu:8;filter:0);
  ACP_Q10: tAudioCompressionProfile      = (tag:'q10';     quantBits:6;ulawBits:0;log2Mu:0;filter:0);
  ACP_Q12: tAudioCompressionProfile      = (tag:'q12';     quantBits:4;ulawBits:0;log2Mu:0;filter:0);
  ACP_Q16: tAudioCompressionProfile      = (tag:'q16';     quantBits:0;ulawBits:0;log2Mu:0;filter:0);

var
  LA96_ENABLE_STATS: boolean = false;

implementation

const
  VER_SMALL = 2;
  VER_BIG = 0;
  FRAME_SIZE = 1024;

  {
  changes
  ---------------
  v0.1: initial file format
  v0.2: framePtr moved from footer to header
  }

type
  tFrameSpec = record
    length: word; {number of samples in frame}
    idx: int32; {might be -1}
    midShift, difShift:byte;
    midUTable, difUTable: ^tULawLookup;
    centerShift: byte;
    cMid, cDif: int32;
  end;

  pFrameSpec = ^tFrameSpec;

{$I la96_ref.inc}
{$I la96_asm.inc}

type
  {todo: make one record with options...}
  tAudioStreamProcessor = class
    x, prevX, y, prevY: int32;
    xPrime: int32; {what our decoder will produce}
    savedX, savedY: int32;
    function lastError: int32;
    procedure encode(newX: int32); virtual;
    procedure reset(initialValue: int32=0); virtual;
    procedure save(); virtual;
    procedure restore(); virtual;
  end;

  {encode the difference between samples}
  tASPDelta = class(tAudioStreamProcessor)
    procedure encode(newX: int32); override;
  end;

  tASPULaw = class(tAudioStreamProcessor)
    ulawEncode, ulawDecode: tULawLookup;
    log2Mu: byte;
    uLawBits: byte;
    constructor create(uLawBits: byte=8;log2Mu: byte=8);
    destructor destroy(); override;
    procedure encode(newX: int32); override;
  end;

  {delta on uLaw}
  tASPULawDelta = class(tASPULaw)
    prevU: int32;
    savedU: int32;
    procedure save(); override;
    procedure restore(); override;
    procedure reset(initialValue: int32=0); override;
    procedure encode(newX: int32); override;
  end;


{-------------------------------------------------------}
{ helpers }
{-------------------------------------------------------}

function tLA96FileHeader.verStr(): string;
begin
  result := utils.format('%d.%d', [versionBig, versionSmall]);
end;

{convert from +=0, -=1 to +=$00.., -=$FF..}
procedure convertSigns(signs: tDwords);
var
  signsPtr: pointer;
  len: dword;
begin
  signsPtr := @signs[0];
  len := length(signs);
  asm
    push ecx
    push edi
    mov  ecx, len
    mov  edi, signsPtr
  @SIGN_LOOP:
    neg  [edi]
    add  edi, 4
    dec  ecx
    jnz @SIGN_LOOP
    pop  edi
    pop  ecx
  end;
end;

{-------------------------------------------------------}

constructor tLA96Reader.create();
var
  bits: int32;
begin
  {init vars}
  fillchar(header, sizeof(header), 0);
  fs := nil;
  looping := false;
end;

procedure tLA96Reader.load(filename: string); overload;
begin
  if not filesystem.fs.exists(filename) then error(format('Could not open audio file "%s"', [filename]));
  fs := tStream.create();
  fs.readFromFile(filename);
  ownsStream := true;
  self.loadHeader();
end;

{loads from a stream. Stream is still owned by caller and so must
 be freed by them}
procedure tLA96Reader.load(aStream: tStream); overload;
begin
  fs := aStream;
  ownsStream := false;
  self.loadHeader();
end;

{seek to given frame within the file
 requires framePtrs (v0.2+) to seek except for seek(0) which
 is always supported.
}
procedure tLA96Reader.seek(frameNumber: integer);
begin
  if not isLoaded then error('Can not seek on file, as it is not loaded');
  if looping then frameNumber := frameNumber mod header.numFrames;
  if (frameNumber < 0) or (frameNumber >= header.numFrames) then
    error(format('Tried to seek to frame %d/%d', [frameNumber+1, header.numFrames]));
  if framePtr[frameNumber] < 0 then
    error(format('Can not seek to position %d, as file has no framePtrs.', [frameNumber]));
  fs.seek(framePtr[frameNumber]);
  frameOn := frameNumber;
end;

procedure tLA96Reader.loadHeader();
var
  startPos: int32;
  bits: integer;
  i: integer;
begin
  {first read header, and make sure everything is ok}
  startPos := fs.pos;
  fs.readBlock(header, sizeof(header));

  if header.tag <> 'LA96' then raise ValueError.create(format('Not an LA96 file. Found "%s", expecting LA96', [header.tag]));
  if (header.versionSmall > VER_SMALL) or (header.versionBig <> VER_BIG) then
    raise ValueError.create(format('Expecting v%d.%d, but found v%d.%d', [VER_SMALL, VER_BIG, header.versionSmall, header.versionBig]));
  if header.format <> 0 then raise ValueError.create(format('Format type %d not supported', [header.format]));
  if header.compressionMode <> 0 then raise ValueError.create('Compression not supported');
  if header.frameSize <> 1024 then raise ValueError.create('Framesize must be 1024');

  fs.seek(startPos+128);

  {read frame headers}
  setLength(framePtr, header.numFrames);
  if header.versionSmall >= 2 then begin
    fs.readBlock(framePtr[0], header.numFrames*4)
  end else begin
    fillchar(framePtr[0], header.numFrames*4, $ff);
    {atleast we know the position of the first frame}
    framePtr[0] := fs.pos;
  end;

  {setup our buffers}
  setLength(midCodes, header.frameSize-1);
  setLength(difCodes, header.frameSize-1);
  setLength(midSigns, header.frameSize-1);
  setLength(difSigns, header.frameSize-1);

  {create ulaw tables}
  for bits := low(ulawTable) to high(ulawTable) do
    ulawTable[bits].initDecode(bits, header.log2mu);

  seek(0);

end;

destructor tLA96Reader.destroy();
begin
  close();
  inherited destroy();
end;

procedure tLA96Reader.close();
begin
  if assigned(fs) and ownsStream then begin
    fs.free;
    fs := nil;
  end;
  fillchar(header, sizeof(header), 0);
end;

function tLA96Reader.isLoaded: boolean;
begin
  result := header.numFrames > 0;
end;

function tLA96Reader.frameSize: integer;
begin
  result := header.frameSize;
end;

{read entire SFX out and return it uncompressed}
function tLA96Reader.readSFX(): tSoundEffect;
var
  i: integer;
begin
  result := tSoundEffect.create(AF_16_STEREO, header.numSamples);
  for i := 0 to header.numFrames-1 do begin
    nextFrame(result, i*header.frameSize);
  end;
end;

function tLA96Reader.getULAW(bits: byte): pULawLookup;
begin
  result := nil;
  if bits = 0 then exit;
  if bits in [1..8] then
    result := @ulawTable[bits]
  else
    error(format('Invalid ulaw bits %d, expecting (1..8)', [bits]));
end;

{decodes the next frame into sfx at given sample position.
 can be used to stream music compressed in memory.}
{todo: this should be just writing to a pointer}
{todo: remove timers and other stuff unless verbose is on}
procedure tLA96Reader.nextFrame(sfx: tSoundEffect;sfxOffset: dword);
var
  frameType: byte;
  midShift, difShift, midULaw, difULaw: byte;

  midCode, difCode: int32;
  signFormat: byte;
  alpha: single;

  i: int32;

  sample: tAudioSample16S;
  sfxSamplePtr: pAudioSample16S;
  frameSpec: tFrameSpec;

  procedure readSigns(var signs: tDwords);
  var
    len: dword;
    signsPtr: pointer;
  begin
    if fs.readByte() <> $00 then error('invalid sign format');
    len := header.frameSize-1;
    signsPtr := signs;
    fs.readVLCSegment(len, signs);
    convertSigns(signs);
  end;

begin

  if sfx.format <> AF_16_STEREO then error('Can only decompress to 16bit stereo');

  //writeln('processing frame ',frameOn);

  startTimer('LA96_DF');

  {read frame header}
  frameType := fs.readByte(); midShift := frameType and $f; midUlaw := frameType shr 4;
  frameType := fs.readByte(); difShift := frameType and $f; difUlaw := frameType shr 4;

  midCode := negDecode(fs.readVLC());
  difCode := negDecode(fs.readVLC());
  fs.byteAlign();

  startTimer('LA96_DF_ReadSegments');
  fs.readVLCSegment(header.frameSize-1, midCodes);
  fs.readVLCSegment(header.frameSize-1, difCodes);

  readSigns(midSigns);
  readSigns(difSigns);
  stopTimer('LA96_DF_ReadSegments');

  sfxSamplePtr := sfx.data + (sfxOffset * 4);

  frameSpec.length := header.frameSize;
  frameSpec.midShift := midShift;
  frameSpec.difShift := difShift;
  frameSpec.midUTable := getULAW(midULaw);
  frameSpec.difUTable := getULAW(difULaw);
  frameSpec.idx := 0;
  frameSpec.centerShift := 16-header.centering;
  frameSpec.cMid := 0; frameSpec.cDif := 0;

  {final frame support}
  if frameOn = header.numFrames-1 then
    frameSpec.length := ((header.numSamples-1) mod header.frameSize)+1;

  sfxSamplePtr^ := generateSample(midCode, difCode, @frameSpec);

  startTimer('LA96_DF_Process');
  process_ASM(
    pointer(sfxSamplePtr)+4,
    midCode, difCode,
    midCodes, difCodes,
    midSigns, difSigns,
    @frameSpec
  );
  stopTimer('LA96_DF_Process');

  {stub: show values}
  {
  for i := 0 to 10 do begin
    log(format('%d (%d,%d)', [sfxOffset, sfx[sfxOffset+i].left, sfx[sfxOffset+i].right]));
  end;
  }

  {todo: implement this as a frameGenHook}
  if ENABLE_POST_PROCESS and (header.postFilter > 0) then begin
    startTimer('LA96_DF_PostProcess');
    alpha := exp((-2 * pi * header.postFilter * 1000) / 44100);
    postProcessEMA(sfxSamplePtr, cLeft, cRight, frameSpec.length, alpha);
    stopTimer('LA96_DF_PostProcess');
  end;

  if assigned(frameGenHook) then
    frameGenHook(frameOn, sfxSamplePtr, frameSpec.length);

  inc(frameOn);

  if (frameOn = header.numFrames) and looping then begin
    frameOn := 0;
    seek(0);
  end;

  stopTimer('LA96_DF');


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

procedure tULawLookup.initDecode(bits: byte; log2Mu: byte);
var
  i: int32;
  codeSize: int32;
  mu: int32;
begin
  mu := 1 shl log2Mu;
  codeSize := (1 shl bits);
  table := tIntList.create(codeSize+1); {0..codesize (inclusive)}
  for i := 0 to codeSize do
    table[i] := uLawInv(i / codeSize, mu);
end;

procedure tULawLookup.initEncode(bits: byte; log2Mu: byte);
var
  i: int32;
  codeSize: int32;
  mu: int32;
begin
  mu := 1 shl log2Mu;
  codeSize := (1 shl bits);
  table := tIntList.create(32*1024+1);
  for i := 0 to 32*1024 do
    table[i] := round(uLaw(i, mu) * codeSize);
end;

function tULawLookup.lookup(x: int32): int32; inline;
begin
  result := table[abs(x)];
  if x < 0 then result := -result;
end;

{-------------------------------------------------------}

procedure tAudioStreamProcessor.reset(initialValue: int32=0);
begin
  x := initialValue;
  y := initialValue;
  prevX := 0;
  prevY := 0;
  xPrime := initialValue;
end;

{saves enough of the stats of the stream processor to be able to call encode again}
procedure tAudioStreamProcessor.save();
begin
  savedX := x;
  savedY := y;
end;

{restores enough of the stats of the stream processor to be able to call encode again}
procedure tAudioStreamProcessor.restore();
begin
  x := savedX;
  y := savedY;
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
  uLawEncode.initEncode(uLawBits, log2Mu);
  uLawDecode.initDecode(uLawBits, log2Mu);
end;

destructor tASPULaw.destroy();
begin
  inherited destroy();
end;

procedure tASPULaw.encode(newX: int32);
begin
  prevX := x;
  prevY := y;
  y := ulawEncode.lookup(newX);
  x := newX;
  xPrime := uLawDecode.lookup(y);
end;


{------}

procedure tASPULawDelta.save();
begin
  savedX := x;
  savedY := y;
  savedU := prevU;
end;

procedure tASPULawDelta.restore();
begin
  x := savedX;
  y := savedY;
  prevU := savedU;
end;

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
  thisU := uLawEncode.table.data[ax];
  if newX < 0 then thisU := -thisU;

  y := thisU - prevU;
  x := newX;
  prevU := thisU;
  xPrime := uLawDecode.table.data[abs(thisU)];
  if thisU < 0 then xPrime := -xPrime;
end;

procedure tASPULawDelta.reset(initialValue: int32=0);
begin
  inherited reset(initialValue);
  prevU := uLawEncode.lookup(initialValue);
  y := prevU;
  xPrime := initialValue;
end;

{-------------------------------------------------------}

function decodeLA96(s: tStream): tSoundEffect;
var
  reader: tLA96Reader;
begin
  reader := tLA96Reader.create();
  reader.load(s);
  result := reader.readSFX();
  reader.free;
end;

function quant(x: int32;shiftAmount: byte): int32; inline; pascal;
asm
  push cx
  mov cl,   shiftAmount
  mov eax,  x
  sar eax,  cl
  pop cx
  end;

{return mid channel given left, right, and settings}
function qMid(left, right:int32; center: int32; quantBits: byte): int32; inline;
begin
  {best is to add then divide, but this means we 'round' and therefore
   occasionly overshoot. To compenstate for this I first clip LF}
  {note: I think this is right. For 8 quant bits we divide by 256,
   so we should exclude the last 128 (unscaled) values}
  if quantBits > 0 then begin
    left := clamp16(left, (1 shl (quantBits-1)));
    right := clamp16(right, (1 shl (quantBits-1)))
  end;
  asm
    push cx
    mov cl,   quantBits
    mov eax,  left
    add eax,  right
    sar eax,  1
    sub eax,  center
    sar eax,  cl
    pop cx
    end;
end;

{return mid channel given left, right, and settings}
function qDif(left, right:int32; center: int32; quantBits: byte): int32; inline;
begin
  {best is to add then divide, but this means we 'round' and therefore
   occasionly overshoot. To compenstate for this I first clip LF}
  if quantBits > 0 then begin
    left := clamp16(left, (1 shl (quantBits-1)));
    right := clamp16(right, (1 shl (quantBits-1)))
  end;
  asm
    push cx
    mov cl,   quantBits
    mov eax,  left
    sub eax,  right
    sar eax,  1
    sub eax,  center
    sar eax,  cl
    pop cx
    end;
end;


function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile;verbose: boolean=false): tStream;
const
  {note: we don't use centering anymore as it adds too much noise}
  CENTERING_RESOLUTION = 0; {16=perfect, 0=off}
  MAX_ATTEMPTS = 100; {max attempts for clipping protection (0=off)}
var
  i,j,k: int32;

  samplePtr: pAudioSample;

  thisMidValue, thisDifValue: int32;

  {note: we write FRAME_SIZE-1 deltas, which is FRAME_SIZE samples when including
   the initial value}
  midCodes: array[0..(FRAME_SIZE-1)-1] of dword;
  difCodes: array[0..(FRAME_SIZE-1)-1] of dword;
  midSigns: array[0..(FRAME_SIZE-1)-1] of int8;
  difSigns: array[0..(FRAME_SIZE-1)-1] of int8;

  signBits: array[0..(FRAME_SIZE-1)-1] of dword;

  fs: tStream;  // our file stream
  fsEndPos: dword;

  counter: int32;
  numFrames: int32;
  framePtr: tDwords;
  frameSizes: tDwords;
  maxSamplePtr: pointer;
  aspMid, aspDif: tAudioStreamProcessor;
  decMid, decDif: int32; {what the decoder will output}

  cMid, cDif: int32; {centers}
  tmp: int32;
  header: tLA96FileHeader;
  attempt: int32;

  fullStats, frameStats: tCSVWriter;

  midFrameSize, difFrameSize: int32;

  midXStats, difXStats,
  midYStats, difYStats: tStats;

  {for noise shaping}
  trueMid, trueDif: int32;
  outMid, outDif: int32;
  inMid, inDif: int32;
  inLeft, inRight: int32;
  outLeft, outRight: int32;
  midError, difError: single;
  noiseAlpha: single;

  clipGuard: int32; {padding for clipping}
  centerShift: byte;

  neededChange: boolean;
  penultimateValue: single;
  ulawMaxError: int32;
  clipAdjustment: int32;

  procedure writeOutSigns(signs: array of int8);
  var
    startPos: int32;
    bytesUsed: int32;
    i: integer;
  begin
    startPos := fs.pos;
    fs.writeByte($00); // sign format
    {todo: support writing these out as gaps between sign changes,
     or even auto detect which is better}
    fillchar(signBits, sizeof(signBits), 0);
    for i := 0 to (FRAME_SIZE-1)-1 do
      if signs[i] < 0 then signBits[i] := 1;
    bytesUsed := fs.writeVLCSegment(signBits);
    {also todo: move sign change detection here}
    {try writing these out as differences}
    //bytesUsed := fs.writeVLCSegment(difSignBits);
    {todo: detect when this doesn't work, and just write out the bits}
    {also.. is this really worth it?}
  end;

begin

  assert(profile.quantBits <= 15);
  assert(profile.ulawBits <= 15);

  if sfx.length = 0 then exit(nil);
  if sfx.format <> AF_16_STEREO then begin
    {convert as needed}
    sfx := sfx.asFormat(AF_16_STEREO);
    result := encodeLA96(sfx, profile);
    sfx.free;
    exit;
  end;

  assert(sfx.format = AF_16_STEREO);

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
  centerShift := 16-CENTERING_RESOLUTION;
  cMid := 0; cDif := 0;
  midError := 0; difError := 0;

  setLength(framePtr, numFrames);

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
  header.format := 0; // this will be for stero / mono etc
  header.compressionMode := 0;
  header.numFrames := numFrames;
  header.numSamples := sfx.length;
  header.frameSize := FRAME_SIZE;
  header.log2mu := profile.log2mu;
  header.postFilter := profile.filter;
  header.centering := CENTERING_RESOLUTION;

  fs.writeBlock(header, sizeof(header));

  // guard against half a quantization step (otherwise rounding might cause clipping)}
  if profile.quantBits = 0 then
    clipGuard := 0
  else
    clipGuard := (1 shl profile.quantBits);

  {not sure why we need to include ulaw error here, decoder tracking should sort this out?}
  if profile.uLawBits <> 0 then begin
    penultimateValue := 1 - (1/(1 shl profile.ulawBits));
    ulawMaxError := uLawInv(1, profile.log2Mu) - uLawInv(penultimateValue, profile.log2Mu);
    clipGuard += ulawMaxError*2;
    //note(format('Adding %d to clip guard due to ulaw', [ulawMaxError]));
  end;

  {write reserved header space}
  if fs.pos > 128 then raise Exception.create('Header length exceeds 128 bytes');
  while fs.pos < 128 do
    fs.writeByte(0);

  {allocate some space for frame pointers}
  for i := 0 to numFrames-1 do
    fs.writeDWord(0);

  // -------------------------
  // Write Frames

  midXStats.init();
  difXStats.init();
  midYStats.init();
  difYStats.init();

  // 0.0 = off, 1 = full, 0.95 = strong
  noiseAlpha := 0;

  for i := 0 to numFrames-1 do begin

    {todo: noise shaping here might be a good idea?}
    aspMid.reset(qMid(samplePtr^.left, samplePtr^.right, 0, profile.quantBits));
    aspDif.reset(qDif(samplePtr^.left, samplePtr^.right, 0, profile.quantBits));
    if samplePtr < maxSamplePtr then inc(samplePtr);

    midXStats.init(false);
    difXStats.init(false);
    midYStats.init(false);
    difYStats.init(false);

    if CENTERING_RESOLUTION > 0 then begin
      cMid := (aspMid.xPrime shl profile.quantBits) shr centerShift shl centerShift;
      cDif := (aspDif.xPrime shl profile.quantBits) shr centerShift shl centerShift;
    end else begin
      cMid := 0;
      cDif := 0;
    end;

    {write frame header (one for each channel)}
    framePtr[i] := fs.pos;
    fs.writeByte(profile.quantBits + profile.ulawBits*16);
    fs.writeByte(profile.quantBits + profile.ulawBits*16);
    fs.writeVLC(negEncode(aspMid.y));
    fs.writeVLC(negEncode(aspDif.y));
    fs.byteAlign();

    startTimer('LA96_process');
    for j := 0 to (FRAME_SIZE-1)-1 do begin

      trueMid := samplePtr^.mid;
      trueDif := samplePtr^.dif;
      inMid := trueMid;
      inDif := trueDif;
      if samplePtr < maxSamplePtr then inc(samplePtr);

      {noise shaping}
      if noiseAlpha > 0 then begin
        inMid += round(noiseAlpha * midError);
        //inDif += round(noiseAlpha * difError);
        midError *= (1-noiseAlpha);
        //difError *= (1-noiseAlpha);
      end;

      inLeft := inMid + inDif;
      inRight := inMid - inDif;

      aspMid.save();
      aspDif.save();

      aspMid.encode(qMid(inLeft, inRight, cMid, profile.quantBits));
      aspDif.encode(qDif(inLeft, inRight, cDif, profile.quantBits));

      {calculate the decoder's output}
      decMid := (aspMid.xPrime shl profile.quantBits) + cMid;
      decDif := (aspDif.xPrime shl profile.quantBits) + cDif;
      outLeft := decMid + decDif;
      outRight := decMid - decDif;

      {see if we have clipping and fix it}
      for attempt := 1 to MAX_ATTEMPTS do begin

        {not an efficent solution at handling clipping, but it'll get the
         job done. And I'm more worried about the decoder speed than
         encoder speed}

        neededChange := false;

        clipAdjustment := (1 shl profile.quantBits) + (clipGuard div 10);
        if outLeft > (high(int16)-clipGuard) then begin
          inLeft -= clipAdjustment;
          neededChange := true;
        end else if outLeft < (low(int16)+clipGuard) then begin
          inLeft += clipAdjustment;
          neededChange := true;
        end;

        if outRight > (high(int16)-clipGuard) then begin
          inRight -= clipAdjustment;
          neededChange := true;
        end else if outRight < (low(int16)+clipGuard) then begin
          inRight += clipAdjustment;
          neededChange := true;
        end;

        if not neededChange then break;

        {try again..}
        aspMid.restore;
        aspDif.restore;
        aspMid.encode(qMid(inLeft, inRight, cMid, profile.quantBits));
        aspDif.encode(qDif(inLeft, inRight, cDif, profile.quantBits));
        decMid := (aspMid.xPrime shl profile.quantBits) + cMid;
        decDif := (aspDif.xPrime shl profile.quantBits) + cDif;
        outLeft := decMid + decDif;
        outRight := decMid - decDif;
      end;

      if (clamp16(outLeft) <> outLeft) or (clamp16(outRight) <> outRight) then
        {indicate clipping}
        warning(format('Clipping %d %d', [outLeft, outRight]));

      {xPrime is decoders quant(decoded-cMid)}
      if CENTERING_RESOLUTION > 0 then begin
        cMid := decMid shr centerShift shl centerShift;
        cDif := decDif shr centerShift shl centerShift;
      end;

      {stats}
      midXStats.addValue(aspMid.x);
      difXStats.addValue(aspDif.x);
      midYStats.addValue(aspMid.y);
      difYStats.addValue(aspDif.y);

      midCodes[j] := abs(aspMid.y);
      difCodes[j] := abs(aspDif.y);

      midSigns[j] := sign(aspMid.y);
      difSigns[j] := sign(aspDif.y);

      {keep track of noise}
      if noiseAlpha > 0 then begin
        midError += trueMid-decMid;
        difError += trueDif-decDif;
      end;

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
    {stub:}
    if sfx.length > 2000 then begin
      midFrameSize := fs.writeVLCSegment(midCodes, ST_VLC2);
      difFrameSize := fs.writeVLCSegment(difCodes, ST_VLC2);
    end else begin
      midFrameSize := fs.writeVLCSegment(midCodes, ST_VLC1);
      difFrameSize := fs.writeVLCSegment(difCodes, ST_VLC1);
    end;
    stopTimer('LA96_segments');

    {write signs}
    writeOutSigns(midSigns);
    writeOutSigns(difSigns);

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

    if verbose and ((i mod 16) = 15) then write('.');

  end;

  {go back and write pointers}
  fsEndPos := fs.pos;
  fs.seek(128);
  for i := 0 to numFrames-1 do
    fs.writeDWord(framePtr[i]);
  fs.seek(fsEndPos);

  {clean up}
  aspMid.free;
  aspDif.free;

  if assigned(fullStats) then fullStats.free;
  if assigned(frameStats) then frameStats.free;

  stopTimer('LA96');

  if verbose then
    note(format('Encoded size %fKB Original %fKB',[fs.len/1024, 4*sfx.length/1024]));
end;

{--------------------------------------------------------}

type
  tLA96Test = class(tTestSuite)
    procedure run; override;
  end;

procedure tLA96Test.run();
var
  lutEncode: tULawLookup;
  lutDecode: tULawLookup;
  i: int32;
  s: tStream;
  sfxIn, sfxOut: tSoundEffect;
  sample: tAudioSample16S;
const
  mu = 256;
  bits = 6;
  codeSize = 1 shl bits;
begin
  {test lookups}
  lutEncode.initEncode(bits, round(log2(mu)));
  lutDecode.initDecode(bits, round(log2(mu)));
  for i := -codeSize to codeSize do
    assertEqual(lutDecode.lookup(i), uLawInv(i/codeSize, mu));
  for i := -1024 to 1024 do begin
    {check all values -1k..-1k, and also samples from whole range}
    assertEqual(lutEncode.lookup(32*i), round(uLaw(32*i, mu) * codeSize));
    assertEqual(lutEncode.lookup(i), round(uLaw(i, mu) * codeSize));
  end;

  {make sure that encoding a very short works correctly}
  sfxIn := tSoundEffect.create(AF_16_STEREO, 3);
  fillchar(sfxIn.data^, 3*4, 0);
  sample.left := 1000;
  sample.right := -300;
  sfxIn[1] := sample;
  s := tStream.create();
  s := encodeLA96(sfxIn, ACP_VERYHIGH);
  s.seek(0);
  sfxOut := decodeLA96(s);

  assertEqual(sfxOut.length, sfxIn.length);
  for i := 0 to sfxOut.length-1 do begin
    {we are compressing, so these just need to be roughtly correct}
    assertClose(sfxOut[i].left, sfxIn[i].left, 16);
    assertClose(sfxOut[i].right, sfxIn[i].right, 16);
  end;

  s.free;
  sfxIn.free;
  sfxOut.free;

end;

{--------------------------------------------------------}

initialization
  tLA96Test.create('LA96');
finalization

end.
