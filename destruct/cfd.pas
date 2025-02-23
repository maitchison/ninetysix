{computational fluid dynamics}
unit cfd;

{

Fast CFD, stored as struct-of-array

Grids are always 256x256

}

interface

uses
  graph2d,
  graph32,
  uScreen;

type

  tGridArray = array[0..127, 0..127] of single;

  tCFDGrid = class
    f, fTemp: array[0..8] of tGridArray;
    displayRho, displayVel: tGridArray;
    procedure init();
    procedure computeMacros(var rho, ux, uy: single; x,y: integer);
    function  freq(i: integer; rho,ux,uy: single): single;
    procedure collision();
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

procedure tCFDGrid.init();
var
  x, y, i: integer;
  rho, ux, uy: single;
begin

  rho := 1.0;
  ux := 0.05;
  uy := 0.00;

  for x := 0 to 128-1 do
    for y := 0 to 128-1 do
      for i := 0 to 8 do begin
        f[i,x,y] := w[i] * rho *
          (
            1.0
            + 3.0*(cx[i]*ux + cy[i]*uy)
            + 4.5*sqr(cx[i]*ux + cy[i]*uy)
            - 1.5*(sqr(ux) + sqr(uy))
          );
      end;
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
  if rho > 1e-8 then begin
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

procedure tCFDGrid.collision();
var
  x,y,i: integer;
  rho, ux, uy, freqVal: single;
begin
  for x := 0 to 127 do
    for y := 0 to 127 do begin
      computeMacros(rho, ux, uy, x, y);
      for i := 0 to 8 do begin
        freqVal := freq(i, rho, ux, uy);
        fTemp[i,x,y] := f[i,x,y] + omega * (freqVal - f[i,x,y]);
        displayRho[x,y] := rho;
        displayVel[x,y] := sqr(ux) + sqr(uy);
      end;
    end;
end;

procedure tCFDGrid.stream;
var
  x,y,i,xdst,ydst: integer;
begin
  for x := 0 to 127 do
    for y := 0 to 127 do
      for i := 0 to 8 do begin
        xDst := (x + cx[i] + 128) mod 128;
        yDst := (y + cy[i] + 128) mod 128;
        f[i, xdst, ydst] := fTemp[i, x, y];
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
      c := RGB(round(displayRho[x,y]*100), round(displayVel[x,y]*100), 0);
      screen.canvas.putPixel(xPos+x, yPos+y, c);
    end;
  screen.markRegion(Rect(xPos, yPos, 128, 128));
end;


begin
end.
