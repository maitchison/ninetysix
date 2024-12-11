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

  sample: pAudioSample;
  lastValue,thisValue: int32;
  delta: int32;
  ds: tStream;
  codes: array[0..1024-1] of dword;
  maxCode: dword;

begin
	
	if not assigned(s) then s := tStream.create();
  result := s;

  ds := tStream.create();

  if sfx.length = 0 then exit;

  sample := sfx.sample;

  lastValue := sample^.left;
  {$R-}
  ds.writeWord(word(lastValue));
  {$R+}

  {1M samples, due to memory for the moment}
  for i := 0 to 512-1 do begin
  	maxCode := 0;
  	for j := 0 to 1024-1 do begin
    	{dividing by 2 looses quality, but only when stereo}
	  	thisValue := (sample^.left+sample^.right) div 2;
	    delta := thisValue - lastValue;
	    codes[j] := negEncode(delta);
	    lastValue := thisValue;
	  	inc(sample);
      maxCode := max(maxCode, codes[j]);

    end;
    ds.writeVLCSegment(codes, PACK_ALL);
    write(maxCode, ' ');
  end;

  lastValue := sample^.right;
  {$R-}
  ds.writeWord(word(lastValue));
  {$R+}

  for i := 0 to 512-1 do begin
  	maxCode := 0;
  	for j := 0 to 1024-1 do begin
	  	thisValue := sample^.left-sample^.right;
	    delta := thisValue - lastValue;
	    codes[j] := negEncode(delta);
	    lastValue := thisValue;
	  	inc(sample);
      maxCode := max(maxCode, codes[j]);
    end;
    ds.writeVLCSegment(codes, PACK_ALL);
    write(maxCode, ' ');
  end;

  s.writeBytes(ds.asBytes);

  writeln(format('Encoded used %fKB',[s.len/1024]));

end;


begin
end.
