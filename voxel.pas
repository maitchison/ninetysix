{unit for handling voxel drawing}
unit voxel;

{stub}


{$MODE delphi}

interface

uses
  utils,
  test,
  debug,
  graph32,
  graph2d,
  vga,
  vertex,
  lc96;

var
  {debugging stuff}
  VX_TRACE_COUNT: int32 = 0;
  VX_SHOW_TRACE_EXITS: boolean = false;
  VX_SHOW_CORNERS: boolean = false;
  VX_GHOST_MODE: boolean = false;
  VX_UVW_MODE: boolean = false;


{restrictions
X,Y,Z <= 256
X,Y powers of 2

Y*Z <= 32*1024 (could be chnaged to 64*1024 if needed)
}

type
  tVoxelSprite = class
  protected
    vox: tPage;
    fLog2Width,fLog2Height: byte;
    fWidth,fHeight,fDepth: int16;

    function getDistance_L1(x,y,z: integer): integer;
    function getDistance_L2(x,y,z: integer): single;
    function generateSDF(): tPage;
    procedure transferSDF(sdf: tPage);

  public

    constructor create();
    procedure setPage(page: tPage; height: integer);
    class function loadFromFile(filename: string; height: integer): tVoxelSprite; static;
    function getSize(): V3D16;
    function getVoxel(x,y,z:int32): RGBA;
    procedure setVoxel(x,y,z:int32;c: RGBA);
    function draw(canvas: tPage;atPos, angle: V3D; scale: single=1;asShadow:boolean=false): tRect;
  end;

implementation

uses keyboard; {for debugging}

const
  MAX_SAMPLES = 64;

var
  LAST_TRACE_COUNT: dword = 0;


{$I voxel_ref.inc}
{$I voxel_asm.inc}
{$I voxel_mmx.inc}

{----------------------------------------------------}
{ Poly drawing }
{----------------------------------------------------}

type
  tScreenLine = record
    xMin, xMax: int32;
    procedure reset();
    procedure adjust(x: int16);
  end;

procedure tScreenLine.reset(); inline;
begin
  xMax := 0;
  xMin := videoDriver.width;
end;

procedure tScreenLine.adjust(x: int16); inline;
begin
  xMin := min(x, xMin);
  xMax := max(x, xMax);
end;

var
  screenLines: array[0..1024-1] of tScreenLine;

{-----------------------------------------------------}
{ Signed distance calculations }
{-----------------------------------------------------}

function tVoxelSprite.getDistance_L1(x,y,z: integer): integer;
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

function tVoxelSprite.getDistance_L2(x,y,z: integer): single;
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
          bestD2 := min(bestD2, d2);
        end;
  exit(sqrt(bestD2));
end;

{calculate SDF (the slow way)}
function tVoxelSprite.generateSDF(): tPage;
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
procedure tVoxelSprite.transferSDF(sdf: tPage);
var
  x,y: integer;
  c: RGBA;
  d: byte;
begin
  if (sdf.width <> vox.width) or (sdf.height <> vox.height) then
    error('SDF dims must match page dims');
  for y := 0 to vox.height-1 do
    for x := 0 to vox.width-1 do begin
      d := sdf.getPixel(x,y).g;
      c := vox.getPixel(x,y);
      c.a := 255-d;
      vox.setPixel(x,y,c);
    end;
end;

{-----------------------------------------------------}

constructor tVoxelSprite.create();
begin
  fWidth := 0;
  fHeight := 0;
  fDepth := 0;
  fLog2Width := 0;
  fLog2Height := 0;
end;


procedure tVoxelSprite.setPage(page: tPage; height: integer);
begin
  vox := page;
  fWidth := page.width;
  fHeight := height;
  fDepth := page.height div height;
  if not fWidth in [1,2,4,8,16,32,64,128] then
    error(format('Invalid voxel width %d, must be power of 2, and < 256', [fWidth]));
  if not fHeight in [1,2,4,8,16,32,64,128] then
    error(format('Invalid voxel height %d, must be power of 2, and < 256', [fHeight]));
  fLog2Width := round(log2(fWidth));
  fLog2Height := round(log2(fHeight));
end;

class function tVoxelSprite.loadFromFile(filename: string; height: integer): tVoxelSprite;
var
  img: tPage;
  sdf: tPage;

begin

  result := tVoxelSprite.create();

  {Right now this is hard-coded to preprocess the car sprite.
   Eventually we will so this somewhere else, and perform
   a single image load}

  if exists(filename+'.p96') then
    img := loadLC96(filename+'.p96')
  else begin
    img := loadBMP(filename+'.bmp');
    saveLC96(filename+'.p96', img);
  end;
  img.setTransparent(RGBA.create(255,255,255));

  note(format('Voxel sprite is (%d, %d)', [img.width, img.height]));
  result.setPage(img, height);

  if exists(filename+'.sdf') then begin
    sdf := loadLC96(filename+'.sdf');
  end else begin
    sdf := result.generateSDF();
    saveLC96(filename+'.sdf', sdf);
  end;

  result.transferSDF(sdf);
end;


{get size as 16bit vector}
function tVoxelSprite.getSize(): V3D16;
begin
  result.x := fWidth;
  result.y := fHeight;
  result.z := fDepth;
  result.w := 0;
end;

function tVoxelSprite.getVoxel(x,y,z:int32): RGBA;
begin
  {todo: fast asm}
  result.init(255,0,255,0);
  if (x < 0) or (x >= fWidth) then exit;
  if (y < 0) or (y >= fHeight) then exit;
  if (z < 0) or (z >= fDepth) then exit;
  result := vox.getPixel(x,y+z*fHeight);
end;

procedure tVoxelSprite.setVoxel(x,y,z:int32;c: RGBA);
begin
  {todo: fast asm}
  if (x < 0) or (x >= fWidth) then exit;
  if (y < 0) or (y >= fHeight) then exit;
  if (z < 0) or (z >= fDepth) then exit;
  vox.setPixel(x,y+z*fHeight, c);
end;

{draw voxel sprite, with position given in world space.
returns the bounding rect of the drawn object.
}
function tVoxelSprite.draw(canvas: tPage;atPos, angle: V3D; scale: single=1;asShadow:boolean=false): tRect;
var
  c, debugCol: RGBA;
  faceColor: array[1..6] of RGBA;
  size: V3D; {half size of cuboid}
  cameraX, cameraY, cameraZ, cameraDir: V3D;
  p: array[1..8] of V3D; {world space}


  {view is identity as we have no camera}
  model, projection: tMatrix4X4;
  mvp, mvpInv: tMatrix4X4;

  //objToWorld: tMatrix4X4;
  //worldToObj: tMatrix4X4;
  isometricTransform : tMatrix4x4;
  lastTraceCount: int32;
  i: integer;

  procedure scanSide(a, b: tPoint);
  var
    tmp: tPoint;
    y: int32;
    x: single;
    deltaX: single;
    yMin, yMax: integer;
  begin
    if a.y = b.y then begin
      {special case}
      y := a.y;
      if (y >= 0) and (y < canvas.height) then begin
        screenLines[y].adjust(a.x);
        screenLines[y].adjust(b.x);
      end;
      exit;
    end;

    if a.y > b.y then begin
      tmp := a; a := b; b := tmp;
    end;

    x := a.x;
    deltaX := (b.x-a.x) / (b.y-a.y);
    yMin := a.y;
    if yMin < 0 then begin
      x += deltaX * -yMin;
      yMin := 0;
    end;
    yMax := min(b.y, canvas.height-1);
    for y := yMin to yMax do begin
      screenLines[y].adjust(round(x));
      x += deltaX;
    end;
  end;

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
    y, yMin, yMax: int32;
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

    {do not render back face}
    cross := ((p2.x-p1.x) * (p3.y - p1.y)) - ((p2.y - p1.y) * (p3.x - p1.x));
    if cross <= 0 then exit;

    s1 := p1.toPoint;
    s2 := p2.toPoint;
    s3 := p3.toPoint;
    s4 := p4.toPoint;

    yMin := min(s1.y, s2.y);
    yMin := min(yMin, s3.y);
    yMin := min(yMin, s4.y);
    yMin := max(0, yMin);

    yMax := max(s1.y, s2.y);
    yMax := max(yMax, s3.y);
    yMax := max(yMax, s4.y);
    yMax := min(videoDriver.logicalHeight-1, yMax);

    //do not render offscreen sides
    if yMax < yMin then exit;

    {debuging, show corners}
    if VX_SHOW_CORNERS then begin
      c.init(255,0,255);
      canvas.putPixel(s1.x, s1.y, c);
      canvas.putPixel(s2.x, s2.y, c);
      canvas.putPixel(s3.x, s3.y, c);
      canvas.putPixel(s4.x, s4.y, c);
    end;

    // stub:
    note(format('%d %d', [yMin, yMax]));

    for y := yMin to yMax do
      screenLines[y].reset();

    {scan the sides of the polygon}
    scanSide(s1, s2);
    scanSide(s2, s3);
    scanSide(s3, s4);
    scanSide(s4, s1);

    {alternative solid face render (for debugging)}
    if (faceID in []) then begin
      for y := yMin to yMax do
        canvas.hLine(screenLines[y].xMin, y, screenLines[y].xMax, faceColor[faceID]);
      exit;
    end;

    if asShadow then begin
      for y := yMin to yMax do
        canvas.hline(
          screenLines[y].xMin, y, screenLines[y].xMax,
          rgba.create(0,0,0,48));
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

    if cpuInfo.hasMMX then
      traceProc := traceScanline_MMX
    else
      traceProc := traceScanline_ASM;
    if keyDown(key_f5) then
      traceProc := traceScanline_REF;

    for y := yMin to yMax-1 do begin

      if screenLines[y].xMax < screenLines[y].xMin then
        continue;

      {find the ray's origin given current screenspace coord}
      {note: we trace from the middle of the pixel, not the top-left corner.
       this resolves some precision errors}
      rayOrigin :=
        cameraX*((screenLines[y].xMin)-atPos.x+0.5) +
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
        canvas, self,
        screenLines[y].xMin, screenLines[y].xMax, y,
        pos, cameraDir, deltaX, deltaY
      );
    end;
  end;

begin

  if not assigned(self) then error('Tried to call draw on an assigned vox.');

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
  traceFace(1, p[1], p[2], p[3], p[4]);
  traceFace(2, p[8], p[7], p[6], p[5]);
  traceFace(3, p[4], p[8], p[5], p[1]);
  traceFace(4, p[2], p[6], p[7], p[3]);
  traceFace(5, p[5], p[6], p[2], p[1]);
  traceFace(6, p[4], p[3], p[7], p[8]);

  {return our bounds}
  result := tRect.create(p[1].toPoint.x,p[1].toPoint.y,0,0);
  for i := 2 to 8 do
    result.expandToInclude(p[i].toPoint);
  {seems like we're off by one for some reason}
  result.pad(1);

end;


{-----------------------------------------------------}

begin
end.
