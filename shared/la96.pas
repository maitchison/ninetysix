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

function decodeLA96(s: tStream): tSoundEffect;
function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile;useLZ4: boolean=true): tStream;

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

function decodeLA96(s: tStream): tSoundEffect;
begin
  result := tSoundEffect.create();
  {todo: implement decode}
end;

function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile;useLZ4: boolean=true): tStream;
var
  i,j: int32;

  samplePtr: pAudioSample;

  thisMidValue, lastMidValue: int32;
  thisDifValue, lastDifValue: int32;

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

  framePtr, frameMid, frameDif: tDwords;

  maxSamplePtr: pointer;

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

  // Initialize variables
  if useLZ4 then
    {must defer writes and LZ4 doesn't work with streaming yet}
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

  // -------------------------
  // Write Header

  {write header}
  startPos := fs.pos;
  fs.writeChars('AC96');
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
    lastMidValue := quant(samplePtr^.left+samplePtr^.right, shiftAmount);
    lastDifValue := quant(samplePtr^.left-samplePtr^.right, shiftAmount);
    incPtr();

    framePtr.append(fs.pos);
    frameMid.append(negEncode(lastMidValue));
    frameDif.append(negEncode(lastDifValue));

    for j := 0 to 1023-1 do begin

      thisMidValue := quant(samplePtr^.left+samplePtr^.right, shiftAmount);
      thisDifValue := quant(samplePtr^.left-samplePtr^.right, shiftAmount);

      midCodes[j] := negEncode(thisMidValue-lastMidValue);
      difCodes[j] := negEncode(thisDifValue-lastDifValue);

      lastMidValue := thisMidValue;
      lastDifValue := thisDifValue;

      incPtr();
    end;

    {write out frame}
    ds.writeVLCSegment(midCodes, PACK_BEST);
    ds.writeVLCSegment(difCodes, PACK_BEST);

  end;

  if useLZ4 then
    //fs.writeBytes(LZ4Compress(ds.asBytes));
    //stub:
    fs.writeBytes(ds.asBytes);

  // -------------------------
  // Write Footer
  fs.writeVLCSegment(frameMid, PACK_BEST);
  fs.writeVLCSegment(frameDif, PACK_BEST);
  fs.writeVLCSegment(framePtr, PACK_BEST);

  {clean up}
  ds.free;

  note(format('Encoded size %fKB Original %fKB',[fs.len/1024, 4*sfx.length/1024]));
end;


begin
end.
