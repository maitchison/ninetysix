{sound vizualizor... very simple}
unit sndViz;

interface

uses
  debug,
  test,
  sound,
  utils,
  graph32;

procedure displayAudio(atX, atY: int32; page: tPage; samplePtr: pAudioSample16S; samples: int32; scale: integer=1);

implementation

procedure displayAudio(atX, atY: int32; page: tPage; samplePtr: pAudioSample16S; samples: int32; scale: integer=1);
var
  xlp: integer;
  left, right: integer;
  prevLeft, prevRight: integer;
  leftColor, rightColor: RGBA;
  samplesRemaining: int32;
begin
  leftColor.init(255,0,0,128);
  rightColor.init(0,255,0,128);
  prevLeft := 0; prevRight := 0;
  samplesRemaining := samples;
  for xlp := 0 to 640-1 do begin
    if samplesRemaining <= 0 then break;
    left := samplePtr^.left div 256;
    right := samplePtr^.right div 256;
    page.vLine(atX+xlp, atY+prevLeft, atY+left, leftColor);
    page.vLine(atX+xlp, atY+prevRight, atY+right, rightColor);
    prevLeft := left;
    prevRight := right;
    inc(samplePtr, scale);
    dec(samplesRemaining, scale);
  end;
end;

begin
end.
