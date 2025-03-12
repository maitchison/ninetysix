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
  protected
    background: tPage;
  public
    constructor Create(rect: tRect; aText: string='');
    procedure doDraw(dc: tDrawContext); override;
  end;

implementation

constructor tGuiWindow.Create(rect: tRect; aText: string='');
var
  s: tSprite;
begin
  inherited Create();
  col := RGBA.White;
  style := DEFAULT_GUI_SKIN.styles['box'].clone();
  background := DEFAULT_GUI_SKIN.gfx['innerwindow'];
  bounds := rect;
  enableDoubleBuffered();
end;

procedure tGuiWindow.doDraw(dc: tDrawContext);
var
  oldDc: tDrawContext;
begin
  inherited doDraw(dc);
  //dc.tint := RGBF(0.40,0.42,0.62);
  dc.tint *= RGBF(1.00,0.22,0.12);
  dc.stretchImage(background, innerBounds);
end;

begin
end.
