unit terra;

interface

{
Every pixel is a particle, that can move and collide
}

uses
  test, debug,
  utils,
  graph32, uScreen;

const
  BS_EMPTY = 0;
  BS_FULL = 1;
  BS_ACTIVE = 2;

type

  tDirtType = (DT_EMPTY, DT_DIRT, DT_STONE);

  tTerrainInfo = record
    case byte of
    0: (
      dType: tDirtType;
    );
    1: (code: dword);
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

  tTerrainInfoArray = array[0..256-1, 0..256-1] of tTerrainInfo;
  tTerrainAttrArray = array[0..256-1, 0..32-1] of tTerrainLine;

  tBlockInfoArray = array[0..32-1, 0..32-1] of tBlockInfo;

  tTerrain = class
  public
    {todo: these need to be aligned to 32 bytes, which means custom getMem}
    cellInfo: tTerrainInfoArray;
    cellAttr: tTerrainAttrArray;
    blockInfo: tBlockInfoArray;
  protected
    procedure updateCelluar();
  public
    constructor create();
    destructor destroy(); override;

    procedure clear();

    function  getDirt(x,y: integer): tTerrainInfo;
    procedure setDirt(x,y: integer; dType: tDirtType);

    function  isEmpty(x, y: integer): boolean;
    function  isSolid(x, y: integer): boolean;

    procedure addDirtCircle(atX,atY: integer;r: integer);
    procedure burn(atX,atY: integer;r: integer;power:integer=255);
    function  getTerrainHeight(xPos: integer): integer;

    procedure generate();
    procedure draw(screen: tScreen);
    procedure update(elapsed: single);
  end;

var
  terrain: tTerrain;

implementation

const
  TC_DIRT: RGBA =  (b:$44; g:$80; r:$8d; a: $20);
  TC_ROCK: RGBA =  (b:$44; g:$44; r:$44; a: $ff);
  TC_GRASS: RGBA = (b:$5d; g:$80; r:$0d; a: $0f);
  TC_SKY: RGBA =   (b:$00; g:$00; r:$00; a: $00);

{-----------------------------------------------------------}

constructor tTerrain.create();
begin
  inherited create();
  clear();
end;

destructor tTerrain.destroy();
begin
  inherited destroy();
end;

{--------------------}

procedure tTerrain.clear();
begin
  fillchar(blockInfo, sizeof(blockInfo), 0);
  fillchar(cellInfo, sizeof(cellInfo), 0);
  fillchar(cellAttr, sizeof(cellAttr), 0);
end;

function tTerrain.getDirt(x,y: integer): tTerrainInfo; inline;
begin
  result.code := 0;
  if (x < 0) or (x > 255) or (y < 0) or (y > 255) then exit();
  result := cellInfo[y, x];
{
  asm
    xor eax, eax
    mov al, byte ptr X
    mov ah, byte ptr Y
    mov al, [ebp + blocksInfo + eax]
    end;}
end;

function tTerrain.isEmpty(x, y: integer): boolean;
begin
  result := getDirt(x, y).dType = DT_EMPTY;
end;

function tTerrain.isSolid(x, y: integer): boolean;
begin
  result := getDirt(x, y).dType <> DT_EMPTY;
end;

procedure tTerrain.setDirt(x,y: integer; dType: tDirtType); inline;
begin
  if (x < 0) or (x > 255) or (y < 0) or (y > 255) then exit;
  cellInfo[y, x].code := byte(dType);
  cellAttr[y, x div 8].x[x and $7] := 0;
  cellAttr[y, x div 8].y[x and $7] := 0;
  cellAttr[y, x div 8].vX[x and $7] := 0;
  cellAttr[y, x div 8].vY[x and $7] := 0;
end;

{removes terrain in given radius, and burns edges}
procedure tTerrain.burn(atX,atY: integer;r: integer;power:integer=255);
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
procedure tTerrain.addDirtCircle(atX,atY: integer;r: integer);
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
function tTerrain.getTerrainHeight(xPos: integer): integer;
var
  y: integer;
begin
  result := 0;
  for y := 0 to 255 do
    if getDirt(xPos, y).dType <> DT_EMPTY then exit(255-y);
end;

procedure tTerrain.generate();
var
  dirtHeight: array[0..255] of integer;
  rockHeight: array[0..255] of integer;
  x,y: integer;
  c: RGBA;
  v: single;
begin

  clear();

  for x := 0 to 255 do begin
    dirtHeight[x] := 128 + round(30*sin(3+x*0.0197) - 67*cos(2+x*0.003) + 15*sin(1+x*0.023));
    rockHeight[x] := 200 + round(30*sin(30+x*0.0197) - 67*cos(20+x*0.003) + 15*sin(10+x*0.023)) div 4;
  end;

  for y := 0 to 255 do begin
    for x := 0 to 255 do begin
      if y > rockHeight[x] then
        c := TC_ROCK
      else if y > dirtHeight[x] then
        c := TC_DIRT
      else if y > dirtHeight[x]-1 then
        c := RGB(TC_DIRT.r-10, TC_DIRT.g-10, TC_DIRT.b-10, TC_DIRT.a-10)
      else
        continue;
      v := 0.9+(0.1*(rnd/255));
      c.r := round(c.r * v);
      c.g := round(c.g * v);
      c.b := round(c.r * v);
      c.a := round(c.a * v);
      setDirt(x, y, DT_DIRT);
      //dirtColor.setPixel(x, y, c);
    end;
  end;
end;

procedure tTerrain.draw(screen: tScreen);
var
  c: RGBA;
  x,y: integer;
  srcPtr, dstPtr: pointer;
  solidTiles: integer;
begin
  for y := 0 to 255 do begin
    for x := 0 to 255 do begin
      case getDirt(x,y).dType of
        DT_EMPTY: ;
        DT_DIRT: screen.canvas.setPixel(32+x, y, RGB(128,128,128));
      end;
    end;
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
end;

procedure updateBlock_REF(gx,gy: integer; var blockInfo: tBlockInfoArray; var cellInfo: tTerrainInfoArray; var cellAttr: tTerrainAttrArray);
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
      py := cellAttr[y,x div 8].y[x and $7] + cellAttr[y,x div 8].vy[x and $7];
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

{-----------------------------------------------------------}

begin
end.
