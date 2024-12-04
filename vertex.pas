unit Vertex;
{$MODE delphi}

{Unit for handling 2D and 3D points.}

interface

uses utils;

type V2D = record
    x, y: single;
    //u: single absolute x;
    //v: single absolute y;

    function Abs2: single;
    function Abs: single;
    function ToString(): shortstring;

    constructor Create(x, y: single);

    class operator Add(a, b: V2D): V2D;
    class operator Subtract(a, b: V2D): V2D;
    class operator Multiply(a: V2D; b:single): V2D;

    end;


type V3D = record
    x, y, z, w: single;

    function abs2: single;
    function abs: single;
    function toString(): shortstring;
    function normed(): V3D;

    constructor create(x, y, z: single);

		function rotated(thetaX, thetaY, thetaZ: single): V3D;

    class operator Add(a, b: V3D): V3D;
    class operator Subtract(a, b: V3D): V3D;
    class operator Multiply(a: V3D; b:single): V3D;
    class operator Multiply(a: V3D; b:V3D): V3D;
    end;

type
	Matrix3X3 = record	
  	M: array[1..9] of single;
    function apply(p: V3D): V3D;
    procedure applyScale(factor: single);
    procedure rotation(thetaX, thetaY, thetaZ: single);
    function transpose(): Matrix3x3;
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

function V2D.ToString(): shortstring;
begin
    result := format('(%f, %f)', [x, y]);
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


function V3D.toString(): shortstring;
begin
    result := Format('(%f, %f, %f)', [x, y, z]);
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


class operator V3D.Add(a, b: V3D): V3D; inline;
begin
    result.x := a.x + b.x;
    result.y := a.y + b.y;
    result.z := a.z + b.z;
end;


class operator V3D.Subtract(a, b: V3D): V3D; inline;
begin
    result.x := a.x - b.x;
    result.y := a.y - b.y;
    result.z := a.z - b.z;
end;


class operator V3D.Multiply(a: V3D; b: single): V3D; inline;
begin
    result.x := a.x * b;
    result.y := a.y * b;
    result.z := a.z * b;
end;

class operator V3D.Multiply(a: V3D; b: V3D): V3D; inline;
begin
    result.x := a.x * b.x;
    result.y := a.y * b.y;
    result.z := a.z * b.z;
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

{---------------------------------------------------}


function Matrix3X3.apply(p: V3D): V3D;
begin
  result.x := M[1]*p.x + M[2]*p.y + M[3]*p.z;
  result.y := M[4]*p.x + M[5]*p.y + M[6]*p.z;
  result.z := M[7]*p.x + M[8]*p.y + M[9]*p.z;
end;

procedure Matrix3X3.applyScale(factor: single);
var
	i: integer;
begin
	for i := 1 to 9 do
		M[i] *= factor;
end;

procedure Matrix3X3.rotation(thetaX, thetaY, thetaZ: single);
var
	cosX,sinX,cosY,sinY,cosZ,sinZ: single;
begin
	{Byran angles... maybe should have used euler?}
	sinX := sin(thetaX);
	cosX := cos(thetaX);
	sinY := sin(thetaY);
	cosY := cos(thetaY);
	sinZ := sin(thetaZ);
	cosZ := cos(thetaZ);
  M[1] := cosX*cosY;
  M[2] := cosX*sinY*sinZ-sinX*cosZ;
  M[3] := cosX*sinY*cosZ+sinX*sinZ;
  M[4] := sinX*cosY;
  M[5] := sinX*sinY*sinZ+cosX*cosZ;
  M[6] := sinX*sinY*cosZ-cosX*sinZ;
  M[7] := -sinY;
  M[8] := cosY*sinZ;
  M[9] := cosY*cosZ;
(*
  M[1] := cos(thetaY)*cos(thetaZ);
  M[2] := -cos(thetaY)*sin(thetaZ);
  M[3] := sin(thetaY);
  M[4] := sin(thetaX)*sin(thetaY)*cos(thetaZ)+cos(thetaX)*sin(thetaZ);
  M[5] := sin(thetaX)*sin(thetaY)*sin(thetaZ)-sin(thetaX)*cos(thetaY);
  M[6] := -sin(thetaX)*cos(thetaY);
  M[7] := -cos(thetaX)*sin(thetaY)*cos(thetaZ)+sin(thetaX)*sin(thetaZ);
  M[8] := cos(thetaX)*sin(thetaY)*cos(thetaZ)-sin(thetaX)*cos(thetaZ);
  M[9] := cos(thetaX)*cos(thetaY);
   *)
(*
  M[1] := cos(thetaY)*cos(thetaZ);
  M[2] := -cos(thetaY)*sin(thetaZ);
  M[3] := sin(thetaY);
  M[4] := sin(thetaX)*sin(thetaY)*cos(thetaZ)+cos(thetaX)*sin(thetaZ);
  M[5] := sin(thetaX)*sin(thetaY)*sin(thetaZ)-sin(thetaX)*cos(thetaY);
  M[6] := -sin(thetaX)*cos(thetaY);
  M[7] := -cos(thetaX)*sin(thetaY)*cos(thetaZ)+sin(thetaX)*sin(thetaZ);
  M[8] := cos(thetaX)*sin(thetaY)*cos(thetaZ)-sin(thetaX)*cos(thetaZ);
  M[9] := cos(thetaX)*cos(thetaY);
   *)
end;

{rotates, but applies in ZYX order}
function Matrix3X3.transpose(): Matrix3x3;
begin
	result.M[1] := M[1];
	result.M[2] := M[4];
	result.M[3] := M[7];
	result.M[4] := M[2];
	result.M[5] := M[5];
	result.M[6] := M[8];
	result.M[7] := M[3];
	result.M[8] := M[6];
	result.M[9] := M[9];
end;

{-----------------------------------------------------}
procedure runTests();
var
	p, pInitial: V3D;
  M: Matrix3x3;
  i: integer;
const
	degrees45 = 0.785398; {45 degrees in radians}

begin
	p := V3D.create(rnd,rnd,rnd);
  p := p.normed();
  pInitial := p;
  assert(abs(p.abs-1) < 0.01);

  {rotate 45 degrees}
  M.rotation(degrees45,degrees45,degrees45);
	p := M.apply(pInitial);
	assert(abs(p.abs-1) < 0.01, format('Vector %s was not unit (%f)', [p.toString, p.abs]));

  {rotate random degrees}
  M.rotation(rnd/255-0.5, rnd/255-0.5, rnd/255-0.5);
	p := M.apply(pInitial);
	assert(abs(p.abs-1) < 0.01, format('Vector %s was not unit (%f)', [p.toString, p.abs]));

  {check transpose looks ok}
  M.rotation(rnd/255-0.5, rnd/255-0.5, rnd/255-0.5);
	p := M.transpose.apply(pInitial);
	assert(abs(p.abs-1) < 0.01, format('Vector %s was not unit (%f) after transpose rotation', [p.toString, p.abs]));

end;

begin
	runTests();
end.
