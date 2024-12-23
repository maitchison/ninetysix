program test2;

uses
    crt,
    vertex;

type Frustrum = record
    FoV: single;
    nearZ: single;
    farZ: single;

    function clip2d(out p1, p2: V3D; out uv1, uv2: V2D): integer;
    constructor Create(aFoV, aNearZ, aFarZ: single);
end;


constructor Frustrum.Create(aFoV, aNearZ, aFarZ: single);
begin
    FoV := aFov;
    nearZ := aNearZ;
    farZ := aFarZ;
end;

{Clips edge to a 2D frustrum ignoring the y-axis
Returns
 -1 if line is outside of frustrum
 0 if line is inside
 1 if line was partially inside, and is now clipped.
}
function Frustrum.clip2d(out p1, p2: V3D; out uv1, uv2: V2D): integer;
var
    t: single;
    d1, d2: V3D;
    wasClipped: boolean;
begin

    wasClipped := False;

    {check if we are out of bounds}
    if (p1.z < nearZ) and (p2.z < nearZ) then
        exit(-1);
    if (p1.z > farZ) and (p2.z > farZ) then
        exit(-1);

    {near plane}
    if (p1.z < nearZ) then begin
        t := (nearZ - p1.z) / (p2.z - p1.z);
        p1 := p1 + (p2 - p1) * t;
        uv1 := uv1 + (uv2 - uv1) * t;
        wasClipped := True;
    end;

    if (p2.z < nearZ) then begin
        t := (nearZ - p2.z) / (p1.z - p2.z);
        p2 := p2 + (p1 - p2) * t;
        uv2 := uv2 + (uv2 - uv1) * t;
        wasClipped := True;
    end;


    {far plane}
    if (p1.z > farZ) then begin
        t := (p1.z - farZ) / (p1.z - p2.z);
        p1 := p1 + (p2 - p1) * t;
        uv1 := uv1 + (uv1 - uv2) * t;
        wasClipped := True;
    end;

    if (p2.z > farZ) then begin
        t := (p2.z - farZ) / (p2.z - p1.z);
        p2 := p2 + (p1 - p2) * t;
        uv2 := uv2 + (uv1 - uv2) * t;
        wasClipped := True;
    end;


    if wasClipped then exit(1);
    exit(0);

end;

var
    f: Frustrum;
    p1, p2: V3D;
    uv1, uv2: V2D;
    isClipped: integer;

begin

f := Frustrum.Create(80, 10, 100);

p1 := V3D.Create(-10, 0, -10);
p2 := V3D.Create(30, 0, 110);

uv1 := V2D.Create(0.0, 0.0);
uv2 := V2D.Create(1.0, 1.0);

isClipped := f.clip2d(p1, p2, uv1, uv2);


writeln(isClipped);
writeln('p1:', p1.ToString());
writeln('p2:', p2.ToString());
writeln('uv1:', uv1.ToString());
writeln('uv2:', uv2.ToString());

readkey;

end.