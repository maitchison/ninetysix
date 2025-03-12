program mordor;

uses
  {engine stuff}
  uDebug,
  uTest,
  uVesaDriver,
  uSBDriver,
  uVGADriver,
  uMixer,
  uKeyboard,
  uTimer,
  crt,
  uInput,
  uMouse,
  uScreen,
  uGraph32,
  uSprite,
  uLA96,
  uUtils,
  uRect,
  uResource,
  {$i gui.inc}
  {game stuff}
  res,
  uMapGUI,
  uScene,
  uMap
  ;

type
  tMapEditScene = class(tScene)
  protected
    map: tMap;
    mapGUI: tMapGUI;
  public
    constructor Create();
    destructor Destroy(); override;
    procedure run(); override;
  end;

var
  screen: tScreen;
  scene: tMapEditScene;

procedure setup();
begin
  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    fatal('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    fatal('Requires 1MB video card.');
  videoDriver.setTrueColor(800, 600);
  //musicPlay('res\mordor.a96');
  initMouse();
  initKeyboard();
  initGuiSkinEpic();
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;

  loadResources();
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

(*
procedure encounterScreen();

var
  frame,m1,m2: tSprite;
  atX,atY: integer;
begin
  //screen.pageClear();

  frame := tSprite.Create(gfx['frame']);
  m1 := tSprite.Create(gfx['wolf96']);
  m2 := tSprite.Create(gfx['hobgob96']);

  atX := 100;
  atY := 100;

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
*)

{-------------------------------------------------------}

procedure makeRandomMap(map: tMap);
var
  x,y: integer;
  i: integer;
  tile: tTile;
begin
  map.clear();
  for y := 0 to map.height-1 do begin
    for x := 0 to map.width-1 do begin
      tile.clear();
      case rnd(10) of
        0: tile.floorType := ftStone;
        else tile.floorType := ftStone;
      end;
      case rnd(10) of
        2: tile.mediumType := mtRock;
      end;
      map.tile[x,y] := tile;
    end;
  end;

  (*
  {stub: walls}
  map.tile[0,0].medium.t := mtRock;
  map.tile[1,0].medium.t := mtRock;
  map.tile[0,1].medium.t := mtRock;
  map.tile[1,1].medium.t := mtRock;
  map.tile[0,0].wall[0].t := wtWall;
  map.tile[0,0].wall[1].t := wtWall;
  map.tile[0,0].wall[2].t := wtWall;
  map.tile[0,0].wall[3].t := wtWall;
  map.tile[1,1].wall[0].t := wtWall;
  map.tile[1,1].wall[1].t := wtWall;
  map.tile[1,1].wall[2].t := wtWall;
  map.tile[1,1].wall[3].t := wtWall;
  *)
end;

{-------------------------------------------------------}

constructor tMapEditScene.Create();
begin
  inherited Create();
end;

destructor tMapEditScene.destroy();
begin
  map.free();
  inherited destroy();
end;

procedure onSaveClick(sender: tGuiComponent; msg: string; args: array of const);
begin
  note('Saving map');
  scene.map.save('map.dat');
end;

procedure onLoadClick(sender: tGuiComponent; msg: string; args: array of const);
begin
  note('Loading map');
  scene.map.load('map.dat');
  scene.mapGUI.invalidate();
end;

procedure tMapEditScene.run();
var
  elapsed: single;
  editGUI: tTileEditorGUI;
  saveButton, loadButton: tGuiButton;
  fpsLabel: tGuiLabel;
  timer: tTimer;
  dc: tDrawContext;
begin

  map := tMap.create(32,32);

  screen.background := gfx['title800'];
  screen.pageClear();
  screen.pageFlip();

  editGui := tTileEditorGUI.Create(512+20+20,10);
  gui.append(editGUI);

  mapGUI := tMapGui.Create();
  mapGUI.map := map;
  mapGUI.mode := mmEdit;
  mapGUI.pos := Point(20, 50);
  mapGUI.tileEditor := editGui;
  gui.append(mapGUI);

  saveButton := tGuiButton.create(Point(650,400), 'Save');
  savebutton.addHook(ON_MOUSE_CLICK, onSaveClick);
  gui.append(saveButton);
  loadButton := tGuiButton.create(Point(650,450), 'Load');
  loadbutton.addHook(ON_MOUSE_CLICK, onLoadClick);
  gui.append(loadButton);

  fpsLabel := tGuiLabel.Create(Point(10,10));
  gui.append(fpsLabel);

  makeRandomMap(map);
  mapGUI.invalidate();

  timer := tTimer.create('main');
  dc := screen.getDC();

  repeat

    timer.start();

    elapsed := clamp(timer.elapsed, 0.001, 0.1);
    if timer.avElapsed > 0 then
      fpsLabel.text := format('%.1f', [1/timer.avElapsed]);

    musicUpdate();

    input.update();

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
