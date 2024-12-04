{unit for handling voxel drawing}
unit vox;

interface

uses
	utils,
  test,
  debug;

var
  {debugging stuff}
  TRACE_COUNT: int32 = 0;


{restrictions
X,Y,Z <= 256
X,Y powers of 2

Y*Z <= 32*1024 (could be chnaged to 64*1024 if needed)
}

type
	tVoxelSprite = class
  	fPage: tPage;
  	fLog2Width,fLog2Height: byte;
    fWidth,fHeight,fDepth: int16;
  public

    function create(page: tPage);
  	function getVoxel(x,y,z:int32): RGBA; forward;
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
  xMin := 639;
end;

procedure tScreenLine.adjust(x: int16); inline;
begin
	xMin := min(x, xMin);
  xMax := max(x, xMax);
end;

var
	screenLines: array[0..480-1] of tScreenLine;


{-----------------------------------------------------}
{ Signed distance calculations }
{-----------------------------------------------------}

function getDistance_L1(vox: tVoxelSprite; x,y,z: integer): integer;
var
	dx,dy,dz: integer;
  d, i: integer;
const
	MAX_D=16;	
begin
	if vox.getVoxel(x,y,z).a = 255 then exit(0);
  for d := 1 to MAX_D do
	  for dx := -d to d do	
  		for dy := -d to d do
    		for dz := -d to d do
      		if vox.getVoxel(x+dx, y+dy, z+dz).a = 255 then
        		exit(d);
  exit(MAX_D);
end;

function getDistance_L2(vox: tVoxelSprite; x,y,z: integer): single;
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
  d := trunc(vox.getDistance_L1(x,y,z) * sqrt(2) + 0.999);
  bestD2 := d*d;
	for dx := -d to d do	
		for dy := -d to d do
  		for dz := -d to d do
    		if vox.getVoxel(x+dx, y+dy, z+dz).a = 255 then begin
        	d2 := sqr(dx)+sqr(dy)+sqr(dz);
	        bestD2 := min(bestD2, d2);
  	    end;
  exit(sqrt(bestD2));
end;

{calculate SDF (the slow way) for voxel car.}
function generateSDF(): tPage;
var
	i,j,k: integer;
  minDst: integer;
  d: single;
  c: RGBA;
begin
	result := carSprite.page.clone();
  {todo: use proper L2 distance, not L1}
	{note: doing this as largest cubiod make a lot of sense, and it
   lets me trace super fast in many directions}
	{note, it would be nice to actually have negative for interior... but
  for now just closest is fine}
  for i := 0 to 64-1 do
  	for j := 0 to 32-1 do
    	for k := 0 to 18-1 do begin
      	d := getDistance_L2(i,j,k);
        c.init(trunc(d),trunc(d*4),trunc(d*16),255);
        result.setPixel(i,j+k*32, c);
      end;
end;

{store SDF on the alpha channel of the car image}
procedure transferSDF();
var
	x,y: integer;
  c: RGBA;
  d: byte;
  page: tPage;
begin
	page := carSprite.page;
  for y := 0 to page.height do
		for x := 0 to page.width do begin
    	d := carSDF.getPixel(x,y).g;
      c := page.getPixel(x,y);
      c.a := 255-d;
      page.setPixel(x,y,c);
    end;
end;

{-----------------------------------------------------}

constructor tVoxelSprite.create(page: tPage; height: int16);
begin
	fPage := page;
  fWidth := page.width;
  fHeight := height;
  fDepth := page.height div height;
  if not fWidth in [1,2,4,8,16,32,64,128,256] then
  	error(format('Invalid voxel width %d, must be power of 2, and <= 256', [fWidth]));
  if not fHeight in [1,2,4,8,16,32,64,128,256] then
  	error(format('Invalid voxel height %d, must be power of 2, and <= 256', [fHeight]));
  fLog2Width := round(log2(fWidth);
  fLog2Height := round(log2(fHeight);
end;

function tVoxelSprite.getVoxel(x,y,z:int32): RGBA;
begin
	{todo: fast asm}
	result.init(255,0,255,0);
	if (x < 0) or (x >= fWidth) then exit;
	if (y < 0) or (y >= fHeight) then exit;
	if (z < 0) or (z >= fDepth) then exit;
  result := carSprite.page.getPixel(x,y+z*fWidth);
end;

{-----------------------------------------------------}

begin
end.