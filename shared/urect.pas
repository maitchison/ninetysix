{2D graphics library}
unit uRect;

interface

{
Rect co-ords are inclusive-exclusive

e.g.

01234567890
1
2
3    #---#
4    |   |
5    #---#
6

topLeft     = (5,3)
bottomRight = (10,6)
width  = 5
height = 3

}

uses
  uTest;

type

  tPoint = record
    x, y: int32;
    class operator add(a,b: tPoint): tPoint;
    class operator subtract(a,b: tPoint): tPoint;
    function toString(): string;
  end;

  tRect = record
    pos: tPoint;
    width, height: int32;

    procedure init(left, top, width, height: int32);
    procedure pad(padding: int32);
    function  padded(padding: int32): tRect;
    function  isEmpty: boolean; inline;

    procedure expandToInclude(p: tPoint);
    function  isInside(x,y: int32): boolean;
    function  mid: tPoint;
    class function inset(other: tRect;x1, y1, x2, y2: int32): tRect; static;

  public
    function  getTop: int32; inline;
    function  getLeft: int32; inline;
    function  getBottom: int32; inline;
    function  getRight: int32; inline;
    procedure moveTop(value: int32); inline;
    procedure moveLeft(value: int32); inline;
    procedure moveBottom(value: int32); inline;
    procedure moveRight(value: int32); inline;

    function  getTopLeft: tPoint;
    function  getBottomRight: tPoint;
    function  getBottomLeft: tPoint;
    function  getTopRight: tPoint;
    procedure moveTopLeft(p: tPoint);
    procedure moveBottomRight(p: tPoint);
    procedure moveBottomLeft(p: tPoint);
    procedure moveTopRight(p: tPoint);

  public

    function area: int32;

    procedure clear();
    procedure clipTo(const other: tRect);
    function  clipPoint(p: tPoint): tPoint;

    property topLeft: tPoint read getTopLeft write moveTopLeft;
    property topRight: tPoint read getTopRight write moveTopRight;
    property bottomLeft: tPoint read getBottomLeft write moveBottomLeft;
    property bottomRight: tPoint read getBottomRight write moveBottomRight;

    property left: int32 read getLeft write moveLeft;
    property right: int32 read getRight write moveRight;
    property top: int32 read getTop write moveTop;
    property bottom: int32 read getBottom write moveBottom;
    property x: int32 read pos.x write pos.x;
    property y: int32 read pos.y write pos.y;

    function toString(): string;

  end;

function Rect(x, y, width, height: int32): tRect; inline; overload;
function Rect(width, height: int32): tRect; inline; overload;
function Point(x, y: int32): tPoint; inline;

procedure assertEqual(a, b: tPoint;msg: string=''); overload;

implementation

uses uDebug, uUtils;

{--------------------------------------------------------}

function Rect(x, y, width, height: int32): tRect; inline;
begin
  result.x := x;
  result.y := y;
  result.width := width;
  result.height := height;
end;

function Rect(width, height: int32): tRect; inline;
begin
  result.x := 0;
  result.y := 0;
  result.width := width;
  result.height := height;
end;

function Point(x, y: int32): tPoint; inline;
begin
  result.x := x;
  result.y := y;
end;

{--------------------------------------------------------}

procedure assertEqual(a, b: tPoint;msg: string=''); overload;
begin
  if (a.x <> b.x) or (a.y <> b.y) then
    assertError(Format('Points do not match, expecting %s but found %s %s', [a.toString, b.toString, msg]));
end;

{--------------------------------------------------------}

class operator tPoint.add(a,b: tPoint): tPoint;
begin
  result.x := a.x + b.x;
  result.y := a.y + b.y;
end;

class operator tPoint.subtract(a,b: tPoint): tPoint;
begin
  result.x := a.x - b.x;
  result.y := a.y - b.y;
end;

function tPoint.toString(): string;
begin
  result := format('(%d,%d)',[x, y]);
end;

{--------------------------------------------------------}

procedure tRect.init(left, top, width, height: int32);
begin
  self.x := left;
  self.y := top;
  self.width := width;
  self.height := height;
end;

{adds padding units to each side}
procedure tRect.pad(padding: int32);
begin
  pos.x -= padding;
  pos.y -= padding;
  width += padding * 2;
  height += padding * 2;
end;

{adds padding units to each side}
function tRect.padded(padding: int32): tRect;
begin
  result := self;
  result.pad(padding);
end;

function tRect.isEmpty: boolean; inline;
begin
  result := (width <= 0) or (height <= 0);
end;

function tRect.clipPoint(p: tPoint): tPoint;
begin
  if p.x < x then p.x := x;
  if p.y < y then p.y := y;
  if p.x > right-1 then p.x := right-1;
  if p.y > bottom-1 then p.y := bottom-1;
  result := p;
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

function tRect.mid: tPoint;
begin
  result.x := (left+right+1) div 2;
  result.y := (top+bottom+1) div 2;
end;

{----------------------------------}

function tRect.area: int32;
begin
  result := width * height;
end;

{---------------------------------------}

function tRect.getTop: int32; inline;
begin
  result := y;
end;

function tRect.getLeft: int32; inline;
begin
  result := x;
end;

function tRect.getBottom: int32; inline;
begin
  result := y + height;
end;

function tRect.getRight: int32; inline;
begin
  result := x + width;
end;

procedure tRect.moveTop(value: int32); inline;
begin
  height += y - value;
  y := value;
end;

procedure tRect.moveLeft(value: int32); inline;
begin
  width += x - value;
  x := value;
end;

procedure tRect.moveRight(value: int32); inline;
begin
  width -= x - value;
end;

procedure tRect.moveBottom(value: int32); inline;
begin
  height -= y - value;
end;

function tRect.getTopLeft: tPoint;
begin
  result.x := left;
  result.y := top;
end;

function tRect.getBottomRight: tPoint;
begin
  result.x := right;
  result.y := bottom;
end;

function tRect.getBottomLeft: tPoint;
begin
  result.x := left;
  result.y := bottom;
end;

function tRect.getTopRight: tPoint;
begin
  result.x := right;
  result.y := top;
end;

{moves top left without moving bottom right}
procedure tRect.moveTopLeft(p: tPoint);
begin
  left := p.x;
  top := p.y;
end;

procedure tRect.moveBottomRight(p: tPoint);
begin
  right := p.x;
  bottom := p.y;
end;

procedure tRect.moveBottomLeft(p: tPoint);
begin
  left := p.x;
  bottom := p.y;
end;

procedure tRect.moveTopRight(p: tPoint);
begin
  right := p.x;
  top := p.y;
end;

{---------------------------------}

procedure tRect.clear();
begin
  x := 0; y := 0;
  width := 0; height := 0;
end;

{clips this rect to another, i.e. returns their intersection.
if two rectangles do not intersect sets rect to (0,0,0,0)}
procedure tRect.clipTo(const other: tRect);
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

{expects rect to include new point (if needed)}
procedure tRect.expandToInclude(p: tPoint);
begin
  if p.x < x then begin
    width += (x-p.x);
    x := p.x;
  end;
  if p.y < y then begin
    height += (y-p.y);
    y := p.y;
  end;
  width := max(width, p.x - x);
  height := max(height, p.y - y);
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

type
  tGraph2DTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tGraph2DTest.run();
var
  a,b: tRect;
  r: tRect;
begin

  r := Rect(10,10,50,50);
  AssertEqual(r.toString, '(10,10 50x50)');

  a := Rect(0,0,50,50);
  b := Rect(10,25,10,50);
  a.clipTo(b);
  assertEqual(a.toString, '(10,25 10x25)');

  {make sure we have left/right top/bottom correct.}
  r := Rect(2, 10, 16, 32);
  assertEqual(r.left, 2);
  assertEqual(r.top, 10);
  assertEqual(r.right, 18);
  assertEqual(r.bottom, 42);
  assertEqual(r.width, 16);
  assertEqual(r.height, 32);

  {check expand to include}
  r := Rect(12, 14, 0, 0);
  r.expandToInclude(Point(15, 3));
  r.expandToInclude(Point(22, 19));
  r.expandToInclude(Point(12, 2));
  assertEqual(r.left, 12);
  assertEqual(r.top, 2);
  assertEqual(r.right, 22);
  assertEqual(r.bottom, 19);

  {check corner moving}
  r := Rect(4,4,8,10);
  r.topLeft := Point(2,2);
  assertEqual(r.topLeft, Point(2,2));
  assertEqual(r.width, 10);
  assertEqual(r.height, 12);
  assertEqual(r.bottomRight, Point(12, 14));

end;

initialization
  tGraph2DTest.create('Graph2D');
end.
