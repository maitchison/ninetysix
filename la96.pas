{lossless audio compression library}
unit la96;

{$MODE delphi}

{
	Todo:
  	make block based
    support joint audio
}

interface

uses
	utils,
  lz4,
  dos,
	sound,
	stream;

function decodeLA96(s: tStream): tSoundEffect;
function encodeLA96(sfx: tSoundEffect;s: tStream=nil): tStream;

implementation

function decodeLA96(s: tStream): tSoundEffect;
begin
	result := tSoundEffect.create();
  {todo: implement decode}
end;

function encodeLA96(sfx: tSoundEffect;s: tStream=nil): tStream;
var
	i,j: int32;

  samplePtr: pAudioSample;
  samplesRemaining: dword;

  thisMidValue, lastMidValue, firstMidValue: int32;
  thisDifValue, lastDifValue, firstDifValue: int32;

  midCodes: array[0..1024-1] of dword;
  difCodes: array[0..1024-1] of dword;

  ds: tStream;
  bytes: tBytes;

begin
	
	if not assigned(s) then s := tStream.create();
  result := s;

  if sfx.length = 0 then exit;

  samplePtr := sfx.sample;
  samplesRemaining := sfx.length;

  lastMidValue := (samplePtr^.left+samplePtr^.right) div 2;
	lastDifValue := (samplePtr^.left-samplePtr^.right);

  ds := tStream.create();

  while samplesRemaining >= 1024 do begin

  	{unfortunately we can not encode any final partial}
  	
    firstMidValue := lastMidValue;
    firstDifValue := lastDifValue;

  	for j := 0 to 1024-1 do begin
    	{dividing by 2 looses quality, but only when stereo}
	  	thisMidValue := (samplePtr^.left+samplePtr^.right) div 2;
      thisDifValue := (samplePtr^.left-samplePtr^.right);

      midCodes[j] := negEncode(thisMidValue-lastMidValue);
      difCodes[j] := negEncode(thisDifValue-lastDifValue);

	    lastMidValue := thisMidValue;
	    lastDifValue := thisDifValue;

	  	inc(samplePtr);
    end;

    {prepair playload}
    ds.reset();
    ds.writeVLC(negEncode(firstMidValue));
    ds.writeVLCSegment(midCodes);
    ds.writeVLC(negEncode(firstDifValue));
    ds.writeVLCSegment(difCodes);
    bytes := ds.asBytes;

    {write block header}
    s.byteAlign();
    s.writeByte($00); 					{type = 16-bit joint stereo.}
    s.writeWord(1024); 					{number of samples}
    s.writeWord(length(bytes)); {compressed size}
    s.writeBytes(bytes);

    bytes := nil;
    write(samplesRemaining, ' ');

    dec(samplesRemaining, 1024);

  end;

  ds.Destroy;

  writeln(format('Encoded used %fKB',[s.len/1024]));

end;


begin
end.