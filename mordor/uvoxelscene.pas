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

  tRenderQuality = (rqQuarter, rqHalf, rqFull, rqDone);

  tRenderState = record
    cameraPos: V3D;
    cameraAngle: single;
    pixelX, pixelY: integer;
    width,height: integer;
    quality: tRenderQuality;
    function nextPixel(): boolean;
  end;

  tVoxelScene = class
  protected
    renderState: tRenderState;
    function  traceRay(pos: V3D; dir: V3D): tRayHit;
  public
    cells: array[0..31, 0..31] of tVoxel;
    cameraPos: V3D;
    cameraAngle: single; {radians, 0=north}
    procedure  render(const aDC: tDrawContext;renderTime: single=0.05);
    constructor Create();
  end;

implementation

{returns if finished}
function tRenderState.nextPixel(): boolean;
begin
  result := false;
  if quality = rqDone then exit(true);
  inc(pixelX);
  if (pixelX >= width) then begin
    pixelX := 0;
    inc(pixelY);
  end;
  if (pixelY >= height) then begin
    pixelY := 0;
    inc(quality);
    result := (quality = rqDone);
  end;
end;

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

{render scene. With progressive render we render approximately renderTime seconds.
 first render (preview) takes as long as it takes though.
}
procedure tVoxelScene.render(const aDC: tDrawContext; renderTime: single=0.05);
var
  dx,dy: integer;
  rayPos, rayDir: V3D;
  d: single;
  mid: tPoint;
  viewWidth,viewHeight: integer;
  px,py: integer;
  hit: tRayHit;
  startTime: single;
  dc: tDrawContext;
  pixelSize: integer;

  function getRayDir(px, py: single): V3D;
  begin
    result := V3((px-(viewWidth/2)) / (viewWidth*1.2), -0.5, (py-(viewHeight/2)) / (viewWidth*1.2));
    result := result.rotated(0, 0, renderState.cameraAngle);
    result := result.normed();
  end;

begin

  dc := aDC.asBlendMode(bmBlit);

  viewWidth := dc.page.width;
  viewHeight := round(dc.page.width * 0.75);

  {check render state}
  if (renderState.cameraPos <> cameraPos) or (renderState.cameraAngle <> cameraAngle) then begin
    {reset our render}
    renderState.cameraPos := cameraPos;
    renderState.cameraAngle := cameraAngle;
    renderState.pixelX := 0;
    renderState.pixelY := 0;
    renderState.width := viewWidth;
    renderState.height := viewHeight;
    renderState.quality := rqQuarter;
    dc.fillRect(dc.clip, RGB(12,12,12));
  end;

  mid.x := (dc.clip.left+dc.clip.right) div 2;
  mid.y := (dc.clip.top+dc.clip.bottom) div 2;

  rayPos :=
    renderState.cameraPos
    + V3(0.5, 0.5, 0.5)
    + V3(sin(renderState.cameraAngle+180*DEG2RAD)*0.45, -cos(renderState.cameraAngle+180*DEG2RAD)*0.45, 0);

  startTime := getSec;

  while getSec < (startTime + renderTime) do begin

    pixelSize := 1;
    case renderState.quality of
      rqQuarter: pixelSize := 4;
      rqHalf: pixelSize := 2;
    end;

    if (renderState.pixelX and (pixelSize-1) <> 0) or
       (renderState.pixelY and (pixelSize-1) <> 0) then begin
       renderState.nextPixel();
       continue;
    end;

    rayDir := getRayDir(renderState.pixelX+(pixelSize/2),renderState.pixelY+(pixelSize/2));
    hit := traceRay(rayPos, rayDir);
    dc.fillRect(Rect(renderState.pixelX, 18+renderState.pixelY, pixelSize, pixelSize), hit.col);
    renderState.nextPixel();
  end;
end;

begin
end.
