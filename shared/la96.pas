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
  tAudioCompressionProfile = record
    {we used to have lo and high freq cut, but
     these did nothing, so I've removed them}
    quantBits: word;
  end;

  tAudioStreamProcessor = class
    x, prevX, y, prevY: int32;
    procedure encode(newX: int32); virtual;
    procedure reset(initialValue: int32=0); virtual;
  end;

  tASPDelta = class(tAudioStreamProcessor)
    procedure encode(newX: int32); override;
  end;

  tASPNonLinear = class(tAudioStreamProcessor)
    currentError: int32;
    procedure encode(newX: int32); override;
  end;

function decodeLA96(s: tStream): tSoundEffect;
function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile;useLZ4: boolean=false): tStream;

const
  ACP_LOW: tAudioCompressionProfile = (quantBits:8);
  ACP_MEDIUM: tAudioCompressionProfile = (quantBits:10);
  ACP_HIGH: tAudioCompressionProfile = (quantBits:12);
  ACP_EXTREME: tAudioCompressionProfile = (quantBits:16); // very nearly lossless.
  ACP_LOSSLESS: tAudioCompressionProfile = (quantBits:17);

implementation

const
  VER_SMALL = 1;
  VER_BIG = 0;

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

procedure tASPDelta.encode(newX: int32);
begin
  prevX := x;
  prevY := y;
  y := newX - x;
  x := newX;
end;

function sign(x: single): single;
begin
  if x < 0 then exit(-1);
  if x > 0 then exit(1);
  exit(0);
end;

procedure tASPNonLinear.encode(newX: int32);
var
  jumpDelta: int32;
  yErr: int32;
  yReal: single;
begin

  {
  all zeros

  newX = 10
  prevX = 0
  prevY = 0
  jumpDelta = 10-0 = 10
  yReal := sqrt(10)*1 = 3.3
  if 0 > 3 no
  if 0 < -3 no
  y := 3
  yErr := 9 - 10 = -1
  currentError += -1 (=-1)
  }


  prevX := x;
  prevY := y;

  {try to represent the actual delta we observed in x}
  jumpDelta := newX - x;

  yReal := sqrt(abs(jumpDelta)) * sign(jumpDelta);

  {account for drift... very slowly}
  if currentError > abs(yReal) then yReal -= 0.5;
  if currentError < -abs(yReal) then yReal += 0.5;

  y := round(yReal);

  yErr := y*y - newX;
  currentError += yErr;

  x := newX;
end;

{-------------------------------------------------------}

function decodeLA96(s: tStream): tSoundEffect;
begin
  result := tSoundEffect.create();
  {todo: implement decode}
end;

function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile;useLZ4: boolean=false): tStream;
var
  i,j: int32;

  samplePtr: pAudioSample;

  thisMidValue, thisDifValue: int32;

  {note: we write 1023 deltas, which is 1024 samples when including
   the initial value}
  midCodes: array[0..1023-1] of dword;
  difCodes: array[0..1023-1] of dword;

  fs: tStream;  // our file stream
  ds: tStream;  // our data stream.

  counter: int32;
  numFrames: int32;
  startPos: int32;
  shiftAmount: byte;

  signChanges: integer;

  framePtr, frameMid, frameDif: tDwords;

  maxSamplePtr: pointer;

  aspMid, aspDif: tAudioStreamProcessor;

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

begin

  assert(profile.quantBits >= 1);
  assert(profile.quantBits <= 17);

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
  {note: 17bits is full precision as we are adding two 16bit values together}
  shiftAmount := (17-profile.quantBits);

  framePtr := nil;
  frameMid := nil;
  frameDif := nil;

  aspMid := tASPNonLinear.create();
  aspDif := tASPNonLinear.create();

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

    signChanges := 0;

    startTimer('LA96_process');
    for j := 0 to 1023-1 do begin

      aspMid.encode(quant(samplePtr^.left+samplePtr^.right, shiftAmount));
      aspDif.encode(quant(samplePtr^.left-samplePtr^.right, shiftAmount));

      if (aspMid.y * aspMid.prevY) < 0 then inc(signChanges);

      midCodes[j] := negEncode(aspMid.y);
      difCodes[j] := negEncode(aspDif.y);

      incPtr();
    end;
    stopTimer('LA96_process');

    write(signChanges, ' ');

    {write out frame}
    startTimer('LA96_segments');
    ds.writeVLCSegment(midCodes, PACK_BEST);
    ds.writeVLCSegment(difCodes, PACK_BEST);
    stopTimer('LA96_segments');

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

  stopTimer('LA96');

  note(format('Encoded size %fKB Original %fKB',[fs.len/1024, 4*sfx.length/1024]));
end;


begin
end.
