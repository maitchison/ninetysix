unit terraNova;

interface

{
Every pixel is a particle, that can move and collide
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

  tTerrainModel = class
  protected
    {todo: these need to be aligned to 32 bytes, which means custom getMem}
    cellAttr: tTerrainAttrArray;
    cellInfo: tCellInfoArray;
    blockInfo: tBlockInfoArray;
  public
    constructor create();
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

    procedure draw(screen: tScreen); virtual;
    procedure update(elapsed: single); virtual;
  end;

  {very simple non-moving terrain}
  tStaticTerrain = class(tTerrainModel)
  public
    procedure update(elapsed: single); override;
  end;

implementation

uses
  keyboard; {for debugging}

const

  terrainColors: array[tDirtType] of RGBA = (
    (b:$00; g:$00; r:$00; a: $ff),
    (b:$44; g:$80; r:$8d; a: $ff),
    (b:$44; g:$44; r:$44; a: $ff),
    (b:$5d; g:$80; r:$0d; a: $ff)
  );

var
  terrainColorLookup: array[tDirtType, 0..255] of RGBA;

{-----------------------------------------------------------}

constructor tTerrainModel.create();
begin
  inherited create();
  clear();
end;

destructor tTerrainModel.destroy();
begin
  inherited destroy();
end;

{--------------------}

procedure tTerrainModel.clear();
begin
  fillchar(blockInfo, sizeof(blockInfo), 0);
  fillchar(cellInfo, sizeof(cellInfo), 0);
  fillchar(cellAttr, sizeof(cellAttr), 0);
end;

function tTerrainModel.getCell(x,y: integer): tCellInfo; inline;
begin
  result.code := 0;
  if (x < 0) or (x > 255) or (y < 0) or (y > 255) then exit();
  result := cellInfo[y, x];
end;

procedure tTerrainModel.setCell(x,y: integer; cell: tCellInfo); inline;
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

function tTerrainModel.isEmpty(x, y: integer): boolean; inline;
begin
  result := getCell(x, y).dType = DT_EMPTY;
end;

function tTerrainModel.isSolid(x, y: integer): boolean; inline;
begin
  result := getCell(x, y).dType <> DT_EMPTY;
end;

{removes terrain in given radius, and burns edges}
procedure tTerrainModel.burn(atX,atY: integer;r: integer;power:integer=255);
var
  dx, dy: integer;
  x,y: integer;
  v: integer;
  dst2: integer;
  r2: integer;
  emptyC, burntC: RGBA;
  tc: RGBA;
  dimFactor: integer;
begin
  {todo: implement this with a 'template' and have a linear one
   and a spherical one. Also add some texture to these}
   (*
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
      if isEmpty(x, y) then continue;
      {linear fall off}
      //v := round((1-(dst2/r2)) * power);
      {spherical fall off}
      if dst2 <= r2 then
        v := round(sqrt(r2-dst2)/r * power / 2)
      else
        v := 0;
      tc := dirtColor.getPixel(x, y);
      dimFactor := round(50 * v / (tc.a+1));
      tc.a := clamp(tc.a - v, 0, 255);
      tc.r := clamp(tc.r - dimFactor, 0, 255);
      tc.g := clamp(tc.g - dimFactor, 0, 255);
      tc.b := clamp(tc.b - dimFactor, 0, 255);
      dirtColor.setPixel(x, y, tc);
    end;
    lineStatus[y] := TL_UNKNOWN;
  end;
  *)
end;

{creates a circle of dirt at location}
procedure tTerrainModel.addDirtCircle(atX,atY: integer;r: integer);
var
  dx, dy: integer;
  x,y: integer;
  v: single;
  dst2: integer;
  r2: integer;
  dimFactor: integer;
  c: RGBA;
begin
  (*
  if r <= 0 then exit;
  r2 := r*r;
  for dy := -r to +r do begin
    for dx := -r to +r do begin
      x := atX+dx;
      y := atY+dy;
      dst2 := (dx*dx)+(dy*dy);
      if (dst2 > r2) then continue;
      if not isEmpty(x, y) then continue;
      c := TC_DIRT;
      v := 0.7+(0.1*(rnd/255));
      c.r := round(c.r * v);
      c.g := round(c.g * v);
      c.b := round(c.r * v);
      c.a := round(c.a * v);
      dirtColor.setPixel(x, y, c);
    end;
    lineStatus[y] := TL_UNKNOWN;
  end;
  *)
end;

{returns height of terrain at x position}
function tTerrainModel.getTerrainHeight(xPos: integer): integer;
var
  y: integer;
begin
  result := 0;
  for y := 0 to 255 do
    if getCell(xPos, y).dType <> DT_EMPTY then exit(255-y);
end;

procedure tTerrainModel.generate();
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
end;

procedure tTerrainModel.update(elapsed: single);
begin
  // nothing to do
end;


procedure tTerrainModel.draw(screen: tScreen);
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
  begin
    for j := 0 to 8-1 do begin
      for i := 0 to 8-1 do begin
        x := gx*8+i;
        y := gy*8+j;
        cell := getCell(x,y);
        if cell.dType = DT_EMPTY then continue;
        screen.canvas.setPixel(32+x, y, terrainColorLookup[cell.dtype, cell.strength]);
      end;
    end;
    screen.markRegion(Rect(32+gx*8, gy*8, 8,8));
  end;

  procedure drawBlock_ASM(gx, gy: integer);
  var
    lookupPtr, screenPtr, cellPtr: pointer;
    screenInc: dword;
  begin
    lookupPtr := @terrainColorLookup;
    screenPtr := screen.canvas.getAddress(32+gx*8, gy*8);
    if not assigned(screenPtr) then exit;
    cellPtr := @cellInfo[gy*8, gx*8];
    screenInc := (screen.canvas.width-8) * 4;

    asm
      pushad

      mov ch, 8
      mov edx, LOOKUPPTR
      mov edi, SCREENPTR
      mov esi, CELLPTR

    @YLOOP:
      mov cl, 4

    @XLOOP:
      mov ebx, [esi]      // eax = strength | type (i.e. strength*type*256)
      test bh, bh
      jz @SKIP1
      movzx eax, bx
      mov eax, [edx+eax*4]
      mov [edi], eax
    @SKIP1:
      shr ebx, 16
      test bh, bh
      jz @SKIP2
      mov eax, [edx+ebx*4]
      mov [edi+4], eax
    @SKIP2:
      add edi, 8
      add esi, 4

      dec cl
      jnz @XLOOP

      add edi, SCREENINC
      add esi, (256-8)*2
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

      if bi^.count > 0 then
        drawBlock_ASM(gx, gy);

      if keyDown(key_g) then
        debugDrawBlock(gx, gy);

      bi^.status := bi^.status and (not BS_DIRTY);
    end;
  end;
end;

{----------------------------------------------------------------------}
{ tStaticTerrain }
{----------------------------------------------------------------------}

procedure tStaticTerrain.update(elapsed: single);
begin
  // nothing to do
end;

(*

  {todo: switch to grid system}
  for y := 0 to 240-1 do begin
    {$ifdef debug}
    case lineStatus[y] of
      TL_EMPTY: screen.canvas.putPixel(319, y, RGB(255,0,0));
      TL_MIXED: screen.canvas.putPixel(319, y, RGB(0,255,0));
      TL_FULL: screen.canvas.putPixel(319, y, RGB(0,0,255));
      TL_UNKNOWN: screen.canvas.putPixel(319, y, RGB(255,0,255));
    end;
    {$endif}
    srcPtr := dirtColor.pixels + (y * 256 * 4);
    dstPtr := screen.canvas.pixels + ((32 + (y*screen.canvas.width)) * 4);
    if lineStatus[y] = TL_EMPTY then continue;
    if lineStatus[y] = TL_FULL then begin
      move(srcPtr^, dstPtr^, 256*4);
      continue;
    end;
    asm
      pushad
      mov esi, srcPtr
      mov edi, dstPtr
      mov ecx, 256
      xor ebx, ebx
    @XLOOP:
      mov eax, dword ptr [esi]
      bswap eax
      test al, al
      jz @SKIP
      bswap eax
      inc ebx
      mov dword ptr [edi], eax
    @SKIP:
      add esi, 4
      add edi, 4
      dec ecx
      jnz @XLOOP
    @ENDOFLOOP:
      mov solidTiles, ebx
      popad
    end;

    {since we processed the whole line, lets update it's status}
    if solidTiles = 0 then
      lineStatus[y] := TL_EMPTY
    else if solidTiles = 256 then
      lineStatus[y] := TL_FULL
    else
      lineStatus[y] := TL_MIXED;
  end;
*)

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

{simple celluar based terrain update}
procedure tTerrain.updateCelluar();
var
  gx,gy: integer;
begin
  for gy := 32-1 downto 0 do begin
    for gx := 0 to 32-1 do begin
      if blockInfo[gy, gx].count = 0 then continue;
      updateBlock_REF(gx, gy, blockInfo, cellInfo, cellAttr);
    end;
  end;
end;

procedure tTerrain.update(elapsed: single);
begin
  updateCelluar();
end;
           *)
{-----------------------------------------------------------}

procedure generateTerrainColorLookup();
var
  dType: tDirtType;
  i: integer;
begin
  for dType := low(terrainColors) to high(terrainColors) do
    for i := 0 to 255 do
       terrainColorLookup[dType, i] := RGBA.Lerp(RGB(0,0,0), terrainColors[dType], i/255);
end;

begin
  generateTerrainColorLookup();
end.
