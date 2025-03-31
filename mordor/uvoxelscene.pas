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
    function  traceRay(pos: V3D; dir: V3D;depth: integer=0): tRayHit;
    function  calculateShading(pos,faceNormal: V3D): RGBA;
    function  gatherLighting(p, norm: V3D;nSamples: integer=128; depth: integer=1): RGBA32;
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
    (tag: 'full';       pixelSize: 1; lightingSamples: 64;  aaSamples: 0),
    (tag: 'msaa';       pixelSize: 1; lightingSamples: 128; aaSamples: 4),
    (tag: 'done';       pixelSize: 0; lightingSamples: 0;   aaSamples: 0)
  );

type
  tRenderMode = (
    rmShaded,   { standard lighting }
    rmNormal,   { show normals }
    rmAlbedo,   { get color form voxel... quite fast }
    rmDepth,    { show depth }
    rmEmmisive, { show emmisive}
    rmGI        { show GI only }
  );

const
  renderMode = rmGI;

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

function pseudo(a,b,c: integer): single;
var
  code: dword;
begin
  code := (a * 73856093) xor (b * 19349663) xor (c * 83492791);
  code := code xor ((code shr 16) * $85ebca6b);
  code := code xor ((code shr 13) * $c2b2ae35);
  code := code xor (code shr 16);
  result := ((code shr 4) and $ffff)/$ffff;
end;

{add slight variation to normals}
function perturbNormal(n: V3D; p: V3D32): V3D;
var
  vx,vy,vz: integer;
  dx,dy,dz: single;
begin
  {we could also add 'texture' by looking at sub position}
  {every voxel is divided into 8 subcubes, each with their own
   distortion}
  vx := (p.x div 128) and $ff;
  vy := (p.y div 128) and $ff;
  vz := (p.z div 128) and $ff;
  dx := pseudo(vx,vy,vz);
  dy := pseudo(vy,vz,vx);
  dz := pseudo(vz,vx,vy);
  n := n + (V3(dx,dy,dz)*0.5);
  result := n.normed();
end;

{trace ray thought scene
 depth is recursion depth.
}
function tVoxelScene.traceRay(pos: V3D; dir: V3D;depth: integer=0): tRayHit;
var
  i: integer;
  hit: tRayHit;
  vox: tVoxel;
  stepSize: single;
  curr, prev: V3D32;
  t: single;
  tracePos: V3D;

  function autoStep(p,d: single): single;
  begin
    if d > 0 then result := (1-frac(p))/d else if d < 0 then result := -frac(p)/d else result := 1.0;
  end;

begin

  inc(traceCount);

  {ok... the super slow way for the moment...}
  {breseham is probably the way to go here}
  {although we'll be dense, so maybe it doesn't matter}
  result.clear();

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
    {
    if (curr = prev) then begin
      result.col := RGB(0,255,0);
      exit;
    end;
    }

    if (curr.z < 0) then begin
      result.col := RGB(0,0,0,0); // floor
      exit;
    end;
    if (curr.z >= 1) then begin
      result.col := RGB(0,0,0,0); // sky
      exit;
    end;

    {out of bounds}
    if (dword(curr.x) >= tileSize) or (dword(curr.y) >= tileSize) then begin
      result.col := RGB(255,0,255,0);
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
      tracePos := V3(frac(pos.x)*tileSize, frac(pos.y)*tileSize, frac(pos.z)*tileSize);
      {remove bias, and take a small step back so that we do not start in a voxel}
      tracePos := tracePos - (dir * 0.50);
      hit := vox.trace(tracePos, dir);
      pos += dir * (hit.d/tileSize);
      result.d += (hit.d/tileSize);
      if hit.didHit then begin
        result.hitPos.x := hit.hitPos.x + curr.x*tileSize*256;
        result.hitPos.y := hit.hitPos.y + curr.y*tileSize*256;
        result.hitPos.z := hit.hitPos.z + curr.z*tileSize*256;
        result.hitNormal := perturbNormal(hit.hitNormal, hit.hitPos);
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

{returns linear light}
function tVoxelScene.gatherLighting(p, norm: V3D;nSamples: integer=128;depth: integer=1): RGBA32;
var
  hits: integer;
  tangent, bitangent: V3D;
  d: V3D;
  i: integer;
  hit: tRayHit;
  col32: RGBA32;
  skyColor, lightColor: RGBA32;
begin
  norm.getBasis(tangent, bitangent);

  hits := 0;

  col32.init(0,0,0,0);

  skyColor.init(0.25,0.5,1.0);
  skyColor := skyColor.toLinear();
  lightColor.init(1,0.9,0.1);

  for i := 0 to nSamples-1 do begin
    d := sampleCosine(norm, tangent, bitangent);
    hit := traceRay(p, d, depth);
    {hard code emmissive for the moment}
    if not hit.didHit then
      col32 += skyColor * (0.2/nSamples);
    if hit.col = RGB(255,255,0) then
      col32 += lightColor * (2/nSamples);
  end;
  col32.a := 1;
  result := col32;
end;

{position is in scene space...}
function tVoxelScene.calculateShading(pos,faceNormal: V3D): RGBA;
var
  vx,vy,vz: integer; {position within voxel}
  subPos: V3D; {sub position within voxel}
  vox: tVoxel;
  cameraDir: V3D;
  d: single; {distance from the camera plane}
  voxCol: RGBA;
  gi: RGBA32;
  emmisive: RGBA;
  acc: RGBA32;
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
  { todo: proper emmisive }
  voxCol := vox.getVoxel(vx, vy, vz);
  if voxCol = RGB(255,255,0) then
    emmisive := voxCol
  else
    emmisive := RGBA.Black;

  {calculate distance to camera}
  {todo: cache camera dir}
  cameraDir := V3(0,-1,0).rotated(cameraAngle.x, cameraAngle.y, cameraAngle.z);
  d := cameraDir.dot(pos - cameraPos);

  {gather lighting...}
  if renderMode in [rmShaded, rmGI] then
    {bias the gather point a little}
    gi := gatherLighting(pos+(faceNormal*0.02), faceNormal, renderState.qualitySpec.lightingSamples)
  else
    gi.init(1.0,1.0,1.0);

  {output color}
  case renderMode of
    rmAlbedo: result := voxCol;
    rmNormal:
      result := RGB(
        round(faceNormal.x*128+128),
        round(faceNormal.y*128+128),
        round(faceNormal.z*128+128)
      );
    rmEmmisive: result := emmisive;
    rmGI: result := gi.toGamma().toRGBA;
    rmShaded: begin
      acc := (toRGBA32L(voxCol) * gi) + toRGBA32L(emmisive);
      acc := gi;
      result := acc.toGamma().toRGBA;
    end;
    rmDepth:
      result := RGB(
        255-clamp(round(d*64), 0, 255),
        255-clamp(round(d*64), 0, 255),
        255-clamp(round(d*64), 0, 255)
      );
  end;
  result.a := 255;
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
  hPos,hNorm: V3D;

  function getRayDir(px, py: single): V3D;
  begin
    result := V3((px-(viewWidth/2)) / (viewWidth*1.2), -0.5, (py-(viewHeight/2)) / (viewWidth*1.2));
    result := result.rotated(renderState.cameraAngle.x, renderState.cameraAngle.y, renderState.cameraAngle.z);
    result := result.normed();
  end;

  function sample(dx: single=0; dy: single=0): RGBA;
  begin
    rayDir := getRayDir(renderState.pixelX+(pixelSize/2)+dx,renderState.pixelY+(pixelSize/2)+dy);
    hit := traceRay(rayPos, rayDir);
    if not hit.didHit then col := RGB(0,0,0);
    hPos := hit.hitPos.toV3D * (1/(256*16));
    hNorm := hit.hitNormal;
    result := calculateShading(hPos, hNorm);
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
      assert(renderState.qualitySpec.aaSamples = 4);
      col32.init(0,0,0,0);
      for i := 0 to 1 do begin
        for j := 0 to 1 do begin
          col32 += toRGBA32(sample(((i*2)-1)*0.25, ((j*2)-1)*0.25)) * 0.25;
        end;
      end;
      col := col32.toRGBA();
    end else
      col := sample();

    dc.fillRect(Rect(4+renderState.pixelX, 4+renderState.pixelY, pixelSize, pixelSize), col);
    renderState.nextPixel();

  end;

  traceTime += (getSec - startTime);
end;

begin
end.
