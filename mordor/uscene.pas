unit uScene;

interface

uses
  debug,
  test,
  utils,
  uGui,
  uScreen;

type
  tScene = class
  public
    gui: tGui;
    screen: tScreen;
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
