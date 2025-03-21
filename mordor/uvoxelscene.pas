{for tracing through a 2d world of voxels}
unit uVoxelScene;

interface

uses
  uTest,
  uDebug,
  uUtils,
  uVertex,
  uRect,
  uGraph32,
  uPoly,
  uColor,
  uMath,
  uVoxel;

type

  tVoxelScene = class
  protected
    function  traceRay(pos: V3D; dir: V3D): tRayHit;
  public
    cells: array[0..31, 0..31] of tVoxel;
    cameraPos: V3D;
    cameraAngle: single; {radians, 0=north}
    procedure  render(const dc: tDrawContext);
    constructor Create();
  end;

implementation

constructor tVoxelScene.Create();
begin
  cameraPos := V3(5, 21,0);
  cameraAngle := 0;
  fillchar(cells, sizeof(cells), 0);
end;

{for the moment just trace through scene and return depth}
function tVoxelScene.traceRay(pos: V3D; dir: V3D): tRayHit;
var
  i: integer;
  rx,ry,rz: integer;
  hit: tRayHit;
  vox: tVoxel;
  stepSize: single;
  autoX, autoY: single;

  function autoStep(p,d: single): single;
  begin
    if d > 0 then result := 1-frac(p) else if d < 0 then result := frac(p) else result := 1.0;
  end;

begin
  {ok... the super slow way for the moment...}
  {breseham is probably the way to go here}
  {although we'll be dense, so maybe it doesn't matter}
  result.col := RGBA.Clear;
  result.didHit := false;
  result.d := 0;
  for i := 0 to 1000 do begin
    rx := floor(pos.x);
    ry := floor(pos.y);
    rz := floor(pos.z);
    {out of bounds}
    if (dword(rx) >= 32) or (dword(ry) >= 32) then begin
      result.col := RGB(255,0,255);
      exit;
    end;
    if (rz < 0) then begin
      result.col := RGB(128,0,0); // floor
      result.didHit := true;
      exit;
    end;
    if (rz >= 1) then begin
      result.col := RGB(0,0,128); // sky
      result.didHit := true;
      exit;
    end;

    vox := cells[rx,ry];
    if not assigned(vox) then begin
      {work out a good step size}
      stepSize := minf(autoStep(pos.x, dir.x), autoStep(pos.y, dir.y)) + 0.01;
      pos += dir * stepSize;
      result.d += stepSize;
    end else begin
      {trace through the cell}
      hit := vox.trace(V3(frac(pos.x)*32, frac(pos.y)*32, frac(pos.z)*32), dir);
      pos += dir * (hit.d/32);
      result.d += (hit.d/32);
      if hit.didHit then begin
        result.col := hit.col;
        result.didHit := true;
        exit;
      end;
      {also take a small step just to make sure we move onto the next cell}
      pos += dir * (1/64);
      result.d += (1/64);
    end;
    if result.d > 4 then
      exit; // max distance
  end;
  {out of samples!}
  result.col := RGB(255,0,255);
end;

procedure tVoxelScene.render(const dc: tDrawContext);
var
  dx,dy: integer;
  rayPos, rayDir: V3D;
  d: single;
  mid: tPoint;
  vx,vy: integer;
  hit: tRayHit;
begin
  dc.fillRect(dc.clip, RGB(12,12,12));
  mid.x := (dc.clip.left+dc.clip.right) div 2;
  mid.y := (dc.clip.top+dc.clip.bottom) div 2;

  vx := 40;
  vy := 30;

  rayPos :=
    cameraPos
    + V3(0.5, 0.5, 0.35)
    + V3(sin(cameraAngle+180*DEG2RAD)*0.45, -cos(cameraAngle+180*DEG2RAD)*0.45, 0);

  for dy := -vy to vy do begin
    for dx := -vx to vx do begin
      rayDir := V3(dx / 60, -0.75, dy / 60).normed();
      rayDir := rayDir.rotated(0, 0, cameraAngle);
      hit := traceRay(rayPos, rayDir);
      dc.putPixel(Point(dx+mid.x, dy+mid.y), hit.col);
    end;
  end;
end;

begin
end.
