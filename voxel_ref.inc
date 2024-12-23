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

procedure traceScanline_REF(canvas: tPage; voxSprite: tVoxelSprite; xMin, xMax: int16; y: int16; pos, dir, delta: V3D);
var
  x: int16;
  size: V3D16;
  col: RGBA;
begin

  size := voxSprite.getSize;

  for x := xMin to xMax do begin

    col := trace_REF(voxSprite, pos, dir, size);

    if VX_GHOST_MODE then
       col.init(LAST_TRACE_COUNT,LAST_TRACE_COUNT*4, LAST_TRACE_COUNT*16);

    pos += delta;

    if col.a > 0 then
      canvas.putPixel(x, y, col);
  end;
end;
