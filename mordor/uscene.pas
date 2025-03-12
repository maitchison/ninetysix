unit uScene;

interface

uses
  uDebug,
  uTest,
  {$i gui.inc}
  uUtils,
  uRect,
  uScreen;

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
  gui := tGui.Create();
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
