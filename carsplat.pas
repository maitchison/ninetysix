(*
{write each voxel to the screen, like a point cloud}
procedure drawCar_SPLAT();
var
  M: array[1..9] of single;
  thetaX, thetaY, thetaZ: single;

{transform from object space to screen space}
procedure transform(x,y,z: single;out sX,sY,sZ: int32);
var
  cX, cY: int32;
  nX, nY, nZ: single; {new}
const
  SCALE = 0.5;
begin

  {solving order
  1. switch to raytrace... maybe this is not a bad idea
  2. depth buffer (probably simplest
  3. find an axis-aligned plane that works... maybe there's always one?
  4. switch from splatting pixels, to a plane moving through the vox?

  From memory tracing is not bad, I already have code for this?
  }

  {center point}
  cX := 320;
  cY := 240;
  {simple isometric}
  {
  sX := cX+oX-oY;
  sY := cY-((oX+oY) shr 1)+oZ;
  }
  {rotation matrix}

  {
  nX := x;
  nY := cos(thetaX)*y - sin(thetaX)*z;
  nZ := sin(thetaX)*y + cos(thetaX)*z;
  x := nX; y := nY; z := nZ;

  nX := cos(thetaY)*x + sin(thetaY)*z;
  nY := y;
  nZ := -sin(thetaY)*x + cos(thetaY)*z;
  x := nX; y := nY; z := nZ;

  nX := cos(thetaZ)*x - sin(thetaZ)*y;
  nY := sin(thetaZ)*x + cos(thetaZ)*y;
  nZ := z;
  x := nX; y := nY; z := nZ;
  }

  nX := M[1]*x + M[2]*y + M[3]*z;
  nY := M[4]*x + M[5]*y + M[6]*z;
  nZ := M[7]*x + M[8]*y + M[9]*z;

  {othographic projection}

  {

  y,z
  |
  |
  |
   ----- x

  }

  {add a little noise}
  {
  x += rnd/512;
  y += rnd/512;
  z += rnd/512; {half voxel of noise}
  }

  {this is just xy slices stacked ontop of each other,
   where 'depth' is just the y axis.}
  sX := cX + round(nX*scale);
  sY := cY + round(nY*scale+nZ*scale);
  sZ := round(4*nZ*scale);

  {isometric?}
  {
  sX := cX + round(-x+y);
  sY := cY + round((x+y)*0.66);
  sZ := round(y);
  }
end; *)

function fetch(oX,oY,oZ: int32): RGBA;
begin
  result := carSprite.page.getPixel(oX, oY+(oZ*32));
end;

var
  i,j,k: int32;
  x,y,z: int32;
  dX, dY: int32;
  c,c2,c3: RGBA;
  xStep, yStep, zStep: int32;
  depthByte: byte;
  tmp: int32;
  depthFactor: single;
  voxCounter: int32;
  pCanvas: pDword;

begin

  {
  y  z  x
   \ | /
    \|/
  }

  thetaX := 0;
  thetaY := 0;
  thetaZ := frameCount / 10;

  {calculate transformation matrix}
  M[1] := cos(thetaY)*cos(thetaZ);
  M[2] := cos(thetaY)*sin(thetaZ);
  M[3] := -sin(thetaY);
  M[4] := sin(thetaX)*sin(thetaY)*cos(thetaZ)-cos(thetaX)*sin(thetaZ);
  M[5] := sin(thetaX)*sin(thetaY)*sin(thetaZ)+cos(thetaX)*cos(thetaZ);
  M[6] := sin(thetaX)*cos(thetaY);
  M[7] := cos(thetaX)*sin(thetaY)*cos(thetaZ)+sin(thetaX)*sin(thetaZ);
  M[8] := cos(thetaX)*sin(thetaY)*sin(thetaZ)-sin(thetaX)*cos(thetaZ);
  M[9] := cos(thetaX)*sin(thetaY);


  canvas.fillRect(tRect.create(320-100, 240-100, 200, 200), RGBA.create(0,0,0));
  {dims are 64, 32, 18}
  {note: I should trim this to 64, 32, 18 (for fast indexing)}
  {guess this is 64x64xsomething}
  {carSprite.draw(canvas,320, 240);}

  transform(100, 0, 0, tmp, tmp, xStep);
  transform(0, 100, 0, tmp, tmp, yStep);
  transform(0, 0, 100, tmp, tmp, zStep);

  voxCounter := 0;

  carSprite.page.putPixel(0,0,RGBA.create(255,0,255));
  carSprite.page.putPixel(1,0,RGBA.create(255,0,255));
  carSprite.page.putPixel(0,1,RGBA.create(255,0,255));
  carSprite.page.putPixel(1,1,RGBA.create(255,0,255));

  for j := 0 to 32-1 do
    for i := 0 to 64-1 do
      for k := 0 to 18-1 do begin

        { this doesn't really work unless we also rotate the axis...}
        {
        if xStep >= 0 then x := i else x := 65-1-i;
        if yStep >= 0 then y := j else y := 26-1-j;
        if zStep >= 0 then z := k else z := 18-1-k;}
        x := i; y := j; z := k;

        c := fetch(x,y,z);
        {not sure why this color is transparent}
        if c.r = 192 then
          continue;
        {if y = (frameCount mod 30) then begin
          c := RGBA.create(0,255,0);
        end;}

        {stub: show draw order}
        {if i < 10 then
          c.r := 128;
        if j < 10 then
          c.g := 128;}
          {
        if k > 9 then
          c.init(128, 128, 128);}

        transform(x-32,y-16,z-9,dX,dY,tmp);

        depthByte := clamp(128 + tmp, 0, 255);

        {stub: show depth}
        c *= 1-(depthByte/255);
        c.a := depthByte;

        {stub: really show depth}
{        c.r := depthByte;
        c.g := depthByte;
        c.b := depthByte;}

        pCanvas := pdword(canvas.pixels + ((dx + dy * 640) * 4));

        {direct write}
        c3 := RGBA(pCanvas^);
        if c3.a > c.a then
          RGBA(pCanvas^) := c;
      end;
end;
