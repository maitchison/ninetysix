{unit for handling voxel drawing}
unit uVoxel;

{$MODE delphi}

interface

uses
  uUtils,
  uTest,
  uDebug,
  uColor,
  uRect,
  uGraph32,
  uMath,
  uFilesystem,
  uInfo,
  uVGADriver,
  uVertex,
  uP96;

var
  {debugging stuff}
  VX_TRACE_COUNT: int32 = 0;
  VX_SHOW_TRACE_EXITS: boolean = false;
  VX_GHOST_MODE: boolean = false;
  VX_USE_SDF: boolean = false;
  VX_UVW_MODE: boolean = false;


type
  tLightingMode = (lmNone, lmGradient);

{restrictions
X,Y,Z <= 256
X,Y powers of 2

Y*Z <= 32*1024 (could be chnaged to 64*1024 if needed)
}

type

  tTraceHit = record
    pos: V3D;
    didHit: boolean;
    d: single;
  end;

  tVoxel = class
  protected
    fWidth,fHeight,fDepth: int32;
    fLog2Width,fLog2Height: byte;
  public
    vox: tPage;     {RGBD - baked (todo: 2 bits of D are for alpha)}
    function  getDistance_L1(x,y,z: integer): integer;
    function  getDistance_L2(x,y,z: integer): single;
    function  generateSDF(): tPage;
    procedure transferSDF(sdf: tPage);

    procedure generateLighting(mode: tLightingMode; diffuse: tPage);

    procedure setPage(page: tPage; height: integer);
    procedure loadFromFile(filename: string; height: integer);

  public
    constructor Create(aWidth, aDepth, aHeight: integer);
    constructor Create(filename: string; height: integer);
    destructor destroy(); override;

    function  getSize(): V3D16;
    function  inBounds(x,y,z:int32): boolean; inline; register;
    function  getVoxel(x,y,z:int32): RGBA; inline; register;
    procedure setVoxel(x,y,z:int32;c: RGBA);
    function  trace(pos: V3D; dir: V3D): tTraceHit;

    function  draw(const dc: tDrawContext;atPos, angle: V3D; scale: single=1;asShadow:boolean=false): tRect;
  end;

implementation

uses
  uPoly,
  uKeyboard; {for debugging}

const
  MAX_SAMPLES = 64;

var
  LAST_TRACE_COUNT: dword = 0;


{$I voxel_ref.inc}
{$I voxel_asm.inc}
{$I voxel_mmx.inc}

{-----------------------------------------------------}
{ Signed distance calculations }
{-----------------------------------------------------}

function tVoxel.getDistance_L1(x,y,z: integer): integer;
var
  dx,dy,dz: integer;
  d: integer;
const
  MAX_D=16;
begin
  if getVoxel(x,y,z).a = 255 then exit(0);
  for d := 1 to MAX_D do
    for dx := -d to d do
      for dy := -d to d do
        for dz := -d to d do
          if getVoxel(x+dx, y+dy, z+dz).a = 255 then
            exit(d);
  exit(MAX_D);
end;

function tVoxel.getDistance_L2(x,y,z: integer): single;
var
  dx,dy,dz: integer;
  d: integer;
  d2: single;
  bestD2: single;
begin

  if getVoxel(x,y,z).a = 255 then exit(0);
  {if we hit something L1 distance away, then closest L2 distance must
   be between L1 and sqrt(2)*L1}
  d := trunc(getDistance_L1(x,y,z) * sqrt(2) + 0.999);
  bestD2 := d*d;
  for dx := -d to d do
    for dy := -d to d do
      for dz := -d to d do
        if getVoxel(x+dx, y+dy, z+dz).a = 255 then begin
          d2 := sqr(dx)+sqr(dy)+sqr(dz);
          bestD2 := minf(bestD2, d2);
        end;
  exit(sqrt(bestD2));
end;

{calculate SDF (the slow way)}
function tVoxel.generateSDF(): tPage;
var
  i,j,k: int32;
  d: single;
  c: RGBA;
begin
  result := vox.clone();
  {note: doing this as largest cubiod make a lot of sense, and it
   lets me trace super fast in many directions}
  {note, it would be nice to actually have negative for interior... but
  for now just closest is fine}

  for i := 0 to fWidth-1 do
    for j := 0 to fHeight-1 do
      for k := 0 to fDepth-1 do begin
        d := getDistance_L2(i,j,k);
        c.init(trunc(d),trunc(d*4),trunc(d*16),255);
        result.setPixel(i,j+k*fHeight, c);
      end;
end;

{store SDF on the alpha channel of this voxel sprite}
procedure tVoxel.transferSDF(sdf: tPage);
var
  x,y: integer;
  c: RGBA;
  d: byte;
begin
  if (sdf.width <> vox.width) or (sdf.height <> vox.height) then
    fatal('SDF dims must match page dims');
  for y := 0 to vox.height-1 do
    for x := 0 to vox.width-1 do begin
      d := sdf.getPixel(x,y).g;
      c := vox.getPixel(x,y);
      c.a := 255-d;
      vox.setPixel(x,y,c);
    end;
end;

{-----------------------------------------------------}

constructor tVoxel.Create(filename: string; height: integer);
begin
  inherited create();
  fWidth := 0;
  fHeight := 0;
  fDepth := 0;
  fLog2Width := 0;
  fLog2Height := 0;
  vox := nil;
  loadFromFile(filename, height);
end;

constructor tVoxel.Create(aWidth, aDepth, aHeight: integer);
begin
  inherited create();
  assert(isPowerOfTwo(aWidth));
  assert(isPowerOfTwo(aDepth));
  assert(isPowerOfTwo(aHeight));
  fWidth := aWidth;
  fHeight := aHeight;
  fDepth := aDepth;
  fLog2Width := round(log2(aWidth));
  fLog2Height := round(log2(aDepth));
  vox := tPage.Create(aWidth, aHeight*aDepth);
end;

destructor tVoxel.destroy();
begin
  freeAndNil(vox);
  inherited destroy();
end;

procedure tVoxel.generateLighting(mode: tLightingMode; diffuse: tPage);
var
  emisive, ambient: tPage;
  x,y,z: int32;
  v: single;
  amb,emi,dif,col: RGBA;
begin
  if mode = lmNone then begin
    vox.getDC(bmBlit).drawImage(diffuse, Point(0,0));
    exit;
  end;

  emisive := diffuse.clone();
  emisive.clear();
  ambient := diffuse.clone();
  ambient.clear();

  case mode of
    lmGradient: begin
      for x := 0 to fWidth-1 do
        for y := 0 to fHeight-1 do
          for z := 0 to fDepth-1 do begin
            v := 1-sqr(z / (fDepth-1));
            ambient.setPixel(x,y+z*fWidth, RGBA.Lerp(
              RGB($FF7F7F7F),
              RGB($FFBACEEF),
              v
            ));
          end;
    end;
  end;

  {modulate}
  for x := 0 to fWidth-1 do
    for y := 0 to fHeight-1 do
      for z := 0 to fDepth-1 do begin
        dif := diffuse.getPixel(x,y+z*fWidth);
        amb := ambient.getPixel(x,y+z*fWidth);
        if dif.a < 255 then
          dif := RGBA.Clear
        else
          dif := RGBA.White;
        col := dif*amb;
        vox.setPixel(x,y+z*fWidth, col);
      end;

  emisive.free();
  ambient.free();
end;

procedure tVoxel.loadFromFile(filename: string; height: integer);
var
  img: tPage;
  sdf: tPage;
begin
  img := tPage.Load(filename+'.p96');
  img.setTransparent(RGBA.create(255,255,255));
  note(format(' - voxel sprite is (%d, %d)', [img.width, img.height]));
  self.setPage(img, height);

  if fileSystem.exists(filename+'.sdf') then begin
    sdf := loadLC96(filename+'.sdf');
  end else begin
    sdf := self.generateSDF();
    saveLC96(filename+'.sdf', sdf);
  end;
  self.generateLighting(lmGradient, img);
  self.transferSDF(sdf);

  sdf.free();
end;

procedure tVoxel.setPage(page: tPage; height: integer);
begin
  vox := page;
  fWidth := page.width;
  fHeight := height;
  fDepth := page.height div height;
  if not fWidth in [1,2,4,8,16,32,64,128] then
    fatal(format('Invalid voxel width %d, must be power of 2, and < 256', [fWidth]));
  if not fHeight in [1,2,4,8,16,32,64,128] then
    fatal(format('Invalid voxel height %d, must be power of 2, and < 256', [fHeight]));
  fLog2Width := round(log2(fWidth));
  fLog2Height := round(log2(fHeight));
end;

{get size as 16bit vector}
function tVoxel.getSize(): V3D16;
begin
  result.x := fWidth;
  result.y := fHeight;
  result.z := fDepth;
  result.w := 0;
end;

function tVoxel.inBounds(x,y,z: int32): boolean; inline; register;
begin
  if (dword(x) >= fWidth) then exit(false);
  if (dword(y) >= fHeight) then exit(false);
  if (dword(z) >= fDepth) then exit(false);
  result := true;
end;

function tVoxel.getVoxel(x,y,z:int32): RGBA; inline; register;
begin
  {todo: fast asm}
  result.r := 255; result.g := 0; result.b := 255; result.a := 255;
  if not inBounds(x,y,z) then exit;
  result := pRGBA(vox.pixels + ((x+((y+(z shl fLog2Height)) shl fLog2Width))) shl 2)^;
end;

{
Trace ray through object. ignores initial voxel.
Very slow for the moment.
(0.5,0.5 is center of voxel)
dir should be normalized
}
function tVoxel.trace(pos: V3D; dir: V3D): tTraceHit;
var
  i: integer;
  maxSteps: integer;
  c: RGBA;
  old,cur: V3D32;
const
  STEP_SIZE = 0.1;
begin
  assert(abs(dir.abs2-1.0) < 1e-6);
  maxSteps := ceil(sqrt(sqr(fWidth)+sqr(fHeight)+sqr(fDepth))/STEP_SIZE);
  result.pos := pos;
  result.d := 0;
  old := V3D32.Trunc(pos);
  for i := 0 to maxSteps-1 do begin
    cur := V3D32.Trunc(result.pos);
    if (cur <> old) then begin
      {we moved to a new cell}
      if not inBounds(cur.x, cur.y, cur.z) then begin
        result.didHit := false;
        exit;
      end;
      c := getVoxel(cur.x, cur.y, cur.z);
      if c.a = 255 then begin
        result.didHit := true;
        exit;
      end;
    end;
    result.pos += dir * STEP_SIZE;
    result.d += STEP_SIZE;
  end;

  result.didHit := false;

end;

procedure tVoxel.setVoxel(x,y,z:int32;c: RGBA);
begin
  {todo: fast asm}
  if (x < 0) or (x >= fWidth) then exit;
  if (y < 0) or (y >= fHeight) then exit;
  if (z < 0) or (z >= fDepth) then exit;
  vox.setPixel(x,y+z*fHeight, c);
end;

{draw voxel sprite, with position given in world space.
returns the bounding rect of the drawn object.
todo: correctly account for offset and clip
}
function tVoxel.draw(const dc: tDrawContext;atPos, angle: V3D; scale: single=1;asShadow:boolean=false): tRect;
var
  c, debugCol: RGBA;
  faceColor: array[1..6] of RGBA;
  size: V3D; {half size of cuboid}
  cameraX, cameraY, cameraZ, cameraDir: V3D;
  p: array[1..8] of V3D; {world space}
  polyBounds: tRect;

  {view is identity as we have no camera}
  model, projection: tMatrix4X4;
  mvp, mvpInv: tMatrix4X4;

  //objToWorld: tMatrix4X4;
  //worldToObj: tMatrix4X4;
  isometricTransform : tMatrix4x4;
  lastTraceCount: int32;
  i: integer;

  {traces all pixels within the given polygon.
  points are in world space

  How this works:

  We trace against a cuboid, in object space. That is, the object is
  fixed and to render a rotation we rotate where the intersecting rays
  are comming from.

  We intersect a ray onto the face of a cube, then work out that point
  changes as we scan the ray accross and down the screen.

  We consider the initial position of the ray, as well as the intersection
  point, aswell as how far the ray must travel from origin before it
  intersects the face

  We caculate

    rayOrigin - location of ray origin in object space
    pos     - location of intersection, in object space
    t       - The distance from the ray's origin to the intersection point;

    deltaX  - How much intersection point changes as we can accross screen
    deltaY  - How much intersection point changes as we can accross down
    txDelta - How much t changes as we scan accross
    tyDelta - How much t changes as we scan down
  }
  procedure traceFace(faceID: byte; p1,p2,p3,p4: V3D);
  var
    c: RGBA;
    cross: single;
    y: int32;
    x: int32;
    worldPos: V3D;
    t: single;
    rayOrigin, pos, basePos, deltaX, deltaY: V3D;
    txDelta, tyDelta: single;
    aZ, invZ: single;
    value: integer;
    c1,c2,c3,c4: RGBA;
    s1,s2,s3,s4: tPoint;
    traceProc: tTraceScanlineProc;
  begin

    {for debugging}
    if true then begin
      if keyDown(key_1) and (faceID = 1) then exit;
      if keyDown(key_2) and (faceID = 2) then exit;
      if keyDown(key_3) and (faceID = 3) then exit;
      if keyDown(key_4) and (faceID = 4) then exit;
      if keyDown(key_5) and (faceID = 5) then exit;
      if keyDown(key_6) and (faceID = 6) then exit;
    end;

    {scan the sides of the polygon}
    polyDraw.scanPoly(dc.page, p1.toPoint, p2.toPoint, p3.toPoint, p4.toPoint);
    polyBounds := polyDraw.bounds;
    if polyBounds.area <= 0 then exit;

    {alternative solid face render (for debugging)}
    if (keyDown(key_0)) then begin
      for y := polyBounds.top to polyBounds.bottom-1 do
        dc.hLine(Point(polyDraw.scanLine[y].xMin, y), polyDraw.scanLine[y].len, faceColor[faceID]);
      exit;
    end;

    if asShadow then begin
      for y := polyBounds.top to polyBounds.bottom-1 do
        dc.hline(
          Point(polyDraw.scanLine[y].xMin, y), polyDraw.scanLine[y].len,
          RGB(0,0,0,48));
      exit;
    end;

    case faceID of
      1: aZ := cameraDir.z;
      2: aZ := cameraDir.z;
      3: aZ := cameraDir.x;
      4: aZ := cameraDir.x;
      5: aZ := cameraDir.y;
      6: aZ := cameraDir.y;
    end;
    if aZ = 0 then exit; {this should not happen}
    invZ := 1/aZ;

    {calculate our deltas}
    case faceID of
      1: begin txDelta := -cameraX.z * invZ; tyDelta := -cameraY.z * invZ; end;
      2: begin txDelta := -cameraX.z * invZ; tyDelta := -cameraY.z * invZ; end;
      3: begin txDelta := -cameraX.x * invZ; tyDelta := -cameraY.x * invZ; end;
      4: begin txDelta := -cameraX.x * invZ; tyDelta := -cameraY.x * invZ; end;
      5: begin txDelta := -cameraX.y * invZ; tyDelta := -cameraY.y * invZ; end;
      6: begin txDelta := -cameraX.y * invZ; tyDelta := -cameraY.y * invZ; end;
    end;
    deltaX := cameraX + cameraDir*txDelta;
    deltaY := cameraY + cameraDir*tyDelta;

    //stub:
    {
    if cpuInfo.hasMMX then
      traceProc := traceScanline_MMX
    else
      traceProc := traceScanline_ASM;
    if keyDown(key_f5) then
      traceProc := traceScanline_REF;
    }
    traceProc := traceScanline_REF;

    for y := polyBounds.top to polyBounds.bottom-1 do begin

      if polyDraw.scanLine[y].xMax < polyDraw.scanLine[y].xMin then
        continue;

      {find the ray's origin given current screenspace coord}
      {note: we trace from the middle of the pixel, not the top-left corner.
       this resolves some precision errors}
      rayOrigin :=
        cameraX*((polyDraw.scanLine[y].xMin)-atPos.x+0.5) +
        cameraY*(y-atPos.y+0.5)+
        cameraDir*(0-atPos.z);

      case faceID of
        1: t := (-size.z-rayOrigin.z) * invZ;
        2: t := (+size.z-rayOrigin.z) * invZ;
        3: t := (-size.x-rayOrigin.x) * invZ;
        4: t := (+size.x-rayOrigin.x) * invZ;
        5: t := (-size.y-rayOrigin.y) * invZ;
        6: t := (+size.y-rayOrigin.y) * invZ;
        else t := 0;
      end;

      pos := rayOrigin + cameraDir * (t+0.50); {start half way in a voxel}
      pos += V3D.create(fWidth/2,fHeight/2,fDepth/2); {center object}

      traceProc(
        dc.page, self,
        polyDraw.scanLine[y].xMin+dc.offset.x, polyDraw.scanLine[y].xMax+dc.offset.x, y+dc.offset.y,
        pos, cameraDir, deltaX, deltaY
      );
    end;
  end;

begin

  if not assigned(self) then fatal('Tried to call draw on an assigned vox.');

  VX_TRACE_COUNT := 0;
  if scale = 0 then exit;

  faceColor[1].init(255,0,0);
  faceColor[2].init(128,0,0);
  faceColor[3].init(0,255,0);
  faceColor[4].init(0,128,0);
  faceColor[5].init(0,0,255);
  faceColor[6].init(0,0,128);

  {note:
    I make use of transpose to invert the rotation matrix, but
    this means I need to apply scale and translate later on
    which is a bit of a pain
  }

  {set up our matrices}
  model.setRotationXYZ(angle.x, angle.y, angle.z);
  if asShadow then
    model.scale(1,1,0);
  projection.setRotationX(-0.615); //~35 degrees
  mvp := model * projection;

  {convert given world position}
  atPos := projection.apply(atPos);

  {calculate the inverse matrix}
  mvpInv := mvp.transposed();
  model.scale(scale);
  mvp.scale(scale);
  mvpInv.scale(1/scale);

  {handle translation here as a bit of a hack, as I want the
   inversion to be simple}
  model.translate(atPos);
  mvp.translate(atPos);
  mvpInv.translate(atPos * -1);

  cameraX := mvpInv.apply(V3D.create(1,0,0,0));
  cameraY := mvpInv.apply(V3D.create(0,1,0,0));
  cameraZ := mvpInv.apply(V3D.create(0,0,1,0));
  cameraDir := cameraZ.normed();

  {get cube corners}
  {note: this would be great place to apply cropping}
  size := V3D.create(fWidth/2,fHeight/2,fDepth/2);

  {object space -> world space}
  p[1] := mvp.apply(V3D.create(-size.x, -size.y, -size.z, 1));
  p[2] := mvp.apply(V3D.create(+size.x, -size.y, -size.z, 1));
  p[3] := mvp.apply(V3D.create(+size.x, +size.y, -size.z, 1));
  p[4] := mvp.apply(V3D.create(-size.x, +size.y, -size.z, 1));
  p[5] := mvp.apply(V3D.create(-size.x, -size.y, +size.z, 1));
  p[6] := mvp.apply(V3D.create(+size.x, -size.y, +size.z, 1));
  p[7] := mvp.apply(V3D.create(+size.x, +size.y, +size.z, 1));
  p[8] := mvp.apply(V3D.create(-size.x, +size.y, +size.z, 1));

  {trace each side of the cubeoid}
  polyDraw.backfaceCull := true;
  traceFace(1, p[1], p[2], p[3], p[4]);
  traceFace(2, p[8], p[7], p[6], p[5]);
  traceFace(3, p[4], p[8], p[5], p[1]);
  traceFace(4, p[2], p[6], p[7], p[3]);
  traceFace(5, p[5], p[6], p[2], p[1]);
  traceFace(6, p[4], p[3], p[7], p[8]);

  {return our bounds}
  result := Rect(p[1].toPoint.x,p[1].toPoint.y,0,0);
  for i := 2 to 8 do
    result.expandToInclude(p[i].toPoint);
  {seems like we're off by one for some reason}
  result.pad(1);

end;


{-----------------------------------------------------}

begin
end.
