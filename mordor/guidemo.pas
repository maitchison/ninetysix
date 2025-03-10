{demonstrate the gui}
program guiDemo;

uses
  {engine stuff}
  debug,
  test,
  utils,
  crt,
  sbDriver,
  mixLib,
  graph2d,
  graph32,
  resource,
  keyboard,
  vga,
  vesa,
  sound,
  uMouse,
  uScreen,
  uInput,
  uTimer,
  uScene,
  uGui;


type
  tGuiScene = class(tScene)
    procedure run(); override;
  end;

var
  scene: tGuiScene;
  gfx: tGFXLibrary;
  sfx: tSFXLibrary;

{-------------------------------------------------------}

procedure tGuiScene.run();
var
  timer: tTimer;
  elapsed: single;
begin

  timer := tTimer.create('main');

  repeat

    timer.start();

    elapsed := clamp(timer.elapsed, 0.001, 0.1);
    if timer.avElapsed > 0 then
      fpsLabel.text := format('%.1f', [1/timer.avElapsed]);

    musicUpdate();

    input.update();

    gui.update(elapsed);
    screen.clearAll();
    gui.draw(screen);
    screen.flipAll();

    timer.stop();

  until keyDown(key_esc);

end;

{-------------------------------------------------------}

begin

  autoHeapSize();

  textAttr := White + Blue*16;
  clrscr;

  debug.VERBOSE_SCREEN := llNote;

  runTestSuites();

  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    fatal('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    fatal('Requires 1MB video card.');
  videoDriver.setTrueColor(800, 600);

  gfx := tGFXLibrary.Create(true);
  gfx.loadFromFolder('res', '*.p96');
  sfx := tSFXLibrary.Create(true);
  sfx.loadFromFolder('res', '*.a96');


  initMouse();
  initKeyboard();

  musicPlay('res\prologue.a96');

  {init sounds}
  DEFAULT_MOUSEDOWN_SFX := sfx['clickdown'];
  DEFAULT_MOUSECLICK_SFX := sfx['clickup'];

  scene := tGuiScene.create();
  scene.run();
  scene.free();

  videoDriver.setText();

  logTimers();

  printLog(32);

end.
