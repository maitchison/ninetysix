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

  tIntCellArray = array[0..127, 0..127] of single;
  tFloatCellArray = array[0..127, 0..127] of single;
  tGridArray = array[0..15, 0..15] of byte;

  tCFDGrid = class
    size: tPowerOfTwo;
    procedure init(); virtual;
    procedure addDensity(x,y: integer; value: single);
    procedure setDensity(x,y: integer; value: single); virtual; abstract;
    function  getDensity(x,y: integer): single; virtual; abstract;
    procedure update(); virtual; abstract;
    procedure draw(screen: tScreen;xPos, yPos: integer); virtual; abstract;
  end;

  {method1: pressure 'diffuses' into the surrounding area. Implemented with a blur}
  tDiffusionGrid = class(tCFDGrid)
  protected
    f, fTemp: tFloatCellArray;
  public
    procedure init(); override;
    procedure setDensity(x,y: integer; value: single); override;
    function  getDensity(x,y: integer): single; override;
    procedure update(); override;
    procedure draw(screen: tScreen;xPos, yPos: integer); override;
  end;

  tLatticeBoltzmannGrid = class(tCFDGrid)
  protected
    f, fTemp: array[0..8] of tFloatCellArray;
    displayRho, displayVel: tFloatCellArray;
    procedure computeMacros(var rho, ux, uy: single; x,y: integer); inline;
    function  calcFreq(i: integer; rho,ux,uy,uxuv: single): single; inline;
    procedure collision(force: boolean=false);
    procedure stream();
  public
    procedure init(); override;
    procedure setDensity(x,y: integer; value: single); override;
    function  getDensity(x,y: integer): single; override;
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

procedure tCFDGrid.addDensity(x,y: integer; value: single);
begin
  setDensity(x,y, getDensity(x,y) + value);
end;

{---------------------------------------------------------------}

procedure tDiffusionGrid.init();
begin
  fillchar(f, sizeof(f), 0);
  fillchar(fTemp, sizeof(fTemp), 0);
end;

procedure tDiffusionGrid.setDensity(x,y: integer; value: single);
begin
  if (x < 0) or (y < 0) or (x > 127) or (y > 127) then exit;
  f[y, x] := value;
end;

function tDiffusionGrid.getDensity(x,y: integer): single;
begin
  result := 0;
  if (x < 0) or (y < 0) or (x > 127) or (y > 127) then exit;
  result := f[y, x]
end;

procedure tDiffusionGrid.update();
var
  x,y: integer;
  dx,dy: integer;
  prev4, this4, next4: single;
begin
  for y := 1 to 128-2 do begin
    prev4 := f[y,0]*0.25;
    this4 := f[y,1]*0.25;
    for x := 1 to 128-2 do begin
      next4 := f[y,x+1]*0.25;
      f[y,x] := (prev4) + (this4*2) + (next4);
      prev4 := this4;
      this4 := next4;
    end;
  end;
  for x := 1 to 128-2 do begin
    prev4 := f[0,x]*0.25;
    this4 := f[1,x]*0.25;
    for y := 1 to 128-2 do begin
      next4 := f[y+1,x]*0.25;
      f[y,x] := (prev4) + (this4*2) + (next4);
      prev4 := this4;
      this4 := next4;
    end;
  end;
end;

procedure tDiffusionGrid.draw(screen: tScreen;xPos, yPos: integer);
var
  x,y: integer;
  density, velocity: single;
  c: RGBA;
begin
  for x := 0 to 127 do
    for y := 0 to 127 do begin
      c := RGB(round(f[y,x]*1000), round(f[y,x]*200), 0);
      screen.canvas.setPixel(xPos+x, yPos+y, c);
    end;
  screen.markRegion(Rect(xPos, yPos, 128, 128));
end;


{---------------------------------------------------------------}

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

procedure tLatticeBoltzmannGrid.setDensity(x,y: integer; value: single);
begin
  if (x < 0) or (y < 0) or (x > 127) or (y > 127) then exit;
  f[0, x, y] := value;
end;

function tLatticeBoltzmannGrid.getDensity(x,y: integer): single;
begin
  result := 0;
  if (x < 0) or (y < 0) or (x > 127) or (y > 127) then exit;
  result := displayRho[x, y]
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
  rho, ux, uy, uv, freq: single;
  ux3, uy3: single; {3*ux}
  uxux,uyuy: single;  {ux*ux}
  eu3: single;
  oneMinusUv15: single;
  a: array[0..8] of single;

begin
  for y := 0 to 127 do begin
    for x := 0 to 127 do begin

      {compute macro}
      for i := 0 to 8 do a[i] := f[i,x,y];
      rho := a[0] + a[1] + a[2] + a[3] + a[4] + a[5] + a[6] + a[7] + a[8];
      if rho < 1e-4 then begin
        for i := 0 to 8 do fTemp[i,x,y] := a[i];
        displayRho[x,y] := 255;
        displayVel[x,y] := 255;
        continue;
      end else begin
        ux := (a[1] - a[3] + a[5] - a[6] - a[7] + a[8]) / rho;
        uy := (a[2] - a[4] + a[5] + a[6] - a[7] - a[8]) / rho;
      end;

      uxux := ux*ux;
      uyuy := uy*uy;
      ux3 := 3*ux;
      uy3 := 3*uy;
      uv := uxux + uyuy;
      oneMinusUv15 := 1 - (uv * 1.5);

      freq := (4/9) * rho * (oneMinusUv15);
      fTemp[0,x,y] := a[0] + omega * (freq - a[0]);
      freq := (1/9) * rho * (oneMinusUv15 + ux3 + 4.5 * uxux);
      fTemp[1,x,y] := a[1] + omega * (freq - a[1]);
      freq := (1/9) * rho * (oneMinusUv15 + uy3 + 4.5 * uyuy);
      fTemp[2,x,y] := a[2] + omega * (freq - a[2]);
      freq := (1/9) * rho * (oneMinusUv15 - ux3 + 4.5 * uxux);
      fTemp[3,x,y] := a[3] + omega * (freq - a[3]);
      freq := (1/9) * rho * (oneMinusUv15 - uy3 + 4.5 * uyuy);
      fTemp[4,x,y] := a[4] + omega * (freq - a[4]);
      eu3 := +ux3+uy3;
      freq := (1/36) * rho * (oneMinusUv15 + eu3 + 0.5 * eu3 * eu3);
      fTemp[5,x,y] := a[5] + omega * (freq - a[5]);
      eu3 := -ux3+uy3;
      freq := (1/36) * rho * (oneMinusUv15 + eu3 + 0.5 * eu3 * eu3);
      fTemp[6,x,y] := a[6] + omega * (freq - a[6]);
      eu3 := -ux3-uy3;
      freq := (1/36) * rho * (oneMinusUv15 + eu3 + 0.5 * eu3 * eu3);
      fTemp[7,x,y] := a[7] + omega * (freq - a[7]);
      eu3 := +ux3-uy3;
      freq := (1/36) * rho * (oneMinusUv15 + eu3 + 0.5 * eu3 * eu3);
      fTemp[8,x,y] := a[8] + omega * (freq - a[8]);

      displayRho[x,y] := rho;
      displayVel[x,y] := uv;
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
