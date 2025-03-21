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
  VX_USE_SDF: boolean = true;
  VX_UVW_MODE: boolean = false;

const
  VX_FACE_COLOR: array[1..6] of RGBA = (
    (b: $00; g: $00; r: $ff; a:$ff),
    (b: $00; g: $00; r: $7f; a:$ff),
    (b: $00; g: $ff; r: $00; a:$ff),
    (b: $00; g: $7f; r: $00; a:$ff),
    (b: $ff; g: $00; r: $00; a:$ff),
    (b: $7f; g: $00; r: $00; a:$ff)
  );

type
  tLightingMode = (lmNone, lmGradient, lmSimple, lmGI, lmAO);

{restrictions
X,Y,Z <= 256
X,Y powers of 2

Y*Z <= 32*1024 (could be chnaged to 64*1024 if needed)
}

type

  tRayHit = record
    pos: V3D;
    col: RGBA;
    d: single;
    didHit: boolean;
  end;

  tSDFQuality = (sdfNone, sdfFast, sdfFull);

  tVoxel = class
  protected
    fWidth,fHeight,fDepth: int32;
    fRadius: single;
    fVolume: int32;
    fLog2Width,fLog2Height: byte;
  protected
    {for progressive lighting}
    lx,ly,lz: integer;
    lMode: tLightingMode;
    lSamples: integer;
  protected
    procedure generateSDF_fast(maxDistance: integer=-1);
    function  getSDF_slow(maxDistance: integer=-1): tPage;
    procedure transferSDF(sdf: tPage);
    procedure applyLighting(x,y,z: integer; lightingMode: tLightingMode);
    function  calculateGI(x,y,z: integer): single;
  protected
    function  trace_ref(pos: V3D; dir: V3D): tRayHit;
    function  trace_asm(aPos: V3D; aDir: V3D): tRayHit;
  public
    vox: tPage;     // RGBD - baked (todo: 2 bits of D are for alpha)
    function  getDistance_L1(x,y,z: integer;minDistance: integer=-1; maxDistance: integer=-1): integer;
    function  getDistance_L2(x,y,z: integer;minDistance: integer=-1; maxDistance: integer=-1): single;
    procedure generateSDF(quality: tSDFQuality=sdfFast);

    procedure generateLighting(lightingMode: tLightingMode;defer: boolean=false);
    function  updateLighting(maxSamples: integer=1): boolean;

    procedure setPage(page: tPage; height: integer);
    //procedure loadP96FromFile(filename: string; height: integer);
    procedure loadVoxFromFile(filename: string; height: integer);

    property  lightingSamples: integer read lSamples write lSamples;

  public
    constructor Create(aWidth, aDepth, aHeight: integer); overload;
    constructor Create(aFilename: string; aHeight: integer); overload;
    constructor Create(aPage: tPage; aHeight: integer); overload;
    destructor destroy(); override;

    function  getSize(): V3D16;
    function  inBounds(x,y,z:int32): boolean; inline; register;
    function  getAddr(x,y,z:int32): int32; inline; register;
    function  getVoxel(x,y,z:int32): RGBA; inline; register;
    procedure setVoxel(x,y,z:int32;c: RGBA);
    function  trace(pos: V3D; dir: V3D): tRayHit;
    procedure swapVoxels(x,y,z: integer;a,b,c: integer); inline;
    procedure rotate();

    function  draw(const dc: tDrawContext;atPos, angle: V3D; scale: single=1;asShadow:boolean=false): tRect;
  end;

implementation

uses
  uPoly,
  uKeyboard; {for debugging}

const
  MAX_SAMPLES = 128;

var
  LAST_TRACE_COUNT: dword = 0;


{$I voxel_ref.inc}
{$I voxel_asm.inc}
{$I voxel_mmx.inc}

{-----------------------------------------------------}
{ Signed distance calculations }
{-----------------------------------------------------}

function tVoxel.getDistance_L1(x,y,z: integer;minDistance: integer=-1;maxDistance: integer=-1): integer;
var
  dx,dy,dz: integer;
  d: integer;
begin
  if getVoxel(x,y,z).a = 255 then exit(0);
  if maxDistance < 0 then maxDistance := ceil(fRadius);
  if minDistance < 0 then minDistance := 0;
  for d := 1 to maxDistance do
    for dx := -d to d do
      for dy := -d to d do
        for dz := -d to d do
          if getVoxel(x+dx, y+dy, z+dz).a = 255 then exit(d);
  exit(maxDistance);
end;

function tVoxel.getDistance_L2(x,y,z: integer;minDistance: integer=-1; maxDistance: integer=-1): single;
var
  dx,dy,dz: integer;
  d: integer;
  d2: single;
  innerD: integer;
  bestD2: single;
begin
  if getVoxel(x,y,z).a = 255 then exit(0);
  {if we hit something L1 distance away, then closest L2 distance must
   be between L1 and sqrt(2)*L1}
  innerD := getDistance_L1(x,y,z);
  d := trunc(innerD * sqrt(2) + 0.999);
  bestD2 := d*d;
  for dx := -d to d do begin
    for dy := -d to d do begin
      for dz := -d to d do begin
        if getVoxel(x+dx, y+dy, z+dz).a = 255 then begin
          d2 := sqr(dx)+sqr(dy)+sqr(dz);
          bestD2 := minf(bestD2, d2);
        end;
      end
    end;
  end;
  exit(sqrt(bestD2));
end;

{calculate SDF (the fast way)}
procedure tVoxel.generateSDF_Fast(maxDistance: integer=-1);
var
  d,i,j,k: integer;
  depth: array of byte;
  vPtr: pRGBA;
  dPtr: pByte;
  lp: dword;
  layerCount: array of int32;

  function getDepth(x,y,z: integer): integer; inline;
  begin
    if not inBounds(x,y,z) then exit(-1);
    result := depth[getAddr(x,y,z)];
  end;

  procedure setDepth(x,y,z: integer;d:byte); inline;
  var
    addr: dword;
  begin
    if not inBounds(x,y,z) then exit;
    addr := getAddr(x,y,z);
    if depth[addr] = 255 then begin
      inc(layerCount[z]);
      depth[addr] := d;
    end;
  end;

  procedure setNeighbours(x,y,z: integer;d: byte);
  var
    dx,dy,dz: integer;
  begin
    for dx := -1 to 1 do
      for dy := -1 to 1 do
        for dz := -1 to 1 do
          setDepth(x+dx, y+dy, z+dz, d);
  end;

begin

  if maxDistance < 0 then maxDistance := ceil(fRadius);

  {number of set voxels in each depth layer}
  setLength(layerCount, fDepth);
  filldword(layerCount[0], fDepth, 0);

  {init distance field}
  setLength(depth, fVolume);
  fillchar(depth[0], length(depth), 255);
  vPtr := vox.pixels;
  dPtr := @depth[0];
  for lp := 0 to fVolume-1 do begin
    if vPtr^.a = 255 then dPtr^ := 0;
    inc(vPtr);
    inc(dPtr);
  end;

  for d := 0 to maxDistance-1 do
    for k := 0 to fDepth-1 do begin
      //if layerCount[k] = (fWidth*fHeight) then continue;
      dPtr := @depth[getAddr(0,0,k)];
      for lp := 0 to fWidth*fHeight-1 do begin
        if dPtr^ = d then
          setNeighbours(lp and (fWidth-1), lp shr fLog2Width, k, d+1);
        inc(dPtr);
      end;
    end;

  {apply back}
  vPtr := vox.pixels;
  dPtr := @depth[0];
  for lp := 0 to fVolume-1 do begin
    d := dPtr^;
    if d = 255 then d := maxDistance;
    vPtr^.a := clamp(255-(d*4), 0, 255);
    inc(vPtr);
    inc(dPtr);
  end;

  setLength(depth,0);
end;


{calculate SDF (the slow way)}
function tVoxel.getSDF_Slow(maxDepth: integer=-1): tPage;
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

{calculate SDF}
procedure tVoxel.generateSDF(quality: tSDFQuality=sdfFast);
begin
  case quality of
    sdfNone: generateSDF_Fast(0);
    sdfFast: generateSDF_Fast(8);
    sdfFull: generateSDF_Fast(ceil(fRadius));
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

constructor tVoxel.Create(aFilename: string; aHeight: integer);
begin
  inherited Create();
  fWidth := 0;
  fHeight := 0;
  fDepth := 0;
  fLog2Width := 0;
  fLog2Height := 0;
  fRadius := 0;
  fVolume := 0;
  lSamples := 64;
  vox := nil;
  loadVoxFromFile(aFilename, aHeight);
end;

constructor tVoxel.Create(aPage: tPage; aHeight: integer);
var
  pPtr: pRGBA;
  lp: dword;
begin
  Create(aPage.width, aHeight, aPage.height div aHeight);
  // transfer diffuse to voxels
  vox.getDC(bmBlit).drawImage(aPage, Point(0,0));

  // set very simple SDF, but treat all a<>0 pixels as solid.
  pPtr := vox.pixels;
  for lp := 0 to fVolume-1 do begin
    if pPtr^.a = 0 then pPtr^.a := 255-4 else pPtr^.a := 255-0;
    inc(pPtr);
  end;
end;

constructor tVoxel.Create(aWidth, aDepth, aHeight: integer);
begin
  inherited Create();
  assert(isPowerOfTwo(aWidth));
  assert(isPowerOfTwo(aDepth));
  assert(isPowerOfTwo(aHeight));
  fWidth := aWidth;
  fHeight := aHeight;
  fDepth := aDepth;
  fLog2Width := round(log2(aWidth));
  fLog2Height := round(log2(aDepth));
  fRadius := sqrt(sqr(fWidth)+sqr(fHeight)+sqr(fDepth));
  fVolume := fWidth * fHeight * fDepth;
  lSamples := 64;
  vox := tPage.Create(aWidth, aHeight*aDepth);
end;

destructor tVoxel.destroy();
begin
  freeAndNil(vox);
  inherited destroy();
end;

function tVoxel.calculateGI(x,y,z: integer): single;
var
  i: integer;
  p,d: V3D;
  hit: tRayHit;
  hits: integer;
  norm,tangent,biTangent: V3D;
  orig: V3D32;

  function isSolid(x,y,z: int32): boolean; inline;
  begin
    if z < 0 then exit(false); {open sky}
    if not inBounds(x,y,z) then exit(true);
    result := vox.getPixel(x,y+z*fWidth).a = 255;
  end;

  {guess which way the voxel is 'pointing'}
  function guessNorm(): V3D;
  begin
    result := V3(0,0,0);
    if not isSolid(x-1,y,z) then result += V3(-1,0,0);
    if not isSolid(x+1,y,z) then result += V3(+1,0,0);
    if not isSolid(x,y-1,z) then result += V3(0,-1,0);
    if not isSolid(x,y+1,z) then result += V3(0,+1,0);
    if not isSolid(x,y,z-1) then result += V3(0,0,-1);
    if not isSolid(x,y,z+1) then result += V3(0,0,+1);
    // default to facing camera
    if result.abs2 = 0 then result := V3(0,-1,0);
    result := result.normed();
  end;

begin
  orig.x := x; orig.y := y; orig.z := z;
  norm := guessNorm();
  p := V3(x, y, z) + norm + V3(0.5, 0.5, 0.5);
  hits := 0;

  norm.getBasis(tangent, bitangent);

  for i := 0 to lSamples-1 do begin
    d := sampleCosine(norm, tangent, bitangent);
    {hemisphere sampling}
    if d.z > 0 then begin
      {hit a pretend floor plane}
      inc(hits);
      continue;
    end;
    hit := trace(p, d);
    if hit.didHit then inc(hits);
  end;
  result := 1-(hits/lSamples);
end;

procedure tVoxel.swapVoxels(x,y,z: integer;a,b,c: integer); inline;
var
  t: RGBA;
begin
  t := getVoxel(x,y,z);
  setVoxel(x,y,z, getVoxel(a,b,c));
  setVoxel(a,b,c,t);
end;

{rotate voxel around z by 90 degrees}
procedure tVoxel.rotate();
var
  x,y,z: integer;
begin
  for z := 0 to fDepth-1 do
    for y := 0 to fHeight-1 do
      for x := y to fWidth-1 do begin
        swapVoxels(x,y,z,y,x,z);
      end;

  for z := 0 to fDepth-1 do
    for y := 0 to fHeight-1 do
      for x := 0 to (fWidth div 2)-1 do begin
        swapVoxels(x,y,z,(fWidth-1)-x,y,z);
      end;
end;

function tVoxel.updateLighting(maxSamples: integer=1): boolean;
var
  pVox: pRGBA;

  procedure nextVoxel();
  begin
    {move to next voxel}
    inc(lx);
    if lx >= fWidth then begin
      lx := 0;
      inc(ly);
    end;
    if ly >= fHeight then begin
      ly := 0;
      inc(lz);
    end;
    if lz >= fDepth then begin
      lMode := lmNone;
      lz := 0;
    end;
  end;
begin
  if lMode = lmNone then exit(true);

  {update the lighting for current voxel}
  applyLighting(lx,ly,lz,lMode);
  {find next voxel to}
  repeat
    nextVoxel();
    pVox := pRGBA(vox.pixels + getAddr(lx,ly,lz)*4);
  until (lMode = lmNone) or (pVox^.a = 255);

  {return if we are done}
  result := (lMode = lmNone);
  {mark it for debugging}
  {
  if not result then begin
    pVox^.r := 255;
    pVox^.g := 0;
    pVox^.b := 255;
  end;
  }
end;

procedure tVoxel.applyLighting(x,y,z: integer; lightingMode: tLightingMode);
var
  v: single;
  pVox: pRGBA;
  addr: dword;
  amb: RGBA;

  {returns number of neighbours for current cell}
  function countNeighbours(): integer;
  begin
    result := 0;
    if vox.getPixel((x-1),(y)+(z)*fWidth).a = 255 then inc(result);
    if vox.getPixel((x+1),(y)+(z)*fWidth).a = 255 then inc(result);
    if vox.getPixel((x),(y-1)+(z)*fWidth).a = 255 then inc(result);
    if vox.getPixel((x),(y+1)+(z)*fWidth).a = 255 then inc(result);
    if vox.getPixel((x),(y)+(z-1)*fWidth).a = 255 then inc(result);
    if vox.getPixel((x),(y)+(z+1)*fWidth).a = 255 then inc(result);
  end;

  function isOccluded(): boolean;
  begin
    result := (x<>0) and (y<>0) and (z<>0) and (x<>fWidth-1) and (y<>fHeight-1) and (z<>fDepth-1) and (countNeighbours = 6);
  end;

begin
  if getVoxel(x,y,z).a <> 255 then exit;
  //if isOccluded then continue; // this is a good idea.. but test it.
  case lightingMode of
    lmGradient: v := 1.2-sqr(z / (fDepth-1));
    lmSimple: v := 1.2-(countNeighbours()/6);
    lmGI, lmAO:
      // this is the technically correct one
      //v := power(calculateGI(x,y,z), 0.4545);
      // this look much better though
      v := sqr(calculateGI(x,y,z));
  end;
  amb := RGBA.Lerp(
    //RGB($FF0F0F0F),
    //RGB($FFBACEEF),
    RGBA.Black,
    RGBA.White,
    v
  );
  {modulate}
  addr := getAddr(x,y,z);
  pVox := pRGBA(vox.pixels+addr*4);
  if lightingMode in [lmAO] then begin
    pVox^.r := 200; pVox^.g := 200; pVox^.b := 200;
  end;
  pVox^ := pVox^*amb;
end;

procedure tVoxel.generateLighting(lightingMode: tLightingMode;defer: boolean=false);
begin
  lMode := lightingMode;
  lx := 0; ly := 0; lz := 0;
  if not defer then
    while lMode <> lmNone do updateLighting();
end;

// todo: remove this
(*
procedure tVoxel.loadP96FromFile(filename: string; height: integer);
var
  img: tPage;
  sdf: tPage;
  loadFilename: string;
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
  // is this a good idea?
  self.generateLighting(lmGradient, img);
  self.transferSDF(sdf);

  sdf.free();
end;
*)

{with lighting built it}
procedure tVoxel.loadVoxFromFile(filename: string; height: integer);
var
  img: tPage;
  loadFilename: string;
begin
  img := loadLC96(filename+'.vox');
  img.setTransparent(RGBA.create(255,255,255));
  note(format(' - voxel sprite is (%d, %d)', [img.width, img.height]));
  self.setPage(img, height);
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

function tVoxel.getAddr(x,y,z:int32): int32; inline; register;
begin
  result := x+((y+(z shl fLog2Height)) shl fLog2Width);
end;

function tVoxel.getVoxel(x,y,z:int32): RGBA; inline; register;
begin
  {todo: fast asm}
  result.r := 255; result.g := 0; result.b := 255; result.a := 255;
  if not inBounds(x,y,z) then exit;
  result := pRGBA(vox.pixels + getAddr(x,y,z)*4)^;
end;

{
Trace ray through object.
a bit slow for the moment.
coords are all 0..31
(0.5,0.5 is center of voxel)
dir should be normalized
}
function tVoxel.trace(pos: V3D; dir: V3D): tRayHit;
begin
  result := trace_asm(pos, dir);
end;

{not really asm, just fixed point... but will be asm}
function tVoxel.trace_asm(aPos: V3D; aDir: V3D): tRayHit;
var
  pos, dir, dirInv, prev, initialPos: V3D32;
  maxSteps: int32;
  maskW, maskH, maskD: word;
  distanceTraveled: int32;
  col: RGBA;
  d,s: int32;
  i: integer;
  tmp: int32;
  p: V3D;
  stepSize: integer;

  function autoStep(p,dInv,s: int32): int32; inline;
  begin

    if dInv > 0 then
      result := ((((1+s)*256)-(p and $ff)) * dInv) div 256
    else if dInv < 0 then
      result := (((-s*256)-(p and $ff)) * dInv) div 256
    else
      result := 99999;
  end;

  function safeInv(x: int32): int32;
  var
    f: single;
  begin
    if x = 0 then exit(0);
    result := round((1/(x/256)) * 256);
  end;

  procedure safeSet(var t: single; newT: single); inline;
  begin
    if newT <= 0 then exit;
    if newT < t then t := newT;
  end;

  {clip distance traveled to edge of cuboid}
  function clipDistance(t: single): single;
  begin
    {todo: calculate invADir as float, then round to get invDir}
    if dir.x > 0 then safeSet(t, (fWidth*256-initialPos.x) / dir.x)
    else if dir.x < 0 then safeSet(t, -initialPos.x / dir.x);
    if dir.y > 0 then safeSet(t, (fHeight*256-initialPos.y) / dir.y)
    else if dir.y < 0 then safeSet(t, -initialPos.y / dir.y);
    if dir.z > 0 then safeSet(t, (fWidth*256-initialPos.z) / dir.z)
    else if dir.z < 0 then safeSet(t, -initialPos.z / dir.z);
    result := t;
  end;

begin
  assert(abs(aDir.abs2-1.0) < 1e-6);
  maxSteps := ceil(fRadius)+1;

  maskW := $ffff-((fWidth*256)-1);
  maskH := $ffff-((fHeight*256)-1);
  maskD := $ffff-((fDepth*256)-1);

  pos := V3D32.Round(aPos * 256);
  initialPos := pos;
  dir := V3D32.Round(aDir * 256);
  dirInv.x := safeInv(dir.x);
  dirInv.y := safeInv(dir.y);
  dirInv.z := safeInv(dir.z);

  distanceTraveled := 0;

  result.didHit := false;
  result.col := RGBA.Clear;

  prev.x := -1;

  for i := 0 to maxSteps-1 do begin

    {check out of bounds}
    if ((pos.x and maskW) <> 0) or ((pos.y and maskH) <> 0) or ((pos.z and maskD) <> 0) then begin
      {clipping... this can be a bit slow...}
      result.d := clipDistance(distanceTraveled / 256);
      exit;
    end;

    {get voxel}
    col := pRGBA(vox.pixels +
      (
      (pos.x shr 8) +
      (pos.y shr 8 shl fLog2Width) +
      (pos.z shr 8 shl (fLog2Width + fLog2Height))
      ) shl 2
    )^;

    if col.a = 255 then begin
      result.didHit := true;
      result.col := col;
      result.d := distanceTraveled / 256;
      exit;
    end;

    d := (255-col.a) div 4;
    s := d-1;

    {figure out distance to travel to get to next cell}
    stepSize := autoStep(pos.x, dirInv.x, s);
    tmp := autoStep(pos.y, dirInv.y, s);
    if tmp < stepSize then stepSize := tmp;
    tmp := autoStep(pos.z, dirInv.z, s);
    if tmp < stepSize then stepSize := tmp;
    stepSize += 16; // move slightly into next cell

    prev := pos;

    pos.x += (dir.x * stepSize) div 256;
    pos.y += (dir.y * stepSize) div 256;
    pos.z += (dir.z * stepSize) div 256;

    {same voxel detection}
    {
    if (((prev.x shr 8) = (pos.x shr 8)) and
      ((prev.y shr 8) = (pos.y shr 8)) and
      ((prev.z shr 8) = (pos.z shr 8))) then begin
        result.didHit := true;
        result.col := RGB(255,0,0);
        exit;
    end;
    }

    distanceTraveled += stepSize;

  end;

  result.d := distanceTraveled / 256;
end;


function tVoxel.trace_ref(pos: V3D; dir: V3D): tRayHit;
var
  i: integer;
  maxSteps: integer;
  d: integer;
  c: RGBA;
  cur: V3D32;
  dirInv: V3D;
  stepSize: single;
  s: integer;

  {s here is the number of 'save' L1 moves}
  function autoStep(p,dInv: single; s: integer): single; inline;
  begin
    if dInv > 0 then result := ((1+s)-frac(p))*dInv else if dInv < 0 then result := ((-s)-frac(p))*dInv else result := 99.0;
  end;

  function isCloseToEdge(x: single): boolean;
  begin
    result := (frac(x) < 0.1) or (frac(x) > 0.9);
  end;

  function safeInv(x: single): single;
  begin
    if x = 0 then exit(0);
    result := 1/x;
  end;

begin
  {todo: make this asm...}
  assert(abs(dir.abs2-1.0) < 1e-6);
  maxSteps := ceil(fRadius)+1;

  dirInv.x := safeInv(dir.x);
  dirInv.y := safeInv(dir.y);
  dirInv.z := safeInv(dir.z);

  result.pos := pos;
  result.d := 0;
  result.col := RGBA.Clear;
  for i := 0 to maxSteps-1 do begin
    cur := V3D32.Floor(result.pos);
    if not inBounds(cur.x, cur.y, cur.z) then begin
      result.didHit := false;
      exit;
    end;

    c := getVoxel(cur.x, cur.y, cur.z);
    if c.a = 255 then begin
      result.didHit := true;
      result.col := c;
      exit;
    end;

    {ok, so here's how this works
    d is the safe 'distance', we define Dx to mean "L1 distance of x" where
      0-> this cell is solid
      1-> a D1 neighbour may be solid
      2-> no D1 neighbours are solid but D2 might be
      ...
    therefore for d=1 we can step to next cell, and for d=2 we can step twice
    }

    d := (255-c.a) div 4;
    s := d-1; {number of safe moves}

    {figure out distance to travel to get to next cell}
    stepSize := minf(
      autoStep(result.pos.x, dirInv.x, s),
      autoStep(result.pos.y, dirInv.y, s),
      autoStep(result.pos.z, dirInv.z, s)
    );
    stepSize += 0.001; // move slightly into next cell

    result.pos += dir * stepSize;
    result.d += stepSize;

    {make sure it worked...}
    {
    if not (isCloseToEdge(pos.x) or isCloseToEdge(pos.y) or isCloseToEdge(pos.z)) then begin
      note('%s -> %s step:%f.3', [(result.pos-dir*stepSize).toString, result.pos.toString, stepSize]);
    end;
    }
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
    x1,x2,clipDelta: integer;
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
    polyDraw.scanPoly(dc, p1.toPoint, p2.toPoint, p3.toPoint, p4.toPoint);
    polyBounds := polyDraw.bounds;
    if polyBounds.area <= 0 then exit;

    {alternative solid face render (for debugging)}
    if (keyDown(key_0)) then begin
      for y := polyBounds.top to polyBounds.bottom-1 do
        dc.hLine(Point(polyDraw.scanLine[y].xMin, y), polyDraw.scanLine[y].len, VX_FACE_COLOR[faceID]);
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
    if cpuInfo.hasMMX then
      traceProc := traceScanline_MMX
    else
      traceProc := traceScanline_ASM;

    if keyDown(key_f4) or keyDown(key_f5) or keyDown(key_f6) or keyDown(key_f7) then
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

      {apply x clipping}
      x1 := polyDraw.scanLine[y].xMin+dc.offset.x;
      x2 := polyDraw.scanLine[y].xMax+dc.offset.x;
      clipDelta := (dc.clip.left-x1);
      if clipDelta > 0 then begin
        x1 += clipDelta;
        pos += deltaX * clipDelta;
      end;

      clipDelta := (x2-dc.clip.right);
      if clipDelta > 0 then
        x2 -= clipDelta;

      traceProc(
        dc.page, self,
        x1, x2, y+dc.offset.y,
        pos, cameraDir, deltaX, deltaY
      );
    end;
  end;

begin

  if not assigned(self) then fatal('Tried to call draw on an assigned vox.');

  VX_TRACE_COUNT := 0;
  if scale = 0 then exit;

  {note:
    I make use of transpose to invert the rotation matrix, but
    this means I need to apply scale and translate later on
    which is a bit of a pain
  }

  {set up our matrices}
  model.setRotationXYZ(angle.x, angle.y, angle.z);
  if asShadow then
    model.scale(1,1,0);

  {ortho projection:}
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

{-----------------------------------------}

type
  tVoxelTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tVoxelTest.run();
var
  vox: tVoxel;
  pixelsCopy: tPage;
begin

  {make sure rotation is vauguely correct}
  vox := tVoxel.Create(4,4,4);
  makePageRandom(vox.vox);
  pixelsCopy := vox.vox.clone();
  vox.rotate();
  vox.rotate();
  vox.rotate();
  vox.rotate();
  assertEqual(vox.vox, pixelsCopy);

  vox.free;
  pixelsCopy.free;
end;

{--------------------------------------------------------}


initialization
  tVoxelTest.Create('Voxel');
finalization

end.
