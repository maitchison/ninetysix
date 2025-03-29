{---------------------------------------------------------}
{
 my original tracer
 speed: ...
 issues: misses corners
 sdf: optional
 steps_per_ray:
}
{---------------------------------------------------------}

function trace_old(vox: tVoxel; pos: V3D;dir: V3D): tRayHit;
var
  k: integer;
  c: RGBA;
  d: int32;
  x,y,z: int32;
  dx,dy,dz: int32;
  sx,sy,sz: int32;
  depth: int32;
  voxPtr: pointer;
begin

  sx := trunc(256*pos.x);
  sy := trunc(256*pos.y);
  sz := trunc(256*pos.z);

  depth := 0;
  dx := round(256*dir.x);
  dy := round(256*dir.y);
  dz := round(256*dir.z);

  {clamping sucks, but lets do it}
  {this is needed due either bugs in my tracer, or precision issues}
  sx := clamp(sx, 0, vox.width*256-1);
  sy := clamp(sy, 0, vox.height*256-1);
  sz := clamp(sz, 0, vox.depth*256-1);

  voxPtr := vox.vox.pData;

  result.d := 0;
  result.col := RGBA.Clear;
  result.didHit := false;

  for k := 0 to MAX_SAMPLES-1 do begin

    inc(VX_STEP_COUNT);
    inc(VX_LAST_STEP_COUNT);

    x := sx div 256;
    y := sy div 256;
    z := sz div 256;

    if (dword(x) >= vox.width) then begin
      if not VX_SHOW_TRACE_EXITS then exit;
      result.col := RGB(255,0,0);
      exit;
    end;
    if (dword(y) >= vox.height) then begin
      if not VX_SHOW_TRACE_EXITS then exit;
      result.col := RGB(0,255,0);
      exit;
    end;
    if (dword(z) >= vox.depth) then begin
      if not VX_SHOW_TRACE_EXITS then exit;
      result.col := RGB(0,0,255);
      exit;
    end;

    c := vox.getVoxel(x, y, z);

    if c.a = 255 then begin
      result.didHit := true;
      result.col := c;
      exit;
    end;

    if VX_USE_SDF then begin
      {move to next voxel}
      d := (255-c.a);
    end else begin
      d := 4;
    end;

    {d is distance * 4}
    sx := sx + ((dx * d) div 4);
    sy := sy + ((dy * d) div 4);
    sz := sz + ((dz * d) div 4);
    depth += d;
    result.d := d;
  end;

  {color used when we ran out of samples}
  result.col := RGB(255,0,255); {purple}
  result.didHit := false;

end;

{---------------------------------------------------------}
{
 besenham voxel tracing
 we work out which edge is closest and then traverse to that.
 we can take advantage of L1 SDF to safely skip over empty areas
 gets around 12k traces/second in a large world.
}
{---------------------------------------------------------}

function trace_bres(vox: tVoxel; pos: V3D; dir: V3D): tRayHit;
var
  pos32, dir32, dirInv32, prev32, initialPos32: V3D32;
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
    if dir32.x > 0 then safeSet(t, (vox.width*256-initialPos32.x) / dir32.x)
    else if dir32.x < 0 then safeSet(t, -initialPos32.x / dir.x);
    if dir32.y > 0 then safeSet(t, (vox.height*256-initialPos32.y) / dir32.y)
    else if dir32.y < 0 then safeSet(t, -initialPos32.y / dir.y);
    if dir32.z > 0 then safeSet(t, (vox.depth*256-initialPos32.z) / dir32.z)
    else if dir32.z < 0 then safeSet(t, -initialPos32.z / dir.z);
    result := t;
  end;

begin
  assert(abs(dir.abs2-1.0) < 1e-6);
  maxSteps := ceil(vox.radius);

  maskW := $ffff-((vox.width*256)-1);
  maskH := $ffff-((vox.height*256)-1);
  maskD := $ffff-((vox.depth*256)-1);

  pos32 := V3D32.Round(pos * 256);
  initialPos32 := pos32;
  dir32 := V3D32.Round(dir * 256);
  dirInv32.x := safeInv(dir32.x);
  dirInv32.y := safeInv(dir32.y);
  dirInv32.z := safeInv(dir32.z);

  distanceTraveled := 0;

  result.didHit := false;
  result.col := RGBA.Clear;

  prev32.x := -1;

  for i := 0 to maxSteps-1 do begin

    {check out of bounds}
    if ((pos32.x and maskW) <> 0) or ((pos32.y and maskH) <> 0) or ((pos32.z and maskD) <> 0) then begin
      {clipping... this can be a bit slow...}
      result.d := clipDistance(distanceTraveled / 256);
      exit;
    end;

    {get voxel}
    col := vox.vox.pixel^[
      (pos32.x shr 8) +
      (pos32.y shr 8 shl vox.fLog2Width) +
      (pos32.z shr 8 shl (vox.fLog2Width + vox.fLog2Height))
    ];

    if col.a = 255 then begin
      result.didHit := true;
      result.col := col;
      result.d := distanceTraveled / 256;
      exit;
    end;

    d := (255-col.a) div 4;
    s := d-1;

    {figure out distance to travel to get to next cell}
    stepSize := autoStep(pos32.x, dirInv32.x, s);
    tmp := autoStep(pos32.y, dirInv32.y, s);
    if tmp < stepSize then stepSize := tmp;
    tmp := autoStep(pos32.z, dirInv32.z, s);
    if tmp < stepSize then stepSize := tmp;
    stepSize += 16; // move slightly into next cell

    prev32 := pos32;

    pos32.x += (dir32.x * stepSize) div 256;
    pos32.y += (dir32.y * stepSize) div 256;
    pos32.z += (dir32.z * stepSize) div 256;

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

{---------------------------------------------------------}
{
 dda voxel tracing.
 we move in fixed step sizes based on the L1 SDF.
 typically minimum movement is 0.25 voxels.
 will miss corners of voxels sometimes
 gets around 18k traces/second in a large world.
}
{---------------------------------------------------------}

function trace_dda(vox: tVoxel;pos: V3D; dir: V3D): tRayHit;
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
  maxSteps := ceil(vox.fRadius);

  dirInv.x := safeInv(dir.x);
  dirInv.y := safeInv(dir.y);
  dirInv.z := safeInv(dir.z);

  result.pos := pos;
  result.d := 0;
  result.col := RGBA.Clear;
  for i := 0 to maxSteps-1 do begin
    cur := V3D32.Floor(result.pos);
    if not vox.inBounds(cur.x, cur.y, cur.z) then begin
      result.didHit := false;
      exit;
    end;

    c := vox.getVoxel(cur.x, cur.y, cur.z);
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

{---------------------------------------------------------}
{
this is based on the fast voxel tracing algorithm
it's unforuntaly not too fast.
we can optionally take advantage of SDF to skip areas, but it's a bit clunky
speed is
  5k normal
  10k with SDF skipping
}
{---------------------------------------------------------}

function trace_fast(vox: tVoxel; pos: V3D; dir: V3D): tRayHit;
var
  maxSteps: int32;
  col: RGBA;
  i: integer;
  s,d: integer;

  initialPos: V3D;
  dInv: V3D;
  x,y,z: integer;
  stepX,stepY,stepZ: integer;
  tDeltaX, tDeltaY, tDeltaZ: single;
  tMaxX, tMaxY, tMaxZ: single;
  oldT,newT: single;
  xJump,yJump,zJump: single;
  safeJump: single;
  bound: integer;
  edge: integer;

  function safeInv(x: single): single; inline;
  begin
    if x = 0 then exit(99999999);
    result := 1/x;
  end;

  function sign(x: single): integer; inline;
  begin
    result := 0;
    if x < 0 then exit(-1) else if x > 0 then exit(1);
  end;

  function fracs(x: single;s: integer): single; inline;
  begin
    if s > 0 then
      result := 1 - frac(x)
    else
      result := frac(x);
  end;

  function getVoxel(): RGBA; inline;
  begin
    result := vox.vox.pixel^[
      (x) +
      (y shl vox.fLog2Width) +
      (z shl (vox.fLog2Width + vox.fLog2Height))
    ];
  end;

  procedure init(); inline;
  begin
    {clamping is not be best strategy... but works for small errors}
    x := clamp(floor(pos.x), 0, vox.width-1);
    y := clamp(floor(pos.y), 0, vox.height-1);
    z := clamp(floor(pos.z), 0, vox.depth-1);
    tMaxX := fracs(pos.x, stepX) * tDeltaX;
    tMaxY := fracs(pos.y, stepY) * tDeltaY;
    tMaxZ := fracs(pos.z, stepZ) * tDeltaZ;
    oldT := 0;
  end;

  function autoStep(p, dInv: single; size: integer;limit: integer): single; inline;
  begin
    if dInv > 0 then begin
      edge := floor(p)+1+size;
      if edge > limit then edge := limit;
    end else if dInv < 0 then begin
      edge := floor(p)-size;
      if edge < 0 then edge := 0;
    end else
      exit(9999);
    //note('%.3f %.3f %d %d', [p,dInv,size,edge]);
    result := (edge - p) * dInv;
  end;

begin
  assert(abs(dir.abs2-1.0) < 1e-6);

  maxSteps := vox.width+vox.height+vox.depth;

  stepX := sign(dir.x);
  stepY := sign(dir.y);
  stepZ := sign(dir.z);

  dInv.x := safeInv(dir.x);
  dInv.y := safeInv(dir.y);
  dInv.z := safeInv(dir.z);
  tDeltaX := abs(dInv.x);
  tDeltaY := abs(dInv.y);
  tDeltaZ := abs(dInv.z);

  initialPos := pos;
  init();

  result.d := 0;
  result.didHit := false;
  result.col := RGBA.Clear;

  {check if we start inside a voxel}
  col := getVoxel();
  if col.a = 255 then begin
    result.didHit := true;
    result.col := col;
    exit();
  end;

  for i := 0 to maxSteps-1 do begin

    inc(VX_STEP_COUNT);
    inc(VX_LAST_STEP_COUNT);



    {this roughly doubles the speed}
    d := ((255-col.a) div 4);
    s := d-1;

    if s >= 2 then begin
      {perform a leap by intersecting a larger cube}
      pos := initialPos + (dir * result.d);
      if (pos.x < 0) or (pos.x >= vox.width) then exit;
      if (pos.y < 0) or (pos.y >= vox.height) then exit;
      if (pos.z < 0) or (pos.z >= vox.depth) then exit;
      xJump := autoStep(pos.x, dInv.x, s, vox.width);
      yJump := autoStep(pos.y, dInv.y, s, vox.height);
      zJump := autoStep(pos.z, dInv.z, s, vox.depth);
      safeJump := minf(xJump, yJump, zJump);
      result.d += safeJump + 0.01;
      pos := initialPos + (dir * result.d);
      if (pos.x < 0) or (pos.x >= vox.width) then exit;
      if (pos.y < 0) or (pos.y >= vox.height) then exit;
      if (pos.z < 0) or (pos.z >= vox.depth) then exit;
      {inline the init}
      x := trunc(pos.x);
      y := trunc(pos.y);
      z := trunc(pos.z);
      tMaxX := fracs(pos.x, stepX) * tDeltaX;
      tMaxY := fracs(pos.y, stepY) * tDeltaY;
      tMaxZ := fracs(pos.z, stepZ) * tDeltaZ;
      oldT := 0;
      col := getVoxel();
      continue;
    end;


    if tMaxX < tMaxY then begin
      if tMaxX < tMaxZ then begin
        newT:= tMaxX;
        x += stepX;
        tMaxX += tDeltaX;
        if dword(X) >= vox.width then exit;
      end else begin
        newT:= tMaxZ;
        z += stepZ;
        tMaxZ += tDeltaZ;
        if dword(Z) >= vox.depth then exit;
      end;
    end else begin
      if tMaxY < tMaxZ then begin
        newT:= tMaxY;
        y += stepY;
        tMaxY += tDeltaY;
        if dword(Y) >= vox.height then exit;
      end else begin
        newT:= tMaxZ;
        z += stepZ;
        tMaxZ += tDeltaZ;
        if dword(Z) >= vox.depth then exit;
      end;
    end;

    result.d += (newT - oldT);
    oldT := newT;

    {get voxel}
    col := getVoxel();

    if col.a = 255 then begin
      result.didHit := true;
      result.col := col;
      exit;
    end;

  end;
end;
