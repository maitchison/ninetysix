unit uScene;

interface

uses
  debug,
  test,
  utils,
  ui,
  uScreen;

type
  tScene = class
  public
    gui: tGuiComponents;
    screen: tScreen;
    constructor Create();
    destructor destroy(); override;
    procedure run(); virtual;
  end;

implementation

constructor tScene.Create();
begin
  inherited Create();
  gui := tGuiComponents.create();
  screen := tScreen.create();
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
