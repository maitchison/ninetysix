{Audio compression library}
unit la96;

{$MODE delphi}

(*
  changes
  ---------------
  v0.1: initial file format
  v0.2: framePtr moved from footer to header
  v0.3:
    - switch to VCL2
    - no more centering
    - support for difReduction
    - sign bit compression
  v0.4
    - added rice codes
  [pending] v0.5:
    - new format with integrated sign bits
  [future] v0.6:
    - linear prediction
  [future] v0.7:
    - variable bitrate
*)


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
  LOSSLESS  5         1.5x
  LOW       3         10x
  MEDIUM    3         7.8x
  HIGH      5         4.6x
  Q10       5         3.5x  (10bit audio)


  Decompression speed is very fast. Currently at 20x realtime on P166 MMX
  An ASM/MMX decoder should get this to 30x.

  There are also some compression improvements to be made. I think we'll probably
  get VERY_LOW=7x, MEDIUM=5x and HIGH=4x. For the moment you can just zip them
  for some extra compression.

  Pending features
  -------------------------------------------------
  [done] Sign bit compression (should be +5% or so)
  [done] ASM Decoder (should be 25x realtime)
  MMX Decoder (should be 35x realtime)
  variable bit-rate (hoping for medium level with 5x compression)

  -------------------------------------------------
  How it all works (x? means x is optional via config settings)

  LeftRight_to_MidDif -> QUANTIZE -> ULAW -> DELTA

  and to unwind

  INV_DELTA -> INV_ULAW -> INV_QUANTIZE -> LeftRight_to_MidDif

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

type

  {fast uLaw calculations via a lookup table}
  {settings bits to 0 gives identity transform}
  tULawLookup = record
    maxValue: int32;
    table: tIntList;
    procedure initEncode(bits: byte; log2Mu: byte);
    procedure initDecode(bits: byte; log2Mu: byte);
    function tableCenterPtr: pointer; inline;
    function lookup(x: int32): int32; inline;
  end;
  pULawLookup = ^tULawLookup;

  tAudioCompressionProfile = record
    tag: string;
    {todo: remove quant bits / difReduce and just use mid/dif?}
    quantBits: byte; // number of bits to remove 0..15 (0=off)
    ulawBits: byte;  // number of ulaw bits, 0..15 (0 = off).
    log2mu: byte;    // log2 of mu parameter (if ulaw is active)
    difReduce: byte; // reduces quality (and volume) of mid channel
    function midQuantBits: byte; // reduces quality of mid channel
    function difQuantBits: byte; // reduces quality of dif channel
    function difShift: byte;     // reduces volume of dif channel
    function ulawDifBits: byte;
    function toString: string;
  end;

  tLA96FileHeader = packed record
    tag: array[1..4] of char;
    versionSmall, versionBig: word;
    format, compressionMode: byte;
    numFrames: int32;
    numSamples: int32;
    frameSize: word;
    log2mu: byte;
    postFilter: byte; {requested post processing highpass filter in KHZ}
    centering: byte;  {0=off, 8=on with 256 resolution}
    function verStr: string;
  end;

  tFrameFrameProc = procedure(frameOn: int32; samplePtr: pAudioSample16S; frameLength: int32);
  tPlaybackFinishedProc = procedure();

  tLA96Reader = class
  private
    fs: tStream;
    ownsStream: boolean;
  protected
    header: tLA96FileHeader;
    ulawTable: array[1..8] of tULawLookup;
    midCodes, difCodes: tDWords; {todo: make 16bit}
    framePtr: tInt32s; {will be filled with -1 if no frame pointers}
    frameOn: int32;
    cLeft, cRight: single; {used for EMA}
  protected
    function  getULAW(bits: byte): pULawLookup;
    procedure loadHeader();
  public
    filename: string;
    looping: boolean;
    frameReadHook: tFrameFrameProc;
    playbackFinishedHook: tPlaybackFinishedProc;
  public
    constructor create();
    destructor destroy(); override;
    function  isLoaded: boolean;
    function  duration: single;
    function  frameSize: integer;
    procedure seek(frameNumber: integer);
    procedure open(aFilename: string); overload;
    procedure open(aStream: tStream); overload;
    procedure close();
    function  readSFX(): tSoundEffect;
    procedure readNextFrame(samplePtr: pAudioSample16S);
  end;

  tLA96Writer = class
  protected
    fs: tStream;
    ownsStream: boolean;
    frameOn: int32;
    header: tLA96FileHeader;
    profile: tAudioCompressionProfile;
    // raw frame values to write out
    inBuffer: tDwords;
    outA, outB: tDWords;
    ulawTable: array[1..8] of tULawLookup;
  public
    {hooks}
    frameWriteHook: tFrameFrameProc;
  protected
    function getULAW(bits: byte): pULawLookup;
  public
    constructor create();
    destructor destroy(); override;
    procedure open(aFilename: string); overload;
    procedure open(aStream: tStream); overload;

    procedure writeNextFrame(samplePtr: pAudioSample16S);
    procedure close();
    procedure writeSFX(sfx: tSoundEffect; aProfile: tAudioCompressionProfile); overload;
    procedure writeSFX(sfx: tSoundEffect); overload;
  end;

function decodeLA96(s: tStream): tSoundEffect;
function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile;verbose: boolean=false): tMemoryStream;

const
  {note: low sounds very noisy, but I think we can fix this with some post filtering}
  {todo: high should be 8/7 for ulaw}
  ACP_LOW: tAudioCompressionProfile      = (tag:'low';     quantBits:6;ulawBits:8;log2Mu:8;difReduce:15);
  ACP_MEDIUM: tAudioCompressionProfile   = (tag:'medium';  quantBits:5;ulawBits:8;log2Mu:8;difReduce:4);
  ACP_HIGH: tAudioCompressionProfile     = (tag:'high';    quantBits:4;ulawBits:8;log2Mu:8;difReduce:1);
  ACP_VERYHIGH: tAudioCompressionProfile = (tag:'veryhigh';quantBits:2;ulawBits:8;log2Mu:8;difReduce:0);
  ACP_Q8: tAudioCompressionProfile       = (tag:'q8';      quantBits:8;ulawBits:0;log2Mu:0;difReduce:0);
  ACP_Q10: tAudioCompressionProfile      = (tag:'q10';     quantBits:6;ulawBits:0;log2Mu:0;difReduce:0);
  ACP_Q12: tAudioCompressionProfile      = (tag:'q12';     quantBits:4;ulawBits:0;log2Mu:0;difReduce:0);
  ACP_Q16: tAudioCompressionProfile      = (tag:'q16';     quantBits:0;ulawBits:0;log2Mu:0;difReduce:0);

var
  LA96_ENABLE_STATS: boolean = false;

implementation

const
  VER_SMALL = 5;
  VER_BIG = 0;
  FRAME_SIZE = 1024;

type
  tFrameSpec = record
    length: word; {number of samples in frame}
    idx: int32; {might be -1}
    midShift, difShift:byte;
    midUTable, difUTable: ^tULawLookup;
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

{returns number of ulaw bits for mid channel. 0=off}
function tAudioCompressionProfile.ulawDifBits: byte;
begin
  result := clamp(ulawBits, 0, 255);
end;

function tAudioCompressionProfile.difQuantBits: byte;
begin
  result := clamp(quantBits+difReduce, 0, 15)
end;

function tAudioCompressionProfile.difShift: byte;
begin
  result := clamp(difReduce-1, 0, 15)
end;

function tAudioCompressionProfile.midQuantBits: byte;
begin
  result := quantBits;
end;

function tAudioCompressionProfile.toString();
begin
  result := format('%s quant:%d,%d ulaw:%d,%d', [tag, midQuantBits, difQuantBits, ulawBits, ulawDifBits]);
end;

{----------------------}

function tLA96FileHeader.verStr(): string;
begin
  result := utils.format('%d.%d', [versionBig, versionSmall]);
end;

{----------------------}

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

{-------------------------------------------------------------------------}
{ tLA96Reader }
{-------------------------------------------------------------------------}

constructor tLA96Reader.create();
var
  bits: int32;
begin
  {init vars}
  fillchar(header, sizeof(header), 0);
  fs := nil;
  looping := false;
end;

procedure tLA96Reader.open(aFilename: string); overload;
begin
  if isLoaded then begin
    if self.filename = aFilename then begin
      self.fs.seek(0);
      self.loadHeader();
      exit;
    end else
      self.close();
  end;
  self.fs := tFileStream.create(aFilename, FM_READ);
  self.ownsStream := true;
  self.filename := aFilename;
  self.loadHeader();
end;

{loads from a stream. Stream is still owned by caller and so must
 be freed by them}
procedure tLA96Reader.open(aStream: tStream); overload;
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

function tLA96Reader.duration: single;
begin
  result := header.numSamples / 44100;
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
  for i := 0 to header.numFrames-1 do
    readNextFrame(result.data + (i*header.frameSize*4));
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
 can be used to stream music compressed in memory.

 samplePtr: the destination to write one frame of sample data to
 }
{todo: remove timers and other stuff unless verbose is on}
procedure tLA96Reader.readNextFrame(samplePtr: pAudioSample16S);
var
  frameType: byte;
  midShift, difShift, midULaw, difULaw: byte;

  midValue, difValue: int16;
  signFormat: byte;
  alpha: single;

  i: int32;

  sample: tAudioSample16S;
  frameSpec: tFrameSpec;

  procedure readSigns(var signs: tDwords);
  var
    len: dword;
    signsPtr: pointer;
  begin
    len := header.frameSize-1;
    {this is a bit slower, but more efficent for complex sign patterns}
    signsPtr := signs;
    fs.readSegment(len, signs);
    convertSigns(signs);
  end;

begin

  if (frameOn >= header.numFrames) then begin
    {if we reached the end, then just output silence}
    filldword(samplePtr^, header.frameSize, 0);
    exit;
  end;

  //writeln('processing frame ',frameOn);

  startTimer('LA96_FRAME');

  {read frame header}
  fs.readWord(); // this should be 0, for joint stereo.
  frameType := fs.readByte(); midShift := frameType and $f; midUlaw := frameType shr 4;
  frameType := fs.readByte(); difShift := frameType and $f; difUlaw := frameType shr 4;

  midValue := zagZig(fs.readWord());
  difValue := zagZig(fs.readWord());

  startTimer('LA96_FRAME_ReadSegments');
  {todo: read 16bit segment}
  fs.readSegment(header.frameSize-1, midCodes);
  fs.readSegment(header.frameSize-1, difCodes);
  stopTimer('LA96_FRAME_ReadSegments');

  frameSpec.length := header.frameSize;
  frameSpec.midShift := midShift;
  frameSpec.difShift := difShift;
  frameSpec.midUTable := getULAW(midULaw);
  frameSpec.difUTable := getULAW(difULaw);
  frameSpec.idx := 0;

  {final frame support}
  if frameOn = header.numFrames-1 then
    frameSpec.length := ((header.numSamples-1) mod header.frameSize)+1;

  samplePtr^ := generateSample(midValue, difValue, @frameSpec);

  startTimer('LA96_FRAME_Process');
  process_REF(
    pointer(samplePtr)+4,
    midValue, difValue,
    midCodes, difCodes,
    @frameSpec
  );
  stopTimer('LA96_FRAME_Process');

  {show values}
  {
  for i := 0 to 10 do begin
    log(format('%d (%d,%d)', [sfxOffset, sfx[sfxOffset+i].left, sfx[sfxOffset+i].right]));
  end;
  }

  if assigned(frameReadHook) then
    frameReadHook(frameOn, samplePtr, frameSpec.length);

  inc(frameOn);

  if (frameOn = header.numFrames) then begin
    if looping then begin
      frameOn := 0;
      seek(0);
    end else begin
      {hmm if hook loads another file, and we read all of it, we get
       here again?}
      if assigned(playbackFinishedHook) then
        playbackFinishedHook();
    end;
  end;

  stopTimer('LA96_FRAME');

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
  mu: int32;
begin
  mu := 1 shl log2Mu;
  maxValue := (1 shl bits);
  table := tIntList.create(2*maxValue+1); {-codesize..codesize (inclusive)}
  for i := -maxValue to maxValue do begin
    table[maxValue+i] := uLawInv(i / maxValue, mu);
  end;
end;

{pointer to midpoint of table, i.e. f(0)}
function tULawLookup.tableCenterPtr: pointer; inline;
begin
  result := @table.data[maxValue];
end;

procedure tULawLookup.initEncode(bits: byte; log2Mu: byte);
var
  i: int32;
  codeSize: int32;
  mu: int32;
begin
  mu := 1 shl log2Mu;
  codeSize := (1 shl bits);
  maxValue := 32*1024;
  table := tIntList.create(2*maxValue+1);
  for i := -maxValue to maxValue do
    table[maxValue+i] := round(uLaw(i, mu) * codeSize);
end;

function tULawLookup.lookup(x: int32): int32; inline;
begin
  result := table.data[maxValue+x];
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
begin
  prevX := x;
  prevY := y;
  newX := clamp(newX, -32*1024, 32*1024);
  thisU := uLawEncode.lookup(newX);

  y := thisU - prevU;
  x := newX;
  prevU := thisU;
  xPrime := uLawDecode.lookup(thisU);
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
  reader.open(s);
  result := reader.readSFX();
  reader.free;
end;

procedure updateEncodeProgress(frameOn: int32; samplePtr: pAudioSample16S; frameLength: int32);
begin
  {todo: do something fancy here, like eta, speed etc}
  if frameOn mod 16 = 15 then write('.');
end;

function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile;verbose: boolean=false): tMemoryStream;
var
  writer: tLA96Writer;
  ms: tMemoryStream;
begin
  writer := tLA96Writer.create();
  if verbose then
    writer.frameWriteHook := updateEncodeProgress;
  ms := tMemoryStream.create();
  writer.open(ms);
  writer.writeSFX(sfx, profile);
  result := ms;
  writer.free;
end;

{------------------------------------------------------}

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

{-------------------------------------------------------------------------}
{ tLA96Writer }
{-------------------------------------------------------------------------}

constructor tLA96Writer.create();
var
  bits: integer;
begin

  inherited create();

  {setup buffers}
  setLength(inBuffer, FRAME_SIZE);
  setLength(outA, FRAME_SIZE-1);
  setLength(outB, FRAME_SIZE-1);

  {create ulaw tables}
  for bits := low(ulawTable) to high(ulawTable) do
    ulawTable[bits].initEncode(bits, 8);

  fs := nil;
  ownsStream := false;
  frameOn := 0;
  frameWriteHook := nil;
  profile := ACP_HIGH;
end;

destructor tLA96Writer.destroy();
begin
  close();
  inherited destroy();
end;

procedure tLA96Writer.close();
begin
  if assigned(fs) then begin
    if ownsStream then fs.free;
  end;
  fs := nil;
  frameOn := 0;
  ownsStream := false;
end;

procedure tLA96Writer.open(aFilename: string);
var
  fs: tFileStream;
begin
  fs := tFileStream.create(aFilename, FM_WRITE);
  open(fs);
  ownsStream := true;
end;

procedure tLA96Writer.open(aStream: tStream);
begin
  close();
  fs := aStream;
  ownsStream := false;
  frameOn := 0;
  fillchar(header, sizeof(header), 0);
end;

{---------------------------}
{todo: move these into ASM / REF}
{---------------------------}

{converts samples from LeftRight to quantized Mid/Diff}
procedure ApplyLRtoQMD_REF(samplePtr: pAudioSample16S;qMid, qDif: byte; n: int32);
var
  i: integer;
  mid, dif: int16;
begin
  for i := 0 to n-1 do begin
    mid := samplePtr^.toMid;
    dif := samplePtr^.toDif;
    samplePtr^.a := shiftRight(mid, qMid);
    samplePtr^.b := shiftRight(dif, qDif);
    inc(samplePtr);
  end;
end;

{converts samples from Linear to ULaw}
procedure ApplyULAW_REF(samplePtr: pAudioSample16S;lutA, lutB: pUlawLookup; n: int32);
var
  i: integer;
begin
  for i := 0 to n-1 do begin
    samplePtr^.a := lutA^.lookup(samplePtr^.a);
    samplePtr^.b := lutB^.lookup(samplePtr^.b);
    inc(samplePtr);
  end;
end;

procedure ApplyDeltaModulation_REF(samplePtr: pAudioSample16S; n: int32);
var
  i: integer;
  prevA, prevB: int32;
  deltaA, deltaB: int32;
begin
  prevA := 0;
  prevB := 0;
  for i := 0 to n-1 do begin
    {todo: support wrapping optimization - i.e. use wrap around delta if it's smaller}
    {note wrapping is also required for 16bit uncompressed I think}
    deltaA := samplePtr^.a - prevA;
    deltaB := samplePtr^.b - prevB;
    prevA := samplePtr^.a;
    prevB := samplePtr^.b;
    samplePtr^.a := deltaA;
    samplePtr^.b := deltaB;
    inc(samplePtr);
  end;
end;

function tLA96Writer.getULAW(bits: byte): pULawLookup;
begin
  result := nil;
  if bits = 0 then exit;
  if bits in [1..8] then
    result := @ulawTable[bits]
  else
    error(format('Invalid ulaw bits %d, expecting (1..8)', [bits]));
end;

procedure tLA96Writer.writeNextFrame(samplePtr: pAudioSample16S);
var
  i: integer;
  frameSize: integer;
begin

  if assigned(frameWriteHook) then frameWriteHook(frameOn, samplePtr, FRAME_SIZE);

  {handle last frame}
  if frameOn = header.numFrames-1 then
    frameSize := header.numSamples mod FRAME_SIZE
  else
    frameSize := FRAME_SIZE;

  {make a copy of the input, as we will modify it}
  fillchar(inBuffer[0], FRAME_SIZE*4, 0);
  move(samplePtr^, inBuffer[0], frameSize*4);
  samplePtr := @inBuffer[0];

  {write frame header}
  fs.writeWord(0); // frame type (16bit, joint stereo)
  fs.writeByte(profile.midQuantBits + profile.ulawBits*16);
  fs.writeByte(profile.difQuantBits + profile.ulawDifBits*16);

  {process audio}
  ApplyLRToQMD_REF(
    samplePtr,
    profile.midQuantBits,
    profile.difQuantBits + profile.difShift,
    frameSize
  );
  if profile.ulawBits > 0 then
    ApplyULaw_REF(
      samplePtr,
      getULaw(profile.ulawBits),
      getULaw(profile.ulawDifBits),
      frameSize
    );
  ApplyDeltaModulation_REF(samplePtr, frameSize);

  {convert using zigZag}
  fs.writeWord(zigZag(samplePtr^.a));
  fs.writeWord(zigZag(samplePtr^.b));
  inc(samplePtr);
  fillchar(outA[0], length(outA)*4, 0);
  fillchar(outB[0], length(outB)*4, 0);
  for i := 0 to frameSize-2 do begin
    outA[i] := zigZag(samplePtr^.a);
    outB[i] := zigZag(samplePtr^.b);
    inc(samplePtr);
  end;
  dec(samplePtr, frameSize-1);

  {write out}
  fs.writeSegment(outA);
  fs.writeSegment(outB);

  fs.flush();
  inc(frameOn);
end;

procedure tLA96Writer.writeSFX(sfx: tSoundEffect;aProfile: tAudioCompressionProfile);
begin
  self.profile := aProfile;
  writeSFX(sfx);
end;

procedure tLA96Writer.writeSFX(sfx: tSoundEffect);
var
  i: integer;
  startPos, endPos: int32;
  framePtr: tDwords;
begin

  if (profile.log2mu <> 8) then error('Values other than 8 for Log2MU are not currently supported');

  startPos := fs.pos;

  { write header }
  fillchar(header, sizeof(header),0);
  header.tag := 'LA96';
  header.versionSmall := VER_SMALL;
  header.versionBig := VER_BIG;
  header.format := 0; // this will be for stero / mono etc
  header.compressionMode := 0;
  header.numFrames := (sfx.length + FRAME_SIZE - 1) div FRAME_SIZE;
  header.numSamples := sfx.length; // we don't know this yet
  header.frameSize := FRAME_SIZE;
  header.log2mu := profile.log2mu;
  header.postFilter := 0; // not used anymore
  fs.writeBlock(header, sizeof(header));
  while fs.pos < startPos + 128 do
    fs.writeByte(0);

  { write pointers }
  for i := 0 to header.numFrames-1 do
    fs.writeDWord(0);

  { write frames }
  setLength(framePtr, header.numFrames);
  for i := 0 to header.numFrames-1 do begin
    framePtr[i] := fs.pos-startPos;
    writeNextFrame(sfx.data + (i*header.frameSize*4));
  end;

  { go back and write frame pointers}
  endPos := fs.pos;
  fs.seek(startPos+128);
  fs.writeBlock(framePtr[0], length(framePtr)*4);
  fs.seek(endPos);

end;


{todo: remove this}
function xencodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile;verbose: boolean=false): tMemoryStream;
const
  {note: we don't use centering anymore as it adds too much noise}
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

  fs: tMemoryStream;  // our file stream
  fsEndPos: dword;

  counter: int32;
  numFrames: int32;
  framePtr: tDwords;
  frameSizes: tDwords;
  maxSamplePtr: pointer;
  aspMid, aspDif: tAudioStreamProcessor;
  decMid, decDif: int32; {what the decoder will output}

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

  clipGuard: int32; {padding for clipping}

  neededChange: boolean;
  penultimateValue: single;
  ulawMaxError: int32;
  clipAdjustment: int32;

  procedure writeOutSigns(signs: array of int8);
  var
    startPos: int32;
    i: integer;
  begin
    startPos := fs.pos;
    fillchar(signBits, sizeof(signBits), 0);
    for i := 0 to (FRAME_SIZE-1)-1 do
      if signs[i] < 0 then signBits[i] := 1;
    fs.writeSegment(signBits, ST_PACK1);
  end;

begin

  assert(profile.quantBits <= 15);
  assert(profile.ulawBits <= 15);

  if sfx.length = 0 then exit(nil);
  if sfx.format <> AF_16_STEREO then begin
    {convert as needed}
    sfx := sfx.asFormat(AF_16_STEREO);
    result := xencodeLA96(sfx, profile);
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
  fs := tMemoryStream.create(2*sfx.length);
  result := fs;

  startTimer('LA96');

  counter := 0;
  samplePtr := sfx.data;
  maxSamplePtr := pointer(dword(samplePtr) + (sfx.length * 4));
  numFrames := (sfx.length + (FRAME_SIZE-1)) div FRAME_SIZE;

  setLength(framePtr, numFrames);

  if profile.ulawBits > 0 then begin
    aspMid := tASPULawDelta.create(profile.ulawBits, profile.log2mu);
    aspDif := tASPULawDelta.create(profile.ulawDifBits, profile.log2mu);
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
  header.postFilter := 0; // not used anymore

  fs.writeBlock(header, sizeof(header));

  // guard against half a quantization step (otherwise rounding might cause clipping)}
  {todo: remove clip guard and just let the decoder clamp (since it'll be MMX anyway)}
  {alternatively, clamp on mid + dif, with different quant levels}
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

  {todo: have mid/dif as a preprocessing step, and do below entirely with
   two channels. Also perform clipping checks in mid/dif space
   (which means decodeer must clamp)}
  {this also gives us mid/dif quantization levels}
  {also, remove centering}

  for i := 0 to numFrames-1 do begin

    trueMid := samplePtr^.toMid;
    trueDif := samplePtr^.toDif;
    trueDif := shiftRight(trueDif, profile.difShift);
    inMid := trueMid;
    inDif := trueDif;
    inLeft := inMid + inDif;
    inRight := inMid - inDif;

    aspMid.reset(qMid(inLeft, inRight, 0, profile.midQuantBits));
    aspDif.reset(qDif(inLeft, inRight, 0, profile.difQuantBits));
    if samplePtr < maxSamplePtr then inc(samplePtr);

    midXStats.init(false);
    difXStats.init(false);
    midYStats.init(false);
    difYStats.init(false);

    {write frame header (one for each channel)}
    framePtr[i] := fs.pos;
    fs.writeByte(profile.midQuantBits + profile.ulawBits*16);
    fs.writeByte(profile.difQuantBits + profile.ulawDifBits*16);
    fs.writeWord(negEncode(aspMid.y));
    fs.writeWord(negEncode(aspDif.y));

    startTimer('LA96_process');
    for j := 0 to (FRAME_SIZE-1)-1 do begin

      trueMid := samplePtr^.toMid;
      trueDif := samplePtr^.toDif;
      trueDif := shiftRight(trueDif, profile.difShift);
      inMid := trueMid;
      inDif := trueDif;
      if samplePtr < maxSamplePtr then inc(samplePtr);

      inLeft := inMid + inDif;
      inRight := inMid - inDif;

      aspMid.save();
      aspDif.save();

      aspMid.encode(qMid(inLeft, inRight, 0, profile.midQuantBits));
      aspDif.encode(qDif(inLeft, inRight, 0, profile.difQuantBits));

      {calculate the decoder's output}
      decMid := aspMid.xPrime shl profile.midQuantBits;
      decDif := aspDif.xPrime shl profile.difQuantBits;
      outLeft := decMid + decDif;
      outRight := decMid - decDif;

      {see if we have clipping and fix it}
      {todo: remove this}
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
        aspMid.encode(qMid(inLeft, inRight, 0, profile.midQuantBits));
        aspDif.encode(qDif(inLeft, inRight, 0, profile.difQuantBits));
        decMid := aspMid.xPrime shl profile.midQuantBits;
        decDif := aspDif.xPrime shl profile.difQuantBits;
        outLeft := decMid + decDif;
        outRight := decMid - decDif;
      end;

      if (clamp16(outLeft) <> outLeft) or (clamp16(outRight) <> outRight) then
        {indicate clipping}
        warning(format('Clipping %d %d', [outLeft, outRight]));

      {stats}
      midXStats.addValue(aspMid.x);
      difXStats.addValue(aspDif.x);
      midYStats.addValue(aspMid.y);
      difYStats.addValue(aspDif.y);

      midCodes[j] := abs(aspMid.y);
      difCodes[j] := abs(aspDif.y);

      midSigns[j] := sign(aspMid.y);
      difSigns[j] := sign(aspDif.y);

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
    midFrameSize := fs.writeSegment(midCodes);
    difFrameSize := fs.writeSegment(difCodes);
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
  s := encodeLA96(sfxIn, ACP_VERYHIGH);
  s.seek(0);

  //logbytes
  {
  log(intToStr(s.len));
  for i := 0 to 1024-1 do begin
    if i mod 32 = 0 then writeln();
    s.seek(i);
    write(hexStr(s.readByte,2));
  end;
  }

  sfxOut := decodeLA96(s);

  {show output}
  for i := 0 to sfxOut.length-1 do begin
    log(format('in: %s out:%s', [sfxIn[i].toString, sfxOut[i].toString]));
  end;

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
