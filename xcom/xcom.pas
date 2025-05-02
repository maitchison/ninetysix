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
  uVESADriver,
  uVGADriver;

const

  TS_INACTIVE = 1;
  TS_LOWP = 2;
  TS_DIRTY = 4;

type
  tCell = record
    cType: byte;
    strength: byte
  end;

  tTile = record
    status: byte; {see TS_...}
  end;

const
  GRID_X = 128;
  GRID_Y = 128;
  GRID_Z = 64;

var
  grid: array[0..GRID_Z-1, 0..GRID_Y-1,0..GRID_X-1] of tCell;
  tile: array[0..(GRID_Z div 8)-1, 0..(GRID_Y div 8)-1,  0..(GRID_X div 8)-1] of tTile;
  screen: tScreen;

{initialize a semi random grid}
procedure initGrid();
var
  i,j,k: integer;
begin
  fillchar(grid, sizeof(grid), 0);
  for i := 0 to GRID_X-1 do
    for j := 0 to GRID_Y-1 do
      for k := 0 to GRID_Z-1 do begin
        if rnd > k*8 then
          grid[k,j,i].cType := 1;
      end;
end;

{render our grid, by drawing every voxel... super slow...}
procedure renderGrid_REF();
var
  x,y,z: integer;
  dx,dy: integer;
  c: RGBA;
  l: byte;
begin
  for z := 0 to GRID_Z-1 do
    for x := 0 to GRID_X-1 do
      for y := 0 to GRID_Y-1 do
      if grid[z,y,x].cType = 1 then begin
        dx := 160 + x - y;
        dy := 200 - z - ((x+y) div 2);
        l := 255-(z*4);
        screen.canvas.putPixel(dx, dy, RGB(l,l,l));

    end;
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
begin

  renderGrid_REF();
  screen.pageFlip();

  repeat
  until keyDown(key_esc);
end;

begin
  setup();
  initGrid();
  main();
  videoDriver.setText();
end.

