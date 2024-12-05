{2D graphics library}

{$MODE delphi}

unit graph2d;

interface

uses
	test,
	utils;

type

	tPoint = record
  	x, y: Integer;
    class operator add(a,b: TPoint): TPoint;
    constructor Create(AX, AY: Integer);
  end;

	tRect = record
  	position: TPoint;
    width, height: Integer;

    constructor Create(ALeft, ATop, AWidth, AHeight: Integer);
    class function Inset(Other: tRect;x1, y1, x2, y2: integer): TRect; static;
    class operator Explicit(a: TRect): ShortString;

  private

  	function GetX: Integer;
  	function GetY: Integer;
  	procedure SetX(x: Integer);
  	procedure SetY(y: Integer);

  public

    function Area: Integer;

    function TopLeft: TPoint;
    function BottomRight: TPoint;

    function Top: Integer; inline;
    function Left: Integer; inline;
    function Bottom: Integer; inline;
    function Right: Integer; inline;

    property x:Integer read GetX write SetX;
    property y:Integer read GetY write SetY;
  end;


implementation

{--------------------------------------------------------}

class operator TPoint.add(a,b: TPoint): TPoint;
begin
	result.x := a.x + b.x;
  result.y := a.y + b.y;
end;

constructor TPoint.Create(AX, AY: integer);
begin
	self.x := AX;
  self.y := AY;
end;


{--------------------------------------------------------}

constructor TRect.Create(ALeft, ATop, AWidth, AHeight: integer);
begin
	self.Position.x := ALeft;
	self.Position.y := ATop;
  self.Width := AWidth;
  self.Height := AHeight;
end;

function TRect.GetX: Integer;
begin
	result := position.x;
end;

function TRect.GetY: Integer;
begin
	result := position.y;
end;

procedure TRect.SetX(x: Integer);
begin
	position.x := x;
end;

procedure TRect.SetY(y: Integer);
begin
	position.y := y;
end;


class operator TRect.Explicit(a: TRect): ShortString;
begin
	result := Format('%d,%d (%d,%d)', [a.x, a.y, a.width, a.height]);
end;

{
Create a new rectangle inset from the other.

If values are negative, they are taken as distance from edge of other rectangle

Note: 0 means width/height if used for x2 or y2.
}
class function TRect.Inset(Other: TRect;x1, y1, x2, y2: integer): TRect; static;
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

function TRect.Area: Integer;
begin
	result := Width * Height;
end;

function TRect.TopLeft: TPoint;
begin
	result.x := Left;
  result.y := Top;
end;

function TRect.BottomRight: TPoint;
begin
	result.x := Right;
  result.y := Bottom;
end;

function TRect.Top: Integer; inline;
begin
	result := position.y;
end;

function TRect.Left: Integer; inline;
begin
	result := position.x;
end;

function TRect.Bottom: Integer; inline;
begin
	result := position.y + height;
end;

function TRect.Right: Integer; inline;
begin
	result := position.x + width;
end;

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
