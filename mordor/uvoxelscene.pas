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

  tRenderQuality = (rqPreview, rqQuarter, rqHalf, rqFull, rqAA, rqDone);

  tRenderState = record
    cameraPos: V3D;
    cameraAngle: V3D;
    pixelX, pixelY: integer;
    width,height: integer;
    quality: tRenderQuality;
    function nextPixel(): boolean;
  end;

  tVoxelScene = class
  protected
    renderState: tRenderState;
    traceCount: int32;
    cellCount: int32;
    traceTime: single;
    tileSize: integer;
    function  traceRay(pos: V3D; dir: V3D): tRayHit;
  public
    cells: array[0..31, 0..31] of tVoxel;
    cameraPos: V3D;
    cameraAngle: V3D; {radians, 0=north}
    function   tracesPerSecond: single;
    function   cellsPerTrace: single;
    function   isDone: boolean;
    function   didCameraMove: boolean;
    procedure  render(const aDC: tDrawContext;renderTime: single=0.05);
    constructor Create(aTileSize: integer);
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
    //stub: finish after half
    if quality > rqHalf then quality := rqDone;
    result := (quality = rqDone);
  end;
end;

constructor tVoxelScene.Create(aTileSize: integer);
begin
  inherited Create();
  cameraPos := V3(5, 21,0);
  cameraAngle := V3(0,0,0);
  tileSize := aTileSize;
  fillchar(cells, sizeof(cells), 0);
end;

function tVoxelScene.tracesPerSecond: single;
begin
  if traceTime = 0 then exit(-1);
  result := traceCount / traceTime;
end;

function tVoxelScene.cellsPerTrace: single;
begin
  if traceCount = 0 then exit(-1);
  result := cellCount / traceCount;
end;

{for the moment just trace through scene and return depth}
function tVoxelScene.traceRay(pos: V3D; dir: V3D): tRayHit;
var
  i: integer;
  hit: tRayHit;
  vox: tVoxel;
  stepSize: single;
  curr, prev: V3D32;
  t: single;
  didHaveProblem: boolean;

  function autoStep(p,d: single): single;
  begin
    if d > 0 then result := (1-frac(p))/d else if d < 0 then result := -frac(p)/d else result := 1.0;
  end;

begin

  inc(traceCount);

  {ok... the super slow way for the moment...}
  {breseham is probably the way to go here}
  {although we'll be dense, so maybe it doesn't matter}
  result.col := RGBA.Clear;
  result.d := 0;

  {if ray starts too high then project it down}
  if (pos.z < 0) then begin
    if dir.z > 0 then begin
      t := -pos.z / dir.z;
      t += 0.01;
      pos += dir * t;
      result.d := t;
    end;
  end;

  prev.x := -1; prev.y := -1; prev.z := -1;
  didHaveProblem := false;


  for i := 0 to 100 do begin

    inc(cellCount);

    curr.x := floor(pos.x);
    curr.y := floor(pos.y);
    curr.z := floor(pos.z);

    {same cell detection... this shouldn't happen}

    if (curr = prev) then begin
      //result.col := RGB(0,255,0);
      //exit;
    end;

    {out of bounds}
    if (dword(curr.x) >= tileSize) or (dword(curr.y) >= tileSize) then begin
      result.col := RGB(255,0,255);
      exit;
    end;
    if (curr.z < 0) then begin
      result.col := RGB(128,0,0); // floor
      exit;
    end;
    if (curr.z >= 1) then begin
      result.col := RGB(0,0,128); // sky
      exit;
    end;

    vox := cells[curr.x,curr.y];
    if not assigned(vox) then begin
      {work out a good step size}
      stepSize := minf(autoStep(pos.x, dir.x), autoStep(pos.y, dir.y), autoStep(pos.z, dir.z));
      stepSize += (1/128);
      pos += dir * stepSize;
      result.d += stepSize;
    end else begin
      {trace through the cell}
      hit := vox.trace(V3(frac(pos.x)*tileSize, frac(pos.y)*tileSize, frac(pos.z)*tileSize), dir);
      pos += dir * (hit.d/tileSize);
      result.d += (hit.d/tileSize);
      if hit.didHit then begin
        result.col := hit.col;
        exit;
      end;
      {also take a small step just to make sure we move onto the next cell}
      pos += dir * (1/64);
      result.d += (1/64);
    end;
    if result.d > 8 then
      exit; // max distance
    prev := curr;
  end;
  {out of samples!}
  result.col := RGB(255,0,255);
end;

{did the camera move since our last render?}
function tVoxelScene.didCameraMove: boolean;
begin
  result := (renderState.cameraPos <> cameraPos) or (renderState.cameraAngle <> cameraAngle);
end;

function tVoxelScene.isDone: boolean;
begin
  result := renderState.quality = rqDone;
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
  i,j: integer;
  col32: RGBA32;
  aspect: single;

  function getRayDir(px, py: single): V3D;
  begin
    result := V3((px-(viewWidth/2)) / (viewWidth*1.2), -0.5, (py-(viewHeight/2)) / (viewWidth*1.2));
    result := result.rotated(renderState.cameraAngle.x, renderState.cameraAngle.y, renderState.cameraAngle.z);
    result := result.normed();
  end;

begin

  dc := aDC.asBlendMode(bmBlit);

  viewWidth := dc.page.width-8;
  viewHeight := dc.page.height-8;
  aspect := viewWidth / viewHeight;

  {check render state}
  if didCameraMove() then begin
    {reset our render}
    renderState.cameraPos := cameraPos;
    renderState.cameraAngle := cameraAngle;
    renderState.pixelX := 0;
    renderState.pixelY := 0;
    renderState.width := viewWidth;
    renderState.height := viewHeight;
    renderState.quality := rqPreview;
    //dc.fillRect(dc.clip, RGB(12,12,12));
  end;

  if renderState.quality = rqDone then exit;

  mid.x := (dc.clip.left+dc.clip.right) div 2;
  mid.y := (dc.clip.top+dc.clip.bottom) div 2;

  rayPos := renderState.cameraPos;

  startTime := getSec;

  while (getSec < (startTime + renderTime)) or (renderState.quality = rqPreview) do begin

    pixelSize := 1;
    case renderState.quality of
      rqPreview: pixelSize := 8;
      rqQuarter: pixelSize := 4;
      rqHalf: pixelSize := 2;
    end;

    if (renderState.pixelX and (pixelSize-1) <> 0) or
       (renderState.pixelY and (pixelSize-1) <> 0) then begin
       renderState.nextPixel();
       continue;
    end;

    if renderState.quality = rqAA then begin
      col32 := RGB(0,0,0);
      for i := 0 to 1 do for j := 0 to 1 do begin
        rayDir := getRayDir(renderState.pixelX+0.25+0.5*i,renderState.pixelY+0.25+0.5*j);
        hit := traceRay(rayPos, rayDir);
        col32 += hit.col * 0.25;
      end;
      dc.putPixel(Point(4+renderState.pixelX, 4+renderState.pixelY), col32);
      renderState.nextPixel();
    end else begin
      rayDir := getRayDir(renderState.pixelX+(pixelSize/2),renderState.pixelY+(pixelSize/2));
      hit := traceRay(rayPos, rayDir);
      dc.fillRect(Rect(4+renderState.pixelX, 4+renderState.pixelY, pixelSize, pixelSize), hit.col);
      renderState.nextPixel();
    end;
  end;

  traceTime += (getSEc - startTime);

end;

begin
end.
