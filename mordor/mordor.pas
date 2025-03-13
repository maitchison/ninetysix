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
  uRes,
  uGameState,
  uMapGui,
  uTileEditorGui,
  uScene,
  uMDRImporter,
  uMDRParty,
  uMDRMap;

type
  tMapEditScene = class(tScene)
  protected
    mapGUI: tMapGUI;
  public
    procedure run(); override;
  end;

  tGameScene = class(tScene)
  protected
    mapGUI: tMapGUI;
  public
    procedure run(); override;
  end;

var
  screen: tScreen;
  scene: tScene;

{-------------------------------------------------------}

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

{-------------------------------------------------------}

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

procedure makeRandomMap(map: tMDRMap);
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
        0: tile.floor := ftStone;
        else tile.floor := ftStone;
      end;
      case rnd(10) of
        2: tile.medium := mtRock;
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

procedure tGameScene.run();
var
  elapsed: single;
  fpsLabel: tGuiLabel;
  timer: tTimer;
  dc: tDrawContext;
begin

  gs.map := tMDRMap.Create(32,32);
  gs.exploredMap := tMDRMap.Create(32,32);
  gs.map.load('map.dat');
  gs.map.setExplored(eFull);
  gs.exploredMap.load('map.dat');
  gs.map.setExplored(eNone);

  gs.party := tMDRParty.create();
  gs.party.pos := Point(9, 11);
  gs.party.dir := dNorth;

  screen.background := gfx['title800'];
  screen.pageClear();
  screen.pageFlip();

  mapGUI := tMapGui.Create();
  mapGUI.map := gs.map;
  mapGUI.mode := mmParty;
  mapGUI.pos := Point(20, 50);
  gui.append(mapGUI);

  fpsLabel := tGuiLabel.Create(Point(10,10));
  gui.append(fpsLabel);

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

procedure onSaveClick(sender: tGuiComponent; msg: string; args: array of const);
begin
  note('Saving map');
  gs.map.save('map.dat');
end;

procedure loadMap();
begin
  note('Loading map');
  gs.map.load('map.dat');
  // hmm... how to do this?
  //scene.mapGUI.invalidate();
end;

procedure importMap();
var
  importer: tMDRImporter;
begin
  note('Importing map');
  importer := tMDRImporter.Create();
  importer.load('res\mdata11.mdr');
  if assigned(gs.map) then gs.map.free;
  gs.map := importer.readMap(1);
  // hmm... how to do this?
  //scene.mapGUI.invalidate();
end;

procedure onLoadClick(sender: tGuiComponent; msg: string; args: array of const);
begin
  importMap();
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

  gs.map := tMDRMap.create(32,32);

  screen.background := gfx['title800'];
  screen.pageClear();
  screen.pageFlip();

  editGui := tTileEditorGUI.Create(512+20+20,10);
  gui.append(editGUI);

  mapGUI := tMapGui.Create();
  mapGUI.map := gs.map;
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

  makeRandomMap(gs.map);
  mapGUI.invalidate();

  timer := tTimer.create('main');
  dc := screen.getDC();

  importMap();

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
  scene := tGameScene.Create();
  scene.run();
  scene.free();

  videoDriver.setText();

  logTimers();

  printLog(32);

end.
