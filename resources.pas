unit Resources;

interface

uses
  graph32,
  graph2d,
  sprite;

var
  ButtonSprite: TSprite;
  BoxSprite: TSprite;
  PanelSprite: TSprite;
  FrameSprite: TSprite;

procedure LoadGFX();

implementation

function MakeSprite(filename: string; Border: TBorder): TSprite;
var page: TPage;
begin
  page := LoadBMP('gui\'+filename+'.bmp');
  result := TSprite.Create(page);
  result.Border := Border;
end;

procedure LoadGFX();
begin
  ButtonSprite := MakeSprite('EC_SquareButton_Normal', TBorder.Create(14,14,14,14));
  BoxSprite := MakeSprite('EC_Box_Brown', TBorder.Create(20,20,20,20));
  PanelSprite := MakeSprite('Panel', TBorder.Create(4,4,4,4));
  FrameSprite := MakeSprite('EC_Frame', TBorder.Create(4,4,4,4));
end;

begin
end.
