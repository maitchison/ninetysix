unit uGuiPanel;

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
end;

begin
end.
