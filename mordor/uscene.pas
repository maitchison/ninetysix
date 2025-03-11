unit uScene;

interface

uses
  debug,
  test,
  {$i gui.inc}
  utils,
  uScreen,
  graph2d;

type
  tScene = class
  public
    gui: tGuiContainer;
    screen: tScreen;
    fpsLabel: tGuiLabel;
    constructor Create();
    destructor destroy(); override;
    procedure run(); virtual;
  end;

implementation

constructor tScene.Create();
begin
  inherited Create();
  gui := tGuiContainer.Create();
  screen := tScreen.Create();

  {default gui}
  fpsLabel := tGuiLabel.Create(Point(10,10));
  gui.append(fpsLabel);
end;

destructor tScene.destroy();
begin
  gui.free();
  screen.free();
end;

procedure tScene.run();
begin
  {descendant to override}
end;

end.
