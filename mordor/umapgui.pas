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
  uRes,
  uTileEditorGui,
  uMDRMap;

type

  tMapMode = (mmView, mmEdit, mmParty);

  tMapGUI = class(tGuiComponent)
  protected
    background: tSprite;
    cursorPos: tPoint;
    cursorDir: tDirection;
    // todo: make this sizeable
    isTileDirty: array[0..31, 0..31] of boolean;
  protected
    function  tilePos(x,y: integer): tPoint;
    procedure drawCursor(dc: tDrawContext);
    procedure invalidateTile(x,y: integer);
  const
    TILE_SIZE = 15;
  public
    map: tMDRMap;
    mode: tMapMode;
    tileEditor: tTileEditorGUI;
    constructor Create();
    destructor destroy(); override;
    procedure onKeyPress(code: word); override;
    procedure renderTile(dc: tDrawContext; x,y: integer);
    procedure moveCursor(dx,dy: integer);
    procedure setCursorPos(aPos: tPoint);
    procedure setCursorDir(d: tDirection);
    procedure doUpdate(elapsed: single); override;
    procedure doDraw(const dc: tDrawContext); override;
    procedure invalidate(); override;
  end;

implementation

{-------------------------------------------------------}

constructor tMapGUI.Create();
begin
  inherited Create();
  map := nil;
  mode := mmView;
  cursorPos.x := 0;
  cursorPos.y := 0;
  //background := tSprite.create(gfx['darkmap']);
  setSize(512, 512);
  tileEditor := nil;
  doubleBufferMode := dbmOff;
  invalidate();
end;

destructor tMapGUI.destroy();
begin
  inherited destroy();
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
  {in edit mode we own the cursor, so we need to move it when
   keys are pressed}
  if mode <> mmEdit then exit;
  case code of
    key_left: moveCursor(-1,0);
    key_right: moveCursor(+1,0);
    key_up: moveCursor(0,-1);
    key_down: moveCursor(0,+1);
    key_space:
      if assigned(map) and assigned(tileEditor) then begin
        tileEditor.applyToMapTile(map, cursorPos.x, cursorPos.y);
        invalidateTile(cursorPos.x, cursorPos.y);
      end;
  end;
end;

{renders a single map tile}
procedure tMapGUI.renderTile(dc: tDrawContext; x, y: integer);
var
  tile: tTile;
  wall: tWall;
  pos: tPoint;
  dx,dy: integer;
  id: integer;
  d: tDirection;
  padding : integer;
begin

  tile := map.tile[x,y].asExplored;

  pos := tilePos(x,y);

  {todo: support background}
  dc.fillRect(Rect(pos.x, pos.y, TILE_SIZE, TILE_SIZE), RGB(0,0,0));

  {floor}
  id := tile.floorSpec.spriteIdx;
  if id >= 0 then mapSprites.sprites[id].draw(dc, pos.x, pos.y);

  {medium}
  id := MEDIUM_SPRITE[tile.medium];
  if id >= 0 then mapSprites.sprites[id].draw(dc, pos.x, pos.y);

  {walls}
  for d in tDirection do begin
    wall := map.wall[x,y,d].asExplored;
    id := WALL_SPRITE[wall.t];
    if id < 0 then continue;
    dx := WALL_DX[d];
    dy := WALL_DY[d];
    if dy <> 0 then inc(id); // rotated varient
    mapSprites.sprites[id].draw(dc, pos.x+dx, pos.y+dy);
  end;

  {cursor}
  if (x = cursorPos.x) and (y = cursorPos.y) then
    drawCursor(dc);

  isTileDirty[x,y] := false;
end;

procedure tMapGUI.doUpdate(elapsed: single);
begin
  inherited doUpdate(elapsed);
  {hack for holding space}
  if keyDown(key_space) then onKeyPress(key_space);
end;

procedure tMapGUI.doDraw(const dc: tDrawContext);
var
  x,y: integer;
  flipDc: tDrawContext;
begin

  if not assigned(map) then exit();

  flipDC := dc;
  flipDC.clearFlags := FG_FLIP;

  for y := 0 to map.height-1 do
    for x := 0 to map.width-1 do
      if isTileDirty[x,y] then
        renderTile(flipDC, x, y);
end;

procedure tMapGui.drawCursor(dc: tDrawContext);
begin
  case mode of
    mmView: ;
    mmEdit: mapSprites.sprites[CURSOR_SPRITE].draw(
      dc,
      tilePos(cursorPos.x,cursorPos.y).x,
      tilePos(cursorPos.x,cursorPos.y).y
      );
    mmParty: mapSprites.sprites[PARTY_SPRITE+ord(cursorDir)].draw(
      dc,
      tilePos(cursorPos.x,cursorPos.y).x,
      tilePos(cursorPos.x,cursorPos.y).y
      );
  end;
end;

procedure tMapGui.moveCursor(dx,dy: integer);
begin
  setCursorPos(Point(cursorPos.x+dx, cursorPos.y+dy));
end;

procedure tMapGui.setCursorPos(aPos: tPoint);
var
  oldPos: tPoint;
begin
  oldPos := cursorPos;
  cursorPos.x := clamp(aPos.x, 0, map.width-1);
  cursorPos.y := clamp(aPos.y, 0, map.height-1);
  invalidateTile(oldPos.x, oldPos.y);
  invalidateTile(cursorPos.x, cursorPos.y);
end;

procedure tMapGui.setCursorDir(d: tDirection);
begin
  cursorDir := d;
  invalidateTile(cursorPos.x, cursorPos.y);
end;

end.
