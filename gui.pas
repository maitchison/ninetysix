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
	PanelSprite: TSprite;
  FrameSprite: TSprite;

procedure GUILabel(page: tPage; atX, atY: integer; s: string);

implementation

procedure GUILabel(page: tPage; atX, atY: integer; s: string);
var
	padX, padY: integer;
begin

	FrameSprite.NineSlice(page, atX, atY, 300, 22);
  atX += PanelSprite.border.left;
  atY += PanelSprite.border.top;
  {Custom positioning}
  atX += 5;
  atY -= 0;
  TextOut(page, atX+1, atY+1, s, RGBA.create(10, 10, 10, 100));
  TextOut(page, atX, atY, s, RGBA.create(245, 250, 253, 240));
end;

procedure InitGui();
begin
	Info('[init] GUI');

  panelSprite := TSprite.Create(LoadBMP('gui/panel.bmp'));
  panelSprite.Border := TBorder.Create(2,2,2,2);

  FrameSprite := TSprite.Create(LoadBMP('gui/ec_frame.bmp'));
  FrameSprite.Border := TBorder.Create(8,8,8,8);

end;

begin
	InitGui();
end.
