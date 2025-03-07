unit uMapGUI;

interface

uses
  test,
  debug,
  utils,
  ui,
  graph2d,
  graph32,
  sprite,
  uScreen,
  keyboard,
  font,
  {game stuff}
  res,
  uMap
  ;

type

  tMapMode = (mmView, mmEdit);

  tFloorSelectionGUI = class(tGuiComponent)
  protected
    selectedID: integer;
  public
    constructor Create(x,y: integer);
    procedure changeSelection(delta: integer);
    procedure onKeyPress(code: word); override;
    procedure doDraw(screen: tScreen); override;
  end;

  tMapGUI = class(tGuiComponent)
  protected
    background: tSprite;
    canvas: tPage;
    cSprite: tSprite; // todo: remove this and enabled pages to draw
    cursor: tPoint;
  protected
  function tilePos(x,y: integer): tPoint;
    procedure drawCursor();
  const
    TILE_SIZE = 15;
  public
    map: tMap;
    mode: tMapMode;
    constructor Create();
    destructor destroy(); override;
    procedure renderTile(x,y: integer);
    procedure moveCursor(dx,dy: integer);
    procedure doDraw(screen: tScreen); override;
    procedure refresh();
  end;

implementation

{-------------------------------------------------------}

constructor tFloorSelectionGUI.Create(x,y: integer);
begin
  inherited Create();
  bounds.init(x, y, 200, 32);
  selectedID := 0;
end;

procedure tFloorSelectionGUI.changeSelection(delta: integer);
begin
  {delta := delta mod length(tFloorTypes);
  selectedID := ((selectedID + delta + length(tiles)) mod length(tiles);
  }
end;

procedure tFloorSelectionGUI.onKeyPress(code: word);
begin
  case code of:
    Key_OpenSquareBracket: changeSelection(-1);
    Key_CloseSquareBracket: changeSelection(+1);
  end;
end;

procedure tFloorSelectionGUI.doDraw(screen: tScreen);
var
  ft: tFloorType;
  fs: tFloorSpec;
  i: integer;
begin
  screen.canvas.fillRect(bounds, RGB(0,0,0));
  screen.canvas.drawRect(bounds, RGB(255,255,255));
  for ft in tFloorType do begin
    i := ord(ft);
    fs := FLOOR_SPEC[ft];
    if fs.spriteIdx >= 0 then
      mapSprites.sprites[fs.spriteIdx].draw(screen.canvas, bounds.x+i*16, bounds.y);
    if i = selectedID then begin
      mapSprites.sprites[CURSOR_SPRITE].draw(screen.canvas, bounds.x+i*16, bounds.y);
      DEFAULT_FONT.textOut(screen.canvas, bounds.x+1, bounds.y+15, fs.tag, RGB(255,255,255));
    end;
  end;
  screen.markRegion(bounds);
end;

{-------------------------------------------------------}

constructor tMapGUI.Create();
begin
  inherited Create();
  map := nil;
  mode := mmView;
  cursor.x := 0;
  cursor.y := 0;
  //background := tSprite.create(gfx['darkmap']);
  bounds.width := 512;
  bounds.height := 512;
  canvas := tPage.create(bounds.width, bounds.height);
  cSprite := tSprite.create(canvas);
end;

destructor tMapGUI.destroy();
begin
  canvas.free;
  cSprite.free;
  inherited destroy;
end;

function tMapGUI.tilePos(x,y: integer): tPoint;
var
  padding: integer;
begin
  padding:= (512 - ((TILE_SIZE * 32)+1)) div 2;
  result.x := x*TILE_SIZE+padding;
  result.y := y*TILE_SIZE+padding;
end;

{renders a single map tile}
procedure tMapGUI.renderTile(x,y: integer);
var
  tile: tTile;
  pos: tPoint;
  dx,dy: integer;
  id: integer;
  i: integer;
  padding : integer;
begin

  tile := map.tile[x,y];

  pos := tilePos(x,y);

  {todo: support background}
  canvas.fillRect(Rect(pos.x, pos.y, TILE_SIZE, TILE_SIZE), RGB(0,0,0));

  {floor}
  id := tile.floorSpec.spriteIdx;
  if id >= 0 then mapSprites.sprites[id].draw(canvas, pos.x, pos.y);

  {medium}
  id := MEDIUM_SPRITE[tile.mediumType];
  if id >= 0 then mapSprites.sprites[id].draw(canvas, pos.x, pos.y);

  {walls}
  {
  for i := 0 to 3 do begin
    id := WALL_SPRITE[tile.wall[i].t];
    if id < 0 then continue;
    dx := WALL_DX[i];
    dy := WALL_DY[i];
    if dy <> 0 then inc(id); // rotated varient
    mapSprites.sprites[id].draw(screen.canvas, atX+dx, atY+dy);
  end;
  }

end;

procedure tMapGUI.doDraw(screen: tScreen);
begin
  cSprite.blit(screen.canvas, bounds.x, bounds.y);
  screen.markRegion(bounds);
end;

procedure tMapGui.drawCursor();
begin
  mapSprites.sprites[CURSOR_SPRITE].draw(
    canvas,
    tilePos(cursor.x,cursor.y).x,
    tilePos(cursor.x,cursor.y).y
  );
end;

procedure tMapGui.moveCursor(dx,dy: integer);
var
  oldCursor: tPoint;
begin
  oldCursor := cursor;
  cursor.x := clamp(cursor.x + dx, 0, map.width-1);
  cursor.y := clamp(cursor.y + dy, 0, map.height-1);
  renderTile(oldCursor.x, oldCursor.y);
  drawCursor;
end;

procedure tMapGui.refresh();
var
  x,y: integer;
begin
  if assigned(background) then
    background.draw(canvas, 0, 0);
  if not assigned(map) then exit();
  for y := 0 to map.height-1 do
    for x := 0 to map.width-1 do
      renderTile(x, y);
  if mode = mmEdit then
    drawCursor();
end;

end.
