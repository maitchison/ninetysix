{A simple immedate mode gui}
Unit gui;
{$MODE delphi}

interface

uses
  debug,
  font,
  sprite,
  lc96,
  graph32;

var
  panelSprite: tSprite = nil;
  frameSprite: tSprite = nil;

procedure GUILabel(page: tPage; atX, atY: integer; s: string);
procedure GUIText(page: tPage; atX, atY: integer; s: string;shadow:boolean=false);

implementation

procedure GUILabel(page: tPage; atX, atY: integer; s: string);
begin
  if not assigned(panelSprite) or not assigned(frameSprite) then
    error('Tried to draw gui component before InitGUI called.');

  FrameSprite.NineSlice(page, atX, atY, 300, 22);
  atX += panelSprite.border.left;
  atY += panelSprite.border.top;
  {Custom positioning}
  atX += 5;
  atY -= 0;
  TextOut(page, atX+1, atY+1, s, RGBA.create(10, 10, 10, 100));
  TextOut(page, atX, atY, s, RGBA.create(245, 250, 253, 240));
end;

procedure GUIText(page: tPage; atX, atY: integer; s: string;shadow:boolean=false);
begin
  if not assigned(panelSprite) or not assigned(frameSprite) then
    error('Tried to draw gui component before InitGUI called.');
  if shadow then
    textOut(page, atX+1, atY+1, s, RGBA.create(10, 10, 10, 100));
  textOut(page, atX, atY, s, RGBA.create(245, 250, 253, 240));
end;


procedure InitGui();
begin
  info('[init] GUI');

  panelSprite := tSprite.Create(LoadLC96('res/panel.p96'));
  panelSprite.Border := tBorder.Create(2,2,2,2);

  frameSprite := tSprite.Create(LoadLC96('res/ec_frame.p96'));
  frameSprite.Border := tBorder.Create(8,8,8,8);

end;

begin
  initGui();
end.
