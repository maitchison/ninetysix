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

  tCellType = (CT_EMPTY, CT_DIRT);

  tCell = record
    cType: tCellType;
    strength: byte
  end;

  tTile = record
    status: byte; {see TS_...}
  end;

const

  TILES_X = 8;
  TILES_Y = 8;
  TILES_Z = 4;

  GRID_X = TILES_X*8;
  GRID_Y = TILES_Y*8;
  GRID_Z = TILES_Z*8;

var
  grid: array[0..GRID_Z-1, 0..GRID_Y-1,0..GRID_X-1] of tCell;
  tile: array[0..TILES_Z-1, 0..TILES_Y-1,  0..TILES_X-1] of tTile;
  screen: tScreen;

{initialize a semi random grid}
procedure initGrid();
var
  i,j,k: integer;
begin
  fillchar(grid, sizeof(grid), 0);
  fillchar(tile, sizeof(tile), TS_DIRTY);
  for i := 0 to GRID_X-1 do
    for j := 0 to GRID_Y-1 do
      for k := 0 to GRID_Z-1 do begin
        if rnd > k*8 then
          grid[k,j,i].cType := CT_DIRT;
      end;
end;

procedure updateTile(tx,ty,tz: integer);
var
  {number of changes applied to neighbour tiles}
  changes: array[-1..1, -1..1, -1..1] of integer;
  i,j,k: integer;
  x,y,z: integer;
  cell: tCell;
  cType: tCellType;
  selfChanged: boolean;
  {locals for subcalls, but I don't want stack frame}
  cx,cy,cz: integer;
  otherCell: tCell;

  procedure doMove(dx,dy,dz: integer); inline;
  begin
    selfChanged := true;
    if (i+dx < 0) then cx := -1 else if (i+dx >= 8) then cx := +1 else cx := 0;
    if (j+dy < 0) then cy := -1 else if (j+dy >= 8) then cy := +1 else cy := 0;
    if (k+dz < 0) then cz := -1 else if (k+dz >= 8) then cz := +1 else cz := 0;
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
    otherCell := grid[z+dz, y+dy, x+dx];
    result := (otherCell.cType = CT_EMPTY);
    if result then doMove(dx,dy,dz);
  end;

begin
  fillchar(changes, sizeof(changes), 0);
  for i := 0 to 7 do
    for j := 0 to 7 do
      for k := 7 downto 0 do begin
        x := tx*8+i;
        y := ty*8+j;
        z := tz*8+k;
        cell := grid[z,y,x];
        case cell.cType of
          CT_EMPTY: ;
          CT_DIRT: begin
            checkAndMove(0,0,-1);
          end;
        end;
      end;
end;

procedure updateGrid();
var
  i,j,k: integer;
begin
  for k := TILES_Z-1 downto 0 do
    for i := 0 to TILES_X-1 do
      for j := 0 to TILES_Y-1 do
        updateTile(i,j,k);
end;


{render our grid, by drawing every voxel... super slow...}
procedure renderGrid_REF();
var
  x,y,z: integer;
  dx,dy: integer;
  c: RGBA;
  l: byte;
begin
  screen.canvas.clear(RGB(100,200,250));
  {$R-}
  for z := 0 to GRID_Z-1 do
    for x := 0 to GRID_X-1 do
      for y := 0 to GRID_Y-1 do
      if grid[z,y,x].cType <> CT_EMPTY then begin
        dx := 160 + x - y;
        dy := 200 - z - ((x+y) div 2);
        l := 255-(z*4);
        screen.canvas.putPixel(dx, dy, RGB(l,l,l));
    end;
  {$R+}
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
begin
  renderGrid_REF();
  screen.pageFlip();

  ui := tGui.Create();

  fpsLabel := tGuiLabel.Create(Point(10,10));
  ui.append(fpsLabel);

  timer := tTimer.Create('main');

  repeat

    timer.start();

    elapsed := clamp(timer.elapsed, 0.001, 0.1);
    if timer.avElapsed > 0 then
      fpsLabel.text := format('%.1f', [1/timer.avElapsed]);

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
