unit uGuiLabel;

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
  tGuiLabel = class(tGuiComponent)
  protected
    procedure setText(aText: string); override;
  public
    autoSize: boolean;
  public
    constructor Create(aPos: tPoint; aText: string='');
  end;

implementation

constructor tGuiLabel.Create(aPos: tPoint; aText: string='');
begin
  inherited Create();
  bounds.x := aPos.x;
  bounds.y := aPos.y;

  style := DEFAULT_GUI_SKIN.styles['panel'].clone();

  fontStyle.centered := true;
  fontStyle.shadow := true;
  fontStyle.col := RGB(250, 250, 250, 230);

  col := RGBA.Clear;
  text := aText;
  autoSize := true;
end;

procedure tGuiLabel.setText(aText: string);
begin
  {todo: set dirty}
  inherited setText(aText);
  if autoSize then
    bounds := font.textExtents(text, bounds.topLeft);
end;

begin
end.