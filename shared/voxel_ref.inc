type
  tTraceScanlineProc = procedure(canvas: tPage; voxSprite: tVoxel; xMin, xMax: int16; y: int16; pos, dir, deltaX, deltaY: V3D);

procedure traceScanline_REF(canvas: tPage; voxSprite: tVoxel; xMin, xMax: int16; y: int16; pos, dir, deltaX, deltaY: V3D);
var
  x: int16;
  size: V3D16;
  col: RGBA;
  col16: RGBA16;
  i,j: integer;
  dx,dy: single;
  goodSamples: integer;
begin

  size := voxSprite.getSize;

  for x := xMin to xMax-1 do begin

    col := trace_old(voxSprite, pos, dir).col;

    if (VX_GHOST_MODE or keyDown(key_f4)) then
       col.init(VX_LAST_STEP_COUNT,VX_LAST_STEP_COUNT*4, VX_LAST_STEP_COUNT*16);

    if (VX_UVW_MODE or keyDown(key_f5) )and (col.a = 0) then
       col.init(trunc(pos.x*4), trunc(pos.y*8), trunc(pos.z*16));

    if keyDown(key_f6) then begin
      {5 point AA}
      goodSamples := 0;
      if col.a > 0 then begin
        col16.r := col.r;
        col16.g := col.g;
        col16.b := col.b;
        col16.a := col.a;
        inc(goodSamples);
      end else
        fillchar(col16, sizeof(col16), 0);
      for i := 0 to 1 do
        for j := 0 to 1 do begin
          {The first sample is at pixel center (0.5,0.5)
          each of these four samples is taken in a grid around the
          center pixel}
          dx := ((i * 2) - 1) * 0.25;
          dy := ((i * 2) - 1) * 0.25;
          col := trace_old(voxSprite, pos+(deltaX*dx)+(deltaY*dy), dir).col;
          if col.a > 0 then begin
            col16.r += col.r; col16.g += col.g; col16.b += col.b; col16.a += col.a;
            inc(goodSamples)
          end;
        end;
      if goodSamples = 0 then
        col := RGBA.create(0,0,0,0)
      else begin
        col16.r := col16.r div goodSamples;
        col16.g := col16.g div goodSamples;
        col16.b := col16.b div goodSamples;
        col16.a := col16.a div 5;
        col := RGBA(col16);
      end;
    end;

    pos += deltaX;

    // simulate precision
    if keyDown(key_o) then begin
      pos := V3D16.round(pos*256).toV3D() * (1/256);
      deltaX := V3D16.round(deltaX*256).toV3D() * (1/256);
    end;
    if keyDown(key_p) then begin
      pos := V3D32.round(pos*256*65536).toV3D() * (1/(256*65536));
      deltaX := V3D32.round(deltaX*256*65536).toV3D() * (1/(256*65536));
    end;
    if keyDown(key_k) then begin
      pos := V3D16.trunc(pos*256).toV3D() * (1/256);
      deltaX := V3D16.trunc(deltaX*256).toV3D() * (1/256);
    end;
    if keyDown(key_l) then begin
      pos := V3D32.trunc(pos*256*65536).toV3D() * (1/(256*65536));
      deltaX := V3D32.trunc(deltaX*256*65536).toV3D() * (1/(256*65536));
    end;

    if col.a > 0 then
      canvas.putPixel(x, y, col);
  end;
end;
