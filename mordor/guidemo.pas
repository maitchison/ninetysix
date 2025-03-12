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
  guiSkin: tGuiSkin;

{-------------------------------------------------------}

procedure tGuiScene.run();
var
  timer: tTimer;
  elapsed: single;
  myButton: tGuiButton;
  myLabel: tGuiLabel;
  myPanel: tGuiPanel;
  myWindow: tGuiWindow;
begin

  timer := tTimer.create('main');

  myButton := tGuiButton.Create(Point(10, 100), 'Test button');
  gui.append(myButton);

  myLabel := tGuiLabel.MakeLabel(Point(10, 150), 'This is some text that is a bit longer.');
  gui.append(myLabel);

  myPanel := tGuiPanel.Create(Rect(300, 10, 200, 100));
  gui.append(myPanel);

  myWindow := tGuiWindow.Create(Rect(350, 10, 200, 400));
  gui.append(myWindow);

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

{todo: make this an ini file}
procedure initGui();
var
  style: tGuiStyle;

  function makeSprite(tag: string; aBorder: tBorder): tSprite;
  begin
    result := tSprite.Create(guiSkin.gfx[tag]);
    result.border := aBorder;
    result.innerBlendMode := ord(bmBlit); // faster
  end;

  procedure makeStateSprites(style: tGuiStyle; tag: string; aBorder: tBorder);
  var
    state: string;
    gfxName: string;
  begin
    for state in GUI_STATE_NAME do begin
      gfxName := tag+'_'+state;
      if guiSkin.gfx.hasResource(gfxName) then
        style.sprites[state] := makeSprite(gfxName, aBorder)
      else
        warning('Missing gui gfx: "'+gfxName+'"');
    end;
  end;

begin
  guiSkin := tGuiSkin.Create();
  guiSkin.gfx.loadFromFolder('gui', '*.p96');
  guiSkin.sfx.loadFromFolder('sfx', '*.a96');

  style := tGuiStyle.Create();
  guiSkin.styles['default'] := style;

  style := tGuiStyle.Create();
  style.padding.init(8,11,8,11);
  style.sprites['default'] := makeSprite('ec_box', Border(40,40,40,40));
  style.sprites['default'].innerBlendMode := ord(bmNone); // nothing to draw here
  guiSkin.styles['box'] := style;

  style := tGuiStyle.Create();
  style.padding.init(8,5,8,9);
  makeStateSprites(style, 'ec_button', Border(8,8,6,11));
  style.sounds['clickup'] := sfx['clickup'];
  style.sounds['clickdown'] := sfx['clickdown'];
  guiSkin.styles['button'] := style;

  style := tGuiStyle.Create();
  style.sprites['default'] := makeSprite('ec_toggle_off', Border(4,4,6,6));
  style.sprites['selected'] := makeSprite('ec_toggle_on', Border(4,4,6,6));
  guiSkin.styles['toggle'] := style;

  style := tGuiStyle.Create();
  style.padding.init(4,4,4,4);
  style.sprites['default'] := makeSprite('ec_panel', Border(4,4,4,4));
  guiSkin.styles['panel'] := style;

  DEFAULT_GUI_SKIN := guiSkin;
end;

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

  initGui();

  initMouse();
  initKeyboard();

  //musicPlay('res\prologue.a96');

  scene := tGuiScene.create();
  scene.run();
  scene.free();

  videoDriver.setText();

  logTimers();

  printLog(32);

end.
