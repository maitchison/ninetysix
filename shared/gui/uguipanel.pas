unit uGuiPanel;

interface

uses
  uDebug,
  uTest,
  uUtils,
  uSprite,
  uRect,
  uGraph32,
  uColor,
  uGui;

type
  tGuiPanel = class(tGuiContainer)
  public
    constructor Create(rect: tRect; aText: string='');
  end;

implementation

constructor tGuiPanel.Create(rect: tRect; aText: string='');
var
  s: tSprite;
begin
  inherited Create();

  col := RGB(128,128,128);
  style := DEFAULT_GUI_SKIN.styles['panel'].clone();
  bounds := rect;

  enableDoubleBuffered();
end;

begin
end.
