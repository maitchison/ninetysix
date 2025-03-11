unit uGuiButton;

interface

uses
  debug,
  test,
  utils,
  sprite,
  graph32,
  graph2d,
  uColor,
  uGui;

type
  tGuiButton = class(tGuiComponent)
  public
    constructor Create(aPos: tPoint; aText: string='');
  end;

implementation

constructor tGuiButton.Create(aPos: tPoint; aText: string='');
var
  s: tSprite;
begin
  inherited Create();

  isInteractive := true;

  style := DEFAULT_GUI_SKIN.styles['button'].clone();

  fontStyle.centered := true;
  fontStyle.shadow := true;
  fontStyle.col := RGB(250, 250, 250, 230);

  bounds.x := aPos.x;
  bounds.y := aPos.y;

  text := aText;

  sizeToContent();

end;

begin
end.
