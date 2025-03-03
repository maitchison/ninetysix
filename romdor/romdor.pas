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
  graph2d,
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
    background: tSprite;
  const
    TILE_SIZE = 15;
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

{-------------------------------------------------------}

constructor tMapGUI.Create();
begin
  inherited Create();
  map := nil;
  background := tSprite.create(gfx['darkmap']);
  bounds.width := 512;
  bounds.height := 512;
end;

{renders a single map tile}
procedure tMapGUI.drawTile(screen: tScreen; x,y: integer);
var
  tile: tTile;
  atX, atY: integer;
  dx,dy: integer;
  id: integer;
  i: integer;
  padding : integer;
begin
  padding:= (512 - ((TILE_SIZE * 32)+1)) div 2;
  atX := bounds.x + x*TILE_SIZE+padding;
  atY := bounds.y + y*TILE_SIZE+padding;
  tile := map.tile[x,y];

  {grid}
  screen.canvas.drawRect(Rect(atX, atY, 16, 16), RGB(0,0,0,32));

  {floor}
  id := FLOOR_SPRITE[tile.floor.t];
  if id >= 0 then mapSprites.sprites[id].draw(screen.canvas, atX, atY);

  {medium}
  id := MEDIUM_SPRITE[tile.medium.t];
  if id >= 0 then mapSprites.sprites[id].draw(screen.canvas, atX, atY);

  {walls}
  for i := 0 to 3 do begin
    id := WALL_SPRITE[tile.wall[i].t];
    if id < 0 then continue;
    dx := WALL_DX[i];
    dy := WALL_DY[i];
    if dy <> 0 then inc(id); // rotated varient
    mapSprites.sprites[id].draw(screen.canvas, atX+dx, atY+dy);
  end;

end;

procedure tMapGUI.doDraw(screen: tScreen);
var
  x,y: integer;
begin
  //screen.canvas.fillRect(bounds, RGB(0,0,0));
  //screen.canvas.drawRect(bounds, RGB(128,128,128));
  background.draw(screen.canvas, bounds.x, bounds.y);

  screen.markRegion(bounds);
  if not assigned(map) then exit();
  for y := 0 to map.height-1 do begin
    for x := 0 to map.width-1 do begin
      drawTile(screen, x, y);
    end;
  end;
end;

{-------------------------------------------------------}

procedure makeRandomMap(map: tMap);
var
  x,y: integer;
  i: integer;
begin
  map.clear();
  for y := 0 to map.height-1 do begin
    for x := 0 to map.width-1 do begin
      case rnd(10) of
        1: map.tile[x,y].floor.t := ftWater;
        2: map.tile[x,y].floor.t := ftDirt;
        3: map.tile[x,y].floor.t := ftGrass;
        else map.tile[x,y].floor.t := ftStone;
      end;
      case rnd(10) of
        1: map.tile[x,y].medium.t := mtMist;
        2: map.tile[x,y].medium.t := mtRock;
      end;
    end;
  end;

  {boundary}
  for i := 0 to 31 do begin
    map.tile[i,0].medium.t := mtRock;
    map.tile[i,31].medium.t := mtRock;
    map.tile[0,i].medium.t := mtRock;
    map.tile[31,i].medium.t := mtRock;
  end;

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
  mapGUI.bounds.x := 50;
  mapGUI.bounds.y := 50;
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
