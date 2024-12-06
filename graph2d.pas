{2D graphics library}

{$MODE delphi}

unit graph2d;

interface

uses
	test,
	utils;

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
    procedure clip(other: tRect);

  end;


implementation

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

class operator tRect.Explicit(a: TRect): ShortString;
begin
	result := Format('%d,%d (%d,%d)', [a.x, a.y, a.width, a.height]);
end;

{
Create a new rectangle inset from the other.

If values are negative, they are taken as distance from edge of other rectangle

Note: 0 means width/height if used for x2 or y2.
}
class function TRect.Inset(Other: TRect;x1, y1, x2, y2: int32): TRect; static;
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

function TRect.area: int32;
begin
	result := width * height;
end;

function TRect.topLeft: TPoint;
begin
	result.x := left;
  result.y := top;
end;

function TRect.bottomRight: TPoint;
begin
	result.x := right;
  result.y := bottom;
end;

function TRect.top: int32; inline;
begin
	result := y;
end;

function TRect.left: int32; inline;
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
procedure tRect.clip(other: tRect);
begin
	x := max(x, other.x);
	y := max(y, other.y);
  width := min(width, other.x-x+other.width);
  height := min(height, other.y-y+other.height);
  if (width <= 0) or (height <= 0) then clear();
end;

{--------------------------------------------------}

procedure UnitTests();
var	
	r: TRect;
begin
	r := TRect.Create(10,10,50,50);
  AssertEqual(ShortString(r),'10,10 (50,50)');
end;

begin
	UnitTests();
end.
