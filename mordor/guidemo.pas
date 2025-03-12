{demonstrate the gui}
program guiDemo;

uses
  uDebug,
  uTest,
  crt,
  {$i gui.inc}
  uUtils,
  uSBDriver,
  uVgaDriver,
  uVesaDriver,
  uMixer,
  uRect,
  uGraph32,
  uResource,
  uKeyboard,
  uSound,
  uSprite,
  uMouse,
  uScreen,
  uColor,
  uInput,
  uTimer,
  uScene;

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
  myButton: tGuiButton;
  myLabel: tGuiLabel;
  myPanel: tGuiPanel;
  myWindow: tGuiWindow;
  dc: tDrawContext;
begin

  timer := tTimer.create('main');

  myLabel := tGuiLabel.MakeLabel(Point(10, 150), 'This is some text that is a bit longer.');
  gui.append(myLabel);

  myPanel := tGuiPanel.Create(Rect(300, 10, 200, 100));
  gui.append(myPanel);

  myWindow := tGuiWindow.Create(Rect(350, 20, 200, 400));
  gui.append(myWindow);

  myButton := tGuiButton.Create(Point(5, 5), 'Test button');
  myWindow.append(myButton);

  repeat

    timer.start();

    elapsed := clamp(timer.elapsed, 0.001, 0.1);
    if timer.avElapsed > 0 then
      fpsLabel.text := format('%.1f', [1/timer.avElapsed]);

    musicUpdate();

    input.update();

    dc := screen.getDc;

    gui.update(elapsed);
    screen.clearAll();
    gui.draw(dc);
    screen.flipAll();

    timer.stop();

  until keyDown(key_esc);

end;

{-------------------------------------------------------}

begin

  autoHeapSize();

  textAttr := White + Blue*16;
  clrscr;

  uDebug.VERBOSE_SCREEN := llNote;

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
  sfx.loadFromFolder('sfx', '*.a96');

  initMouse();
  initKeyboard();
  initGuiSkinEpic();

  //musicPlay('res\prologue.a96');

  scene := tGuiScene.create();
  scene.run();
  scene.free();

  videoDriver.setText();

  logTimers();

  printLog(32);

end.
