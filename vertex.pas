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
    function dot(other: V3D): single;
    procedure clip(maxLen: single);

    class operator Add(a, b: V3D): V3D;
    class operator Subtract(a, b: V3D): V3D;
    class operator Multiply(a: V3D; b:single): V3D;
    class operator Multiply(a: V3D; b:V3D): V3D;
    end;

type
  tMatrix3x3 = record
    data: array[1..9] of single;

    function M(i,j: integer): single; inline;

    function apply(p: V3D): V3D;
    procedure applyScale(factor: single);

    procedure rotationX(theta: single);

    procedure rotationZYX(thetaZ, thetaY, thetaX: single);
    procedure rotationXYZ(thetaX, thetaY, thetaZ: single);

    function MM(other: tMatrix3x3): tMatrix3x3;
    function transposed(): tMatrix3x3;
    function cloned(): tMatrix3x3;
    function toString(): string;
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
  if len = 0 then exit;
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

function V3D.dot(other: V3D): single;
begin
  result := x*other.x + y*other.y + z*other.z;
end;

constructor V3D.Create(x, y, z: single);
begin
    self.x := x;
    self.y := y;
    self.z := z;
end;

procedure V3D.clip(maxLen: single);
begin
  if self.abs2 > maxLen*maxLen then
    self := self.normed()*maxLen;
end;

{---------------------------------------------------}

function tMatrix3x3.M(i,j: integer): single; inline;
begin
  result := data[i+(j-1)*3];
end;

function tMatrix3x3.apply(p: V3D): V3D;
begin
  result.x := data[1]*p.x + data[2]*p.y + data[3]*p.z;
  result.y := data[4]*p.x + data[5]*p.y + data[6]*p.z;
  result.z := data[7]*p.x + data[8]*p.y + data[9]*p.z;
end;

procedure tMatrix3X3.applyScale(factor: single);
var
  i: integer;
begin
  for i := 1 to 9 do
    data[i] *= factor;
end;

procedure tMatrix3X3.rotationZYX(thetaZ, thetaY, thetaX: single);
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
  data[1] := cosX*cosY;
  data[2] := cosX*sinY*sinZ-sinX*cosZ;
  data[3] := cosX*sinY*cosZ+sinX*sinZ;
  data[4] := sinX*cosY;
  data[5] := sinX*sinY*sinZ+cosX*cosZ;
  data[6] := sinX*sinY*cosZ-cosX*sinZ;
  data[7] := -sinY;
  data[8] := cosY*sinZ;
  data[9] := cosY*cosZ;
end;

procedure tMatrix3X3.rotationXYZ(thetaX, thetaY, thetaZ: single);
var
  cosX,sinX,cosY,sinY,cosZ,sinZ: single;
begin
  sinX := sin(thetaX);
  cosX := cos(thetaX);
  sinY := sin(thetaY);
  cosY := cos(thetaY);
  sinZ := sin(thetaZ);
  cosZ := cos(thetaZ);
  data[1] := cosY*cosZ;
  data[2] := sinX*sinY*cosZ-cosX*sinZ;
  data[3] := cosX*sinY*cosZ+sinX*sinZ;
  data[4] := cosY*sinZ;
  data[5] := sinX*sinY*sinZ+cosX*cosZ;
  data[6] := cosX*sinY*sinZ-sinX*cosZ;
  data[7] := -sinY;
  data[8] := sinX*cosY;
  data[9] := cosX*cosY;
end;

procedure tMatrix3X3.rotationX(theta: single);
var
  cs,sn: single;
begin
  cs := cos(theta);
  sn := sin(theta);
  data[1] := 1;
  data[2] := 0;
  data[3] := 0;
  data[4] := 0;
  data[5] := cs;
  data[6] := -sn;
  data[7] := 0;
  data[8] := sn;
  data[9] := cs;
end;

{matrix multiplication}
function tMatrix3X3.MM(other: tMatrix3x3): tMatrix3x3;
var
  i,j,k: integer;
  value: single;
begin
  for i := 1 to 3 do
    for j := 1 to 3 do begin
      value := 0;
      for k := 1 to 3 do
        value += M(i,k) * other.M(k,j);
      result.data[i+((j-1)*3)] := value;
    end;
end;

{returns the transpose}
function tMatrix3X3.transposed(): tMatrix3x3;
begin
  result.data[1] := data[1];
  result.data[2] := data[4];
  result.data[3] := data[7];
  result.data[4] := data[2];
  result.data[5] := data[5];
  result.data[6] := data[8];
  result.data[7] := data[3];
  result.data[8] := data[6];
  result.data[9] := data[9];
end;

function tMatrix3X3.cloned(): tMatrix3x3;
begin
  move(data, result.data, length(data)*sizeof(data[1]));
end;

function tMatrix3X3.toString(): string;
var
  i: integer;
begin
  result := '';
  for i := 0 to 2 do
    result += format('%f %f %f', [data[i*3+1],data[i*3+2],data[i*3+3]]) + #13#10;
end;

{-----------------------------------------------------}
procedure runTests();
var
  p, pInitial: V3D;
  target: single;
  A,B,C: tMatrix3x3;
  i,j: integer;
const
  degrees45 = 0.785398; {45 degrees in radians}

begin
  p := V3D.create(rnd,rnd,rnd);
  p := p.normed();
  pInitial := p;
  assert(abs(p.abs-1) < 0.01);

  {rotate 45 degrees}
  A.rotationZYX(degrees45,degrees45,degrees45);
  p := A.apply(pInitial);
  assert(abs(p.abs-1) < 0.01, format('Vector %s was not unit (%f)', [p.toString, p.abs]));

  {rotate random degrees}
  A.rotationZYX(rnd/255-0.5, rnd/255-0.5, rnd/255-0.5);
  p := A.apply(pInitial);
  assert(abs(p.abs-1) < 0.01, format('Vector %s was not unit (%f)', [p.toString, p.abs]));

  {rotate random degrees}
  A.rotationXYZ(rnd/255-0.5, rnd/255-0.5, rnd/255-0.5);
  p := A.apply(pInitial);
  assert(abs(p.abs-1) < 0.01, format('Vector %s was not unit (%f)', [p.toString, p.abs]));

  {check transpose looks ok}
  A.rotationZYX(rnd/255-0.5, rnd/255-0.5, rnd/255-0.5);
  p := A.transposed().apply(pInitial);
  assert(abs(p.abs-1) < 0.01, format('Vector %s was not unit (%f) after transpose rotation', [p.toString, p.abs]));

  {make sure inverses kind of work}
  A.rotationXYZ(rnd/255-0.5, rnd/255-0.5, rnd/255-0.5);
  p := A.apply(pInitial);
  B := A.transposed();
  C := A.MM(B);
  for i := 1 to 3 do
    for j := 1 to 3 do begin
      if i=j then target := 1 else target := 0;
      assert(abs(C.M(i,j)-target) < 0.01, 'Inversion did not work: '+#10#13+C.toString);
    end;


end;

begin
  runTests();
end.
