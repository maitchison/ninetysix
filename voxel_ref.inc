type
  tTraceScanlineProc = procedure(canvas: tPage; voxSprite: tVoxelSprite; xMin, xMax: int16; y: int16; pos, dir, deltaX, deltaY: V3D);

{trace ray at location and direction (in object space)}
function trace_REF(voxSprite: tVoxelSprite; pos: V3D;dir: V3D;size: V3D16): RGBA;
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

  LAST_TRACE_COUNT := 0;

  {color used when initial sample is out of of bounds}
  {this shouldn't happen, but might due to rounding error or bug}
  result.init(255,0,0,255);

  sx := trunc(256*pos.x);
  sy := trunc(256*pos.y);
  sz := trunc(256*pos.z);

  result.init(255,0,255,0); {color used when out of bounds}

  depth := 0;
  dx := round(256*dir.x);
  dy := round(256*dir.y);
  dz := round(256*dir.z);

  {clamping sucks, but lets do it}
  {this is needed due either bugs in my tracer, or precision issues}
  sx := clamp(sx, 0, size.x*256-1);
  sy := clamp(sy, 0, size.y*256-1);
  sz := clamp(sz, 0, size.z*256-1);

  voxPtr := voxSprite.vox.pixels;

  for k := 0 to MAX_SAMPLES-1 do begin

    inc(VX_TRACE_COUNT);
    inc(LAST_TRACE_COUNT);

    x := sx div 256;
    y := sy div 256;
    z := sz div 256;

    if (x < 0) or (x >= size.x) then begin
      if not VX_SHOW_TRACE_EXITS then exit;
      exit(RGBA.create(255,0,0));
    end;
    if (y < 0) or (y >= size.y) then begin
      if not VX_SHOW_TRACE_EXITS then exit;
      exit(RGBA.create(0,255,0));
    end;
    if (z < 0) or (z >= size.z) then begin
      if not VX_SHOW_TRACE_EXITS then exit;
      exit(RGBA.create(0,0,255));
    end;

    c := voxSprite.getVoxel(x, y, z);

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

procedure traceScanline_REF(canvas: tPage; voxSprite: tVoxelSprite; xMin, xMax: int16; y: int16; pos, dir, deltaX, deltaY: V3D);
var
  x: int16;
  size: V3D16;
  col: RGBA;
  col16: RGBA16;
  i,j: integer;
  dx,dy: single;
begin

  size := voxSprite.getSize;

  for x := xMin to xMax-1 do begin

    col := trace_REF(voxSprite, pos, dir, size);

    if VX_GHOST_MODE then
       col.init(LAST_TRACE_COUNT,LAST_TRACE_COUNT*4, LAST_TRACE_COUNT*16);

    if VX_UVW_MODE and (col.a = 0) then
       col.init(trunc(pos.x*4), trunc(pos.y*8), trunc(pos.z*16));

    if keyDown(key_f6) then begin
      {5 point AA}
      if col.a > 0 then begin
        col16.r := col.r;
        col16.g := col.g;
        col16.b := col.b;
        col16.a := col.a;
      end else
        fillchar(col16, sizeof(col16), 0);
      for i := 0 to 1 do
        for j := 0 to 1 do begin
          {the first sample is at pixel center (0.5,0.5)
          each of these four samples is taken uniformally at random
          from each of the pixels quadrants.
          update: disabled random sampling
          }

          dx := ((i * 2) - 1) * 0.25;
          dy := ((i * 2) - 1) * 0.25;
          //dx += ((rnd/256) - 0.5) * 0.50;
          //dy += ((rnd/256) - 0.5) * 0.50;
          col := trace_REF(voxSprite, pos+(deltaX*dx)+(deltaY*dy), dir, size);
          if col.a > 0 then begin
            col16.r += col.r; col16.g += col.g; col16.b += col.b; col16.a += col.a;
          end;
        end;
      col16.r := col16.r div 5;
      col16.g := col16.g div 5;
      col16.b := col16.b div 5;
      col16.a := col16.a div 5;
      col := RGBA(col16);
    end;

    pos += deltaX;

    if col.a > 0 then
      canvas.putPixel(x, y, col);
  end;
end;
