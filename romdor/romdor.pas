program romdor;

uses
  {engine stuff}
  debug,
  test,
  sbDriver,
  mixlib,
  vesa,
  keyboard,
  timer,
  vga,
  crt,
  mouse,
  uScreen,
  graph32,
  sprite,
  lc96,
  utils,
  ui,
  resource,
  {game stuff}
  uScene,
  uMap
  ;

var
  screen: tScreen;
  gfx: tGFXLibrary;
  mapSprites: tSpriteSheet;

type
  tMapGUI = class(tGuiComponent)
  protected
    map: tMap;
  public
    constructor Create();
    procedure drawTile(screen: tScreen; x,y: integer);
    procedure doDraw(screen: tScreen); override;
  end;

type
  tMapEditScene = class(tScene)
  protected
    map: tMap;
  public
    constructor Create();
    destructor Destroy(); override;
    procedure run(); override;
  end;

procedure setup();
begin
  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    fatal('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    fatal('Requires 1MB video card.');
  videoDriver.setTrueColor(800, 600);
  musicPlay('res\mordor.a96');
  initMouse();
  initKeyboard();
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;

  {load resources}
  gfx := tGFXLibrary.Create();
  gfx.loadFromFolder('res', '*.p96');

  mapSprites := tSpriteSheet.create(gfx['map']);
  mapSprites.grid(16,16);

end;

procedure titleScreen();
begin
  screen.background := gfx['title800.p96'];
  screen.pageClear();
  screen.pageFlip();

  repeat
    musicUpdate();
  until keyDown(key_esc) or keyDown(key_space);

  freeAndNil(screen.background);
end;

procedure encounterScreen();

var
  frame,m1,m2: tSprite;
  atX,atY: integer;
begin
  //screen.pageClear();

  frame := tSprite.Create(tPage.Load('res/frame.p96'));
  m1 := tSprite.Create(tPage.Load('res/wolf96.p96'));
  m2 := tSprite.Create(tPage.Load('res/hobgob96.p96'));

  atX := 100;
  atY := 200;

  m1.draw(screen.canvas, atX,atY);
  frame.draw(screen.canvas, atX,atY);
  m2.draw(screen.canvas, atX+(96+10)*1,atY);
  frame.draw(screen.canvas, atX+(96+10)*1,atY);
  m1.draw(screen.canvas, atX+(96+10)*2,atY);
  frame.draw(screen.canvas, atX+(96+10)*2,atY);
  m1.draw(screen.canvas, atX+(96+10)*3,atY);
  frame.draw(screen.canvas, atX+(96+10)*3,atY);

  screen.pageFlip();

  repeat
    musicUpdate();
  until keyDown(key_esc);

  freeAndNil(screen.background);
end;

{-------------------------------------------------------}

constructor tMapGUI.Create();
begin
  inherited Create();
  map := nil;
  bounds.width := 32*8;
  bounds.height := 32*8;
end;

{renders a single map tile}
procedure tMapGUI.drawTile(screen: tScreen; x,y: integer);
begin

end;

procedure tMapGUI.doDraw(screen: tScreen);
var
  x,y: integer;
begin
  screen.canvas.fillRect(bounds, RGB(0,0,0));
  screen.canvas.drawRect(bounds, RGB(128,128,128));
  screen.markRegion(bounds);
  if not assigned(map) then exit();
  for y := 0 to map.height-1 do begin
    for x := 0 to map.width-1 do begin
      drawTile(screen, x,y);
    end;
  end;
end;

{-------------------------------------------------------}

procedure makeRandomMap(map: tMap);
var
  x,y: integer;
begin
  map.clear();
  for y := 0 to map.height-1 do begin
    for x := 0 to map.width-1 do begin
      case rnd(2) of
        0: map.tile[x,y].floor.t := ftStone;
        1: map.tile[x,y].floor.t := ftWater;
      end;
    end;
  end;
end;

{-------------------------------------------------------}

constructor tMapEditScene.Create();
begin
  inherited Create();
  map := tMap.create(32,32);
end;

destructor tMapEditScene.destroy();
begin
  map.free();
  inherited destroy();
end;

procedure tMapEditScene.run();
var
  elapsed: single;
  mapGUI: tMapGUI;
begin

  screen.background := gfx['title800'];
  screen.pageClear();
  screen.pageFlip();

  elapsed := 0.01; // todo: update this}

  mapGUI := tMapGui.create();
  mapGUI.map := map;
  mapGUI.bounds.x := 100;
  mapGUI.bounds.y := 100;
  gui.append(mapGUI);

  makeRandomMap(map);

  repeat
    screen.clearAll();
    musicUpdate();

    gui.update(elapsed);
    gui.draw(screen);

    screen.flipAll();
  until keyDown(key_esc);
end;

{-------------------------------------------------------}

var
  scene: tScene;

begin

  autoHeapSize();

  textAttr := White + Blue*16;
  clrscr;

  debug.VERBOSE_SCREEN := llNote;

  runTestSuites();

  setup();

  //titleScreen();
  //encounterScreen();
  scene := tMapEditScene.create();
  scene.run();
  scene.free();

  videoDriver.setText();

  logTimers();

  printLog(32);

end.
