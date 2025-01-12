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
  sound,
  audioFilter,
  stream;

type
  tAudioCompressionProfile = record
    quantBits: word;
    freqLow: word;
    freqHigh: word;
  end;

function decodeLA96(s: tStream): tSoundEffect;
function encodeLA96(sfx: tSoundEffect; profile: tAudioCompressionProfile; s: tStream=nil): tStream;

const
  ACP_LOW: tAudioCompressionProfile = (quantBits:8; freqLow: 10; freqHigh:16000);
  ACP_MEDIUM: tAudioCompressionProfile = (quantBits:10; freqLow: 10; freqHigh:18000);
  ACP_HIGH: tAudioCompressionProfile = (quantBits:12; freqLow: 10; freqHigh:20000);

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

begin

  {guess that we'll need 1 byte per sample, i.e 4:1 compression vs 16bit stereo}
  if not assigned(s) then s := tStream.create(sfx.length*2);
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

  while samplesRemaining >= 1024 do begin

    {unfortunately we can not encode any final partial}

    firstMidValue := lastMidValue;
    firstDifValue := lastDifValue;

    for j := 0 to 1024-1 do begin
      {dividing by 2 is needed so as to not overflow.
       This method looses 1-bit of quality, but only when stereo.}

      thisMidValue := (samplePtr^.left+samplePtr^.right) div 2;
      thisDifValue := (samplePtr^.left-samplePtr^.right) div 2;

      {convert to 8-bit}
      {thisMidValue := thisMidValue div 256;
      thisDifValue := thisDifValue div 256;}

      midCodes[j] := negEncode(thisMidValue-lastMidValue);
      difCodes[j] := negEncode(thisDifValue-lastDifValue);

      lastMidValue := thisMidValue;
      lastDifValue := thisDifValue;

      inc(samplePtr);
    end;

    {prepare playload}
    ds.softReset();
    ds.writeVLC(negEncode(firstMidValue));
    ds.writeVLCSegment(midCodes);
    ds.writeVLC(negEncode(firstDifValue));
    ds.writeVLCSegment(difCodes);

    {write block header}
    s.byteAlign();
    s.writeByte($00);            {type = 16-bit joint stereo.}
    s.writeWord(1024);           {number of samples}
    s.writeWord(ds.len);         {compressed size}

    s.writeBytes(ds.getBuffer, ds.len);

    write('.');

    //stub:
    if counter and $ff = 0 then
      logHeapStatus(intToStr(counter));

    dec(samplesRemaining, 1024);
    inc(counter);

  end;

  ds.free;
  {note: we write out s.len bytes}
  writeln(s.capacity);
  writeln(s.len);
  writeln(s.pos);
  writeln(ds.capacity);
  writeln(ds.len);
  writeln(ds.pos);

  note(format('Encoded size %fKB',[s.len/1024]));
end;


begin
end.
