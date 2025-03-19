unit uGuiLabel;

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
  tGuiLabel = class(tGuiComponent)
  protected
    procedure setText(aText: string); override;
  public
    autoSize: boolean;
  public
    class function MakeText(aPos: tPoint; aText: string=''): tGuiLabel;
    class function MakeLabel(aPos: tPoint; aText: string=''): tGuiLabel;
    constructor Create(aPos: tPoint; aText: string='');
  end;

implementation

{simple fixed size no-background text label}
class function tGuiLabel.MakeText(aPos: tPoint; aText: string=''): tGuiLabel;
begin
  result := tGuiLabel.Create(aPos, aText);
  result.backgroundCol := RGBA.Clear;
end;

{text with label, auto size}
class function tGuiLabel.MakeLabel(aPos: tPoint; aText: string=''): tGuiLabel;
begin
  result := tGuiLabel.Create(aPos, aText);
  result.backgroundCol := RGBA.White;
  result.autoSize := true;
  result.sizeToContent();
end;

constructor tGuiLabel.Create(aPos: tPoint; aText: string='');
begin
  inherited Create();

  bounds.x := aPos.x;
  bounds.y := aPos.y;

  guiStyle := DEFAULT_GUI_SKIN.styles['panel'].clone();

  fontStyle.centered := false;
  fontStyle.shadow := true;
  fontStyle.col := RGB(250, 250, 250, 230);

  guiStyle.padding := Border(3,3,3,3);

  autoSize := false;
  setBounds(Rect(aPos.x, aPos.y, 120, 20));

  backgroundCol := RGB(128, 128, 138);
  text := aText;
end;

procedure tGuiLabel.setText(aText: string);
begin
  inherited setText(aText);
  if autoSize then
    sizeToContent();
end;

begin
end.
