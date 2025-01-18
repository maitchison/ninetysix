{sound vizualizor... very simple}
unit sndViz;

interface

uses
  debug,
  test,
  sound,
  utils,
  graph32;

procedure displayAudio(page: tPage; sfx: tSoundEffect; scale: integer);

implementation

procedure displayAudio(page: tPage; sfx: tSoundEffect; scale: integer);
var
  xlp: integer;
  left, right: integer;
  prevLeft, prevRight: integer;
  leftColor, rightColor: RGBA;

begin
  leftColor.init(255,0,0,128);
  rightColor.init(0,255,0,128);
  prevLeft := 0; prevRight := 0;
  for xlp := 0 to 640-1 do begin
    left := sfx[xlp*scale].left div 256;
    right := sfx[xlp*scale].right div 256;
    page.vLine(xlp, 320+prevLeft, 320+left, leftColor);
    page.vLine(xlp, 320+prevRight, 320+right, rightColor);
    prevLeft := left;
    prevRight := right;
    //stub:
    log(format('%d: (%d,%d)', [xlp, left, right]));
  end;
end;

begin
end.
