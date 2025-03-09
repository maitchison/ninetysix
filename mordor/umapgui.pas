unit uMapGUI;

interface

uses
  test,
  debug,
  utils,
  uGui,
  graph2d,
  graph32,
  sprite,
  uScreen,
  uColor,
  keyboard,
  font,
  {game stuff}
  res,
  uMap;

type

  tMapMode = (mmView, mmEdit);
  tEditMode = (emFloor);

  {todo: change to tile editor, and show / change all types}
  tTileEditorGUI = class(tGuiComponent)
  protected
    fFloorType: tFloorType;
    fEditMode: tEditMode;
  public
    constructor Create(x,y: integer);
    procedure changeSelection(delta: integer);
    procedure applyToMapTile(map: tMap; atX, atY: integer);
    procedure onKeyPress(code: word); override;
    procedure doDraw(screen: tScreen); override;
    property floorType: tFloorType read fFloorType;
    property editMode: tEditMode read fEditMode;
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
    tileEditor: tTileEditorGUI;
    constructor Create();
    destructor destroy(); override;
    procedure onKeyPress(code: word); override;
    procedure renderTile(x,y: integer);
    procedure moveCursor(dx,dy: integer);
    procedure doUpdate(elapsed: single); override;
    procedure doDraw(screen: tScreen); override;
    procedure refresh();
  end;

implementation

{-------------------------------------------------------}

constructor tTileEditorGUI.Create(x,y: integer);
begin
  inherited Create();
  bounds.init(x, y, 200, 200);
  fEditMode := emFloor;
  fFloorType := ftStone;
end;

procedure tTileEditorGUI.applyToMapTile(map: tMap; atX, atY: integer);
var
  tile: tTile;
begin
  case editMode of
    emFloor: begin
      tile := map.tile[atX, atY];
      tile.floorType := fFloorType;
      map.tile[atX, atY] := tile;
    end;
  end;
end;

procedure tTileEditorGUI.changeSelection(delta: integer);
begin
  fFloorType := tFloorType(clamp(ord(fFloorType) + delta, 0, length(FLOOR_SPEC)-1));
end;

procedure tTileEditorGUI.onKeyPress(code: word);
begin
  case code of
    Key_OpenSquareBracket: changeSelection(-1);
    Key_CloseSquareBracket: changeSelection(+1);
  end;
end;

procedure tTileEditorGUI.doDraw(screen: tScreen);
var
  ft: tFloorType;
  fs: tFloorSpec;
  i: integer;
begin

  screen.canvas.dc.fillRect(bounds, RGB(0,0,0));
  screen.canvas.dc.drawRect(bounds, RGB(255,255,255));
  for ft in tFloorType do begin
    i := ord(ft);
    fs := FLOOR_SPEC[ft];
    if fs.spriteIdx >= 0 then
      mapSprites.sprites[fs.spriteIdx].draw(screen.canvas, bounds.x+i*16, bounds.y);
    if ft = floorType then begin
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
  tileEditor := nil;
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

procedure tMapGUI.onKeyPress(code: word);
begin
  case code of
    key_left: moveCursor(-1,0);
    key_right: moveCursor(+1,0);
    key_up: moveCursor(0,-1);
    key_down: moveCursor(0,+1);
    key_space:
      if assigned(map) and assigned(tileEditor) then begin
        tileEditor.applyToMapTile(map, cursor.x, cursor.y);
        renderTile(cursor.x, cursor.y);
        drawCursor();
      end;
  end;
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
  canvas.dc.fillRect(Rect(pos.x, pos.y, TILE_SIZE, TILE_SIZE), RGB(0,0,0));

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

procedure tMapGUI.doUpdate(elapsed: single);
begin
  inherited doUpdate(elapsed);
  {hack for holding space}
  if keyDown(key_space) then onKeyPress(key_space);
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
