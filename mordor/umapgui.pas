unit uMapGUI;

interface

uses
  uTest,
  uDebug,
  uUtils,
  uGui,
  uRect,
  uGraph32,
  uSprite,
  uScreen,
  uColor,
  uKeyboard,
  uFont,
  {game stuff}
  res,
  uTileEditorGui,
  uMap;

type

  tMapMode = (mmView, mmEdit);

  tMapGUI = class(tGuiComponent)
  protected
    background: tSprite;
    cursor: tPoint;
    // todo: make this sizeable
    isTileDirty: array[0..31, 0..31] of boolean;
  protected
    function  tilePos(x,y: integer): tPoint;
    procedure drawCursor(dc: tDrawContext);
    procedure invalidateTile(x,y: integer);
  const
    TILE_SIZE = 15;
  public
    map: tMap;
    mode: tMapMode;
    tileEditor: tTileEditorGUI;
    constructor Create();
    destructor destroy(); override;
    procedure onKeyPress(code: word); override;
    procedure renderTile(dc: tDrawContext; x,y: integer);
    procedure moveCursor(dx,dy: integer);
    procedure doUpdate(elapsed: single); override;
    procedure doDraw(dc: tDrawContext); override;
    procedure invalidate(); override;
  end;

implementation

{-------------------------------------------------------}

constructor tMapGUI.Create();
begin
  inherited Create();
  map := nil;
  mode := mmView;
  cursor.x := 0;
  cursor.y := 0;
  //background := tSprite.create(gfx['darkmap']);
  setSize(512, 512);
  tileEditor := nil;
  doubleBufferMode := dbmBlit;
  invalidate();
end;

destructor tMapGUI.destroy();
begin
  inherited destroy;
end;

procedure tMapGUI.invalidate();
begin
  inherited invalidate();
  fillChar(isTileDirty, sizeof(isTileDirty), true);
  isDirty := true;
end;

{mark tile as needing to be redrawn}
procedure tMapGUI.invalidateTile(x,y: integer);
begin
  isTileDirty[x,y] := true;
  isDirty := true;
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
        invalidateTile(cursor.x, cursor.y);
      end;
  end;
end;

{renders a single map tile}
procedure tMapGUI.renderTile(dc: tDrawContext; x, y: integer);
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
  dc.fillRect(Rect(pos.x, pos.y, TILE_SIZE, TILE_SIZE), RGB(0,0,0));

  {floor}
  id := tile.floorSpec.spriteIdx;
  if id >= 0 then mapSprites.sprites[id].draw(dc, pos.x, pos.y);

  {medium}
  id := MEDIUM_SPRITE[tile.mediumType];
  if id >= 0 then mapSprites.sprites[id].draw(dc, pos.x, pos.y);

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

  {cursor}
  if (mode = mmEdit) and (x = cursor.x) and (y = cursor.y) then
    drawCursor(dc);

  isTileDirty[x,y] := false;
end;

procedure tMapGUI.doUpdate(elapsed: single);
begin
  inherited doUpdate(elapsed);
  {hack for holding space}
  if keyDown(key_space) then onKeyPress(key_space);
end;

procedure tMapGUI.doDraw(dc: tDrawContext);
  var
  x,y: integer;
begin
  if not assigned(map) then exit();

  for y := 0 to map.height-1 do
    for x := 0 to map.width-1 do
      if isTileDirty[x,y] then
        renderTile(dc, x, y);
end;

procedure tMapGui.drawCursor(dc: tDrawContext);
begin
  mapSprites.sprites[CURSOR_SPRITE].draw(
    dc,
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
  invalidateTile(oldCursor.x, oldCursor.y);
  invalidateTile(cursor.x, cursor.y);
end;

end.
