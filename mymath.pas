{replacement for built in math library}
unit myMath;

{
  Math imports sysutils, and we don't like that, so rewrite the
  (small) number of functions we actually use here.
}

interface

uses
  test;

type
  tFloat = extended;  // floating point type to use

function degToRad(x: tFloat): tFloat;
function radToDeg(x: tFloat): tFloat;
function arccos(x: tFloat): tFloat;
function arctan2(y,x: tFloat): tFloat;

implementation

function degToRad(x: tFloat): tFloat;
begin
  result := x / 180 * pi;
end;

function radToDeg(x: tFloat): tFloat;
begin
  result := x * 180 / pi;
end;

function arccos(x: tFloat): tFloat;
begin
  result := arctan2(sqrt((1.0-x)*(1.0+x)), x);
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
end;

initialization
  tMathTest.create('Math');
end.
