program xcom;

(*
This is really just a 3d falling sand simulation for the moment.

Very much a prototype.

Goal is to get a 'sandpit' that fills up with sand.
*)

uses
  uTest,
  uDebug,
  uUtils,
  uVertex,
  uRect,
  uGraph32,
  uPoly,
  uColor,
  uMath,
  uVoxel,
  uMouse,
  uKeyboard,
  uScreen,
  uGui,
  uTimer,
  uGuiLabel,
  uVESADriver,
  uVGADriver;

const

  TS_INACTIVE = 1;
  TS_LOWP = 2;
  TS_DIRTY = 4;

type

  tCellType = (CT_EMPTY, CT_DIRT, CT_SAND, CT_ROCK);

  tCell = record
    cType: tCellType;
    damage: byte;
    rng: byte;
  end;

  tTile = record
    status: byte; {see TS_...}
    count: word; {number of cells in tile}
  end;

  pTile = ^tTile;

const

  TILES_X = 16;
  TILES_Y = 16;
  TILES_Z = 16;

  TILE_SIZE = 4;

  GRID_X = TILES_X*TILE_SIZE;
  GRID_Y = TILES_Y*TILE_SIZE;
  GRID_Z = TILES_Z*TILE_SIZE;

var
  grid: array[0..GRID_Z-1, 0..GRID_Y-1,0..GRID_X-1] of tCell;
  tile: array[0..TILES_Z-1, 0..TILES_Y-1,  0..TILES_X-1] of tTile;
  screen: tScreen;

const
  STAT_TILE_DRAW: integer = 0;
  STAT_TILE_UPDATE: integer = 0;

procedure refreshTiles();
var
  i,j,k: integer;
  x,y,z: integer;
begin
  for i := 0 to TILES_X-1 do
    for j := 0 to TILES_Y-1 do
      for k := 0 to TILES_Z-1 do begin
        tile[k,j,i].count := 0;
        tile[k,j,i].status := TS_DIRTY;
      end;
  for x := 0 to GRID_X-1 do
    for y := 0 to GRID_Y-1 do
      for z := 0 to GRID_Z-1 do begin
        if grid[z,y,x].cType <> CT_EMPTY then inc(tile[z div TILE_SIZE, y div TILE_SIZE, z div TILE_SIZE].count);
      end;
end;

procedure addSand(x,y,z: integer; ctype: tCellType=CT_SAND);
var
  tileRef: pTile;
begin
  if word(x) >= GRID_X then exit;
  if word(y) >= GRID_Y then exit;
  if word(z) >= GRID_Z then exit;
  tileRef := @tile[z div TILE_SIZE, y div TILE_SIZE, x div TILE_SIZE];
  if grid[z,y,x].cType = CT_EMPTY then inc(tileRef^.count);
  grid[z,y,x].cType := ctype;
  grid[z,y,x].damage := (rnd mod 32) + round(sin(getSec) * 100)+100;
  if keyDown(key_space) then grid[z,y,x].damage := 255;
  grid[z,y,x].rng := rnd;
  tileRef^.status := TS_DIRTY;
end;

{initialize a semi random grid}
procedure initGrid();
var
  i,j,k: integer;
begin
  fillchar(grid, sizeof(grid), 0);
  for i := 0 to GRID_X-1 do
    for j := 0 to GRID_Y-1 do
      for k := 0 to GRID_Z-1 do begin
        if rnd > k * 8 then
          grid[k,j,i].cType := CT_SAND;
      end;

  for i := 0 to GRID_X-1 do
    for j := 0 to 20 do
      for k := 0 to 3 do
        addSand(i, 10+k, j, CT_ROCK);

  refreshTiles();
end;

procedure updateTile(tx,ty,tz: integer);
var
  {number of changes applied to neighbour tiles}
  changes: array[-1..1, -1..1, -1..1] of integer;
  t: integer;
  i,j,k: integer;
  x,y,z: integer;
  cell: tCell;
  cType: tCellType;
  selfChanged: boolean;
  delta: integer;
  rng: byte;
  dx,dy: integer;
  {locals for subcalls, but I don't want stack frame}
  cx,cy,cz: integer;
  otherCell: tCell;
  thisTile, otherTile: pTile;
  perm1, perm2: array[0..TILE_SIZE-1] of byte;
  a,b,c: integer;

  procedure doMove(dx,dy,dz: integer); inline;
  begin
    selfChanged := true;
    if (i+dx < 0) then cx := -1 else if (i+dx >= TILE_SIZE) then cx := +1 else cx := 0;
    if (j+dy < 0) then cy := -1 else if (j+dy >= TILE_SIZE) then cy := +1 else cy := 0;
    if (k+dz < 0) then cz := -1 else if (k+dz >= TILE_SIZE) then cz := +1 else cz := 0;
    inc(changes[cx,cy,cz]);
    otherCell := grid[z+dz, y+dy, x+dx];
    grid[z+dz, y+dy, x+dx] := cell;
    grid[z, y, x] := otherCell;
  end;

  function checkAndMove(dx,dy,dz: integer): boolean; inline;
  begin
    {bounds checking}
    if dword(x+dx) >= GRID_X then exit(false);
    if dword(y+dy) >= GRID_Y then exit(false);
    if dword(z+dz) >= GRID_Z then exit(false);
    result := (grid[z+dz, y+dy, x+dx].cType = CT_EMPTY);
    if result then doMove(dx,dy,dz);
  end;

  procedure genPerm(var perm: array of byte);
  var
    i: integer;
    a,b,temp: integer;
  begin
    for i := 0 to TILE_SIZE-1 do
      perm[i] := i;
    for i := 0 to 3 do begin
      a := rnd and (TILE_SIZE-1);
      b := rnd and (TILE_SIZE-1);
      temp := perm[a];
      perm[a] := perm[b];
      perm[b] := temp;
    end;
  end;


const
  DELTA_X: array of integer = [1, 0, 0, -1, -1, -1, 1, 1];
  DELTA_Y: array of integer = [0, 1, -1, 0, -1, 1,  1, -1];

begin
  fillchar(changes, sizeof(changes), 0);
  selfChanged := false;

  inc(STAT_TILE_UPDATE);

  genPerm(perm1);
  genPerm(perm2);

  for a := 0 to TILE_SIZE-1 do
    for b := 0 to TILE_SIZE-1 do
      for c := 0 to TILE_SIZE-1 do begin
        {update order, do z in order, and other do random perm}
        i := perm1[c];
        j := perm2[b];
        k := a;

        x := tx*TILE_SIZE+i;
        y := ty*TILE_SIZE+j;
        z := tz*TILE_SIZE+k;
        cell := grid[z,y,x];
        case cell.cType of
          CT_EMPTY,
          CT_ROCK
          : ;
          CT_DIRT: begin
            checkAndMove(0,0,-1);
          end;
          CT_SAND: begin
            if checkAndMove(0,0,-1) then continue;
            rng := rnd and $7;
            if (rng >= 4) and ((rnd and $1) = 1) then continue; {only check corerns half the time}
            if checkAndMove(DELTA_X[rng], DELTA_Y[rng], -1) then continue;
          end;
        end;
      end;

  thisTile := @tile[tz, ty, tx];

  {keep track of tile stats}
  if (not selfChanged) then begin
    {if nothing moved then we sleep the block.}
    thisTile^.status := thisTile^.status or TS_INACTIVE;
    exit;
  end;

  thisTile^.status := thisTile^.status or TS_DIRTY;

  for cx := -1 to 1 do begin
    for cy := -1 to 1 do begin
      for cz := -1 to 1 do begin
        delta := changes[cx,cy,cz];
        if word(tx+cx) >= TILES_X then continue;
        if word(ty+cy) >= TILES_Y then continue;
        if word(tz+cz) >= TILES_Z then continue;
        otherTile := @tile[tz+cz,ty+cy,tx+cx];
        {exchange}
        otherTile^.count += delta;
        thisTile^.count -= delta;

        {let other tile know to check itself, as our change might cause it
         to no longer be stable}
        otherTile.status := otherTile.status and (not TS_INACTIVE);
        if delta <> 0 then
          otherTile.status := otherTile.status or TS_DIRTY;
      end;
    end;
  end;
end;

procedure updateGrid();
var
  i,j,k: integer;
begin
  STAT_TILE_UPDATE := 0;
  for k := 0 to TILES_Z-1 do
    for j := 0 to TILES_Y-1 do
      for i := 0 to TILES_X-1 do begin
        if ((tile[k,j,i].status and TS_INACTIVE) = TS_INACTIVE) then continue;
        updateTile(i,j,k);
      end;
end;

procedure drawTile_REF(tx,ty,tz: integer);
var
  i,j,k: integer;
  x,y,z: integer;
  dx,dy,dz: integer;
  l: integer;
  c: RGBA;
  tileRef: pTile;
  cType: tCellType;
begin
  inc(STAT_TILE_DRAW);

  {draw our marker - if needed}
  {
  dx := 160 + tx*TILE_SIZE - ty*TILE_SIZE;
  dy := 200 - tz*TILE_SIZE - ((tx*TILE_SIZE+ty*TILE_SIZE) div 2);
  c := RGB(0,0,0);
  tileRef := @tile[tz, ty, tx];
  if (tileRef^.status and TS_INACTIVE) = TS_INACTIVE then c.r := 128;
  if (tileRef^.status and TS_DIRTY) = TS_DIRTY then c.r := 255;
  c.g := tileRef^.count and $ff;
  c.a := 0;
  screen.canvas.setPixel(dx, dy, c);
  }

  for i := 0 to TILE_SIZE-1 do
    for j := 0 to TILE_SIZE-1 do begin
      x := tx*TILE_SIZE+i;
      y := ty*TILE_SIZE+j;
      dx := 160 + x - y;
      dz := (x + y); {z is depth}
      l := dz;
      for k := 0 to TILE_SIZE-1 do begin
        z := tz*TILE_SIZE+k;
        cType := grid[z,y,x].cType;
        if cType = CT_EMPTY then continue;
        dy := 200 - z - ((x+y) div 2);
        if dz >= screen.canvas.getPixel(dx,dy).a then continue;
        case cType of
          CT_ROCK: c := RGB(128,128,128);
          CT_SAND: c := RGB(l,grid[z,y,x].damage,l,dz);
        end;
        screen.canvas.setPixel(dx, dy, c);
    end;
  end;
end;

proc

{render our grid, by drawing every voxel... super slow...}
procedure renderGrid_REF();
var
  tx,ty,tz: integer;
  x,y,z: integer;
  dx,dy: integer;
  c: RGBA;
  l: byte;
begin
  STAT_TILE_DRAW := 0;
  screen.canvas.clear(RGB(100,200,250,255));
  for tz := 0 to TILES_Z-1 do
    for ty := 0 to TILES_Y-1 do
      for tx := 0 to TILES_X-1 do
        if tile[tz, ty, tx].count > 0 then
          drawTile_REF(tx,ty,tz);
end;

procedure setup();
begin
  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    fatal('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    fatal('Requires 1MB video card.');
  videoDriver.setTrueColor(320, 240);
  initMouse();
  initKeyboard();
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;
end;

procedure main();
var
  ui: tGui;
  fpsLabel: tGuiLabel;
  timer: tTimer;
  elapsed: single;
  i: integer;
begin
  renderGrid_REF();
  screen.pageFlip();

  ui := tGui.Create();

  fpsLabel := tGuiLabel.Create(Point(10,10));
  fpsLabel.setSize(120,21);
  ui.append(fpsLabel);

  timer := tTimer.Create('main');

  repeat

    timer.start();

    elapsed := clamp(timer.elapsed, 0.001, 0.1);
    if timer.avElapsed > 0 then
      fpsLabel.text := format('%.1f %d %d', [1/timer.avElapsed, STAT_TILE_DRAW, STAT_TILE_UPDATE]);

    for i := 0 to 15 do
      addSand(round(sin(getSec*3.1)*4)+32-4+(rnd mod 4),round(cos(getSec*3.1)*4)+32-4+(rnd mod 4), GRID_Z-1-(rnd mod 4));
    updateGrid();
    renderGrid_REF();

    ui.update(elapsed);
    ui.draw(screen.getDC());

    screen.pageFlip();

    timer.stop();
  until keyDown(key_esc);
end;

begin
  setup();
  initGrid();
  main();
  videoDriver.setText();
end.
