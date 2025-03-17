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
  guiStyle := DEFAULT_GUI_SKIN.styles['box'].clone();
  fImage := DEFAULT_GUI_SKIN.gfx.getWithDefault('innerwindow', nil);
  fImageCol := RGBF(0.40,0.42,0.62);
  fontStyle.centered := true;
  fontStyle.shadow := true;
  setBounds(aRect);
end;

begin
end.
