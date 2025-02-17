{A simple immedate mode gui}
Unit gui;
{$MODE delphi}

{TODO: remove this, just use UI}

interface

uses
  debug,
  font,
  sprite,
  lc96,
  uScreen,
  graph2d,
  mouse,
  graph32;

var
  panelSprite: tSprite = nil;
  frameSprite: tSprite = nil;
  buttonSprite: tSprite = nil;

procedure GUILabel(page: tPage; atX, atY: integer; s: string);
function  GUIButton(screen: tScreen; atX, atY: integer; s: string): boolean;
procedure GUIText(page: tPage; atX, atY: integer; s: string;shadow:boolean=false);

implementation

procedure GUILabel(page: tPage; atX, atY: integer; s: string);
begin
  if not assigned(panelSprite) or not assigned(frameSprite) then
    fatal('Tried to draw gui component before InitGUI called.');

  FrameSprite.NineSlice(page, atX, atY, 320, 24);
  atX += panelSprite.border.left;
  atY += panelSprite.border.top;
  {Custom positioning}
  atX += 5;
  atY -= 0;
  TextOut(page, atX+1, atY+1, s, RGBA.create(10, 10, 10, 100));
  TextOut(page, atX, atY, s, RGBA.create(245, 250, 253, 240));
end;

function GUIButton(screen: tScreen; atX, atY: integer; s: string): boolean;
const
  WIDTH = 120;
  HEIGHT = 26;
var
  textWidth: integer;
  padLeft: integer;
  bounds: tRect;
begin
  buttonSprite.nineSlice(screen.canvas, atX, atY, WIDTH, HEIGHT);
  atX += panelSprite.border.left;
  atY += panelSprite.border.top;
  {Custom positioning}
  textWidth := textExtents(s).width;
  padLeft := (WIDTH - textWidth) div 2;
  textOut(screen.canvas, atX+1+padLeft, atY+2, s, RGBA.create(10, 10, 10, 100));
  textOut(screen.canvas, atX+0+padLeft, atY+1, s, RGBA.create(245, 250, 253, 250));
  bounds := tRect.create(atX, atY, WIDTH, HEIGHT);
  screen.markRegion(bounds);
  result := (mouse_b and $1 = $1) and bounds.isInside(mouse_x, mouse_y);
end;

procedure GUIText(page: tPage; atX, atY: integer; s: string;shadow:boolean=false);
begin
  if not assigned(panelSprite) or not assigned(frameSprite) then
    fatal('Tried to draw gui component before InitGUI called.');
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

  buttonSprite := tSprite.Create(LoadLC96('res/button.p96'));
  buttonSprite.Border := tBorder.Create(10,10,10,10);

end;

begin
  initGui();
end.
