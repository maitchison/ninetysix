unit terraNova;

interface

{
Every pixel is a particle, that can moves and collide
}

uses
  test, debug,
  utils,
  vertex,
  template,
  graph2d, graph32, uScreen;

const
  BS_INACTIVE = 1;   // no updates required as no cells can move
  BS_DIRTY = 2;      // must redraw this block as it's changed
  BS_LOWP = 4;       // update every 4th tick (if active)

type

  tDirtType = (DT_EMPTY, DT_DIRT, DT_SAND, DT_ROCK, DT_GRASS, DT_WATER, DT_LAVA, DT_OBSIDIAN, DT_BEDROCK, DT_TANKCORE);

  tCellInfo = record
    case byte of
    0: (
      strength: byte;
      dType: tDirtType;
    );
    1: (code: word);
  end;

  pCellInfo = ^tCellInfo;

  tBlockInfo = record
    status: byte;
  end;

  tCellInfoArray = array[0..256-1, 0..256-1] of tCellInfo;
  tBlockInfoArray = array[0..32-1, 0..32-1] of tBlockInfo;

  tCellChangeHook = procedure (x,y: integer;cell: pCellInfo);
  tCellDamageHook = procedure (x,y: integer;damage: integer);

  tTerrain = class
  protected
    {todo: these need to be aligned to 32 bytes, which means custom getMem}
    cellInfo: tCellInfoArray;
    blockInfo: tBlockInfoArray;
    timeUntilNextSolve: single;
    tick: dword;
  public

    {fired only for DT_TANKCORE}
    onCellChange: tCellChangeHook;
    onCellDamage: tCellDamageHook;

    sky: tPage;

    constructor create();
    destructor destroy(); override;

    procedure clear(); virtual;

    function  getCell(x,y: integer): tCellInfo; inline;
    procedure setCell(x,y: integer; cell: tCellInfo); inline;
    function  isEmpty(x, y: integer): boolean; inline;
    function  isSolid(x, y: integer): boolean; inline;
    function  getCellColor(c: tCellInfo): RGBA; inline;

    procedure putCircle(atX,atY: integer;r: integer; dType: tDirtType=DT_DIRT);
    procedure putDirt(atX,atY: integer;cell: tCellInfo);
    procedure burn(atX,atY: integer;r: integer;power:integer=255);
    function  getTerrainHeight(xPos: integer): integer;
    function  getGradient(x,y: integer;radius: integer=2): V2D;

    procedure generate(minHeight: integer=0);

    procedure draw(screen: tScreen);
    procedure update(elapsed: single);
  end;

const
  TERRAIN_COLOR: array[tDirtType] of RGBA = (
    (b:$00; g:$00; r:$00; a: $ff), //none
    (b:$44; g:$80; r:$8d; a: $ff), //dirt
    (b:$99; g:$e5; r:$ff; a: $ff), //sand
    (b:$44; g:$44; r:$44; a: $ff), //rock
    (b:$5d; g:$80; r:$0d; a: $ff), //grass
    (b:$fd; g:$30; r:$2d; a: $ff), //water
    (b:$04; g:$08; r:$ad; a: $ff), //lava
    (b:$6e; g:$40; r:$39; a: $ff), //obsidian
    (b:$10; g:$20; r:$30; a: $ff), //bedrock
    (b:$ff; g:$00; r:$ff; a: $00)  //tankcore
  );

  {todo: seperate table for type, i.e solid,liquid,gas}
  {currently -1 -> water or gas, 0+ -> solid}
  TERRAIN_DECAY: array[tDirtType] of integer = (
    -1, //empty
    3,  //dirt
    6,  //sand
    2,  //rock
    32 ,//grass
    -1, //water
    -1, //lava
    1,  //obsidian
    0,  //bedrock
    1   //tankcore
  );


implementation

uses
  uGameObjects,
  game,
  keyboard; {for debugging}

var
  terrainColorLookup: array[tDirtType, 0..255] of RGBA;

{-----------------------------------------------------------}

constructor tTerrain.create();
begin
  inherited create();
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
  result := TERRAIN_DECAY[getCell(x, y).dType] >= 0;
end;

function tTerrain.getCellColor(c: tCellInfo): RGBA; inline;
begin
  result := terrainColorLookup[c.dtype, c.strength];
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
      if TERRAIN_DECAY[cell.dtype] <= 0 then continue;
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
begin
  if r <= 0 then exit;
  r2 := r*r;
  for dy := -r to +r do begin
    for dx := -r to +r do begin
      x := atX+dx;
      y := atY+dy;
      if word(x)>255 then continue;
      if word(y)>255 then continue;
      dst2 := (dx*dx)+(dy*dy);
      if (dst2 > r2) then continue;
      if isSolid(x, y) then continue;
      cell.dType := dType;
      cell.strength := 200+rnd(40);
      setCell(x, y, cell);
    end;
  end;
end;

{places dirt at location, if location is full will place nearby}
procedure tTerrain.putDirt(atX,atY: integer;cell: tCellInfo);
var
  dx,dy: integer;

  function trySet(dx,dy: integer): boolean;
  begin
    result := not(isSolid(atX+dx, atY+dy));
    if result then setCell(atX+dx, atY+dy, cell)
  end;

begin
  if trySet(0, 0) then exit;
  if trySet(0, -1) then exit;
  if trySet(+1, -1) then exit;
  if trySet(-1, -1) then exit;
  if trySet(+1, 0) then exit;
  if trySet(-1, 0) then exit;
  if trySet(+1, 1) then exit;
  if trySet(-1, 1) then exit;
  {ok.. failed}
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

{gets gradient at given location. this is not fast...
gradient points away from dirt
}
function tTerrain.getGradient(x,y: integer;radius: integer=2): V2D;
var
  centerOfMass: V2D;
  dx,dy: integer;
begin
  centerOfMass := V2(0,0);
  for dy := -radius to +radius do
    for dx := -radius to +radius do
      if isSolid(x+dx,y+dy) then
        centerOfMass += V2(dx,dy);
  result := centerOfMass * (-1/sqr(2*radius+1));
end;

procedure tTerrain.generate(minHeight: integer);
var
  dirtHeight: array[0..255] of integer;
  rockHeight: array[0..255] of integer;
  i,x,y: integer;
  c: RGBA;
  cell: tCellInfo;
  v: single;
  prob: single;
  phase: array[1..6] of single;
begin

  clear();

  for i := 1 to 6 do
    phase[i] := (rnd/256)*2*pi;

  for x := 0 to 255 do begin
    dirtHeight[x] := minHeight+158 + round(30*sin(phase[1]+x*0.0197) - 67*cos(phase[2]+x*0.003) + 15*sin(phase[3]+x*0.023));
    rockHeight[x] := minHeight+220 + round(30*sin(phase[4]+x*0.0197) - 67*cos(phase[5]+x*0.003) + 15*sin(phase[6]+x*0.023)) div 4;
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

  {add bedrock layer}
  for y := 235 to 255 do begin
    case y of
      235: prob := 0.25;
      236: prob := 0.50;
      237: prob := 0.75;
      else prob := 1.0;
    end;
    for x := 0 to 255 do begin
      if (rnd/255) > prob then continue;
      cell.dType := DT_BEDROCK;
      cell.strength := 200+rnd(50);
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
    r := Rect(gx*8+VIEWPORT_X, gy*8+VIEWPORT_Y, 9,9);
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
        if c.a = 0 then continue;
        screen.background.setPixel(x+VIEWPORT_X, y+VIEWPORT_Y, c);
      end;
    end;
    screen.markRegion(Rect(gx*8+VIEWPORT_X, gy*8+VIEWPORT_Y, 8,8));
  end;

  procedure drawBlock_ASM(gx, gy: integer);
  var
    skyPtr, lookupPtr, screenPtr, cellPtr: pointer;
    screenInc: dword;
  begin
    lookupPtr := @terrainColorLookup;
    screenPtr := screen.background.getAddress(gx*8+VIEWPORT_X, gy*8+VIEWPORT_Y);
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
      cmp ah, byte(DT_TANKCORE)
      je  @SKY

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

    screen.markRegion(Rect(gx*8+VIEWPORT_X, gy*8+VIEWPORT_Y, 8,8));
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
  otherCell: tCellInfo;
  dtype: tDirtType;
  rng: byte;

  procedure doMove(dx,dy: integer); inline;
  begin
    if (cell.dType <> DT_LAVA) then selfChanged := true;
    if (j+dx < 0) then cx := -1 else if (j+dx >= 8) then cx := +1 else cx := 0;
    if ((7-i)+dy < 0) then cy := -1 else if ((7-i)+dy >= 8) then cy := +1 else cy := 0;
    inc(changes[cx,cy]);
    otherCell := terrain.cellInfo[y+dy, x+dx];
    terrain.cellInfo[y+dy, x+dx] := cell;
    terrain.cellInfo[y, x] := otherCell;
  end;

  {returns if move completed}
  function checkAndMove(dx,dy: integer): boolean; inline;
  begin
    {todo: no bounds checking..}
    if (dword(x+dx) and $ffffff00) <> 0 then exit(false);
    if (dword(y+dy) and $ffffff00) <> 0 then exit(false);
    dtype := terrain.cellInfo[y+dy,x+dx].dtype;
    {we can swap with liquids, but liquids so not self swap}
    result := (dType = DT_EMPTY);
    if result then doMove(dx,dy);
  end;

  {returns if move completed, swaps with liquid}
  function checkAndSwap(dx,dy: integer): boolean; inline;
  begin
    {todo: no bounds checking..}
    if (dword(x+dx) and $ffffff00) <> 0 then exit(false);
    if (dword(y+dy) and $ffffff00) <> 0 then exit(false);
    dtype := terrain.cellInfo[y+dy,x+dx].dtype;
    {we can swap with liquids, but liquids so not self swap}
    result := (TERRAIN_DECAY[dType] < 0) and (dtype <> cell.dType);
    if result then doMove(dx,dy);
  end;

  {returns if cell is empty}
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
    if dword(x+dx) > 255 then exit(0);
    if dword(y+dy) > 255 then exit(0);
    dType := terrain.cellInfo[y+dy,x+dx].dType;
    case dType of
      DT_EMPTY, DT_LAVA, DT_OBSIDIAN: exit(0);
      DT_TANKCORE: begin
        if assigned(terrain.onCellDamage) then
          terrain.onCellDamage(x+dx,y+dy,1);
      end;
      else terrain.burn(x+dx, y+dy, 1, burn);
    end;
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
        DT_EMPTY,
        DT_ROCK,
        DT_BEDROCK,
        DT_TANKCORE:
          ;
        DT_DIRT: checkAndMove(0,1);
        DT_OBSIDIAN: begin
          {slowly move down in water}
          if (rnd > 128) then
            checkAndSwap(0,1)
          else
            checkAndMove(0,1);
        end;
        DT_SAND: begin
          rng := rnd;
          if (rnd > 10) then begin
            if checkAndMove(0,1) then continue
          end else begin
            {disolve into lava / water}
            if checkAndSwap(0,1) then continue;
          end;
          if rng > 128 then coin := 1 else coin := -1;
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
          heatLost += doBurn(0, 1, 3);
          heatLost += doBurn(-1, 1, 2);
          heatLost += doBurn(+1, 1, 2);
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
      if word(gx+cx) >= 32 then continue;
      if word(gy+cy) >= 32 then continue;
      // let all neighbours know to check themselves
      terrain.blockInfo[gy+cy, gx+cx].status := terrain.blockInfo[gy+cy, gx+cx].status and (not BS_INACTIVE);
      if delta = 0 then continue;
      terrain.blockInfo[gy+cy, gx+cx].status := terrain.blockInfo[gy+cy, gx+cx].status or BS_DIRTY;
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

    inc(tick);

    for gy := 31-1 downto 1 do begin
      for gx := 0 to 32-1 do begin
        if ((blockInfo[gy, gx].status and BS_INACTIVE) <> 0) then continue;
        if ((blockInfo[gy, gx].status and BS_LOWP) <> 0) and (tick and $1 <> 0) then continue;
        updateBlockFalling_REF(gx, gy, self);
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
