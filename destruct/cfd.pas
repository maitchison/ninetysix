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
    size: tPowerOfTwo;
    procedure init(); virtual;
    procedure setDensity(x,y: integer; value: integer); virtual; abstract;
    procedure update(); virtual; abstract;
    procedure draw(screen: tScreen;xPos, yPos: integer); virtual; abstract;
  end;

  tLatticeBoltzmannGrid = class(tCFDGrid)
  protected
    f, fTemp: array[0..8] of tCellArray;
    displayRho, displayVel: tCellArray;
    procedure computeMacros(var rho, ux, uy: single; x,y: integer); inline;
    function  calcFreq(i: integer; rho,ux,uy,uxuv: single): single; inline;
    procedure collision(force: boolean=false);
    procedure stream();
  public
    procedure init(); override;
    procedure setDensity(x,y: integer; value: integer); override;
    procedure update(); override;
    procedure draw(screen: tScreen;xPos, yPos: integer); override;
  end;


const
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

{---------------------------------------------------------------}

procedure tCFDGrid.init();
begin
  size.init(7); {128x128}
end;

procedure tLatticeBoltzmannGrid.init();
var
  x, y, i: integer;
  rho, ux, uy: single;
begin

  inherited init();

  fillchar(displayRho, sizeof(displayRho), 0);
  fillchar(displayVel, sizeof(displayVel), 0);

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

procedure tLatticeBoltzmannGrid.setDensity(x,y: integer; value: integer);
begin
  if x < 0 then x := 0;
  if y < 0 then y := 0;
  if x > 127 then x := 127;
  if y > 127 then y := 127;
  f[0, x, y] := value;
end;

procedure tLatticeBoltzmannGrid.computeMacros(var rho, ux, uy: single; x,y: integer);
var
  i: integer;
  a: array[0..8] of single;
begin
  for i := 0 to 8 do a[i] := f[i,x,y];
  rho := a[0] + a[1] + a[2] + a[3] + a[4] + a[5] + a[6] + a[7] + a[8];
  if rho < 1e-6 then begin
    ux := 0; uy := 0;
    exit;
  end;
  ux := (a[1] - a[3] + a[5] - a[6] - a[7] + a[8]) / rho;
  uy := (a[2] - a[4] + a[5] + a[6] - a[7] - a[8]) / rho;
end;

function tLatticeBoltzmannGrid.calcFreq(i: integer; rho,ux,uy,uxuv: single): single; inline;
var
  eu: single;
begin
  eu := cx[i]*ux + cy[i]*uy;
  result := w[i] * rho * (1.0 + 3.0 * eu + 4.5 * eu * eu - 1.5 * uxuv);
end;

procedure tLatticeBoltzmannGrid.collision(force: boolean=false);
var
  x,y,i: integer;
  rho, ux, uy, freq: single;
  ux3, uy3: single; {3*ux}
  uxux,uyuy: single;  {ux*ux}
  eu3: single;
  uxuv,uv15: single;
  eu: single;

begin
  for y := 0 to 127 do begin
    for x := 0 to 127 do begin
      computeMacros(rho, ux, uy, x, y);

      {
      for i := 0 to 8 do begin
        freq := calcFreq(i, rho, ux, uy, uxuv);
        fTemp[i,x,y] := f[i,x,y] + omega * (freq - f[i,x,y]);
      end;}

      uxux := ux*ux;
      uyuy := uy*uy;
      ux3 := 3*ux;
      uy3 := 3*uy;
      uxuv := uxux + uyuy;
      uv15 := uxuv * 1.5;

      freq := (4/9) * rho * (1.0 - uv15);
      fTemp[0,x,y] := f[0,x,y] + omega * (freq - f[0,x,y]);
      freq := (1/9) * rho * (1.0 + ux3 + 4.5 * uxux - uv15);
      fTemp[1,x,y] := f[1,x,y] + omega * (freq - f[1,x,y]);
      freq := (1/9) * rho * (1.0 + uy3 + 4.5 * uyuy - uv15);
      fTemp[2,x,y] := f[2,x,y] + omega * (freq - f[2,x,y]);
      freq := (1/9) * rho * (1.0 - ux3 + 4.5 * uxux - uv15);
      fTemp[3,x,y] := f[3,x,y] + omega * (freq - f[3,x,y]);
      freq := (1/9) * rho * (1.0 - uy3 + 4.5 * uyuy - uv15);
      fTemp[4,x,y] := f[4,x,y] + omega * (freq - f[4,x,y]);
      eu3 := +ux3+uy3;
      freq := (1/36) * rho * (1.0 + eu3 + 0.5 * eu3 * eu3 - uv15);
      fTemp[5,x,y] := f[5,x,y] + omega * (freq - f[5,x,y]);
      eu3 := -ux3+uy3;
      freq := (1/36) * rho * (1.0 + eu3 + 0.5 * eu3 * eu3 - uv15);
      fTemp[6,x,y] := f[6,x,y] + omega * (freq - f[6,x,y]);
      eu3 := -ux3-uy3;
      freq := (1/36) * rho * (1.0 + eu3 + 0.5 * eu3 * eu3 - uv15);
      fTemp[7,x,y] := f[7,x,y] + omega * (freq - f[7,x,y]);
      eu3 := +ux3-uy3;
      freq := (1/36) * rho * (1.0 + eu3 + 0.5 * eu3 * eu3 - uv15);
      fTemp[8,x,y] := f[8,x,y] + omega * (freq - f[8,x,y]);

      displayRho[x,y] := rho;
      displayVel[x,y] := uxuv;
    end;
  end;
end;

procedure tLatticeBoltzmannGrid.stream();
var
  x,y,i,j,xdst,ydst: integer;
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

  procedure process(x,y: integer);
  var
    i, xDst, yDst: integer;
  begin
    for i := 0 to 8 do begin
      xDst := (x + cx[i] + size.value) and size.mask;
      yDst := (y + cy[i] + size.value) and size.mask;
      f[i, xdst, ydst] := fTemp[i, x, y];
    end;
  end;

begin
  {this is literally just a mem copy... I can ASM this no problem}
  {but this is a place where we also want to active inactive cells}
  for i := 0 to 8 do begin
    {perform copy}
    move(fTemp[i, 1, 1], f[i, 1+cx[i], 1+cy[i]], 126*128*4);
  end;
  {handle edges correctly}
  for j := 0 to 127 do begin
    process(0, j);
    process(j, 0);
    process(127, j);
    process(j, 127);
    process(1, j);
    process(j, 1);
    process(126, j);
    process(j, 126);
  end;
end;

procedure tLatticeBoltzmannGrid.update();
begin
  collision();
  stream();
end;

procedure tLatticeBoltzmannGrid.draw(screen: tScreen;xPos, yPos: integer);
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
