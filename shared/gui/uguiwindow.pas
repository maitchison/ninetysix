unit uGuiWindow;

interface

uses
  debug,
  test,
  utils,
  sprite,
  graph32,
  graph2d,
  uColor,
  uScreen,
  uGui;

type
  tGuiWindow = class(tGuiContainer)
  protected
    background: tPage;
  public
    constructor Create(rect: tRect; aText: string='');
    procedure doDraw(screen: tScreen); override;
  end;

implementation

constructor tGuiWindow.Create(rect: tRect; aText: string='');
var
  s: tSprite;
begin
  inherited Create();
  col := RGB(128,128,128);
  style := DEFAULT_GUI_SKIN.styles['box'].clone();
  background := DEFAULT_GUI_SKIN.gfx['innerwindow'];
  bounds := rect;
end;

procedure tGuiWindow.doDraw(screen: tScreen);
var
  dc: tDrawContext;
begin
  inherited doDraw(screen);
  dc := screen.canvas.dc;
  //dc.tint := RGBF(0.40,0.42,0.62);
  dc.tint := RGBF(1.00,0.22,0.12);
  dc.stretchSubImage(background, innerBounds, background.bounds);
end;

begin
end.
