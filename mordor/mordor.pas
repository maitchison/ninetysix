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
  uColor,
  {$i gui.inc}
  {game stuff}
  uRes,
  uMapGui,
  uTileEditorGui,
  uScene,
  uEncounterGui,
  uMDRImporter,
  uMDRParty,
  uMDRMap;

type
  tMapEditScene = class(tScene)
  protected
    map: tMDRMap;
    mapGUI: tMapGUI;
    procedure onLoadClick(sender: tGuiComponent; msg: string; args: array of const);
    procedure onSaveClick(sender: tGuiComponent; msg: string; args: array of const);
    procedure loadMap();
    procedure saveMap();
    procedure importMap();
  public
    procedure run(); override;
  end;

  tGameScene = class(tScene)
  protected
    map: tMDRMap;
    party : tMDRParty;
    mapGUI: tMapGUI;
    encounterGUI: tEncounterGUI;
    procedure moveParty(turn: integer; move: integer);
    {todo: setup this up to auto hook, and then just override}

    procedure onKeyPress(sender: tGuiComponent; msg: string; args: array of const);
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

procedure tGameScene.moveParty(turn: integer; move: integer);
var
  tile: tTile;
  wall: tWall;
  dir: tDirection;
  pos: tPoint;
begin
  assert(abs(turn) <= 2);
  assert(abs(move) <= 1);

  pos := party.pos;
  dir := party.dir;

  dir := tDirection((4 + ord(dir) + turn) mod 4);
  party.dir := dir;
  mapGui.setCursorDir(dir);

  if map.wall[pos.x, pos.y, dir].isSolid then begin
    // play some sound?
    exit;
  end;

  pos.x += DX[dir] * move;
  pos.y += DY[dir] * move;

  party.pos := pos;
  mapGui.setCursorPos(pos);

  {todo: if we transit through a secret door then reveal it}

  {reveal new square}
  tile := map.tile[pos.x, pos.y];
  tile.status.explored := eFull;
  map.tile[pos.x, pos.y] := tile;
  for dir in tDirection do begin
    wall := map.wall[pos.x, pos.y, dir];
    wall.status.explored := ePartial;
    map.wall[pos.x, pos.y, dir] := wall;
  end;
end;

procedure tGameScene.onKeyPress(sender: tGuiComponent; msg: string; args: array of const);
var
  code: word;
  shift: boolean;
begin
  code := args[0].VInteger;
  shift := keyDown(key_leftshift) or keyDown(key_rightshift);

  case code of
    0: ;
    key_right: if shift then moveParty(1, 1) else moveParty(1, 0);
    key_left: if shift then moveParty(-1, 1) else moveParty(-1, 0);
    key_up: moveParty(0, 1);
    key_down: if shift then moveParty(2, 1) else moveParty(2, 0);
    key_z: begin
      map.setExplored(eFull);
      mapGui.invalidate();
    end;
  end;
end;

procedure tGameScene.run();
var
  elapsed: single;
  fpsLabel: tGuiLabel;
  timer: tTimer;
  dc: tDrawContext;
  panel: tGuiWindow;
const
  RHS_DIVIDE = 280;
  LOWER_DIVIDE = 160;
  UPPER_DIVIDE = 200;
begin

  uGui.GUI_DRAWMODE := gdmDirty;

  map := tMDRMap.Create(32,32);
  map.load('map.dat');
  map.setExplored(eNone);

  party := tMDRParty.create();
  party.pos := Point(5, 9);
  party.dir := dNorth;

  encounterGui := tEncounterGui.Create();

  mapGUI := tMapGui.Create();
  mapGUI.map := map;
  mapGUI.mode := mmParty;
  mapGUI.pos := Point(10,10);

  {create some pannels to map out what this should look like}
  panel := tGuiWindow.create(Rect(800-RHS_DIVIDE, 0, RHS_DIVIDE, 600 - LOWER_DIVIDE));
  panel.text := 'CHARACTER';
  panel.imageCol := RGBF(1.00,0.22,0.12);
  gui.append(panel);
  panel := tGuiWindow.create(Rect(800-RHS_DIVIDE, 600 - LOWER_DIVIDE, RHS_DIVIDE, LOWER_DIVIDE));
  panel.text := 'PARTY';
  gui.append(panel);
  panel := tGuiWindow.create(Rect(0, 600 - LOWER_DIVIDE, 800-RHS_DIVIDE, LOWER_DIVIDE));
  panel.text := 'LOG';
  gui.append(panel);

  panel := tGuiWindow.create(Rect(0, UPPER_DIVIDE, 800-RHS_DIVIDE, 600-LOWER_DIVIDE-UPPER_DIVIDE));
  panel.text := 'MAP';
  panel.append(mapGUI);
  gui.append(panel);

  panel := tGuiWindow.create(Rect(0, 0, 800-RHS_DIVIDE, UPPER_DIVIDE));
  panel.text := 'DUNGEON';
  panel.append(encounterGui);
  gui.append(panel);

  fpsLabel := tGuiLabel.Create(Point(10,10));
  fpsLabel.setSize(60, 21);
  gui.append(fpsLabel);



  timer := tTimer.create('main');
  dc := screen.getDC();

  gui.addHook(ON_KEYPRESS, self.onKeyPress);
  moveParty(0,0);

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

{-------------------------------------------------------}

procedure tMapEditScene.onSaveClick(sender: tGuiComponent; msg: string; args: array of const);
begin
  saveMap();
end;

procedure tMapEditScene.saveMap();
begin
  note('Saving map');
  map.save('map.dat');
end;

procedure tMapEditScene.loadMap();
begin
  note('Loading map');
  map.load('map.dat');
  mapGUI.invalidate();
end;

procedure tMapEditScene.importMap();
var
  importer: tMDRImporter;
begin
  note('Importing map');
  importer := tMDRImporter.Create();
  importer.load('res\mdata11.mdr');
  if assigned(map) then map.free;
  map := importer.readMap(1);
  mapGUI.invalidate();
end;

procedure tMapEditScene.onLoadClick(sender: tGuiComponent; msg: string; args: array of const);
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

  map := tMDRMap.create(32,32);

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
