unit uGuiWindow;

interface

uses
  uDebug,
  uTest,
  uUtils,
  uSprite,
  uRect,
  uGraph32,
  uColor,
  uScreen,
  uGui;

type
  tGuiWindow = class(tGuiContainer)
  public
    constructor Create(aRect: tRect; aText: string='');
  end;

implementation

constructor tGuiWindow.Create(aRect: tRect; aText: string='');
var
  s: tSprite;
begin
  inherited Create();
  col := RGBA.White;
  style := DEFAULT_GUI_SKIN.styles['box'].clone();
  background := DEFAULT_GUI_SKIN.gfx.getWithDefault('innerwindow', nil);
  //backgroundCol := RGBF(0.40,0.42,0.62);
  backgroundCol := RGBF(1.00,0.22,0.12);
  fontStyle.centered := true;
  fontStyle.shadow := true;
  setBounds(aRect);
end;

begin
end.
