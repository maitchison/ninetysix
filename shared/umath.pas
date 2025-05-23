{replacement for built in math library}
unit uMath;

{
  Math imports sysutils, and we don't like that, so rewrite the
  (small) number of functions we actually use here.
}

interface

uses
  uTest;

type
  tFloat = extended;  // floating point type to use

function degToRad(x: tFloat): tFloat; inline;
function radToDeg(x: tFloat): tFloat; inline;
function ceil(x: tFloat): int64; inline;
function floor(x: tFloat): int64; inline;
function arccos(x: tFloat): tFloat;
function arctan2(y,x: tFloat): tFloat;
function tan(x: tFloat): tFloat;

const
  DEG2RAD = pi / 180;
  RAD2DEG = 180 / pi;

implementation

uses
  uUtils;

function degToRad(x: tFloat): tFloat;
begin
  result := x / 180 * pi;
end;

function radToDeg(x: tFloat): tFloat;
begin
  result := x * 180 / pi;
end;

{weird that I have to implement this...}
function ceil(x: tFloat): int64; inline;
begin
  if frac(x) > 0 then
    result := trunc(x) + 1
  else
    result := trunc(x);
end;

{weird that I have to implement this...}
function floor(x: tFloat): int64; inline;
begin
  result := trunc(x);
  if (x < 0) and (frac(x) <> 0) then result -= 1;
end;

function arccos(x: tFloat): tFloat;
begin
  x := clamp(x, -1, 1);
  result := arctan2(sqrt(1.0-x*x), x);
end;

function arctan2(y,x: tFloat): tFloat;
begin
  if x = 0 then begin
    if y = 0 then
      result := 0
    else if y > 0 then
      result := pi/2
    else
      result := -pi/2;
    end
  else begin
    result := arctan(y/x);
    if x < 0 then
      if y < 0 then
        result -= pi
      else
        result += pi;
  end;
end;

function tan(x: tFloat): tFloat;
begin
  result := sin(x) / cos(x);
end;

{--------------------------------------------------------}

type
  tMathTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tMathTest.run();
begin

  assertClose(arccos(cos(0.7)), 0.7);

  assertEqual(arctan2(0,1), 0.0);
  assertClose(arctan2(1,0), pi/2);
  assertClose(arctan2(0,-1), pi);
  assertClose(arctan2(-1,0), -pi/2);
  assertClose(arctan2(1,1), pi/4);

  assertEqual(ceil(3.2), 4);
  assertEqual(ceil(3.0), 3);
  assertEqual(ceil(-2.3), -2);
  assertEqual(ceil(-0.3), 0);

  assertEqual(floor(3.2), 3);
  assertEqual(floor(3.0), 3);
  assertEqual(floor(-4), -4);
  assertEqual(floor(-2.3), -3);
  assertEqual(floor(-0.3), -1);
end;

initialization
  tMathTest.create('Math');
end.
