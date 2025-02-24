unit terraNova;

interface

{
Every pixel is a particle, that can moves and collide
}

uses
  test, debug,
  utils,
  graph2d, graph32, uScreen;

const
  BS_LOCKED = 1;   // no updates required as no particles can move
  BS_DIRTY = 2;    // must redraw this block as it's changed

type

  tDirtType = (DT_EMPTY, DT_DIRT, DT_ROCK, DT_GRASS);

  tCellInfo = record
    case byte of
    0: (
      strength: byte;
      dType: tDirtType;
    );
    1: (code: word);
  end;

  {optimized for MMX reads, also is 32bytes so fits into a cache line.}
  tTerrainLine = packed record
    x: array[0..7] of byte;
    y: array[0..7] of byte;
    vx: array[0..7] of byte;
    vy: array[0..7] of byte;
  end;

  tBlockInfo = record
    status: byte;
    count: byte;
  end;

  tCellInfoArray = array[0..256-1, 0..256-1] of tCellInfo;
  tTerrainAttrArray = array[0..256-1, 0..32-1] of tTerrainLine;

  tBlockInfoArray = array[0..32-1, 0..32-1] of tBlockInfo;

  tTerrainSolver = (TS_STATIC, TS_FALLING, TS_PARTICLE);

  tTerrain = class
  protected
    {todo: these need to be aligned to 32 bytes, which means custom getMem}
    cellAttr: tTerrainAttrArray;
    cellInfo: tCellInfoArray;
    blockInfo: tBlockInfoArray;
    solver: tTerrainSolver;
    timeUntilNextSolve: single;

    procedure updateStatic();
    procedure updateFalling();

  public

    sky: tPage;

    constructor create(aSolver: tTerrainSolver = TS_FALLING);
    destructor destroy(); override;

    procedure clear(); virtual;

    function  getCell(x,y: integer): tCellInfo; inline;
    procedure setCell(x,y: integer; cell: tCellInfo); inline;
    function  isEmpty(x, y: integer): boolean; inline;
    function  isSolid(x, y: integer): boolean; inline;

    procedure addDirtCircle(atX,atY: integer;r: integer);
    procedure burn(atX,atY: integer;r: integer;power:integer=255);
    function  getTerrainHeight(xPos: integer): integer;

    procedure generate();

    procedure draw(screen: tScreen);
    procedure update(elapsed: single);
  end;

implementation

uses
  keyboard; {for debugging}

const

  TERRAIN_DECAY: array[tDirtType] of integer = (
    0, 6, 2, 32
  );

  TERRAIN_COLOR: array[tDirtType] of RGBA = (
    (b:$00; g:$00; r:$00; a: $ff),
    (b:$44; g:$80; r:$8d; a: $ff),
    (b:$44; g:$44; r:$44; a: $ff),
    (b:$5d; g:$80; r:$0d; a: $ff)
  );

var
  terrainColorLookup: array[tDirtType, 0..255] of RGBA;

{-----------------------------------------------------------}

constructor tTerrain.create(aSolver: tTerrainSolver = TS_FALLING);
begin
  inherited create();
  solver := aSolver;
  sky := tPage.create(256, 256);
  clear();
end;

destructor tTerrain.destroy();
begin
  sky.free();
  inherited destroy();
end;

{--------------------}

procedure tTerrain.clear();
begin
  fillchar(blockInfo, sizeof(blockInfo), 0);
  fillchar(cellInfo, sizeof(cellInfo), 0);
  fillchar(cellAttr, sizeof(cellAttr), 0);
end;

function tTerrain.getCell(x,y: integer): tCellInfo; inline;
begin
  result.code := 0;
  if (x < 0) or (x > 255) or (y < 0) or (y > 255) then exit();
  result := cellInfo[y, x];
end;

procedure tTerrain.setCell(x,y: integer; cell: tCellInfo); inline;
var
  bi: ^tBlockInfo;
begin
  if (x < 0) or (x > 255) or (y < 0) or (y > 255) then exit;
  if cellInfo[y, x].dType <> DT_EMPTY then dec(blockInfo[y div 8, x div 8].count);
  cellInfo[y, x] := cell;
  bi := @blockInfo[y div 8, x div 8];
  if cell.dType <> DT_EMPTY then inc(bi^.count);
  bi^.status := bi^.status or BS_DIRTY;
end;

function tTerrain.isEmpty(x, y: integer): boolean; inline;
begin
  result := getCell(x, y).dType = DT_EMPTY;
end;

function tTerrain.isSolid(x, y: integer): boolean; inline;
begin
  result := getCell(x, y).dType <> DT_EMPTY;
end;

{removes terrain in given radius, and burns edges}
procedure tTerrain.burn(atX,atY: integer;r: integer;power:integer=255);
var
  dx, dy: integer;
  x,y: integer;
  dst2: integer;
  r2: integer;
  emptyC, burntC: RGBA;
  tc: RGBA;
  dimFactor: integer;
  cell: tCellInfo;
  strength: integer;
begin
  {todo: implement this with a 'template' and have a linear one
   and a spherical one. Also add some texture to these}
  if power <= 0 then exit;
  if r <= 0 then exit;
  r2 := r*r;
  for dy := -r to +r do begin
    y := atY+dy;
    if (y < 0) or (y > 255) then continue;
    //if lineStatus[y] = TL_EMPTY then continue;
    for dx := -r to +r do begin
      dst2 := (dx*dx)+(dy*dy);
      x := atX+dx;
      if (dst2 > r2) then continue;
      cell := getCell(x,y);
      if cell.dType = DT_EMPTY then continue;
      {linear fall off}
      dimFactor := round((1-(dst2/r2)) * power) * TERRAIN_DECAY[cell.dtype];
      {spherical fall off}
      {if dst2 <= r2 then
        dimFactor := round(sqrt(r2-dst2)/r * power / 2)
      else
        dimFactor := 0;}

      strength := int32(cell.strength) - dimFactor;
      if strength <= 0 then begin
        cell.dtype := DT_EMPTY;
        cell.strength := 0;
      end else
        cell.strength := strength;

      setCell(x,y, cell);

    end;
  end;
end;

{creates a circle of dirt at location}
procedure tTerrain.addDirtCircle(atX,atY: integer;r: integer);
var
  dx, dy: integer;
  x,y: integer;
  v: single;
  dst2: integer;
  r2: integer;
  dimFactor: integer;
  c: RGBA;
  cell: tCellInfo;
begin
  if r <= 0 then exit;
  r2 := r*r;
  for dy := -r to +r do begin
    for dx := -r to +r do begin
      x := atX+dx;
      y := atY+dy;
      dst2 := (dx*dx)+(dy*dy);
      if (dst2 > r2) then continue;
      if not isEmpty(x, y) then continue;
      cell.dType := DT_DIRT;
      cell.strength := 128+rnd(16);
      setCell(x, y, cell);
    end;
  end;
end;

{returns height of terrain at x position}
function tTerrain.getTerrainHeight(xPos: integer): integer;
var
  y: integer;
begin
  result := 0;
  for y := 0 to 255 do
    if getCell(xPos, y).dType <> DT_EMPTY then exit(255-y);
end;

procedure tTerrain.generate();
var
  dirtHeight: array[0..255] of integer;
  rockHeight: array[0..255] of integer;
  x,y: integer;
  c: RGBA;
  cell: tCellInfo;
  v: single;
begin

  clear();

  for x := 0 to 255 do begin
    dirtHeight[x] := 128 + round(30*sin(3+x*0.0197) - 67*cos(2+x*0.003) + 15*sin(1+x*0.023));
    rockHeight[x] := 200 + round(30*sin(30+x*0.0197) - 67*cos(20+x*0.003) + 15*sin(10+x*0.023)) div 4;
  end;

  for y := 0 to 255 do begin
    for x := 0 to 255 do begin
      if y >= rockHeight[x] then
        cell.dType := DT_ROCK
      else if y >= dirtHeight[x] then
        cell.dType := DT_DIRT
      else
        continue;

      { random strength mostly for texture }
      cell.strength := 220+rnd(30);
      if (y = min(dirtHeight[x], rockHeight[x])) then cell.strength -= 50;

      setCell(x, y, cell);
    end;
  end;

  for x := 0 to 32-1 do
    for y := 0 to 32-1 do
      blockInfo[y,x].status := BS_DIRTY;
end;

{draw terrain to background}
procedure tTerrain.draw(screen: tScreen);
var
  c: RGBA;
  gx, gy: integer;
  srcPtr, dstPtr: pointer;
  solidTiles: integer;
  bi: ^tBlockInfo;

  procedure debugDrawBlock(gx, gy: integer);
  var
    r: tRect;
    c: RGBA;
    bi: tBlockInfo;
  begin
    r := Rect(32+gx*8, gy*8, 9,9);
    c := RGB(128,128,128);
    bi := blockInfo[gy, gx];
    if bi.count = 0 then
      c.r := 0;
    if bi.count = 64 then
      c.r := 255;
    if (bi.status and BS_DIRTY = BS_DIRTY) then
      c.g := 255;
    screen.canvas.drawRect(r, c);
    screen.markRegion(r);
  end;

  procedure drawBlock_REF(gx, gy: integer);
  var
    i,j: integer;
    x,y: integer;
    cell: tCellInfo;
    c: RGBA;
  begin
    for j := 0 to 8-1 do begin
      for i := 0 to 8-1 do begin
        x := gx*8+i;
        y := gy*8+j;
        cell := getCell(x,y);
        if cell.dType = DT_EMPTY then
          c := sky.getPixel(x,y)
        else
          c := terrainColorLookup[cell.dtype, cell.strength];
        screen.background.setPixel(32+x, y, c);
      end;
    end;
    screen.markRegion(Rect(32+gx*8, gy*8, 8,8));
  end;

  procedure drawBlock_ASM(gx, gy: integer);
  var
    skyPtr, lookupPtr, screenPtr, cellPtr: pointer;
    screenInc: dword;
  begin
    lookupPtr := @terrainColorLookup;
    screenPtr := screen.background.getAddress(32+gx*8, gy*8);
    skyPtr := sky.getAddress(gx*8, gy*8);
    cellPtr := @cellInfo[gy*8, gx*8];
    screenInc := (screen.canvas.width-8) * 4;

    asm
      pushad

      mov ch, 8
      mov ebx, SKYPTR
      mov edx, LOOKUPPTR
      mov edi, SCREENPTR
      mov esi, CELLPTR

    @YLOOP:
      mov cl, 8

    @XLOOP:
      movzx eax, word ptr [esi]      // eax = strength | type (i.e. strength*type*256)

      test ah, ah
      jz  @SKY
      jmp @TERRAIN
    @SKY:
      mov eax, [ebx]
      jmp @WRITE
    @TERRAIN:
      movzx eax, ax
      mov eax, [edx+eax*4]
    @WRITE:
      mov [edi], eax
      add edi, 4
      add esi, 2
      add ebx, 4

      dec cl
      jnz @XLOOP

      add edi, SCREENINC
      add esi, (256-8)*2
      add ebx, (256-8)*4
      dec ch
      jnz @YLOOP

      popad

    end;

    screen.markRegion(Rect(32+gx*8, gy*8, 8,8));
  end;

begin
  for gy := 0 to 30-1 do begin
    for gx := 0 to 32-1 do begin

      bi := @blockInfo[gy, gx];

      if keyDown(key_g) then
        debugDrawBlock(gx, gy);

      if (bi^.status and BS_DIRTY) <> BS_DIRTY then continue;

      drawBlock_ASM(gx, gy);

      bi^.status := bi^.status and (not BS_DIRTY);
    end;
  end;
end;

{----------------------------------------------------------------------}
{ tStaticTerrain }
{----------------------------------------------------------------------}

procedure tTerrain.updateStatic();
begin
  // nothing to do.
end;

procedure updateBlockFalling_REF(gx,gy: integer; var blockInfo: tBlockInfoArray; var cellInfo: tCellInfoArray);
var
  i,j,x,y: integer;
  idx: integer;
  px,py: integer;
  empty, cell: tCellInfo;
  selfChanges, belowChanges: integer;
begin
  empty.code := 0;
  selfChanges := 0;
  belowChanges := 0;
  {process lines bottom up}
  for i := 0 to 7 do begin
    y := gy*8+(7-i);
    for j := 0 to 7 do begin
      x := gx*8+j;
      cell := cellInfo[y,x];
      if cell.dtype = DT_EMPTY then continue;
      if cellInfo[y+1,x].dtype = DT_EMPTY then begin
        inc(selfChanges);
        if i = 0 then inc(belowChanges);
        cellInfo[y+1, x] := cell;
        cellInfo[y, x] := empty;
      end;
    end;
  end;
  {keep track of block stats}
  if (selfChanges > 0) then blockInfo[gy, gx].status := blockInfo[gy, gx].status or BS_DIRTY;
  if (belowChanges > 0) then blockInfo[gy+1, gx].status := blockInfo[gy+1, gx].status or BS_DIRTY;
  blockInfo[gy, gx].count -= belowChanges;
  blockInfo[gy+1, gx].count += belowChanges;
end;


procedure tTerrain.updateFalling();
var
  gx,gy: integer;
begin
  for gy := 30-1 downto 0 do begin
    for gx := 0 to 32-1 do begin
      if blockInfo[gy, gx].count = 0 then continue;
      updateBlockFalling_REF(gx, gy, blockInfo, cellInfo);
    end;
  end;
end;

procedure tTerrain.update(elapsed: single);
begin
  {we update the terrain simulation at 30 fps}
  timeUntilNextSolve -= elapsed;

  while timeUntilNextSolve < 0 do begin
    case solver of
      TS_STATIC: updateStatic();
      TS_FALLING: updateFalling();
    end;
    timeUntilNextSolve += (1/30)
  end;
end;

{----------------------------------------------------------------------}
{ tParticleTerrain }
{----------------------------------------------------------------------}
             (*
procedure updateBlock_REF(gx,gy: integer; var blockInfo: tBlockInfoArray; var cellInfo: tCellInfoArray; var cellAttr: tTerrainAttrArray);
var
  i,j,x,y: integer;
  idx: integer;
  px,py: integer;

  procedure doMove(dx, dy: integer);
  var
    nx,ny: integer;
  begin
    nx := x+dx;
    ny := y+dy;
    if byte(nx) <> nx then exit;
    if byte(ny) <> ny then exit;

    if cellInfo[ny, nx].dType <> DT_EMPTY then exit;

    cellInfo[ny,nx].code := cellInfo[y,x].code;
    cellInfo[y,x].code := 0;

    cellAttr[ny,nx div 8].x[nx and $7] := cellAttr[y,x div 8].x[x and $7];
    cellAttr[ny,nx div 8].y[nx and $7] := cellAttr[y,x div 8].y[x and $7];
    cellAttr[ny,nx div 8].vX[nx and $7] := cellAttr[y,x div 8].vX[x and $7];
    cellAttr[ny,nx div 8].vY[nx and $7] := cellAttr[y,x div 8].vY[x and $7];
    cellAttr[y,x div 8].x[x and $7] := 0;
    cellAttr[y,x div 8].y[x and $7] := 0;
    cellAttr[y,x div 8].vX[x and $7] := 0;
    cellAttr[y,x div 8].vY[x and $7] := 0;

    dec(blockInfo[y, x div 8].count);
    inc(blockInfo[ny, nx div 8].count);
    {cellColor.setPixel(nx,ny,RGB(128,128,128));
    cellColor.setPixel(x,y,RGB(0,0,0,0));}
  end;

begin
  {process lines bottom up}
  for i := 0 to 7 do begin
    y := gy*8+(8-i);
    for j := 0 to 7 do begin
      x := gx*8+j;
      if cellInfo[y,x].dtype = DT_EMPTY then continue;
      py := cellAttr [y,x div 8].y[x and $7] + cellAttr[y,x div 8].vy[x and $7];
      cellAttr[y,x div 8].y[x and $7] := byte(py);
      if (py <= -127) then doMove(0,-1);
      if (py >= 128) then doMove(0,+1);
    end;
  end;
end;

           *)
{-----------------------------------------------------------}

procedure generateTerrainColorLookup();
var
  dType: tDirtType;
  i: integer;
begin
  for dType := low(TERRAIN_COLOR) to high(TERRAIN_COLOR) do
    for i := 0 to 255 do
       terrainColorLookup[dType, i] := RGBA.Lerp(RGB(0,0,0), TERRAIN_COLOR[dType], i/255);
end;

begin
  generateTerrainColorLookup();
end.
