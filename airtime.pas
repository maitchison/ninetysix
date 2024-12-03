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
  frameCounter: dword = 0;

  S3D: tS3Driver;


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

procedure drawCar();
var
	x,y,z: int32;
  dX, dY: int32;
  c: RGBA;

{transform from object space to screen space}
procedure transform(oX,oY,oZ: int32;out sX, sY: int32);
var
	cX, cY: int32;
  x, y, rX, rY: double; {realX, realY}
  theta: double;
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

  theta := frameCounter / 10;

  x := oX - 32;
  y := oY - 13;

  rx := sin(theta)*x + cos(theta)*y;
  ry := cos(theta)*x - sin(theta)*y;

  sx := cX + round(rX*0.75);
  sy := cY + round(rY*0.75) + oZ;
end;

function fetch(oX,oY,oZ: int32): RGBA;
begin
	result := carSprite.page.getPixel(oX, oY+(oZ*26));
end;

begin

	{
  y  z  x
   \ | /
    \|/
  }

	canvas.fillRect(tRect.create(320-100, 240-100, 200, 200), RGBA.create(0,0,0));
	{dims are 65, 26, 18}
  {note: I should trim this to 64, 32, 18 (for fast indexing)}
	{guess this is 64x64xsomething}
	{carSprite.draw(canvas,320, 240);}

  {draw in 'y' slices}

  for y := 0 to 26-1 do
  	for x := 0 to 65-1 do
    	for z := 0 to 18-1 do begin
      	c := fetch(x,y,z);
        {not sure why this color is transparent}
        if c.r = 192 then
        	continue;
        if y = (frameCounter mod 30) then begin
        	c := RGBA.create(0,255,0);
        end;
        transform(x,26-y,z,dX,dY);
      	canvas.putPixel(dx, dy, c);
      end;
end;

procedure drawGUI();
var
	fps: double;
begin
	if elapsed > 0 then
		fps := 1.0 / elapsed
  else
  	fps := -1;
	GUILabel(canvas, 10, 10, format('FPS: %f', [fps]));
end;

procedure mainLoop();
var
	startClock,lastClock,thisClock: double;
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
    lastClock := thisClock;
    inc(frameCounter);


  	drawCar();
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
