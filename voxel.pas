program voxel;

uses
	crt,
	graph3d, vertex, screen;

{testing for raytracing voxel engine}

{todo:
[x] all faces
[x] hidden face removal
[ ] lazy lighting calculation
[x] procedual sky map
[ ] soft edges
}

type tStats = record
	traces: dword;
	steps: dword;
  retries: dword;
end;

var
	stats: tStats;

type
	tVoxel = record
  	diffuse: RGBA; // 4 bytes
    emissive: RGBA; // 4 bytes
    faceLighting: array[1..6] of RGBA; // 24 bytes
  end;

  pVoxel = ^tVoxel;

{v1 dense grid}
var
	levels: array[0..5] of array of array of array of byte;
	grid: array[0..31,0..31,0..31] of tVoxel;
  SAMPLES: integer = 16;

const
	faceDir: array[1..6] of V3D = (
  	(x:-1; y: 0; z: 0),
  	(x:+1; y: 0; z: 0),
  	(x: 0; y:-1; z: 0),
  	(x: 0; y:+1; z: 0),
  	(x: 0; y: 0; z:-1),
  	(x: 0; y: 0; z:+1)
  );

  faceCols: array[0..6] of RGBA = (
  	(r:255; g:0;   b:255; a: 255),
  	(r:255; g:0;   b:0;   a: 255),
  	(r:127; g:0;   b:0;   a: 255),
  	(r:0;   g:255; b:0;   a: 255),
  	(r:0;   g:127; b:0;   a: 255),
  	(r:0;   g:0;   b:255; a: 255),
  	(r:0;   g:0;   b:127; a: 255)
  );


{v2 sparse grid}
type
	tCell = record
  	voxel: tVoxel;
  	children: array[0..1, 0..1, 0..1] of ^tCell;
  end;


type
	tHitInfo = record
    face: integer;	{0 = miss}
  	loc: V3D;
  	voxel: pVoxel;

  end;

{write a voxel at given location}
procedure putVoxel(x, y, z: integer; voxel: tVoxel);
begin	
	grid[x, y, z] := voxel;
end;

{get cell in world space}
function getCell(pnt: V3D;l: byte): byte;
var
	s: integer;
  x,y,z: integer;
begin
	x := trunc(pnt.x);
	y := trunc(pnt.y);
	z := trunc(pnt.z);
  if (x < 0) or (x >= 32) then exit(255);
  if (y < 0) or (y >= 32) then exit(255);
  if (z < 0) or (z >= 32) then exit(255);  		
	result := levels[l][x shr l, y shr l, z shr l]
end;

{get voxel at location}
function getVoxel(x, y, z: integer): pVoxel;
begin
	if (x < 0) or (x >= 32) then exit(nil);
  if (y < 0) or (y >= 32) then exit(nil);
  if (z < 0) or (z >= 32) then exit(nil);
  result := @grid[x, y, z];
end;

{get voxel at location}
function getVoxel(pnt: V3D): pVoxel;
begin
	result := GetVoxel(trunc(pnt.x), trunc(pnt.y), trunc(pnt.z));
end;

function calcStep(x, inv: single): single; inline;
begin
	if (inv <= 0) then
  	result := frac(x) * -inv
  else
  	result := (1-frac(x)) * inv;
end;

function min(a,b: single): single; inline;
begin
	if a < b then exit(a) else exit(b);
end;

{trace ray through grid
Uses level of detail grids, but not yet sparse
}
function TraceV3(pnt: V3D; norm: V3D; level: integer): tHitInfo;
var
  i: integer;
  voxel: ^tVoxel;
  cellCode: integer;
  step, inv, fr: V3D;
  whichFace: integer;
  h: tHitInfo;
begin

  inv.X := 1 / (norm.X + 0.000001);
  inv.Y := 1 / (norm.Y + 0.000001);
  inv.Z := 1 / (norm.Z + 0.000001);

  result.face := 0;
  result.voxel := nil;

  for i := 0 to 63 do begin

    step.X := calcStep(pnt.x, inv.X);
    step.Y := calcStep(pnt.y, inv.Y);
    step.Z := calcStep(pnt.z, inv.Z);
    if (step.X <= step.Y) and (step.X <= step.Z) then begin
      if norm.X > 0 then whichFace := 1 else whichFace := 2;
      step.W := step.X;
    end else if (step.Y <= step.X) and (step.Y <= step.Z) then begin
      if norm.Y > 0 then whichFace := 3 else whichFace := 4;
      step.W := step.Y;
    end else begin
      if norm.Z > 0 then whichFace := 5 else whichFace := 6;
      step.W := step.Z;
    end;

    step.W := step.W + 0.0001;

    pnt := pnt + (norm * step.W);
    result.loc := pnt;

    stats.steps := stats.steps + 1;

    cellCode := getCell(pnt, level);

    {outside of valid region}
    if cellCode = 255 then exit;

    {nothing there so continue}
    if cellCode = 0 then continue;

    {if we are at base level then stop}
    if level = 0 then begin
	    voxel := GetVoxel(pnt);
      result.face := whichFace;
      result.voxel := voxel;
      exit();
    end;

    {trace through cell to see where we hit}
    h := TraceV3(pnt, norm, level-1)

  end;
end;


{trace ray through grid
Uses a step size that moves to next voxel boundary,
but still using L0
}
function TraceV2(pnt: V3D; norm: V3D): tHitInfo;
var
	i: integer;
  voxel: ^tVoxel;
  step, inv, fr: V3D;
	whichFace: integer;
begin

	inv.X := 1 / (norm.X + 0.000001);
	inv.Y := 1 / (norm.Y + 0.000001);
	inv.Z := 1 / (norm.Z + 0.000001);

	result.face := 0;
  result.voxel := nil;

	for i := 0 to 63 do begin

  	step.X := calcStep(pnt.x, inv.X);
  	step.Y := calcStep(pnt.y, inv.Y);
  	step.Z := calcStep(pnt.z, inv.Z);
    if (step.X <= step.Y) and (step.X <= step.Z) then begin
    	if norm.X > 0 then whichFace := 1 else whichFace := 2;
      step.W := step.X;
    end else if (step.Y <= step.X) and (step.Y <= step.Z) then begin
    	if norm.Y > 0 then whichFace := 3 else whichFace := 4;
      step.W := step.Y;
    end else begin
    	if norm.Z > 0 then whichFace := 5 else whichFace := 6;
      step.W := step.Z;
    end;

    step.W := step.W + 0.001;

    {look for alternates...}
    {if we nearly hit an alternative, and it is solid, but we are not
    then take that instead}
    {also... integer stepping would solve this properly}
    {todo}

  	pnt := pnt + (norm * step.W);
    result.loc := pnt;
    voxel := GetVoxel(pnt);
    stats.steps := stats.steps + 1;
    if (voxel = nil) then exit;
    if (voxel^.diffuse.a > 0) then begin
    	result.face := whichFace;
      result.voxel := voxel;
      exit;
    end;
  end;
end;


{Trace ray through grid.
Uses a fixed step size on L0, which is quite slow.
}
function TraceV1(pnt: V3D; norm: V3D): tHitInfo;
var
	i: integer;
  voxel: ^tVoxel;
  step: single;
  stepX, stepY, stepZ: single;
begin

	result.face := 0;

	{just a simple walk for the moment}
	for i := 0 to 127 do begin

    step := 0.1;
  	pnt := pnt + (norm * step);
    voxel := GetVoxel(pnt);
    stats.steps := stats.steps + 1;
    if (voxel = nil) then exit;
    if (voxel^.diffuse.a > 0) then begin
    	result.face := 1;
      result.loc := pnt;
      result.voxel := voxel;
      exit;
    end;
  end;
end;


{trace with a bit of error correction}
function Trace(pnt: V3D; norm: V3D): tHitInfo;
var
	notOk: boolean;
  i: integer;
begin
	stats.traces := stats.traces + 1;
	for i := 1 to 3 do begin
		result := TraceV3(pnt, norm, 1);
	  notOk := (result.face > 0) and (result.voxel <> nil) and (result.voxel^.faceLighting[result.face].a = 0);
    if not notOk then exit;
    stats.retries := stats.retries + 1;
    {apply jitter and try again}
		pnt.x := pnt.x + (Random()*0.01)-0.005;
    pnt.y := pnt.y + (Random()*0.01)-0.005;
    pnt.z := pnt.z + (Random()*0.01)-0.005;
  end;
end;


function SkyBox(dir: V3D): RGBA;
begin
	result.a := 255;
  result.r := 20;
  result.g := 20;
  result.b := 20;

  if dir.x > 0.8 then begin
  	result.r := 255;
    exit;
  end;

	if -dir.y > 0.8 then begin
  	result.g := 255;
    exit;
  end;


  if dir.z > 0.8 then begin
  	result.b := 255;
    exit;
  end;

  {stub}
  exit;


  if dir.y > 0 then exit;

	
  result.b := trunc(((-dir.y*0.8)+0.2) * 255);
  result.r := trunc(((-dir.y*1.0)) * 50);
  if -dir.y > 0.5 then begin
  	{sun}
	  result.r := 255;
	  result.g := 255;
	end;
end;


{calculate lighting at location and normal}
function Gather(pnt: V3D; norm: V3D): RGBA;
var
	i: integer;
  hit: tHitInfo;
  dir: V3D;
  dot: single;
  hitCol: RGBA;
  c, x: RGBA32;
  factor: single;
begin
	c.a := 1.0;
	for i := 1 to SAMPLES do begin
  	{todo: proper random hemisphere sampling}
    {todo: cosine angle and normal}
    dir.x := Random()-0.5;
    dir.y := Random()-0.5;
    dir.z := Random()-0.5;
    dir := dir.normed();
		dot := (dir.x * norm.x) + (dir.y * norm.y) + (dir.z * norm.z);

    if dot < 0 then dir := dir * -1;

    factor := abs(dot);

    {trace ray}
  	hit := Trace(pnt, dir);
    if hit.face = 0 then begin
    	hitCol := SkyBox(dir);

    end else begin
      hitCol := RGBA.create(0, 0, 0);
    end;
    {use carmack pi, as after rounding its more accurate.}
		c.r := c.r + hitCol.r * factor * 3.141592657;
		c.g := c.g + hitCol.g * factor * 3.141592657;
    c.b := c.b + hitCol.b * factor * 3.141592657;
  end;
  c.r := c.r / 255.0 / SAMPLES;
  c.g := c.g / 255.0 / SAMPLES;
  c.b := c.b / 255.0 / SAMPLES;

  result := c.toRGBA();

end;

procedure generateLighting(x, y, z, f: integer);
var
	p: V3D;
  pVox: PVoxel;
begin
	p.x := x+0.5;
  p.y := y+0.5;
  p.z := z+0.5;
  pVox := getVoxel(p);
  if pVox = nil then exit;
  if pVox^.diffuse.a = 0 then exit;
	if pVox^.faceLighting[f].a = 0 then exit;
  {stub: always regenerate...}
	{if pVox^.faceLighting[f].a = 255 then exit;}
  pVox^.faceLighting[f] := Gather(p + faceDir[f] * 0.51, faceDir[f]);
  pVox^.faceLighting[f].a := 255;
end;


procedure putPixel(x, y: int32; col:rgba);
var
    address: int32;
    ofs: int32;
begin

	if (x < 0) or (x >= 320) then exit;
	if (y < 0) or (y >= 200) then exit;

	ofs := x + (y * 320);

	asm
		push es
    mov edi, ofs
    mov ax, LFB
    mov es, ax

    xor eax, eax
    mov al, col.r
    shl eax, 8
    mov al, col.g
    shl eax, 8
    mov al, col.b

    mov es:[edi*4], eax
    pop es
  	end
end;




procedure Render();
var
	i, j: integer;
  c: RGBA32;
  hit: tHitInfo;
  p, norm, camera: V3D;
  h,w: integer;
  ac, dc, lc, ic: RGBA;
  tmpC: RGBA;
begin
  h := 32*1;
  w := 32*1;
	camera := V3D.create(16, 16, 100);
	for i := 0 to h-1 do begin
  	for j := 0 to w-1 do begin
      p := V3D.create((i+0.5)/h*32, (j+0.5)/w*32, 32.5);
      norm := (p - camera).Normed();
      hit := Trace(p, norm);

      if hit.face = 0 then begin
      	tmpC := SkyBox(norm);
      	c.r := tmpC.r/255;
        c.g := tmpC.g/255;
        c.b := tmpC.b/255;
      end else begin

      	generateLighting(
        	trunc(hit.loc.x),
        	trunc(hit.loc.y),
        	trunc(hit.loc.z),
          hit.face
        );

      	ic := hit.voxel^.emissive;
      	dc := hit.voxel^.diffuse;
        lc := hit.voxel^.faceLighting[hit.face];
        if lc.a = 0 then begin
	        c.r := (ic.r/255) + (dc.r/256);
    	    c.g := (ic.g/255) + (dc.g/256);
  	      c.b := (ic.b/255) + (dc.b/256);
          c.g := 0;
        end else begin
	        c.r := (ic.r/255) + ((dc.r * lc.r)/65536);
    	    c.g := (ic.g/255) + ((dc.g * lc.g)/65536);
  	      c.b := (ic.b/255) + ((dc.b * lc.b)/65536);
          c.r := lc.r/255;
          c.g := lc.g/255;
          c.b := lc.b/255;
        end;
      end;

      putPixel(i, j, c.toRGBA());

      if keypressed then exit;


    end;
  end;
end;


var
	i, j, k, f, s: integer;
  shade: integer;
  vox: tVoxel;
  pVox: pVoxel;
  p: V3D;

{remove and faces that are not visible}
procedure faceRemoval();
var
	x, y, z, f: integer;
  p: V3D;
  pOtherVox: pVoxel;
  pVox: pVoxel;
  isVisible: boolean;

begin
	for x := 0 to 31 do begin
  	for y := 0 to 31 do begin
    	for z := 0 to 31 do begin
	      p := V3D.create(x,y,z);
      	pVox := getVoxel(p);
      	for f := 1 to 6 do begin
         	pOtherVox := getVoxel(p + FaceDir[f]);
          pVox^.faceLighting[f].a := 0;
          if pVox^.diffuse.a = 0 then begin
          	{empty cell no lighting...}
            continue;
          end;
          if pOtherVox = nil then begin
	          pVox^.faceLighting[f].a := 254;
          	{boarders edge of world, so visible}
            continue;
          end;
          if (pOtherVox^.diffuse.a > 0) then begin
  					{face occluded}
            continue;
          end;
          { otherwise visibile}
          pVox^.faceLighting[f].a := 254;
        end;
      end;
    end;
  end;
end;

procedure MakeCube(x,y,z: integer; size: integer);
var
	i,j,k: integer;
begin
	for i := 0 to size-1 do
  	for j := 0 to size-1 do
    	for k := 0 to size-1 do
			  putVoxel(x+i-size div 2, y+j-size div 2 , z+k - size div 2, vox);      	
end;


procedure makeLevels();
var
	size: integer;
  scale: integer;
  i,j,k,l: integer;
  u,v,w: integer;
  children: integer;
begin
	size := 32;
	for l := 0 to 5 do begin
  	setLength(levels[l], size, size, size);
    for i := 0 to size-1 do
    	for j := 0 to size-1 do
	      for k := 0 to size-1 do begin
        	if l = 0 then
          	if grid[i,j,k].diffuse.a > 0 then
	            levels[l][i,j,k] := 1
            else
            	levels[l][i,j,k] := 0
          else begin
          	children := 0;
            for u := 0 to 1 do
            	for v := 0 to 1 do
              	for w := 0 to 1 do
			            if levels[l-1][i div 2 + u, j div 2 + v, k div 2 + w] > 0 then
                  	children := children + 1;
            levels[l][i,j,k] := children
          end;
        end;
    size := size div 2;
  end;
end;

begin

	Randomize();


  {'lights'}
  for i := 0 to 31 do begin
  	for j := 0 to 31 do begin
      if random > 0.05 then continue;
      vox.diffuse := RGBA.create(0, 0, 0, 255);
      vox.emissive := vox.diffuse;
      putVoxel(i, 30, j, vox);
    end;
  end;

  {floor}
  for i := 0 to 31 do begin
  	for j := 0 to 31 do begin
    	if (i+j) mod 2 = 0 then
      	shade := -10
      else
      	shade := 10;
      shade := 0;
			vox.diffuse := RGBA.create(200+shade, 200+shade, 200+shade);
      vox.emissive := RGBA.create(0, 0, 0);
      putVoxel(i, 31 , j, vox);
    end;

  end;

  {wall}
  for i := 0 to 31 do begin
    for j := 0 to 31 do begin
      vox.diffuse := RGBA.create(200, 200, 250);
      vox.emissive := RGBA.create(0, 0, 0);
      putVoxel(0, i , j, vox);
      putVoxel(j, i , 0, vox);
    end;
  end;


  vox.diffuse := RGBA.create(100, 100, 100);
  MakeCube(8, 8, 25, 8);
  MakeCube(24, 8, 25, 8);
  MakeCube(24, 24, 25, 8);
  MakeCube(8, 24, 25, 8);

	init_320x240x32();

  samples := 32;

  {generate lighting}
	faceRemoval();
  makeLevels();

  render();
	
  {Readkey();}
  asm
  	mov ax,03
    int $10
    end;
  writeln('steps   ', stats.steps);
	writeln('retries ', stats.retries);
  writeln('traces  ', stats.traces);
  writeln('steps per trace  ', stats.steps div (stats.traces+1));

end.
