unit terraNova;

interface

{
Every pixel is a particle, that can moves and collide
}

uses
  test, debug,
  utils,
  template,
  graph2d, graph32, uScreen;

const
  BS_INACTIVE = 1;   // no updates required as no cells can move
  BS_DIRTY = 2;      // must redraw this block as it's changed
  BS_LOWP = 4;       // update every 4th tick (if active)

type

  tDirtType = (DT_EMPTY, DT_DIRT, DT_SAND, DT_ROCK, DT_GRASS, DT_WATER, DT_LAVA, DT_OBSIDIAN);

  tCellInfo = record
    case byte of
    0: (
      strength: byte;
      dType: tDirtType;
    );
    1: (code: word);
  end;

  tCellAttributes = record
    x,y,vx,vy: int8;
  end;

  {optimized for MMX reads, also is 32bytes so fits into a cache line.}
  tTerrainLine = packed record
    x: array[0..7] of int8;
    y: array[0..7] of int8;
    vx: array[0..7] of int8;
    vy: array[0..7] of int8;
  end;

  tBlockInfo = record
    status: byte;
  end;

  tCellMovedArray = array[0..256-1, 0..32-1] of byte;
  tCellInfoArray = array[0..256-1, 0..256-1] of tCellInfo;
  tCellAttrArray = array[0..256-1, 0..32-1] of tTerrainLine;

  tBlockInfoArray = array[0..32-1, 0..32-1] of tBlockInfo;

  tTerrainSolver = (TS_STATIC, TS_FALLING, TS_PARTICLE);

  tTerrain = class
  protected
    {todo: these need to be aligned to 32 bytes, which means custom getMem}
    cellAttr: tCellAttrArray;
    cellInfo: tCellInfoArray;
    blockInfo: tBlockInfoArray;
    cellMoved: tCellMovedArray;
    solver: tTerrainSolver;
    timeUntilNextSolve: single;
    tick: dword;
  public

    sky: tPage;

    constructor create(aSolver: tTerrainSolver = TS_FALLING);
    destructor destroy(); override;

    procedure clear(); virtual;

    function  getCell(x,y: integer): tCellInfo; inline;
    procedure setCell(x,y: integer; cell: tCellInfo); inline;
    function  isEmpty(x, y: integer): boolean; inline;
    function  isSolid(x, y: integer): boolean; inline;

    {attributes}
    function  getAttr(x,y: integer): tCellAttributes; inline;
    procedure setAttr(x,y: integer; attr: tCellAttributes); inline;

    procedure putCircle(atX,atY: integer;r: integer; dType: tDirtType=DT_DIRT);
    procedure burn(atX,atY: integer;r: integer;power:integer=255);
    function  getTerrainHeight(xPos: integer): integer;

    procedure generate();

    procedure draw(screen: tScreen);
    procedure update(elapsed: single);
  end;

implementation

uses
  uGameObjects,
  game,
  keyboard; {for debugging}

const

  TERRAIN_DECAY: array[tDirtType] of integer = (
    0, //empty
    6, //dirt
    3, //sand
    2, //rock
    32,//grass
    0, //water
    0, //lava
    1  //obsidian
  );

  TERRAIN_COLOR: array[tDirtType] of RGBA = (
    (b:$00; g:$00; r:$00; a: $ff), //none
    (b:$44; g:$80; r:$8d; a: $ff), //dirt
    (b:$99; g:$e5; r:$ff; a: $ff), //sand
    (b:$44; g:$44; r:$44; a: $ff), //rock
    (b:$5d; g:$80; r:$0d; a: $ff), //grass
    (b:$fd; g:$30; r:$2d; a: $ff), //water
    (b:$04; g:$08; r:$ad; a: $ff), //lava
    (b:$6e; g:$40; r:$39; a: $ff)  //obsidian
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
  cellInfo[y, x] := cell;
  bi := @blockInfo[y div 8, x div 8];
  {set DIRTY clear INACTIVE}
  {todo: really we should to to active all blocks within 1 cell of this one}
  bi^.status := BS_DIRTY;
end;

function tTerrain.isEmpty(x, y: integer): boolean; inline;
begin
  result := getCell(x, y).dType = DT_EMPTY;
end;

function tTerrain.isSolid(x, y: integer): boolean; inline;
begin
  result := TERRAIN_DECAY[getCell(x, y).dType] <> 0;
end;

function tTerrain.getAttr(x,y: integer): tCellAttributes; inline;
begin
  result.x := cellAttr[y, x div 8].x[x and $7];
  result.y := cellAttr[y, x div 8].y[x and $7];
  result.vx := cellAttr[y, x div 8].vx[x and $7];
  result.vy := cellAttr[y, x div 8].vy[x and $7];
end;

procedure tTerrain.setAttr(x,y: integer; attr: tCellAttributes); inline;
begin
  cellAttr[y, x div 8].x[x and $7] := attr.x;
  cellAttr[y, x div 8].y[x and $7] := attr.y;
  cellAttr[y, x div 8].vx[x and $7] := attr.vx;
  cellAttr[y, x div 8].vy[x and $7] := attr.vy;
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
procedure tTerrain.putCircle(atX,atY: integer;r: integer; dType: tDirtType=DT_DIRT);
var
  dx, dy: integer;
  x,y: integer;
  v: single;
  dst2: integer;
  r2: integer;
  dimFactor: integer;
  c: RGBA;
  cell: tCellInfo;
  attr: tCellAttributes;
begin
  if r <= 0 then exit;
  r2 := r*r;
  for dy := -r to +r do begin
    for dx := -r to +r do begin
      x := atX+dx;
      y := atY+dy;
      dst2 := (dx*dx)+(dy*dy);
      if (dst2 > r2) then continue;
      if isSolid(x, y) then continue;
      cell.dType := dType;
      cell.strength := 128+rnd(16);
      setCell(x, y, cell);
      attr.x := 0;
      attr.y := 0;
      attr.vx := clamp(dx*4, -100, 100);
      attr.vy := clamp(dy*4, -100, 100);
      setAttr(x, y, attr);
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
    c := RGB(0,0,0);
    bi := blockInfo[gy, gx];
    {red = dirty}
    {blue = inactive}
    if (bi.status and BS_DIRTY <> 0) then
      c.r := 255;
    if (bi.status and BS_INACTIVE <> 0) then
      c.b := 255;
    if (bi.status and BS_LOWP <> 0) then
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

procedure updateBlockFalling_REF(gx,gy: integer; terrain: tTerrain);
var
  i,j,x,y: integer;
  idx: integer;
  px,py: integer;
  empty, cell: tCellInfo;
  selfChanged: boolean;
  selfNeedsLowP: boolean;
  changes: array[-1..1, -1..1] of int8;
  delta: integer;
  cx,cy: integer;
  coin: integer;
  p: tParticle;
  heatLost: integer;
  oldChanged: boolean;

  procedure doMove(dx,dy: integer); inline;
  begin
    if (cell.dType <> DT_LAVA) then selfChanged := true;
    if (j+dx < 0) then cx := -1 else if (j+dx >= 8) then cx := +1 else cx := 0;
    if ((7-i)+dy < 0) then cy := -1 else if ((7-i)+dy >= 8) then cy := +1 else cy := 0;
    inc(changes[cx,cy]);
    terrain.cellInfo[y+dy, x+dx] := cell;
    terrain.cellInfo[y, x] := empty;
  end;

  {returns if move completed}
  function checkAndMove(dx,dy: integer): boolean; inline;
  begin
    {todo: no bounds checking..}
    if (dword(x+dx) and $ffffff00) <> 0 then exit(false);
    if (dword(y+dy) and $ffffff00) <> 0 then exit(false);
    result := terrain.cellInfo[y+dy,x+dx].dtype = DT_EMPTY;
    if result then doMove(dx,dy);
  end;

  {returns if cell is open}
  function checkEmpty(dx,dy: integer): boolean; inline;
  begin
    {todo: no bounds checking..}
    if (dword(x+dx) and $ffffff00) <> 0 then exit(false);
    if (dword(y+dy) and $ffffff00) <> 0 then exit(false);
    result := terrain.cellInfo[y+dy,x+dx].dtype = DT_EMPTY;
  end;

  {returns head transfered}
  function doBurn(dx,dy: integer;burn: integer): integer; inline;
  begin
    {todo: no bounds checking..}
    if (dword(x+dx) and $ffffff00) <> 0 then exit(0);
    if (dword(y+dy) and $ffffff00) <> 0 then exit(0);
    if (terrain.cellInfo[y+dy,x+dx].dtype in [DT_EMPTY, DT_LAVA, DT_OBSIDIAN]) then exit(0);
    terrain.burn(x+dx, y+dy, 1, burn);
    result := 1;
  end;

begin
  empty.code := 0;
  fillchar(changes, sizeof(changes), 0);
  selfChanged := false;
  selfNeedsLowP := false;
  for i := 0 to 7 do begin
    y := gy*8+(7-i);
    for j := 0 to 7 do begin
      x := gx*8+j;
      cell := terrain.cellInfo[y,x];
      case cell.dtype of
        DT_EMPTY: ;
        DT_ROCK: ;
        DT_DIRT, DT_OBSIDIAN: begin
          checkAndMove(0,1);
        end;
        DT_SAND: begin
          if checkAndMove(0,1) then continue;
          coin := (rnd and $2) * 2 - 1;
          if checkAndMove(coin,1) then continue;
          if checkAndMove(-coin,1) then continue;
        end;
        DT_WATER: begin
          if checkAndMove(0,1) then continue;
          coin := (rnd and $2) * 2 - 1;
          if checkAndMove(coin,1) then continue;
          if checkAndMove(-coin,1) then continue;
          if checkAndMove(coin,0) then continue;
          if checkAndMove(-coin,0) then continue;
        end;
        DT_LAVA: begin
          {lava always keeps block active}
          selfNeedsLowP := true;

          {lava moves and updates at half speed}
          if (terrain.tick and $1 <> 0) then continue;

          {ash and sparks}
          if (rnd = 0) then begin
            if checkEmpty(0, -1) then begin
              {spark}
              p := nextParticle();
              p.pos.x := x;
              p.pos.y := y;
              p.solid := false;
              p.col.init(200,100,2);
              p.vel.x := (rnd-128) div 16;
              p.vel.y := (rnd div 16)-12;
              p.blend := TDM_ADD;
              p.radius := 1;
              p.ttl := 0.5;
            end else if (rnd and $7 = 0) then begin
              {ash}
              p := nextParticle();
              p.pos.x := x;
              p.pos.y := y;
              p.solid := false;
              p.col.init(50-rnd(32),100-rnd(64),100-rnd(32));
              p.vel.x := (rnd div 16)-8;
              p.vel.y := (rnd div 16)-8;
              p.blend := TDM_SUB;
              p.radius := 1;
              p.ttl := 0.5;
            end
          end;

          {burn neighbours}
          heatLost := 0;
          heatLost += doBurn(0, 1, 1);
          heatLost += doBurn(-1, 1, 1);
          heatLost += doBurn(+1, 1, 1);
          heatLost += doBurn(-1, 0, 1);
          heatLost += doBurn(+1, 0, 1);

          {update heat}
          if terrain.cellInfo[y,x].strength <= heatLost then begin
            {replace with stone}
            terrain.cellInfo[y,x].strength := 200+rnd(40);
            terrain.cellInfo[y,x].dType := DT_OBSIDIAN;
            continue;
          end else begin
            terrain.cellInfo[y,x].strength -= heatLost;
          end;

          {move}
          coin := (rnd and $2) * 2 - 1;
          if checkAndMove(0,1) then continue;
          if checkAndMove(coin,1) then continue;
          if checkAndMove(-coin,1) then continue;
          if checkAndMove(coin,0) then continue;
          if checkAndMove(-coin,0) then continue;
        end;
      end;
    end;
  end;

  {keep track of block stats}
  terrain.blockInfo[gy, gx].status := terrain.blockInfo[gy, gx].status and (not BS_LOWP);
  if (not selfChanged) then begin
    {if nothing moved then we sleep the block. if there's lava go into lowPriotiy mode instead}
    if selfNeedsLowP then begin
      terrain.blockInfo[gy, gx].status := terrain.blockInfo[gy, gx].status or (BS_LOWP and BS_DIRTY);
    end else begin
      terrain.blockInfo[gy, gx].status := terrain.blockInfo[gy, gx].status or BS_INACTIVE;
      exit;
    end;
  end;

  terrain.blockInfo[gy, gx].status := terrain.blockInfo[gy, gx].status or BS_DIRTY;

  for cx := -1 to 1 do begin
    for cy := -1 to 1 do begin
      delta := changes[cx,cy];
      // let all neighbours know to check themselves
      terrain.blockInfo[gy+cy, gx+cx].status := terrain.blockInfo[gy+cy, gx+cx].status and (not BS_INACTIVE);
      if delta = 0 then continue;
      terrain.blockInfo[gy+cy, gx+cx].status := terrain.blockInfo[gy+cy, gx+cx].status or BS_DIRTY;
    end;
  end;
end;

procedure updateBlockParticle_REF(gx,gy: integer; var blockInfo: tBlockInfoArray; var cellInfo: tCellInfoArray; var cellAttr: tCellAttrArray;var cellMoved: tCellMovedArray);
var
  i,j,x,y: integer;
  idx: integer;
  px,py,vx,vy: int32;
  empty, cell: tCellInfo;
  selfChanged: boolean;
  changes: array[-1..1, -1..1] of int8;
  delta: integer;
  cx,cy: integer;
  coin: integer;
  dx,dy: integer;
  hasSupport: boolean;
  nx,ny: integer;

  procedure doMove(dx,dy: integer); inline;
  begin
    selfChanged := true;
    if (j+dx < 0) then cx := -1 else if (j+dx >= 8) then cx := +1 else cx := 0;
    if ((7-i)+dy < 0) then cy := -1 else if ((7-i)+dy >= 8) then cy := +1 else cy := 0;
    inc(changes[cx,cy]);
    nx := x+dx;
    ny := y+dy;
    cellInfo[ny, nx] := cell;
    cellInfo[y, x] := empty;

    {grr...}
    cellAttr[ny, nx div 8].x[nx and $7] := cellAttr[y, x div 8].x[x and $7];
    cellAttr[ny, nx div 8].y[nx and $7] := cellAttr[y, x div 8].y[x and $7];
    cellAttr[ny, nx div 8].vx[nx and $7] := cellAttr[y, x div 8].vx[x and $7];
    cellAttr[ny, nx div 8].vy[nx and $7] := cellAttr[y, x div 8].vy[x and $7];
    cellAttr[y, x div 8].x[x and $7] := 0;
    cellAttr[y, x div 8].y[x and $7] := 0;
    cellAttr[y, x div 8].vx[x and $7] := 0;
    cellAttr[y, x div 8].vy[x and $7] := 0;

    cellMoved[ny, nx div 8] := cellMoved[ny, nx div 8] or (1 shl (nx and $7));
  end;

  function checkAndMove(dx,dy: integer): boolean; inline;
  begin
    {todo: no bounds checking..}
    if (dword(x+dx) and $ffffff00) <> 0 then exit(false);
    if (dword(y+dy) and $ffffff00) <> 0 then exit(false);
    result := cellInfo[y+dy,x+dx].dtype = DT_EMPTY;
    if result then doMove(dx,dy);
  end;

begin
  empty.code := 0;
  fillchar(changes, sizeof(changes), 0);
  selfChanged := false;
  for i := 0 to 7 do begin
    y := gy*8+(7-i);
    for j := 0 to 7 do begin
      x := gx*8+j;

      {check if we have already moved}
      if (cellMoved[y, gx] and (1 shl j)) <> 0 then continue;

      cell := cellInfo[y,x];
      if cell.dtype in [DT_EMPTY, DT_ROCK] then continue;
      hasSupport := cellInfo[y+1, x].dtype <> DT_EMPTY;
      {get particle}
      vx := cellAttr[y, x div 8].vx[x and $7];
      vy := cellAttr[y, x div 8].vy[x and $7];
      if (vx = 0) and (vy = 0) and hasSupport then continue;
      selfChanged := true;
      px := cellAttr[y, x div 8].x[x and $7];
      py := cellAttr[y, x div 8].y[x and $7];
      {gravity}
      if not hasSupport then
        vy := clamp(vy + 3, -120, 120);
      cellAttr[y, x div 8].vy[x and $7] := vy;
      {move particle}
      px += vx;
      py += vy;
      if (px <= -127) then dx := -1 else if (px >= 128) then dx := +1 else dx := 0;
      if (py <= -127) then dy := -1 else if (py >= 128) then dy := +1 else dy := 0;
      cellAttr[y, x div 8].x[x and $7] := int8(byte(word(px) and $ff));
      cellAttr[y, x div 8].y[x and $7] := int8(byte(word(py) and $ff));
      if (dx <> 0) or (dy <> 0) then begin
        if not checkAndMove(dx, dy) then begin
          if dx <> 0 then cellAttr[y, x div 8].vx[x and $7] := vx div 2;
          if dy <> 0 then cellAttr[y, x div 8].vy[x and $7] := vy div 2;
        end;
      end;
    end;
  end;
  {keep track of block stats}
  if (not selfChanged) then begin
    blockInfo[gy, gx].status := blockInfo[gy, gx].status or BS_INACTIVE;
    exit;
  end;

  blockInfo[gy, gx].status := blockInfo[gy, gx].status or BS_DIRTY;

  for cx := -1 to 1 do begin
    for cy := -1 to 1 do begin
      delta := changes[cx,cy];
      // let all neighbours know to check themselves
      blockInfo[gy+cy, gx+cx].status := blockInfo[gy+cy, gx+cx].status and (not BS_INACTIVE);
      if delta = 0 then continue;
      blockInfo[gy+cy, gx+cx].status := blockInfo[gy+cy, gx+cx].status or BS_DIRTY;
    end;
  end;
end;

procedure tTerrain.update(elapsed: single);
var
  gx,gy: integer;
begin
  {we update the terrain simulation at 30 fps}
  timeUntilNextSolve -= elapsed;
  while timeUntilNextSolve < 0 do begin

    if solver = TS_PARTICLE then
      fillchar(cellMoved, sizeof(cellMoved), 0);

    inc(tick);

    for gy := 31-1 downto 1 do begin
      for gx := 1 to 31-1 do begin
        if ((blockInfo[gy, gx].status and BS_INACTIVE) <> 0) then continue;
        if ((blockInfo[gy, gx].status and BS_LOWP) <> 0) and (tick and $1 <> 0) then continue;
        case solver of
          TS_STATIC: ;
          TS_FALLING: updateBlockFalling_REF(gx, gy, self);
          TS_PARTICLE: updateBlockParticle_REF(gx, gy, blockInfo, cellInfo, cellAttr, cellMoved);
        end;
      end;
    end;
    timeUntilNextSolve += (1/30)
  end;
end;

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
