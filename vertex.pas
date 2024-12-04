unit Vertex;
{$MODE delphi}

{Unit for handling 2D and 3D points.}

interface

uses math, utils;

type V2D = record
    x, y: single;
    //u: single absolute x;
    //v: single absolute y;

    function Abs2: single;
    function Abs: single;
    function ToString(): string;

    constructor Create(x, y: single);

    class operator Add(a, b: V2D): V2D;
    class operator Subtract(a, b: V2D): V2D;
    class operator Multiply(a: V2D; b:single): V2D;

    end;


type V3D = record
    x, y, z, w: single;

    function Abs2: single;
    function Abs: single;
    function ToString(): string;
    function normed(): V3D;

    constructor Create(x, y, z: single);

		function rotated(thetaX, thetaY, thetaZ: single): V3D;

    class operator Add(a, b: V3D): V3D;
    class operator Subtract(a, b: V3D): V3D;
    class operator Multiply(a: V3D; b:single): V3D;
    end;

type Ray = record
	dir,pos: V3D;
  end;

implementation

function V2D.Abs2: single;
begin
    result := x*x + y*y;
end;

function V2D.Abs: single;
begin
    result := sqrt(abs2);
end;

function V2D.ToString(): string;
begin
    result := format('(%.2f, %.2f)', [x, y]);
end;

class operator V2D.Add(a, b: V2D): V2D;
begin
    result.x := a.x + b.x;
    result.y := a.y + b.y;
end;


class operator V2D.Subtract(a, b: V2D): V2D;
begin
    result.x := a.x - b.x;
    result.y := a.y - b.y;
end;


class operator V2D.Multiply(a: V2D; b: single): V2D;
begin
    result.x := a.x * b;
    result.y := a.y * b;
end;

constructor V2D.Create(x, y: single);
begin
    self.x := x;
    self.y := y;
end;


// --------------------------------------------------------------------

function V3D.Abs2: single;
begin
    result := x*x + y*y + z*z;
end;

function V3D.Abs: single;
begin
    result := sqrt(abs2);
end;


function V3D.ToString(): string;
begin
    result := Format('(%.2f, %.2f, %.2f)', [x, y, z]);
end;

function V3D.Normed(): V3D;
var
	len: single;
begin
	len := self.Abs();
  result.x := x / len;
  result.y := y / len;
  result.z := z / len;
end;


class operator V3D.Add(a, b: V3D): V3D;
begin
    result.x := a.x + b.x;
    result.y := a.y + b.y;
    result.z := a.z + b.z;
end;


class operator V3D.Subtract(a, b: V3D): V3D;
begin
    result.x := a.x - b.x;
    result.y := a.y - b.y;
    result.z := a.z - b.z;
end;


class operator V3D.Multiply(a: V3D; b: single): V3D;
begin
    result.x := a.x * b;
    result.y := a.y * b;
    result.z := a.z * b;
end;

function V3D.rotated(thetaX, thetaY, thetaZ: single): V3D;
var
	nX,nY,nZ: single;
	tX,tY,tZ: single;

begin

	tx := x;
  ty := y;
  tz := z;

  nX := tx;
  nY := cos(thetaX)*ty - sin(thetaX)*tz;
  nZ := sin(thetaX)*ty + cos(thetaX)*tz;
  tx := nX; ty := nY; tz := nZ;

  nX := cos(thetaY)*tx + sin(thetaY)*tz;
  nY := ty;
  nZ := -sin(thetaY)*tx + cos(thetaY)*tz;
  tx := nX; ty := nY; tz := nZ;

  nX := cos(thetaZ)*tx - sin(thetaZ)*ty;
  nY := sin(thetaZ)*tx + cos(thetaZ)*ty;
  nZ := tz;
  tx := nX; ty := nY; tz := nZ;

  result := V3D.create(tx, ty, tz);
end;


constructor V3D.Create(x, y, z: single);
begin
    self.x := x;
    self.y := y;
    self.z := z;
end;


begin
end.
