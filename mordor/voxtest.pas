{test / benchmark for voxel stuff}
program voxTest;

uses
  uTest,
  uDebug,
  uUtils,
  uMouse,
  uKeyboard,
  uScreen,
  uScene,
  uTimer,
  uSound,
  uMixer,
  uInput,
  uGraph32,
  {$i gui.inc}
  uTileBuilder,
  uVESADriver,
  uVGADriver;

type
  tTestScene = class(tScene)
    procedure run(); override;
  end;

var
  screen: tScreen;
  scene: tTestScene;
  tileBuilder: tTileBuilder;


procedure setup();
begin
  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    fatal('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    fatal('Requires 1MB video card.');
  videoDriver.setTrueColor(800, 600);
  initMouse();
  initKeyboard();
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;
end;

procedure tTestScene.run();
var
  timer: tTimer;
  elapsed: single;
  dc: tDrawContext;
begin
  timer := startTimer('main');

  gui := tGui.Create();

  dc := screen.getDC();

  repeat

    timer.start();

    elapsed := clamp(timer.elapsed, 0.001, 0.1);
    if timer.avElapsed > 0 then
      fpsLabel.text := format('%.1f', [1/timer.avElapsed]);

    musicUpdate();

    input.update();

    gui.update(elapsed);
    gui.draw(dc);
    screen.flipAll();

    timer.stop();

  until keyDown(key_esc);


end;

begin
  setup();
  scene := tTestScene.Create();
  scene.run();
  videoDriver.setText();
  printLog(32);
end.
