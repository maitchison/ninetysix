unit uVertex;
{$MODE delphi}

{Unit for handling 2D and 3D points.}

interface

uses
  uTest,
  uDebug,
  uUtils,
  uMath,
  uRect;

type V2D = packed record
    x, y: single;
    //u: single absolute x;
    //v: single absolute y;

    function Abs2: single;
    function Abs: single;
    function normed(): V2D;
    function ToString(): shortstring;

    constructor Create(x, y: single);
    function isUnity: boolean;

    class operator Add(a, b: V2D): V2D;
    class operator Subtract(a, b: V2D): V2D;
    class operator Multiply(a: V2D; b:single): V2D;

    end;

type
  V3D = packed record
    x, y, z, w: single;

    function abs2: single;
    function abs: single;
    function toString(): shortstring;
    function normed(): V3D;

    constructor create(x, y, z: single; w:single=0);

    function toPoint: tPoint; inline;
    function rotated(thetaX, thetaY, thetaZ: single): V3D;
    function dot(other: V3D): single;
    procedure clip(maxLen: single);

    class operator Add(a, b: V3D): V3D; inline;
    class operator Subtract(a, b: V3D): V3D; inline;
    class operator Multiply(a: V3D; b:single): V3D; inline;
    class operator Multiply(a: V3D; b:V3D): V3D; inline;
    end;

  {Int16 vector, useful for MMX}
  V3D16 = packed record
    x, y, z, w: int16;

    function toV3D(): V3D; inline;
    function toString(): shortstring;

    class function make(x, y, z: int16): V3D16; static; inline; overload;
    class function round(a: V3D): V3D16; static; inline;
    class function trunc(a: V3D): V3D16; static; inline;
    end;

  {Int32 vector}
  V3D32 = packed record
    x, y, z, w: int32;

    function toString(): shortstring;
    function toV3D(): V3D; inline;

    function low(): V3D16; inline;
    function high(): V3D16; inline;

    class function round(a: V3D): V3D32; static; inline;
    class function trunc(a: V3D): V3D32; static; inline;
    end;

type
  tMatrix4x4 = record
    data: array[1..16] of single;

    function  getM(i,j: integer): single; inline;
    procedure setM(i,j: integer;value: single); inline;

    function  apply(p: V3D): V3D;

    procedure translate(v: V3D);
    procedure scale(factor: single); overload;
    procedure scale(x,y,z: single); overload;
    procedure rotateXYZ(x,y,z: single);

    procedure setIdentity();
    procedure setTranslate(v: V3D);
    procedure setRotationX(theta: single);
    procedure setRotationZYX(thetaZ, thetaY, thetaX: single);
    procedure setRotationXYZ(thetaX, thetaY, thetaZ: single);

    function  MM(other: tMatrix4x4): tMatrix4x4;
    function  transposed(): tMatrix4x4;
    function  cloned(): tMatrix4x4;
    function  toString(): string;

    class operator Multiply(a: tMatrix4x4; b: tMatrix4x4): tMatrix4x4;
  end;

function V2(x,y: single): V2D;
function V2Polar(degree,r: single): V2D;
function V3(x,y,z: single): V3D;

implementation

{-----------------------------------------}

function V2(x,y: single): V2D;
begin
  result := V2D.create(x,y);
end;

{point in polar coordinates}
function V2Polar(degree,r: single): V2D;
begin
  result := V2D.create(sin(degree*DEG2RAD)*r,-cos(degree*DEG2RAD)*r);
end;

{------------}

function V3(x,y,z: single): V3D;
begin
  result := V3D.create(x,y,z);
end;

{-----------------------------------------}

function V2D.isUnity: boolean;
begin
  result := (x = 1.0) and (y = 1.0);
end;

function V2D.Abs2: single;
begin
    result := x*x + y*y;
end;

function V2D.normed: V2D;
begin
  if self.abs2 = 0 then
    result := V2(0,0)
  else
    result := self * (1/self.abs());
end;

function V2D.Abs: single;
begin
    result := sqrt(abs2);
end;

function V2D.toString(): shortstring;
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
  if len = 0 then exit(self);
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

function V3D.toPoint: tPoint; inline;
begin
  result.x := trunc(self.x);
  result.y := trunc(self.y);
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

  result := V3D.create(tx, ty, tz, 0);
end;

function V3D.dot(other: V3D): single;
begin
  result := x*other.x + y*other.y + z*other.z;
end;

constructor V3D.Create(x, y, z: single; w: single=0);
begin
  self.x := x;
  self.y := y;
  self.z := z;
  self.w := w;
end;

procedure V3D.clip(maxLen: single);
begin
  if self.abs2 > maxLen*maxLen then
    self := self.normed()*maxLen;
end;

{---------------------------------------------------}

function tMatrix4x4.getM(i,j: integer): single; inline;
begin
  result := data[i+(j-1)*4];
end;

procedure tMatrix4x4.setM(i,j: integer;value: single); inline;
begin
  data[i+(j-1)*4] := value;
end;

function tMatrix4x4.apply(p: V3D): V3D;
begin
  result.x := data[1]*p.x + data[2]*p.y + data[3]*p.z + data[4]*p.w;
  result.y := data[5]*p.x + data[6]*p.y + data[7]*p.z + data[8]*p.w;
  result.z := data[9]*p.x + data[10]*p.y + data[11]*p.z + data[12]*p.w;
  result.w := p.w; // ignore these
end;

procedure tMatrix4X4.setRotationZYX(thetaZ, thetaY, thetaX: single);
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
  data[4] := 0;
  data[5] := sinX*cosY;
  data[6] := sinX*sinY*sinZ+cosX*cosZ;
  data[7] := sinX*sinY*cosZ-cosX*sinZ;
  data[8] := 0;
  data[9] := -sinY;
  data[10] := cosY*sinZ;
  data[11] := cosY*cosZ;
  data[12] := 0;
  data[13] := 0;
  data[14] := 0;
  data[15] := 0;
  data[16] := 1;
end;

procedure tMatrix4X4.setRotationXYZ(thetaX, thetaY, thetaZ: single);
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
  data[4] := 0;
  data[5] := cosY*sinZ;
  data[6] := sinX*sinY*sinZ+cosX*cosZ;
  data[7] := cosX*sinY*sinZ-sinX*cosZ;
  data[8] := 0;
  data[9] := -sinY;
  data[10] := sinX*cosY;
  data[11] := cosX*cosY;
  data[12] := 0;
  data[13] := 0;
  data[14] := 0;
  data[15] := 0;
  data[16] := 1;
end;

procedure tMatrix4X4.setIdentity();
var
  i: integer;
begin
  fillchar(self, sizeof(self), 0);
  for i := 1 to 4 do
    setM(i,i,1);
end;

procedure tMatrix4X4.translate(v: V3D);
var
  i: integer;
begin
  data[4] += v.x;
  data[8] += v.y;
  data[12] += v.z;
end;

procedure tMatrix4X4.scale(factor: single); overload;
var
  i: integer;
begin
  for i := 1 to 16 do
    data[i] *= factor;
end;

procedure tMatrix4X4.scale(x,y,z: single); overload;
var
  i: integer;
begin
  for i := 1 to 4 do begin
    data[0+i] *= x;
    data[4+i] *= y;
    data[8+i] *= z;
  end;
end;

procedure tMatrix4X4.rotateXYZ(x,y,z: single);
var
  m: tMatrix4x4;
begin
  m.setRotationXYZ(x,y,z);
  self := self.MM(m);
end;

procedure tMatrix4X4.setTranslate(v: V3D);
var
  i: integer;
begin
  setIdentity;
  setM(4, 1, v.x);
  setM(4, 2, v.y);
  setM(4, 3, v.z);
end;

procedure tMatrix4X4.setRotationX(theta: single);
var
  cs,sn: single;
begin
  cs := cos(theta);
  sn := sin(theta);
  data[1] := 1;
  data[2] := 0;
  data[3] := 0;
  data[4] := 0;
  data[5] := 0;
  data[6] := cs;
  data[7] := -sn;
  data[8] := 0;
  data[9] := 0;
  data[10] := sn;
  data[11] := cs;
  data[12] := 0;
  data[13] := 0;
  data[14] := 0;
  data[15] := 0;
  data[16] := 1;
end;

{matrix multiplication}
function tMatrix4X4.MM(other: tMatrix4x4): tMatrix4x4;
var
  i,j,k: integer;
  value: single;
begin
  // not needed, but stop compiler complaining
  fillchar(result, sizeof(result), 0);
  for i := 1 to 4 do
    for j := 1 to 4 do begin
      value := 0;
      for k := 1 to 4 do
        value += getM(i,k) * other.getM(k,j);
      result.setM(i, j, value);
    end;
end;

{returns the transpose}
function tMatrix4X4.transposed(): tMatrix4x4;
begin
  result.data[1] := data[1+0];
  result.data[2] := data[1+4];
  result.data[3] := data[1+8];
  result.data[4] := data[1+12];
  result.data[5] := data[2+0];
  result.data[6] := data[2+4];
  result.data[7] := data[2+8];
  result.data[8] := data[2+12];
  result.data[9] := data[3+0];
  result.data[10] := data[3+4];
  result.data[11] := data[3+8];
  result.data[12] := data[3+12];
  result.data[13] := data[4+0];
  result.data[14] := data[4+4];
  result.data[15] := data[4+8];
  result.data[16] := data[4+12];
end;

function tMatrix4X4.cloned(): tMatrix4x4;
begin
  move(data, result.data, length(data)*sizeof(data[1]));
end;

function tMatrix4X4.toString(): string;
var
  i: integer;
begin
  result := '';
  for i := 0 to 3 do
    result += format('%f %f %f', [data[i*4+1],data[i*4+2],data[i*4+3], data[i*4+4]]) + #13#10;
end;

class operator tMatrix4X4.Multiply(a: tMatrix4x4; b: tMatrix4x4): tMatrix4x4;
begin
  {todo: check this is the right way around}
  result := a.MM(b);
end;


{-----------------------------------------------------}

function V3D16.toV3D(): V3D; inline;
begin
  result.x := x;
  result.y := y;
  result.z := z;
  result.w := w;
end;

function V3D16.toString(): shortstring;
begin
    result := Format('(%d, %d, %d)', [x, y, z]);
end;

class function V3D16.make(x, y, z: int16): V3D16; static; inline; overload;
begin
  result.x := x;
  result.y := y;
  result.z := z;
  result.w := 0;
end;

class function V3D16.round(a: V3D): V3D16; static; inline;
begin
  {$R-,Q-}
  result.x := system.round(a.x);
  result.y := system.round(a.y);
  result.z := system.round(a.z);
  result.w := 0;
  {$R+,Q+}
end;

class function V3D16.trunc(a: V3D): V3D16; static; inline;
begin
  {$R-,Q-}
  result.x := system.trunc(a.x);
  result.y := system.trunc(a.y);
  result.z := system.trunc(a.z);
  result.w := 0;
  {$R+,Q+}
end;

{-----------------------------------------------------}

function V3D32.toV3D(): V3D; inline;
begin
  result.x := x;
  result.y := y;
  result.z := z;
  result.w := w;
end;

function V3D32.toString(): shortstring;
begin
    result := Format('(%d, %d, %d)', [x, y, z]);
end;

{returns low words as vector}
function V3D32.low(): V3D16; assembler;
  asm
    push bx
    mov bx, [eax+0]
    mov word ptr [result+0], bx
    mov bx, [eax+4]
    mov word ptr [result+2], bx
    mov bx, [eax+8]
    mov word ptr [result+4], bx
    mov bx, [eax+12]
    mov word ptr [result+8], bx
    pop bx
  end;

{returns high words as vector}
function V3D32.high(): V3D16; assembler;
  asm
    push bx
    mov bx, [eax+2]
    mov word ptr [result+0], bx
    mov bx, [eax+6]
    mov word ptr [result+2], bx
    mov bx, [eax+10]
    mov word ptr [result+4], bx
    mov bx, [eax+14]
    mov word ptr [result+8], bx
    pop bx
  end;


class function V3D32.round(a: V3D): V3D32; static; inline;
begin
  {$R-,Q-}
  result.x := system.round(a.x);
  result.y := system.round(a.y);
  result.z := system.round(a.z);
  result.w := 0;
  {$R+,Q+}
end;

class function V3D32.trunc(a: V3D): V3D32; static; inline;
begin
  {$R-,Q-}
  result.x := system.trunc(a.x);
  result.y := system.trunc(a.y);
  result.z := system.trunc(a.z);
  result.w := 0;
  {$R+,Q+}
end;

{-----------------------------------------------------}

type
  tVertexTest = class(tTestSuite)
    procedure testV3D32();
    procedure run; override;
  end;

procedure tVertexTest.testV3D32();
var
  p: V3D;
  bias: V3D;
  p32: V3D32;
  p16: V3D16;
begin
  {make sure low and high look right}
  p := V3D.create(-100.123, 102.9995, 53.2);

  p16 := V3D16.round(p*256);
  p32 := V3D32.round(p*256);
  assertEqual(p32.low.toString, p16.toString);
  // note we expect the sign to be extended to high words
  assertEqual(p32.high.toString, V3D16.make(-1,0,0).toString);

  p16 := V3D16.round(p*256);
  p32 := V3D32.round(p*256*65536);
  // this might be off by one due to rounding
  assert((p32.high.toV3D - p16.toV3D).abs2 < 3);
  assert(p32.low.toString <> V3D16.make(0,0,0).toString);
end;

procedure tVertexTest.run();
var
  p, pInitial: V3D;
  target: single;
  A,B,C: tMatrix4x4;
  i,j: integer;
const
  degrees45 = 0.785398; {45 degrees in radians}

begin

  testV3D32();

  p := V3D.create(rnd,rnd,rnd);
  p := p.normed();
  pInitial := p;
  assert(abs(p.abs-1) < 0.01);

  {rotate 45 degrees}
  A.setRotationZYX(degrees45,degrees45,degrees45);
  p := A.apply(pInitial);
  assert(abs(p.abs-1) < 0.01, format('Vector %s was not unit (%f)', [p.toString, p.abs]));

  {rotate random degrees}
  A.setRotationZYX(rnd/255-0.5, rnd/255-0.5, rnd/255-0.5);
  p := A.apply(pInitial);
  assert(abs(p.abs-1) < 0.01, format('Vector %s was not unit (%f)', [p.toString, p.abs]));

  {rotate random degrees}
  A.setRotationXYZ(rnd/255-0.5, rnd/255-0.5, rnd/255-0.5);
  p := A.apply(pInitial);
  assert(abs(p.abs-1) < 0.01, format('Vector %s was not unit (%f)', [p.toString, p.abs]));

  {check transpose looks ok}
  A.setRotationZYX(rnd/255-0.5, rnd/255-0.5, rnd/255-0.5);
  p := A.transposed().apply(pInitial);
  assert(abs(p.abs-1) < 0.01, format('Vector %s was not unit (%f) after transpose rotation', [p.toString, p.abs]));

  {make sure inverse kind of works}
  A.setRotationXYZ(rnd/255-0.5, rnd/255-0.5, rnd/255-0.5);
  p := A.apply(pInitial);
  B := A.transposed();
  C := A.MM(B);
  for i := 1 to 4 do
    for j := 1 to 4 do begin
      if i=j then target := 1 else target := 0;
      assert(abs(C.getM(i,j)-target) < 0.01, 'Inversion did not work: '+#10#13+C.toString);
    end;
end;

begin
  tVertexTest.create('Vertex');
end.
