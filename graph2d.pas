{2D graphics library}

{$MODE delphi}

unit graph2d;

interface

uses
  test;

type

  tPoint = record
    x, y: int32;
    class operator add(a,b: TPoint): tPoint;
    constructor Create(x, y: int32);
  end;

  tRect = record
    x,y: int32;
    width, height: int32;

    constructor create(width, height: int32); overload;
    constructor create(left, top, width, height: int32); overload;
    procedure pad(padding: int32);
    function padded(padding: int32): tRect;

    function isInside(x,y: int32): boolean;
    class function inset(other: tRect;x1, y1, x2, y2: int32): tRect; static;
    class operator Explicit(a: TRect): ShortString;

  public

    function area: int32;

    function topLeft: tPoint;
    function bottomRight: tPoint;

    function top: int32; inline;
    function left: int32; inline;
    function bottom: int32; inline;
    function right: int32; inline;

    procedure clear();
    procedure clip(const other: tRect);

    function toString: string;

  end;


implementation

uses debug, utils;

{--------------------------------------------------------}

class operator tPoint.add(a,b: TPoint): TPoint;
begin
  result.x := a.x + b.x;
  result.y := a.y + b.y;
end;

constructor tPoint.Create(x, y: int32);
begin
  self.x := x;
  self.y := y;
end;


{--------------------------------------------------------}

constructor tRect.create(width, height: int32); overload;
begin
  self.x := 0;
  self.y := 0;
  self.width := width;
  self.height := height;
end;

constructor tRect.create(left, top, width, height: int32); overload;
begin
  self.x := left;
  self.y := top;
  self.width := width;
  self.height := height;
end;

{adds padding units to each side}
procedure tRect.pad(padding: int32);
begin
  x -= padding;
  y -= padding;
  width += padding * 2;
  height += padding * 2;
end;

{adds padding units to each side}
function tRect.padded(padding: int32): tRect;
begin
  result := self;
  result.pad(padding);
end;

class operator tRect.Explicit(a: TRect): ShortString;
begin
  result := a.toString;
end;

{
Create a new rectangle inset from the other.

If values are negative, they are taken as distance from edge of other rectangle

Note: 0 means width/height if used for x2 or y2.
}
class function tRect.Inset(Other: TRect;x1, y1, x2, y2: int32): TRect; static;
begin
  if x1 < 0 then x1 := Other.Width+x1;
  if y1 < 0 then y1 := Other.Height+y1;
  if x2 <= 0 then x2 := Other.Width+x2;
  if y2 <= 0 then y2 := Other.Height+y2;
  result.x := x1+Other.X;
  result.y := y1+Other.Y;
  result.width := x2-x1;
  result.height := y2-y1;
end;

{----------------------------------}

function tRect.area: int32;
begin
  result := width * height;
end;

function tRect.topLeft: TPoint;
begin
  result.x := left;
  result.y := top;
end;

function tRect.bottomRight: TPoint;
begin
  result.x := right;
  result.y := bottom;
end;

function tRect.top: int32; inline;
begin
  result := y;
end;

function tRect.left: int32; inline;
begin
  result := x;
end;

function tRect.bottom: int32; inline;
begin
  result := y + height;
end;

function tRect.right: int32; inline;
begin
  result := x + width;
end;

procedure tRect.clear();
begin
  x := 0; y := 0;
  width := 0; height := 0;
end;

{clips this rect to another, i.e. returns their intersection.
if two rectangles do not intersect sets rect to (0,0,0,0)}
procedure tRect.clip(const other: tRect);
var
  ox, oy: int32;
begin
  ox := x; oy := y;
  x := max(x, other.x);
  y := max(y, other.y);
  width := min(width-(x-ox), other.x-x+other.width);
  height := min(height-(y-oy), other.y-y+other.height);
  if (width <= 0) or (height <= 0) then clear();
end;

function tRect.isInside(x,y: int32): boolean;
begin
  result := (x >= left) and (y >= top) and (x < right) and (y < bottom);
end;

function tRect.toString(): string;
begin
  result := format('(%d,%d %dx%d)',[x,y,width,height]);
end;

{--------------------------------------------------}

procedure runTests();
var
  a,b: tRect;
  r: tRect;
begin

  note('[test] Graph2d');

  r := tRect.create(10,10,50,50);
  AssertEqual(r.toString, '(10,10 50x50)');

  a := tRect.create(0,0,50,50);
  b := tRect.create(10,25,10,50);
  a.clip(b);
  assertEqual(a.toString, '(10,25 10x25)');


end;

begin
  runTests();
end.
