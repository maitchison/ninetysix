{computational fluid dynamics}
unit cfd;

{

Fast CFD, stored as struct-of-array

Grids are always 256x256

}

interface

uses
  debug,
  utils,
  graph2d,
  graph32,
  uScreen;

type

  tPowerOfTwo = record
    mask: word;
    value: word;
    shift: byte;
    procedure init(aShift: byte);
  end;

  tCellArray = array[0..127, 0..127] of single;
  tGridArray = array[0..15, 0..15] of byte;

  tCFDGrid = class
    f, fTemp: array[0..8] of tCellArray;
    displayRho, displayVel: tCellArray;
    size: tPowerOfTwo;
    procedure init();
    procedure setDensity(x,y: integer; value: integer);
    procedure computeMacros(var rho, ux, uy: single; x,y: integer);
    function  freq(i: integer; rho,ux,uy: single): single;
    procedure collision(force: boolean=false);
    procedure stream();
    procedure update();
    procedure draw(screen: tScreen;xPos, yPos: integer);
  end;


var
  w: array[0..8] of single = (4/9, 1/9, 1/9, 1/9, 1/9, 1/36, 1/36, 1/36, 1/36);
  cx: array[0..8] of integer = (0, +1,  0, -1,  0, +1, -1, -1, +1);
  cy: array[0..8] of integer = (0,  0, +1,  0, -1, +1, +1, -1, -1);
  omega: single = 1.7;

implementation

procedure tPowerOfTwo.init(aShift: byte);
begin
  mask := (1 shl aShift) - 1;
  value := 1 shl aShift;
  shift := aShift;
end;

procedure tCFDGrid.init();
var
  x, y, i: integer;
  rho, ux, uy: single;
begin

  fillchar(displayRho, sizeof(displayRho), 0);
  fillchar(displayVel, sizeof(displayVel), 0);

  size.init(7); {128x128}

  rho := 1.0;
  ux := 0.05;
  uy := 0.00;

  for x := 0 to 127 do
    for y := 0 to 127 do
      for i := 0 to 8 do begin
        f[i,x,y] := w[i] * rho *
          (
            1.0
            + 3.0*(cx[i]*ux + cy[i]*uy)
            + 4.5*sqr(cx[i]*ux + cy[i]*uy)
            - 1.5*(sqr(ux) + sqr(uy))
          );
      end;

  collision(true);
end;

procedure tCFDGrid.setDensity(x,y: integer; value: integer);
begin
  if x < 0 then x := 0;
  if y < 0 then y := 0;
  if x > 127 then x := 127;
  if y > 127 then y := 127;
  f[0, x, y] := value;
end;

procedure tCFDGrid.computeMacros(var rho, ux, uy: single; x,y: integer);
var
  i: integer;
begin
  rho := 0;
  ux := 0;
  uy := 0;
  for i := 0 to 8 do
    rho += f[i,x,y];
  if rho > 1e-6 then begin
    {this could be much optimized with MMX}
    for i := 0 to 8 do begin
      ux += f[i,x,y]*cx[i];
      uy += f[i,x,y]*cy[i];
    end;
    ux := ux / rho;
    uy := uy / rho;
  end else begin
    ux := 0;
    uy := 0;
  end;
end;

function tCFDGrid.freq(i: integer; rho,ux,uy: single): single;
var
  eu, uv: single;
begin
  eu := cx[i]*ux + cy[i]*uy;
  uv := sqr(ux) + sqr(uy);
  freq := w[i] * rho * (1.0 + 3.0 * eu + 4.5 * eu * eu - 1.5 * uv);
end;

procedure tCFDGrid.collision(force: boolean=false);
var
  x,y,i: integer;
  gx,gy: integer;

  procedure cellSlow(gx,gy: integer);
  var
    xx,yy,i,x,y: integer;
    rho, ux, uy, freqVal: single;
  begin
    for yy := 0 to 7 do begin
      for xx := 0 to 7 do begin
        x := gx * 8 + xx;
        y := gy * 8 + yy;
        computeMacros(rho, ux, uy, x, y);
        for i := 0 to 8 do begin
          freqVal := freq(i, rho, ux, uy);
          fTemp[i,x,y] := f[i,x,y] + omega * (freqVal - f[i,x,y]);
        end;
        displayRho[x,y] := rho;
        displayVel[x,y] := sqr(ux) + sqr(uy);
      end;
    end;
  end;

begin
  for gy := 0 to 15 do begin
    for gx := 0 to 15 do begin
      cellSlow(gx, gy);
    end;
  end;
end;

procedure tCFDGrid.stream;
var
  x,y,i,xdst,ydst: integer;
  gx,gy,xx,yy: integer;

  procedure streamCell(gx,gy: integer);
  var
    i,xx,yy,x,y: integer;
  begin
    for yy := 0 to 7 do begin
      for xx := 0 to 7 do begin
        x := gx * 8 + xx;
        y := gy * 8 + yy;
        for i := 0 to 8 do begin
          xDst := (x + cx[i] + size.value) and size.mask;
          yDst := (y + cy[i] + size.value) and size.mask;
          f[i, xdst, ydst] := fTemp[i, x, y];
        end;
      end;
    end;
  end;

begin
  {this is literally just a mem copy... I can ASM this no problem}
  {but this is a place where we also want to active inactive cells}
  for gy := 0 to 15 do begin
    for gx := 0 to 15 do begin
      streamCell(gx, gy);
    end;
  end;
end;

procedure tCFDGrid.update();
begin
  collision();
  stream();
end;

procedure tCFDGrid.draw(screen: tScreen;xPos, yPos: integer);
var
  x,y: integer;
  density, velocity: single;
  c: RGBA;
begin
  for x := 0 to 127 do
    for y := 0 to 127 do begin
      c := RGB(round(displayRho[x,y]*100), round(displayVel[x,y]*200), 0);
      screen.canvas.setPixel(xPos+x, yPos+y, c);
    end;
  screen.markRegion(Rect(xPos, yPos, 128, 128));
end;


begin
end.
