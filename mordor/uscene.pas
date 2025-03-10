unit uScene;

interface

uses
  debug,
  test,
  utils,
  uGui,
  uScreen,
  graph2d;

type
  tScene = class
  public
    gui: tGui;
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
  gui := tGui.create();
  screen := tScreen.create();

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
