function safeInv(x: single): single; inline;
begin
  if x = 0 then exit(99999999);
  result := 1/x;
end;

procedure safeSet(var t: single; newT: single); inline;
begin
  if newT <= 0 then exit;
  if newT < t then t := newT;
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

function getVoxel(vox: tVoxel; x,y,z: integer): RGBA; inline;
begin
  result := pRGBA(
    vox.vox.pData + (((((z shl vox.fLog2Height) + y) shl vox.fLog2Width) + x) shl 2)
  )^;
end;

function autoStep(p,dInv,s: int32): int32; inline;
begin
  if dInv > 0 then
    result := ((((1+s)*256)-(p and $ff)) * dInv) div 256
  else if dInv < 0 then
    result := (((-s*256)-(p and $ff)) * dInv) div 256
  else
    result := 99999;
end;

(*
{this is no faster...}
function autoStep(p,dInv,s: int32): int32; assembler; inline;
asm
  cmp edx, 0
  je @ISZERO
  jg @ISPOS

@ISNEG:
  neg ecx
  shl ecx,8
  and eax,$ff
  sub ecx,eax
  mov eax,ecx
  imul edx
  shrd eax, edx, 8
  sar edx, 8
  jmp @DONE

@ISPOS:
  inc ecx
  shl ecx,8
  and eax, $ff
  sub ecx, eax
  mov eax, ecx
  imul edx
  shrd eax, edx, 8
  sar edx, 8
  jmp @DONE
@ISZERO:
  mov eax, 99999
@DONE:
end;
*)

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
end;

{-------------------------------------------------------------}
{
  simple fixed-point DDA tracing
  has some precision issuese but can be quite fast.
}

function trace_dda(vox: tVoxel; pos: V3D;dir: V3D): tRayHit;
var
  k: integer;
  c: RGBA;
  d: int32;
  x,y,z: int32;
  dx,dy,dz: int32;
  sx,sy,sz: int32;
  voxPtr: pointer;
  maxSamples: integer;

  {clip distance traveled to edge of cuboid}
  function clipDistanceF(t: single): single;
  begin
    {todo: calculate invADir as float, then round to get invDir}
    if dir.x > 0 then safeSet(t, (vox.width-pos.x) / dir.x)
    else if dir.x < 0 then safeSet(t, -pos.x / dir.x);
    if dir.y > 0 then safeSet(t, (vox.height-pos.y) / dir.y)
    else if dir.y < 0 then safeSet(t, -pos.y / dir.y);
    if dir.z > 0 then safeSet(t, (vox.depth-pos.z) / dir.z)
    else if dir.z < 0 then safeSet(t, -pos.z / dir.z);
    result := t;
  end;

begin

  sx := trunc(256*pos.x);
  sy := trunc(256*pos.y);
  sz := trunc(256*pos.z);

  c := getVoxel(vox, sx div 256, sy div 256, sz div 256);
  if c.a = 255 then begin
    result.d := 0;
    result.col := c;
    exit;
  end;

  dx := round(256*dir.x);
  dy := round(256*dir.y);
  dz := round(256*dir.z);

  {clamping sucks, but lets do it}
  {this is needed due either bugs in my tracer, or precision issues}
  sx := clamp(sx, 0, vox.width*256-1);
  sy := clamp(sy, 0, vox.height*256-1);
  sz := clamp(sz, 0, vox.depth*256-1);

  voxPtr := vox.vox.pData;

  maxSamples := ceil(vox.fRadius);

  result.d := 0;
  result.col := RGBA.Clear;

  for k := 0 to maxSamples-1 do begin

    inc(VX_STEP_COUNT);
    inc(VX_LAST_STEP_COUNT);

    x := sx div 256;
    y := sy div 256;
    z := sz div 256;

    if (dword(x) >= vox.width) then begin
      result.d := clipDistanceF(result.d);
      exit;
    end;
    if (dword(y) >= vox.height) then begin
      result.d := clipDistanceF(result.d);
      exit;
    end;
    if (dword(z) >= vox.depth) then begin
      result.d := clipDistanceF(result.d);
      exit;
    end;

    c := getVoxel(vox, x, y, z);

    if c.a = 255 then begin
      result.col := c;
      exit;
    end;

    d := (255-c.a)-2;

    {d is distance * 4}
    sx := sx + ((dx * d) div 4);
    sy := sy + ((dy * d) div 4);
    sz := sz + ((dz * d) div 4);
    result.d += (d/4);
  end;

  {color used when we ran out of samples}
  result.col := RGB(255,0,255); {purple}
end;


{-------------------------------------------------------------}
{
  simple fixed-point DDA tracing
  mmx optimized version
  has some precision issuese but can be quite fast.
  will probably use this for lighting
}

function trace_dda_mmx(vox: tVoxel; pos: V3D;dir: V3D): tRayHit;
var
  k: integer;
  c: RGBA;
  d: int32;
  x,y,z: int32;
  delta: V3D16;
  scaledPos: V3D16;
  voxPtr: pointer;
  maxSamples: integer;
  clipMask32: dword;
  res_d4: integer;
  res_didHit: byte;
  res_col: RGBA;

  {clip distance traveled to edge of cuboid}
  function clipDistanceF(t: single): single;
  begin

    {todo: calculate invADir as float, then round to get invDir}
    if dir.x > 0 then safeSet(t, (vox.width-pos.x) / dir.x)
    else if dir.x < 0 then safeSet(t, -pos.x / dir.x);

    if dir.y > 0 then safeSet(t, (vox.height-pos.y) / dir.y)
    else if dir.y < 0 then safeSet(t, -pos.y / dir.y);

    if dir.z > 0 then safeSet(t, (vox.depth-pos.z) / dir.z)
    else if dir.z < 0 then safeSet(t, -pos.z / dir.z);

    result := t;
  end;

begin

  {easy to remove this requirement}
  assert(vox.width = 16);
  assert(vox.height = 16);
  assert(vox.depth = 16);

  {todo: this could be faster...}
  scaledPos.x := trunc(256*pos.x);
  scaledPos.y := trunc(256*pos.y);
  scaledPos.z := trunc(256*pos.z);

  {clamping sucks, but lets do it}
  {this is needed due either bugs in my tracer, or precision issues}
  scaledPos.x := clamp(scaledPos.x, 0, vox.width*256-1);
  scaledPos.y := clamp(scaledPos.y, 0, vox.height*256-1);
  scaledPos.z := clamp(scaledPos.z, 0, vox.depth*256-1);
  scaledPos.w := 0;

  c := getVoxel(vox, scaledPos.x div 256, scaledPos.y div 256, scaledPos.z div 256);
  if c.a = 255 then begin
    result.d := 0;
    result.col := c;
    exit;
  end;

  delta.x := round(256*dir.x);
  delta.y := round(256*dir.y);
  delta.z := round(256*dir.z);
  delta.w := 0;

  {stub: locked to size 16 for the moment}
  clipMask32 := $f0f0f0f0;

  voxPtr := vox.vox.pData;

  maxSamples := ceil(vox.fRadius);

  result.d := 0;
  result.col := RGBA.Clear;
  res_d4 := 0;
  res_didHit := 0;
  asm

    pushad

    mov ecx, maxSamples
    mov edi, voxPtr
    mov ebx, clipMask32

    {mm0 <- 0}
    pxor mm0,mm0
    {mm1 <- scaledPos}
    movq mm1, scaledPos
    {mm2 <- delta}
    movq mm2, delta

  @PIXELLOOP:

    inc VX_STEP_COUNT
    inc VX_LAST_STEP_COUNT

    {bounds check}
    movq  mm5, mm1
    psrlw mm5, 8
    packuswb mm5, mm5
    movd  eax, mm5    // eax=0xyz
    mov   edx, eax
    and   edx, ebx
    jnz  @OUTOFBOUNDS

    {sample}
    push ebx
    mov ebx, eax          // ax = yz
    shr ebx, 16           // bx = 0x

    mov cx, 4+(4*256)
    xor edx, edx
    or dl, bl
    shl edx, cl
    shr cx, 8
    or dl, ah
    shl edx, cl
    or dl, al
    pop ebx

    mov eax, [edi+edx*4]

    {check for hit}
    cmp eax, $ff000000
    jae @HIT

  @MOVE:
    shr eax, 24
    not al
    sub al, 2   // half steps
    add res_d4, eax

    mov dx, ax
    shl eax, 16
    mov ax, dx            // eax = 0d|0d
    movd      mm6, eax    // 00|00|0d|0d
    punpckldq mm6, mm6    // 0d|0d|0d|0d
    movq      mm5, mm2
    pmullw    mm5, mm6    // v *= d
    psraw     mm5, 2
    paddsw    mm1, mm5    // p += v * (d/4)

    dec ecx
    jnz @PIXELLOOP

    jmp @DONE

  @HIT:
    mov res_col, eax
    mov res_didHit, 1
    jmp @DONE

  @OUTOFBOUNDS:
    mov res_didHit, 2
    jmp @DONE

  @DONE:
    popad
    emms
  end;

  result.col := res_col;
  result.d := res_d4/4;
  {this is a bit weird...}
  case res_didHit of
    0: result.col.a := 0;
    1: result.col.a := 255;
    2: begin
      result.col.a := 0;
      result.d := clipDistanceF(result.d);
    end;
  end;
end;

{---------------------------------------------------------}
{
 besenham style voxel tracing
 we work out which edge is closest and then traverse to that.
 we can take advantage of L1 SDF to safely skip over empty areas
 gets around 12k traces/second in a large world.
}
{---------------------------------------------------------}

function trace_auto(vox: tVoxel; pos: V3D; dir: V3D): tRayHit;
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

  function safeInv(x: int32): int32;
  var
    f: single;
  begin
    if x = 0 then exit(0);
    result := round((1/(x/256)) * 256);
  end;

  {clip distance traveled to edge of cuboid}
  function clipDistanceF(t: single): single;
  begin
    {todo: calculate invADir as float, then round to get invDir}
    if dir.x > 0 then safeSet(t, (vox.width-pos.x) / dir.x)
    else if dir.x < 0 then safeSet(t, -pos.x / dir.x);
    if dir.y > 0 then safeSet(t, (vox.height-pos.y) / dir.y)
    else if dir.y < 0 then safeSet(t, -pos.y / dir.y);
    if dir.z > 0 then safeSet(t, (vox.depth-pos.z) / dir.z)
    else if dir.z < 0 then safeSet(t, -pos.z / dir.z);
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

  result.d := 0;
  result.col := RGBA.Clear;

  prev32.x := -1;

  for i := 0 to maxSteps-1 do begin

    inc(VX_STEP_COUNT);
    inc(VX_LAST_STEP_COUNT);

    {check out of bounds}
    if ((pos32.x and maskW) <> 0) or ((pos32.y and maskH) <> 0) or ((pos32.z and maskD) <> 0) then begin
      {clipping... this can be a bit slow...}
      result.d := clipDistanceF(distanceTraveled / 256);
      exit;
    end;

    {get voxel}
    col := vox.vox.pixel^[
      (pos32.x shr 8) +
      (pos32.y shr 8 shl vox.fLog2Width) +
      (pos32.z shr 8 shl (vox.fLog2Width + vox.fLog2Height))
    ];

    if col.a = 255 then begin
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

    distanceTraveled += stepSize;
  end;
  result.d := distanceTraveled / 256;
end;

{---------------------------------------------------------}
{
this is based on the fast voxel tracing algorithm
it's unforuntaly not too fast.
we can optionally take advantage of SDF to skip areas, but it's a bit clunky
speed is
  10k normal
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
    result := (edge - p) * dInv;
  end;

const
  {minimum safe skip size before we start using the skipping system.
   this involves resetting the trace from a new position, which is slow
   so only use it for largeish skips
   set to 0 to disable.
   }
  {unfortunately this does not help}
  MIN_SKIP_SIZE = 0;

begin
  assert(abs(dir.abs2-1.0) < 1e-6);

  {clamping is not be best strategy... but works for small errors}
  x := clamp(floor(pos.x), 0, vox.width-1);
  y := clamp(floor(pos.y), 0, vox.height-1);
  z := clamp(floor(pos.z), 0, vox.depth-1);

  {check if we start inside a voxel}
  col := getVoxel(vox, x,y,z);
  if col.a = 255 then begin
    result.col := col;
    exit();
  end;

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

  tMaxX := fracs(pos.x, stepX) * tDeltaX;
  tMaxY := fracs(pos.y, stepY) * tDeltaY;
  tMaxZ := fracs(pos.z, stepZ) * tDeltaZ;
  oldT := 0;

  result.d := 0;
  result.col := RGBA.Clear;

  for i := 0 to maxSteps-1 do begin

    inc(VX_STEP_COUNT);
    inc(VX_LAST_STEP_COUNT);

    if MIN_SKIP_SIZE > 0 then begin
      d := ((255-col.a) div 4);
      s := d-1;

      if s >= MIN_SKIP_SIZE then begin
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
        col := getVoxel(vox, x,y,z);
        continue;
      end;
    end;

    if tMaxX < tMaxY then begin
      if tMaxX < tMaxZ then begin
        newT:= tMaxX;
        x += stepX;
        tMaxX += tDeltaX;
        result.d += (newT - oldT);
        if dword(X) >= vox.width then exit;
      end else begin
        newT:= tMaxZ;
        z += stepZ;
        tMaxZ += tDeltaZ;
        result.d += (newT - oldT);
        if dword(Z) >= vox.depth then exit;
      end;
    end else begin
      if tMaxY < tMaxZ then begin
        newT:= tMaxY;
        y += stepY;
        tMaxY += tDeltaY;
        result.d += (newT - oldT);
        if dword(Y) >= vox.height then exit;
      end else begin
        newT:= tMaxZ;
        z += stepZ;
        tMaxZ += tDeltaZ;
        result.d += (newT - oldT);
        if dword(Z) >= vox.depth then exit;
      end;
    end;

    oldT := newT;

    {get voxel}
    col := vox.vox.pixel^[(x) + (y shl vox.fLog2Width) + (z shl (vox.fLog2Width + vox.fLog2Height))];

    if col.a = 255 then begin
      result.col := col;
      exit;
    end;

  end;
end;


{---------------------------------------------------------}
{
  fixed point bresenham
  this is the same speed as the non-asm one.
  tps: 6.0
  spt: 5.3
}
{---------------------------------------------------------}

function trace_fast_asm(vox: tVoxel; pos: V3D; dir: V3D): tRayHit;
var
  x,y,z: integer;
  voxPtr: pointer;
  maxSteps: int32;
  stepX,stepY,stepZ: integer;
  tDeltaX32, tDeltaY32, tDeltaZ32: integer;
  tMaxX32, tMaxY32, tMaxZ32: integer;
  oldT32,newT32: integer;
  col: RGBA;
  invDir: V3D;

  res_d32: integer;
  res_col: RGBA;
  res_didhit: boolean;

begin

  assert(abs(dir.abs2-1.0) < 1e-6);

  {clamping is not be best strategy... but works for small errors}
  x := clamp(floor(pos.x), 0, vox.width-1);
  y := clamp(floor(pos.y), 0, vox.height-1);
  z := clamp(floor(pos.z), 0, vox.depth-1);

  {check if we start inside a voxel}
  col := vox.getVoxel(x,y,z);
  if col.a = 255 then begin
    result.col := col;
    exit();
  end;

  maxSteps := vox.width+vox.height+vox.depth;

  stepX := sign(dir.x);
  stepY := sign(dir.y);
  stepZ := sign(dir.z);

  invDir.x := abs(safeInv(dir.x));
  invDir.y := abs(safeInv(dir.y));
  invDir.z := abs(safeInv(dir.z));

  tDeltaX32 := round(256*invDir.x);
  tDeltaY32 := round(256*invDir.y);
  tDeltaZ32 := round(256*invDir.z);

  tMaxX32 := round(256*(fracs(pos.x, stepX) * invDir.x));
  tMaxY32 := round(256*(fracs(pos.y, stepY) * invDir.y));
  tMaxZ32 := round(256*(fracs(pos.z, stepZ) * invDir.z));

  oldT32 := 0;

  voxPtr := vox.vox.getAddr(0,0);

  res_d32 := 0;
  res_col := RGBA.Clear;

  asm
    pushad

    mov ecx, MAXSTEPS
    mov edi, VOXPTR

    {note: we could put these into MMX registers... might be faster?}

  @TraceLoop:
    {book keeping}
    inc VX_STEP_COUNT
    inc VX_LAST_STEP_COUNT

    {checks}
    mov eax, tMaxX32
    cmp eax, tMaxY32
    jnb @CompareYZ

  @CompareXZ:
    mov eax, tMaxX32
    cmp eax, tMaxZ32
    jnb @UpdateZ
    jmp @UpdateX

  @CompareYZ:
    mov eax, tMaxY32
    cmp eax, tMaxZ32
    jnb @UpdateZ
    jmp @UpdateY

  @UpdateX:
    mov  eax, tMaxX32
    mov  newT32, eax
    sub  eax, oldT32
    add  res_d32, eax
    mov  ebx, STEPX
    add  X, ebx
    mov  eax, tMaxX32
    add  eax, tDeltaX32
    mov  tMaxX32, eax
    mov  edx, X
    cmp  edx, 16 {todo: vox.width}
    jae  @Done
    jmp  @Common
  @UpdateY:
    mov  eax, tMaxY32
    mov  newT32, eax
    sub  eax, oldT32
    add  res_d32, eax
    mov  ebx, STEPY
    add  Y, ebx
    mov  eax, tMaxY32
    add  eax, tDeltaY32
    mov  tMaxY32, eax
    mov  edx, Y
    cmp  edx, 16 {todo: vox.width}
    jae  @Done
    jmp  @Common
  @UpdateZ:
    mov  eax, tMaxZ32
    mov  newT32, eax
    sub  eax, oldT32
    add  res_d32, eax
    mov  ebx, STEPZ
    add  Z, ebx
    mov  eax, tMaxZ32
    add  eax, tDeltaZ32
    mov  tMaxZ32, eax
    mov  edx, Z
    cmp  edx, 16 {todo: vox.width}
    jae  @Done
    jmp  @Common
  @Common:
    mov eax, newT32
    mov oldT32, eax
  @Sample:
    mov eax, Z
    shl eax, 4
    add eax, Y
    shl eax, 4
    add eax, X
    mov eax, [edi+eax*4]

    mov ebx, eax
    shr ebx, 24
    cmp bl, 255
    jne @NoHit

    mov res_didhit, 1
    mov res_col, eax
    jmp @Done

  @NoHit:
    dec ecx
    jnz @TraceLoop

  @Done:
    popad

  end;

  result.col := res_col;
  result.d := res_d32/256;

end;
