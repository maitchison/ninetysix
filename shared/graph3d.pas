{3D graphics unit}
unit graph3d;

{$MODE delphi}

interface

uses
    vertex,
    graph32,
    bmp,
    crt;

type RGBA = packed record
  r,g,b,a: byte;

  constructor create(r,g,b,a: byte); overload;
  constructor create(r,g,b: byte); overload;
  end;

type RGBA32 = packed record
  r,g,b,a: single;

  function toRGBA(): RGBA;
  end;


type Texture = record
  texels: array[0..63, 0..63] of rgba;
  width, height: integer;

  function GetPixel(u, v: integer): rgba;
  constructor Create(Filename: string); overload;

end;

type Frustrum = record
    FoV: single;
    nearZ: single;
    farZ: single;

    function Clip2d(out p1, p2: V3D; out uv1, uv2: V2D): integer;
    constructor Create(aFoV, aNearZ, aFarZ: single);
end;


implementation

function clip(x: single; a,b: integer): integer;
begin
  if x <= a then exit(a);
  if x >= b then exit(b);
  result := trunc(x);
end;

constructor RGBA.create(r,g,b,a: byte); overload;
begin
  self.a := a;
  self.r := r;
  self.g := g;
  self.b := b;
end;


constructor RGBA.create(r,g,b: byte); overload;
begin
  self.a := 255;
  self.r := r;
  self.g := g;
  self.b := b;
end;


function RGBA32.toRGBA(): RGBA;
begin
  result.r := clip(self.r * 255, 0, 255);
  result.g := clip(self.g * 255, 0, 255);
  result.b := clip(self.b * 255, 0, 255);
  result.a := clip(self.a * 255, 0, 255);
end;


{Initialize a default texture.}
constructor Texture.Create(FileName: string); overload;
var
  page: tPage;
  i, j: integer;
  brightness: word;
  loc: word;
begin
  width := 64;
  height := 64;
  page := LoadBMP(filename);
  for i := 0 to 63 do
    for j := 0 to 63 do begin
      texels[i, j].r := page.getPixel(i,j).r;
      texels[i, j].g := page.getPixel(i,j).g;
      texels[i, j].b := page.getPixel(i,j).b;
      texels[i, j].a := page.getPixel(i,j).a;
    end;
end;

function Texture.GetPixel(u, v: integer): rgba;
begin
  result := texels[u and $3F, v and $3F];
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
        uv2 := uv2 + (uv1 - uv2) * t;
        wasClipped := True;
    end;


    {far plane}
    if (p1.z > farZ) then begin
        t := (p1.z - farZ) / (p1.z - p2.z);
        p1 := p1 + (p2 - p1) * t;
        uv1 := uv1 + (uv2 - uv1) * t;
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


begin
end.
