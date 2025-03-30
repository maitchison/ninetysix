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
  tRenderQualitySpec = record
    tag: string;
    pixelSize: integer;
    lightingSamples: integer;
    aaSamples: integer;
  end;

  tRenderState = record
    cameraPos: V3D;
    cameraAngle: V3D;
    pixelX, pixelY: integer;
    width,height: integer;
    quality: tRenderQuality;
    function nextPixel(): boolean;
    function qualitySpec: tRenderQualitySpec;
  end;

  tVoxelScene = class
  protected
    renderState: tRenderState;
    traceCount: int32;
    cellCount: int32;
    traceTime: single;
    tileSize: integer;
    function  traceRay(pos: V3D; dir: V3D): tRayHit;
    function  calculateShading(pos: V3D): RGBA;
    function  gatherLighting(p, norm: V3D;nSamples: integer=128): single;
  public
    cells: array[0..31, 0..31] of tVoxel;
    cameraPos: V3D;
    cameraAngle: V3D; {radians, 0=north}
    function  tracesPerSecond: single;
    function  cellsPerTrace: single;
    function  isDone: boolean;
    function  didCameraMove: boolean;
    procedure render(const aDC: tDrawContext;renderTime: single=0.05);
    constructor Create(aTileSize: integer);
  end;

implementation

const
  RENDER_QUALITY: array[tRenderQuality] of tRenderQualitySpec = (
    (tag: 'preview';    pixelSize: 8; lightingSamples: 1;   aaSamples: 0),
    (tag: 'quarter';    pixelSize: 4; lightingSamples: 4;   aaSamples: 0),
    (tag: 'half';       pixelSize: 2; lightingSamples: 16;  aaSamples: 0),
    (tag: 'full';       pixelSize: 1; lightingSamples: 128; aaSamples: 0),
    (tag: 'msaa';       pixelSize: 1; lightingSamples: 128; aaSamples: 4),
    (tag: 'done';       pixelSize: 0; lightingSamples: 0;   aaSamples: 0)
  );

function tRenderState.qualitySpec: tRenderQualitySpec;
begin
  result := RENDER_QUALITY[quality];
end;

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
    //if quality > rqHalf then quality := rqDone;
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

  for i := 0 to 100 do begin

    inc(cellCount);

    curr.x := floor(pos.x);
    curr.y := floor(pos.y);
    curr.z := floor(pos.z);

    {same cell detection... this shouldn't happen}
    if (curr = prev) then begin
      {result.col := RGB(0,255,0);
      exit;}
    end;

    {out of bounds}
    if (dword(curr.x) >= tileSize) or (dword(curr.y) >= tileSize) then begin
      result.col := RGB(255,0,255);
      exit;
    end;
    if (curr.z < 0) then begin
      result.col := RGB(0,0,0,0); // floor
      exit;
    end;
    if (curr.z >= 1) then begin
      result.col := RGB(0,0,0,0); // sky
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
        result.hitPos.x += curr.x*tilesize;
        result.hitPos.y += curr.y*tilesize;
        result.hitPos.z += curr.y*tilesize;
        result.col := hit.col;
        exit;
      end;
      {also take a small step just to make sure we move onto the next cell}
      pos += dir * (0.25/tileSize);
      result.d += (0.25/tileSize);
    end;
    if result.d > 5 then exit; // max distance
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

type
  tRenderMode = (
    rmNormal,   { show normals }
    rmBaked,    { get color form voxel... quite fast }
    rmDepth,    { show depth }
    rmGI        { show GI only }
  );

{this is a bit noisy... better to trace toward the camera and see
 what we intersect. Also maybe the tRayHit can record exact location
 we landed.}
function getFaceNormal(d: V3D): V3D;
var
  t: single;
  normal: V3D;

  procedure setAndCheck(newT: single;v:V3D);
  begin
    if (newT > 0) and (newT < t) then begin
      t := newT;
      normal := v;
    end;
  end;

begin
  t := 999;
  normal := V3(0,0,0); // degenerate case}
  if d.x > 0 then
    setAndCheck(0.5/d.x, V3(1,0,0))
  else if d.x < 0 then
    setAndCheck(-0.5/d.x, V3(-1,0,0));
  if d.y > 0 then
    setAndCheck(0.5/d.y, V3(0,1,0))
  else if d.y < 0 then
    setAndCheck(-0.5/d.y, V3(0,-1,0));
  if d.z > 0 then
    setAndCheck(0.5/d.z, V3(0,0,1))
  else if d.z < 0 then
    setAndCheck(-0.5/d.z, V3(0,0,-1));
  result := normal;
end;

function tVoxelScene.gatherLighting(p, norm: V3D;nSamples: integer=128): single;
var
  hits: integer;
  tangent, bitangent: V3D;
  d: V3D;
  i: integer;
  hit: tRayHit;
begin
  norm.getBasis(tangent, bitangent);

  hits := 0;

  for i := 0 to nSamples-1 do begin
    d := sampleCosine(norm, tangent, bitangent);
    hit := traceRay(p, d);
    if hit.didHit then inc(hits);
  end;
  result := 1-(hits/nSamples);
end;

{position is in scene space...}
function tVoxelScene.calculateShading(pos: V3D): RGBA;
var
  vx,vy,vz: integer; {position within voxel}
  subPos: V3D; {sub position within voxel}
  vox: tVoxel;
  cameraDir: V3D;
  d: single; {distance from the camera plane}
  voxCol: RGBA;
  faceNormal: V3D;
  gi: single;
const
  renderMode = rmGI;
begin
  result := RGB(0,0,128);
  if (pos.x < 0) or (pos.x >= 32) then exit;
  if (pos.y < 0) or (pos.y >= 32) then exit;
  if (pos.z < 0) or (pos.z >= 1) then exit;

  { get our voxel... }
  vox := cells[trunc(pos.x), trunc(pos.y)];
  if not assigned(vox) then exit;

  vx := trunc(frac(pos.x)*16);
  vy := trunc(frac(pos.y)*16);
  vz := trunc(frac(pos.z)*16);

  subPos.x := (frac(pos.x)*16) - vx;
  subPos.y := (frac(pos.y)*16) - vy;
  subPos.z := (frac(pos.z)*16) - vz;

  { fetch voxel colors }
  voxCol := vox.getVoxel(vx, vy, vz);

  { get face }
  faceNormal := getFaceNormal(subPos - V3(0.5, 0.5, 0.5));

  {calculate distance to camera}
  {todo: cache camera dir}
  cameraDir := V3(0,-1,0).rotated(cameraAngle.x, cameraAngle.y, cameraAngle.z);
  d := cameraDir.dot(pos - cameraPos);

  {calculate the face normal}
  {bias the gather point a little}
  gi := gatherLighting(pos+(faceNormal*0.01), faceNormal, renderState.qualitySpec.lightingSamples);

  {gather lighting...}

  {output color}

  case renderMode of
    rmBaked: begin
      result := voxCol;
      exit;
    end;
    rmNormal: begin
      result := RGB(
        round(faceNormal.x*128+128),
        round(faceNormal.y*128+128),
        round(faceNormal.z*128+128)
      );
      exit;
    end;
    rmGI: begin
      result := RGB(
        round(gi*64),
        round(gi*256),
        round(gi*1024)
      );
      exit;
    end;
    rmDepth: begin
      result.r := 255-clamp(round(d*64), 0, 255);
      result.g := 255-clamp(round(d*64), 0, 255);
      result.b := 255-clamp(round(d*64), 0, 255);
      result.a := 255;
      exit;
    end;
  end;


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
  col: RGBA;

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

    pixelSize := renderSTate.qualitySpec.pixelSize;
    if pixelSize = 0 then exit;

    if (renderState.pixelX and (pixelSize-1) <> 0) or
       (renderState.pixelY and (pixelSize-1) <> 0) then begin
       renderState.nextPixel();
       continue;
    end;

    if renderState.qualitySpec.aaSamples > 0 then begin
      col32 := RGB(0,0,0);
      for i := 0 to 1 do for j := 0 to 1 do begin
        rayDir := getRayDir(renderState.pixelX+0.25+0.5*i,renderState.pixelY+0.25+0.5*j);
        hit := traceRay(rayPos, rayDir);
        if hit.didHit then
          col := calculateShading(rayPos + (rayDir * hit.d))
        else
          col := RGB(0,0,0); { not sure what to do here.}
        col32 += col * 0.25;
      end;
      dc.putPixel(Point(4+renderState.pixelX, 4+renderState.pixelY), col32);
      renderState.nextPixel();
    end else begin
      rayDir := getRayDir(renderState.pixelX+(pixelSize/2),renderState.pixelY+(pixelSize/2));
      hit := traceRay(rayPos, rayDir);
      if hit.didHit then begin
        {todo: check positions}
        col := calculateShading(rayPos + (rayDir * hit.d))
      end else
        col := RGB(0,0,0); { not sure what to do here..}
      dc.fillRect(Rect(4+renderState.pixelX, 4+renderState.pixelY, pixelSize, pixelSize), col);
      renderState.nextPixel();
    end;
  end;

  traceTime += (getSEc - startTime);

end;

begin
end.
