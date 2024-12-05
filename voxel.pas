{unit for handling voxel drawing}
unit voxel;

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
  VX_GHOST_MODE: boolean = false;


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
  	function getVoxel(x,y,z:int32): RGBA;
		procedure draw(canvas: tPage;atX, atY: int16; zAngle: single=0; pitch: single=0; roll: single=0; scale: single=1);
  end;

implementation


{----------------------------------------------------}
{ Poly drawing }
{----------------------------------------------------}

type
	tScreenPoint = record
  	x,y: int16;
  end;

  tScreenLine = record
  	xMin, xMax: int16;
    procedure reset();
    procedure adjust(x: int16);
  end;

procedure tScreenLine.reset(); inline;
begin
	xMax := 0;
  xMin := screen.width;
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
  d, i: integer;
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
  i,d: integer;
 	d2: single;
  bestD2: single;
  max_d: integer;
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
	i,j,k: integer;
  minDst: integer;
  d: single;
  c: RGBA;
begin
  result := vox.clone();
  {todo: use proper L2 distance, not L1}
	{note: doing this as largest cubiod make a lot of sense, and it
   lets me trace super fast in many directions}
	{note, it would be nice to actually have negative for interior... but
  for now just closest is fine}
  for i := 0 to fWidth-1 do
  	for j := 0 to fHeight-1 do
    	for k := 0 to fDepth-1 do begin
      	d := getDistance_L2(i,j,k);
        c.init(trunc(d),trunc(d*4),trunc(d*16),255);
        result.setPixel(i,j+k*32, c);
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


function tVoxelSprite.getVoxel(x,y,z:int32): RGBA;
begin
	{todo: fast asm}
	result.init(255,0,255,0);
	if (x < 0) or (x >= fWidth) then exit;
	if (y < 0) or (y >= fHeight) then exit;
	if (z < 0) or (z >= fDepth) then exit;
  result := vox.getPixel(x,y+z*fWidth);
end;

{draw voxel sprite.}
procedure tVoxelSprite.draw(canvas: tPage;atX, atY: int16; zAngle: single=0; pitch: single=0; roll: single=0; scale: single=1);
var
  size: V3D; {half size of cuboid}
  debugCol: RGBA;
var
	cameraX: V3D;
	cameraY: V3D;
  cameraZ: V3D;
  objToWorld: tMatrix3X3;
  worldToObj: tMatrix3X3;
  lastTraceCount: int32;

var
	faceColor: array[1..6] of RGBA;

{trace ray at location and direction (in object space)}
function trace(pos: V3D;dir: V3D): RGBA;
var
	k: integer;
  c: RGBA;
  d: int32;
  x,y,z: int32;
  dx,dy,dz: int32;
  sx,sy,sz: int32;
	depth: int32;
  voxPtr: pointer;
const
  MAX_SAMPLES = 64;
begin

  lastTraceCount := 0;

	{color used when initial sample is out of of bounds}
  {this shouldn't happen, but might due to rounding error or bug}	
  result.init(255,0,0,255);

  {center}
  {todo: make sender do this for us}
  pos += V3D.create(32,16,9);

  {sometimes initial point is slightly outside. this is due to a bug
   where we trace edges with the suboptimal face projection.
   For the moment I'll just step ahead when this happens}

  sx := trunc(256*pos.x);
	sy := trunc(256*pos.y);
	sz := trunc(256*pos.z);

	result.init(255,0,255,0); {color used when out of bounds}

  depth := 0;
  dx := round(256*dir.x);
  dy := round(256*dir.y);
  dz := round(256*dir.z);

  voxPtr := vox.pixels;

	for k := 0 to MAX_SAMPLES-1 do begin

  	inc(VX_TRACE_COUNT);
    inc(lastTraceCount);

		x := sx div 256;
	  y := sy div 256;
  	z := sz div 256;

		if (x < 0) or (x >= 64) then begin
    	if not VX_SHOW_TRACE_EXITS then exit;
      exit(RGBA.create(255,0,0));
    end;
		if (y < 0) or (y >= 32) then begin
    	if not VX_SHOW_TRACE_EXITS then exit;
    	exit(RGBA.create(0,255,0));
    end;
		if (z < 0) or (z >= 18) then begin
    	if not VX_SHOW_TRACE_EXITS then exit;
    	exit(RGBA.create(0,0,255));
    end;

    asm
    	push edi
      push edx
      push eax

    	mov edi, voxPtr
      xor edx, edx
      or dl, byte ptr [z]
      shl edx, 5
      or dl, byte ptr [y]
      shl edx, 6
      or dl, byte ptr [x]
      mov eax, [edi+edx*4]
      mov [c],eax

      pop eax
      pop edx
      pop edi

    end;

    if c.a = 255 then begin
    	{shade by distance from bounding box}
      c *= (255-(depth*2))/255;
    	exit(c)
    end else begin
    	{move to next voxel}
      d := (255-c.a);
      {d is distance * 4}
      sx := sx + ((dx * d) div 4);
      sy := sy + ((dy * d) div 4);
      sz := sz + ((dz * d) div 4);

      depth += d;
    end;
  end;

  {color used when we ran out of samples}
  result.init(255,0,255,255); {purple}

end;

{traces all pixels within the given polygon.
points are in world space
}
procedure traceFace(faceID: byte; p1,p2,p3,p4: V3D);
var
	c: RGBA;
  cross: single;
  y, yMin, yMax: int32;
  s1,s2,s3,s4: tScreenPoint;

function toScreen(p: V3D): tScreenPoint;
begin
	result.x := atX + trunc(p.x);
	result.y := atY + trunc(p.y);
end;

procedure scanSide(a, b: tScreenPoint);
var
	tmp: tScreenPoint;
  y: int32;
  x: single;
  deltaX: single;
begin
	if a.y = b.y then begin
  	{special case}
    y := a.y;
    screenLines[y].adjust(a.x);
    screenLines[y].adjust(b.x);
    exit;
  end;

  if a.y > b.y then begin
  	tmp := a; a := b; b := tmp;
  end;

  {I think this is off by 1}
  x := a.x;
  deltaX := (b.x-a.x) / (b.y-a.y);
  for y := a.y to b.y do begin
    screenLines[y].adjust(trunc(x));
    x += deltaX;
  end;
end;

var
	x: int32;
  worldPos: V3D;
  t: single;
  pos, basePos, deltaX, deltaY: V3D;
  tDelta: single;
  aZ, invZ: single;
  value: integer;
  c1,c2,c3,c4: RGBA;

begin
	{do not render back face}
	cross := ((p2.x-p1.x) * (p3.y - p1.y)) - ((p2.y - p1.y) * (p3.x - p1.x));
  if cross <= 0 then exit;

  s1 := toScreen(p1);
  s2 := toScreen(p2);
  s3 := toScreen(p3);
  s4 := toScreen(p4);

  yMin := min(s1.y,s2.y);
  yMin := min(yMin,s3.y);
  yMin := min(yMin,s4.y);

  yMax := max(s1.y,s2.y);
  yMax := max(yMax,s3.y);
  yMax := max(yMax,s4.y);

  {debuging, show corners}
  {
	c.init(255,0,255);
	canvas.putPixel(s1.x, s1.y, c);
	canvas.putPixel(s2.x, s2.y, c);
	canvas.putPixel(s3.x, s3.y, c);
	canvas.putPixel(s4.x, s4.y, c);
	}

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

  case faceID of
  	1: aZ := cameraZ.z;
  	2: aZ := cameraZ.z;
  	3: aZ := cameraZ.x;
  	4: aZ := cameraZ.x;
  	5: aZ := cameraZ.y;
  	6: aZ := cameraZ.y;
  end;
  if aZ = 0 then exit; {should not happen?}
  invZ := 1/aZ;

  {calculate our deltas}
	case faceID of
  	1: tDelta := -cameraX.z * invZ;
    2: tDelta := -cameraX.z * invZ;
    3: tDelta := -cameraX.x * invZ;
    4: tDelta := -cameraX.x * invZ;
    5: tDelta := -cameraX.y * invZ;
    6: tDelta := -cameraX.y * invZ;
  end;
  deltaX := cameraX + cameraZ*tDelta;

	for y := yMin to yMax do begin

    pos := (cameraX*(screenLines[y].xMin-atX))+(cameraY*(y-atY));

    case faceID of
    	1: t := (-size.z-pos.z) * invZ;
      2: t := (+size.z-pos.z) * invZ;
      3: t := (-size.x-pos.x) * invZ;
      4: t := (+size.x-pos.x) * invZ;
      5: t := (-size.y-pos.y) * invZ;
      6: t := (+size.y-pos.y) * invZ;
      else t := 0;
    end;

    pos += cameraZ * (t+0.5); {start half way in a voxel}

  	for x := screenLines[y].xMin to screenLines[y].xMax do begin

     	c := trace(pos, cameraZ);
      {show trace count}
      if VX_GHOST_MODE then
     		c.init(lastTraceCount,lastTraceCount*4, lastTraceCount*16);

      {AA}
      {
      c1 := trace(pos+cameraX*0.25+cameraY*0.25, cameraZ);
      c2 := trace(pos-cameraX*0.25+cameraY*0.25, cameraZ);
      c3 := trace(pos-cameraX*0.25-cameraY*0.25, cameraZ);
      c4 := trace(pos+cameraX*0.25-cameraY*0.25, cameraZ);
      c := c*0.2+c1*0.2+c2*0.2+c3*0.2+c4*0.2;
      }

      pos += deltaX;
    	if c.a > 0 then
	      canvas.putPixel(x,y, c);
    end;
  end;

end;


var
	i,j: integer;
  c: RGBA;

  p1,p2,p3,p4,p5,p6,p7,p8: V3D; {world space}

  isometricTransform : tMatrix3x3;


begin

	VX_TRACE_COUNT := 0;
  if scale = 0 then exit;

  faceColor[1].init(255,0,0); 	
  faceColor[2].init(128,0,0);
  faceColor[3].init(0,255,0); 		
  faceColor[4].init(0,128,0); 	
  faceColor[5].init(0,0,255); 	
  faceColor[6].init(0,0,128);

  isometricTransform.rotationX(-0.955);
  objToWorld.rotationXYZ(roll, 0, zAngle);

  objToWorld := objToWorld.MM(isometricTransform);
	{transpose is inverse (for unitary)}
  worldToObj := objToWorld.transposed();



  objToWorld.applyScale(scale);
  worldToObj.applyScale(1/scale);

	cameraX := worldToObj.apply(V3D.create(1,0,0));
  cameraY := worldToObj.apply(V3D.create(0,1,0));
  cameraZ := worldToObj.apply(V3D.create(0,0,1)).normed();

  {get cube corners}
  {note: we apply cropping here, actual half size is 32x16x9}
  size := V3D.create(32,13,9);
  {object space -> world space}
  p1 := objToWorld.apply(V3D.create(-size.x, -size.y, -size.z));
  p2 := objToWorld.apply(V3D.create(+size.x, -size.y, -size.z));
  p3 := objToWorld.apply(V3D.create(+size.x, +size.y, -size.z));
  p4 := objToWorld.apply(V3D.create(-size.x, +size.y, -size.z));
  p5 := objToWorld.apply(V3D.create(-size.x, -size.y, +size.z));
  p6 := objToWorld.apply(V3D.create(+size.x, -size.y, +size.z));
  p7 := objToWorld.apply(V3D.create(+size.x, +size.y, +size.z));
  p8 := objToWorld.apply(V3D.create(-size.x, +size.y, +size.z));

  {trace each side of the cubeoid}
  traceFace(1, p1, p2, p3, p4);
  traceFace(2, p8, p7, p6, p5);
  traceFace(3, p4, p8, p5, p1);
  traceFace(4, p2, p6, p7, p3);
	traceFace(5, p5, p6, p2, p1);
  traceFace(6, p4, p3, p7, p8);
	
end;


{-----------------------------------------------------}

procedure runTests();
begin
end;

begin
	runTests();
end.
