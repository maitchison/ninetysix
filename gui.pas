{A simple immedate mode gui}
Unit gui;
{$MODE delphi}

interface

uses
	debug,
  font,
  sprite,
	graph32;

var
	panelSprite: tSprite = nil;
  frameSprite: tSprite = nil;

procedure GUILabel(page: tPage; atX, atY: integer; s: string);

implementation

procedure GUILabel(page: tPage; atX, atY: integer; s: string);
var
	padX, padY: integer;
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

procedure InitGui();
begin
	info('[init] GUI');

  panelSprite := tSprite.Create(LoadBMP('res/panel.bmp'));
  panelSprite.Border := tBorder.Create(2,2,2,2);

  frameSprite := tSprite.Create(LoadBMP('res/ec_frame.bmp'));
  frameSprite.Border := tBorder.Create(8,8,8,8);

end;

begin
	initGui();
end.
