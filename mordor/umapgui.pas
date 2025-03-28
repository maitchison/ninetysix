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
  uTimer,
  {game stuff}
  uMDRRes,
  uTileEditorGui,
  uMDRMap;

type

  tMapMode = (mmView, mmEdit, mmParty);

  tMapGUI = class(tGuiComponent)
  protected
    background: tSprite;
    tileBuffer: tPage;
    cursorPos: tPoint;
    cursorDir: tDirection;
    // todo: make this sizeable
    isTileDirty: array[0..31, 0..31] of boolean;
  protected
    function  tilePos(x,y: integer): tPoint;
    procedure drawCursor(dc: tDrawContext);
    procedure invalidateTile(x,y: integer);
    procedure renderTileBufferShadow();
  const
    TILE_SIZE = 15;
  public
    map: tMDRMap;
    mode: tMapMode;
    tileEditor: tTileEditorGUI;
    constructor Create();
    destructor destroy(); override;
    procedure onKeyPress(code: word); override;
    procedure renderTile(aDC: tDrawContext; x,y: integer);
    procedure moveCursor(dx,dy: integer);
    procedure setCursorPos(aPos: tPoint);
    procedure setCursorDir(d: tDirection);
    procedure doUpdate(elapsed: single); override;
    procedure doDraw(const dc: tDrawContext); override;
    procedure invalidate(); override;
  end;

implementation

type
  tBackgroundMode = (BM_NONE, BM_GRAY, BM_BLACK, BM_CHECKER, BM_IMAGE);

const BACKGROUND_MODE: tBackgroundMode = BM_IMAGE;

{-------------------------------------------------------}

constructor tMapGUI.Create();
begin
  inherited Create();
  map := nil;
  mode := mmView;
  cursorPos.x := 0;
  cursorPos.y := 0;
  background := tSprite.create(mdr.gfx['bgdark']);
  tileBuffer := tPage.create(TILE_SIZE+1, TILE_SIZE+1);
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

procedure renderTileBufferShadow_REF(page: tPage);
var
  x,y: integer;
  c: RGBA;
  v: byte;
  offset: dword;
  pixelPtr: pRGBA;
  dc: tDrawContext;
begin
  assert(page.width=16);
  assert(page.height=16);
  dc := page.getDC(bmBlit);
  for y := 0 to 15 do begin
    for x := 0 to 15 do begin
      v := 0;
      if dc.getPixel(Point(x, y)).a = 255 then continue;
      if dc.getPixel(Point(x-1, y-1)).a = 255 then v := 1;
      if dc.getPixel(Point(x-1, y)).a = 255 then v := 2;
      if dc.getPixel(Point(x, y-1)).a = 255 then v := 2;
      case v of
        1: dc.putPixel(Point(x, y), RGB(0,0,0,96));
        2: dc.putPixel(Point(x, y), RGB(0,0,0,128));
      end;
    end;
  end;
end;

{auto shadows for given tile}
procedure renderTileBufferShadow_ASM(page: tPage);
var
  x,y: integer;
  c: RGBA;
  v: byte;
  pixelPtr: pRGBA;
  upOfs,leftOfs: int32;
  shadow1, shadow2: RGBA;
begin
  {not really asm, but it's pointer stuff..}
  assert(page.width=16);
  assert(page.height=16);
  upOfs := 16*4;
  leftOfs := 4;
  shadow1 := RGB(0,0,0,96);
  shadow2 := RGB(0,0,0,128);
  for y := 0 to 15 do begin
    pixelPtr := page.getAddr(0,y);
    for x := 0 to 15 do begin
      if pixelPtr^.a = 255 then begin
        inc(pixelPtr);
        continue;
      end;
      v := 0;
      if (x > 0) and (y > 0) and (pRGBA(pointer(pixelPtr) - upOfs - leftOfs)^.a = 255) then v := 1;
      if (x > 0) and (pRGBA(pointer(pixelPtr) - leftOfs)^.a = 255) then v := 2;
      if (y > 0) and (pRGBA(pointer(pixelPtr) - upOfs)^.a = 255) then v := 2;
      case v of
        1: pixelPtr^ := shadow1;
        2: pixelPtr^ := shadow2;
      end;
      inc(pixelPtr);
    end;
  end;
end;

procedure tMapGUI.renderTileBufferShadow();
begin
  renderTileBufferShadow_ASM(tileBuffer);
end;

{renders a single map tile}
procedure tMapGUI.renderTile(aDC: tDrawContext; x, y: integer);
var
  tile: tTile;
  wall: tWall;
  pos: tPoint;
  dx,dy: integer;
  id: integer;
  d: tDirection;
  icd: tIntercardinalDirection;
  padding : integer;
  dc: tDrawContext;
  prevClip: tRect;
begin

  tile := map.tile[x,y].asExplored;

  pos := tilePos(x,y);

  {
  The rules are as follows

  The 'inner' part of the tile is 15x15 (TILE_SIZE).
  However the tiles are 16x16, as follows

  col0 our west wall
  row0 our north wall
  col15 our east wall
  row15 our south wall

  Therefore.. if we want to quickly draw, we can draw 15x15 tiles where we
  render only our north and west walls. However a full redraw requires
  rendering all four walls (as they might overlap our cell) as well as
  the walls from the diagonal tiles... (due to corners)

  }

  // make sure we only draw on our tile
  prevClip := aDC.clip;
  aDC.clip := Rect(pos.x+aDC.offset.x, pos.y+aDC.offset.y, TILE_SIZE, TILE_SIZE);
  aDC.clip.clipTo(prevClip);
  if aDC.clip.area <= 0 then exit;

  startTimer('tile_render');

  {clear background for this tile}
  {todo: support image background}
  dc := tileBuffer.getDC();

  tileBuffer.clear(RGBA.Clear);

  (*
  if (x+y) mod 2 = 0 then
    {show tile boundaries}
    dc.fillRect(Rect(0,0,TILE_SIZE, TILE_SIZE), RGB(255,0,255,128));

  //dc.fillRect(Rect(0,0,TILE_SIZE, TILE_SIZE), RGB(0,0,0));
  *)

  {floor}
  id := tile.floorSpec.spriteIdx;
  if id >= 0 then mdr.mapSprites.sprites[id].draw(dc, 0, 0);

  {medium}
  id := tile.mediumSpec.spriteIdx;
  if id >= 0 then mdr.mapSprites.sprites[id].draw(dc, 0, 0);

  {walls}
  for d in tDirection do begin
    wall := map.wall[x, y, d].asExplored;
    id := wall.spec.spriteIdx;
    if id < 0 then continue;
    {offset to align walls}
    dx := 0;
    dy := 0;

    case ord(d) of
      0: dy := -1;
      1: dx := 1;
      2: dy := 1;
      3: dx := -1;
    end;
    mdr.mapSprites.sprites[id].drawRot90(dc, Point(dx, dy), ord(d)-1);
  end;

  {don't forget the corners}
  for icd in tIntercardinalDirection do
    if map.hasCorner(x, y, icd) then begin
      dx := IDX[icd]; dy := IDY[icd];
      dc.putPixel(Point(8+dx*8, 8+dy*8), RGB($ffe6dcc2));
    end;

  {auto shadow}
  startTimer('tile_shadow');
  renderTileBufferShadow();
  stopTimer('tile_shadow');

  {composite:}

  {1. background}
  case BACKGROUND_MODE of
    BM_CHECKER:
      if (x+y) mod 2 = 0 then
        aDC.fillRect(Rect(pos.x,pos.y,TILE_SIZE, TILE_SIZE), RGB(200,50,200))
      else
        aDC.fillRect(Rect(pos.x,pos.y,TILE_SIZE, TILE_SIZE), RGB(0,0,0));
    BM_GRAY:
      aDC.fillRect(Rect(pos.x,pos.y,TILE_SIZE, TILE_SIZE), RGB(100,100, 100));
    BM_BLACK:
      aDC.fillRect(Rect(pos.x,pos.y,TILE_SIZE, TILE_SIZE), RGB(0,0,0));
    BM_IMAGE: begin
      aDC.drawImage(background.page, Point(0,0));
      // also show cells
      aDC.fillRect(Rect(pos.x,pos.y+1, 1, TILE_SIZE-1), RGB(0,0,0,32));
      aDC.fillRect(Rect(pos.x,pos.y, TILE_SIZE, 1), RGB(0,0,0,32));
    end;
  end;

  {2. overlay the tile}
  aDC.drawImage(tileBuffer, pos);

  {3. overlay the cursor (if any)}
  {if (x = cursorPos.x) and (y = cursorPos.y) then
    drawCursor(aDC);}

  isTileDirty[x,y] := false;

  stopTimer('tile_render');
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
    mmEdit: mdr.mapSprites.sprites[CURSOR_SPRITE].draw(
      dc,
      tilePos(cursorPos.x,cursorPos.y).x,
      tilePos(cursorPos.x,cursorPos.y).y
      );
    mmParty: mdr.mapSprites.sprites[PARTY_SPRITE+ord(cursorDir)].draw(
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
