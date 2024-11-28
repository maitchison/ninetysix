unit Vertex;

{Unit for handling 2D and 3D points.}

interface

uses Math;

type V2D = record
    x, y: single;
    u: single absolute x;
    v: single absolute y;


    function abs2: single;
    function abs: single;

    class operator Add(a, b: V2D): V2D;
    class operator Subtract(a, b: V2D): V2D;
    class operator Multiply(a: V2D; b:single): V2D;
    end;


type V3D = record
    x, y, z, w: single;

    function abs2: single;
    function abs: single;

    class operator Add(a, b: V3D): V3D;
    class operator Subtract(a, b: V3D): V3D;
    class operator Multiply(a: V3D; b:single): V3D;
    end;

implementation

function V2D.abs2: single;
begin
    return x*x + y*y;
end;

function V2D.abs: single;
begin
    return sqrt(abs);
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


// --------------------------------------------------------------------

function V3D.abs2: single;
begin
    return x*x + y*y + z*z;
end;

function V3D.abs: single;
begin
    return sqrt(abs);
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

begin
end.