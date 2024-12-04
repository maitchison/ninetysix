{Airtime game}
program airtime;

{$MODE delphi}

uses
	screen,
  graph32,
  graph2d,
	debug,
  test,
  utils,
  sbDriver,
  mouse,
  keyboard,
  vertex,
  sprite,
  gui,
	lc96,
  s3,
	sound;

var
	music: tSoundFile;

  background: tSprite;
  canvas: tPage;
  carSprite: tSprite;

  {global time keeper}
  elapsed: double = 0;
  gameTime: double = 0;
  frameCounter: dword = 0;

  carDrawTime: double = 0;

  S3D: tS3Driver;

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


procedure loadResources();
var
	startTime: double;
begin
	note('Loading title');
  startTime := getSec;
	background := tSprite.create(loadLC96('gfx\title.p96'));	
  note(format('Loaded background in %fs', [getSec-startTime]));

	note('Loading cars');
  carSprite := tSprite.create(loadBMP('gfx\car1.bmp'));
  note(format('Car sprite is (%d, %d)', [carSprite.width, carSprite.height]));

  note('Loading music');
	music := tSoundFile.create('music\music2.wav');
end;

procedure flipCanvas();
begin	
	{note: s3 upload is 2x faster, but causes stuttering on music}
  asm
  	pusha
  	push es
    mov es,  LFB_SEG
    mov edi,  0
    mov esi, canvas.pixels
    mov ecx, 640*480
    rep movsd
    pop es
    popa
    end;
end;

{trace through voxels to draw the car}
procedure drawCar_TRACE();
var
  size: V3D; {half size of cuboid}
  debugCol: RGBA;
var
	cameraX: V3D;
	cameraY: V3D;
  cameraZ: V3D;
  objToWorld: Matrix3X3;
  worldToObj: Matrix3X3;

var
	faceColor: array[1..6] of RGBA;


function getVoxel(pos: V3D): RGBA;
var
	x,y,z: int32;
begin
	result.init(255,0,255,0);
  x := trunc(pos.x+32.5);
  y := trunc(pos.y+13);
  z := trunc(pos.z+9);
	if (x < 0) or (x >= 65) then exit;
	if (y < 0) or (y >= 26) then exit;
	if (z < 0) or (z >= 18) then exit;
  result := carSprite.page.getPixel(x,y+z*26);
end;

function intersectX(size, pos, dir: V3D): single;
var
	t: single;
  pnt: V3D;
begin
	if dir.x = 0 then exit(9999);
  if dir.x > 0 then
  	t := (-size.x-pos.x) / dir.x
  else
		t := (+size.x-pos.x) / dir.x;
  pos := pos + dir * t;
  if (pos.y < -size.y) or (pos.y > size.y) then exit(9999);
  if (pos.z < -size.z) or (pos.z > size.z) then exit(9999);
  exit(t);
end;

function intersectY(size, pos, dir: V3D): single;
var
	t: single;
  pnt: V3D;
begin
	if dir.y = 0 then exit(9999);
  if dir.y > 0 then
  	t := (-size.y-pos.y) / dir.y
  else
		t := (+size.y-pos.y) / dir.y;
  pos := pos + dir * t;
  if (pos.x < -size.x) or (pos.x > size.x) then exit(9999);
  if (pos.z < -size.z) or (pos.z > size.z) then exit(9999);
  exit(t);
end;

function intersectZ(size, pos, dir: V3D): single;
var
	t: single;
  pnt: V3D;
begin
	if dir.z = 0 then exit(9999);
  if dir.z > 0 then
  	t := (-size.z-pos.z) / dir.z
  else
		t := (+size.z-pos.z) / dir.z;
  pos := pos + dir * t;
  if (pos.x < -size.x) or (pos.x > size.x) then exit(9999);
  if (pos.y < -size.y) or (pos.y > size.y) then exit(9999);
  exit(t);
end;

{trace ray at location and direction (in object space)}
function trace(pos: V3D;dir: V3D): RGBA;
var
	k: integer;
  c: RGBA;
  t,tX,tY,tZ,tMin,tMax: single; {time to intersect each of the planes}

  depth: single;
  maxSamples: integer;
begin

	result.init(0,0,0,0);

  {note: in theory at most one of these should intersect for each of the
   entry and exit points}

	{find the entry point}
  (*
  t := intersectX(size, pos, dir);
  if t > 1000 then
		t := intersectY(size, pos, dir);
  if t > 1000 then
  	t := intersectZ(size, pos, dir);

  if t > 1000 then exit; {did not intersect any faces}
  *) {this is done for us now}

  maxSamples := 128;

  (*
  {move to intersection point}
  t += 0.5; {start halfway in the voxel}
  pos += dir*t;
  *)  	

	result := RGBA.create(0,0,0,255);

	for k := 0 to maxSamples-1 do begin

  	c := getVoxel(pos);

    {fix annoying transparent color}
    if c.r=192 then c.a := 0;

    {left bounds}
    if (c.r=255) and (c.g=0) and (c.b=255) then begin
			{result.init(0,0,0,0);
      exit;}	
    end;

    if c.a > 0 then begin
    	{connection, so stop}
      depth := (255-((t + k)*4))/255;	
      c *= depth;
    	exit(c)
    end else begin
    	{move to next voxel}
	  	pos += dir;
    end;
  end;

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
	result.x := 320 + trunc(p.x);
	result.y := 240 + trunc(p.y);
end;

procedure scanLine(a, b: tScreenPoint);
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

	c.init(255,0,255);
	canvas.putPixel(s1.x, s1.y, c);
	canvas.putPixel(s2.x, s2.y, c);
	canvas.putPixel(s3.x, s3.y, c);
	canvas.putPixel(s4.x, s4.y, c);

  for y := yMin to yMax do
  	screenLines[y].reset();

  scanLine(s1, s2);
  scanLine(s2, s3);
  scanLine(s3, s4);
  scanLine(s4, s1);

  {solid faces}
  {
  if not (faceID in [3,4]) then begin
    for y := yMin to yMax do
			canvas.hLine(screenLines[y].xMin, y, screenLines[y].xMax, faceColor[faceID]);
    exit;
  end;}

  for y := yMin to yMax do begin
  	for x := screenLines[y].xMin to screenLines[y].xMax do begin
    	{map from screen space to object space}
      {worldPos := worldToObj.apply(V3D.create(x - 320, y - 240, -100));}
      worldPos := (cameraX*(x-320))+(cameraY*(y-240))+(cameraZ*-50);


      case faceID of
      	1: t := (-size.z-worldPos.z) / cameraZ.z;
        2: t := (+size.z-worldPos.z) / cameraZ.z;
        3: t := (-size.x-worldPos.x) / cameraZ.x;
        4: t := (+size.x-worldPos.x) / cameraZ.x;
        5: t := (-size.y-worldPos.y) / cameraZ.y;
        6: t := (+size.y-worldPos.y) / cameraZ.y;
        else t := 0;
      end;

      if t > 1000 then begin
      	{this should not happen}
        c.init(0,255,0);
        canvas.putPixel(x,y, c);
        continue;
      end;

      worldPos += cameraZ * (t + 0.5);

      c := trace(worldPos, cameraZ);
     {c := trace((cameraX*i)+(cameraY*j)+(cameraZ*-40), cameraZ);}
    	if c.a > 0 then
	      canvas.putPixel(x,y, c);
    end;
  {
  	c := trace((cameraX*i)+(cameraY*j)+(cameraZ*-40), cameraZ);
      if c.a > 0 then
	      canvas.putPixel(i+320,j+240, c);}

  end;

end;


var
	i,j: integer;
  c: RGBA;


  thetaX,thetaY,thetaZ: single;

  p1,p2,p3,p4,p5,p6,p7,p8: V3D; {world space}


begin

  faceColor[1].init(255,0,0); 	
  faceColor[2].init(128,0,0);
  faceColor[3].init(0,255,0); 		
  faceColor[4].init(0,128,0); 	
  faceColor[5].init(0,0,255); 	
  faceColor[6].init(0,0,128);


  thetaX := gameTime/3;
  thetaY := gameTime/2;
  thetaZ := gameTime;

  objToWorld.rotation(thetaX, thetaY, thetaZ);
  worldToObj := objToWorld.transpose();

	cameraX := worldToObj.apply(V3D.create(1,0,0));
  cameraY := worldToObj.apply(V3D.create(0,1,0));
  cameraZ := worldToObj.apply(V3D.create(0,0,1));

  assert(abs(cameraZ.abs-1)<0.01, 'cameraZ not normed');

  info(cameraZ.toString);

  canvas.fillRect(tRect.create(320-50,240-50,100,100), RGBA.create(0,0,0));

  {get cube corners}
  size := V3D.create(32.5,13,9);
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



	(*
	for i := -32 to 64-1 do begin
  	for j := -32 to 64-1 do begin
    	c := trace((cameraX*i)+(cameraY*j)+(cameraZ*-40), cameraZ);
      if c.a > 0 then
	      canvas.putPixel(i+320,j+240, c);
    end;
  end;
  *)	
	
end;

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
  (*
  x += rnd/512;
  y += rnd/512;
  z += rnd/512; {half voxel of noise}
  *)

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
end;

function fetch(oX,oY,oZ: int32): RGBA;
begin
	result := carSprite.page.getPixel(oX, oY+(oZ*26));
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
  thetaZ := frameCounter / 10;

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
	{dims are 65, 26, 18}
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

  for j := 0 to 26-1 do
  	for i := 0 to 65-1 do
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
        {if y = (frameCounter mod 30) then begin
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

        transform(x-32.5,y-13,z-9,dX,dY,tmp);

        depthByte := clip(128 + tmp, 0, 255);

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

procedure drawGUI();
var
	fps: double;
begin
	if elapsed > 0 then fps := 1.0 / elapsed else fps := -1;
	GUILabel(canvas, 10, 10, format('FPS: %f Car: %f ms', [fps,carDrawTime*1000]));
end;

procedure mainLoop();
var
	startClock,lastClock,thisClock: double;
  startTime: double;
begin

	note('Main loop started');

  background.draw(canvas, 0, 0);
  music.play();
  flipCanvas();

  startClock := getSec;
  lastClock := startClock;

  while True do begin
  	
  	{time keeping}
  	thisClock := getSec;
    elapsed := thisClock-lastClock;
    gameTime += elapsed;
    lastClock := thisClock;
    inc(frameCounter);

    startTime := getSec;
  	drawCar_TRACE();
    carDrawTime := getSec - startTime;
	  drawGUI();

    flipCanvas();

  	if keyDown(key_q) or keyDown(key_esc) then break;
  end;

  note(format('FPS: %f',[frameCounter / (getSec-startClock)]));
end;

begin

  loadResources();

	setMode(640,480,32);
	S3D := tS3Driver.create();
  canvas := tPage.create(SCREEN_WIDTH, SCREEN_HEIGHT);

  initMouse();
  initKeyboard();

  mainLoop();

  setText();
  printLog();
end.
