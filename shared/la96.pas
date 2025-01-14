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
function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile; s: tStream=nil): tStream;

const
  ACP_LOW: tAudioCompressionProfile = (quantBits:8);
  ACP_MEDIUM: tAudioCompressionProfile = (quantBits:10);
  ACP_HIGH: tAudioCompressionProfile = (quantBits:12);
  ACP_EXTREME: tAudioCompressionProfile = (quantBits:16); //very nearly lossless.

implementation

function decodeLA96(s: tStream): tSoundEffect;
begin
  result := tSoundEffect.create();
  {todo: implement decode}
end;

function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile; s: tStream=nil): tStream;
var
  i,j: int32;

  samplePtr: pAudioSample;
  samplesRemaining: dword;

  thisMidValue, lastMidValue, firstMidValue: int32;
  thisDifValue, lastDifValue, firstDifValue: int32;

  midCodes: array[0..1024-1] of dword;
  difCodes: array[0..1024-1] of dword;

  ds: tStream;
  counter: int32;
  bytes: tBytes;

  maxCode, sumCode: int64;
  meanValue, meanAbsValue: double;

  packBitsMid, packBitsDif: integer;
  shiftAmount: byte;

function quant(x: int32;shiftAmount: byte): int32; inline; pascal;
asm
  push cx
  mov cl, [shiftAmount]
  mov eax, [x]
  sar eax, cl
  pop cx
  end;

begin

  {guess that we'll need 2 bytes per sample, i.e 4:1 compression vs 16bit stereo}
  if not assigned(s) then s := tStream.create(2*sfx.length);
  result := s;

  if sfx.length = 0 then exit;

  samplePtr := sfx.data;
  samplesRemaining := sfx.length;

  lastMidValue := (samplePtr^.left+samplePtr^.right) div 2;
  lastDifValue := (samplePtr^.left-samplePtr^.right) div 2;
  lastMidValue := lastMidValue;
  lastDifValue := lastDifValue;

  ds := tStream.create();
  counter := 0;

  assert(profile.quantBits >= 1);
  assert(profile.quantBits <= 17);
  {note: 17bits is full precision as we are adding two 16bit values together}
  shiftAmount := (17-profile.quantBits);
  maxCode := 0;
  sumCode := 0;
  meanValue := 0;
  meanAbsValue := 0;

  while samplesRemaining >= 1024 do begin

    {unfortunately we can not encode any final partial block}

    firstMidValue := quant(samplePtr^.left+samplePtr^.right, shiftAmount);
    firstDifValue := quant(samplePtr^.left-samplePtr^.right, shiftAmount);
    lastMidValue := firstMidValue;
    lastDifValue := firstDifValue;

    for j := 0 to 1024-1 do begin

      thisMidValue := quant(samplePtr^.left+samplePtr^.right, shiftAmount);
      thisDifValue := quant(samplePtr^.left-samplePtr^.right, shiftAmount);

      midCodes[j] := negEncode(thisMidValue-lastMidValue);
      difCodes[j] := negEncode(thisDifValue-lastDifValue);

      lastMidValue := thisMidValue;
      lastDifValue := thisDifValue;

      inc(samplePtr);
    end;

    {prepare playload}
    ds.softReset();
    ds.writeVLC(negEncode(firstMidValue));
    packBitsMid := ds.writeVLCSegment(midCodes, PACK_FAST);
    ds.writeVLC(negEncode(firstDifValue));
    packBitsDif := ds.writeVLCSegment(difCodes, PACK_FAST);

    {write block header}
    s.byteAlign();
    s.writeByte($00);            {type = 16-bit joint stereo.}
    s.writeWord(1024);           {number of samples}
    s.writeWord(ds.len);         {compressed size}

    s.writeBytes(ds.asBytes, ds.len); //todo: remove copy here

    dec(samplesRemaining, 1024);
    inc(counter);

  end;

  ds.free;

  note(format('Encoded size %fKB Original %fKB',[s.len/1024, 4*sfx.length/1024]));
end;


begin
end.
