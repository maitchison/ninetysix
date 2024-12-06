{Airtime game}
program airtime;

{$MODE delphi}

uses
	vga,
  vesa,
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
  voxel,
  screen,
  s3,
	sound;

var

	{screen}
	screen: tScreen;

  {resources}
  titleBackground: tSprite;
	music: tSoundFile;
  track: tSprite;
  carVox: tVoxelSprite;

  {global time keeper}
  elapsed: double = 0;
  gameTime: double = 0;
  frameCount: dword = 0;

  carDrawTime: double = 0;

  S3D: tS3Driver;

procedure mainLoop(); forward;

type
	tCar = class
  	pos: V3D;
    zAngle: single;
    tilt: single;
    constructor create();
    procedure draw();
    procedure update();
  end;


constructor tCar.create();
begin
	pos := V3D.create(videoDriver.width div 2,videoDriver.height div 2,0);
	zAngle := 0;
  tilt := 0;
end;

procedure tCar.draw();
var
	startTime: double;
  dx, dy: int16;
begin
	startTime := getSec;
  carVox.draw(screen.canvas, round(pos.x), round(pos.y), zAngle, 0, tilt, 0.5);
  carDrawTime := getSec - startTime;
end;


procedure tCar.update();
begin
	{process input}
	if keyDown(key_left) then begin
  	zAngle -= elapsed;
  	tilt += elapsed*1.0;
  end;
	if keyDown(key_right) then begin
  	zAngle += elapsed;
  	tilt -= elapsed*1.0;
  end;
	if keyDown(key_up) then begin
  	pos += V3D.create(-50,0,0).rotated(0,0,zAngle) * elapsed;
  end;
  tilt *= 0.90;
end;

{-------------------------------------------------}

function loadSprite(filename: shortstring): tSprite;
var
	startTime: double;
begin
  startTime := getSec;
	result := tSprite.create(loadLC96('gfx\'+filename+'.p96'));
  note(format(' -loaded %s (%dx%d) in %fs', [filename, result.width, result.height, getSec-startTime]));
end;	

procedure loadResources();
begin

	note('Loading Resources.');

  titleBackground := loadSprite('title');
  track := loadSprite('track1');

  carVox := tVoxelSprite.loadFromFile('gfx\car1', 32);
	music := tSoundFile.create('music\music2.wav');
end;

procedure drawGUI();
var
	fps: double;
	tpf: double;
begin
	if elapsed > 0 then fps := 1.0 / elapsed else fps := -1;
  tpf := VX_TRACE_COUNT;
	GUILabel(screen.canvas, 10, 10, format('FPS:%f Car: %f ms', [fps,carDrawTime*1000]));
end;

procedure titleScreen();
var
	thisClock, startClock, lastClock: double;
  xAngle, zAngle: single; {in degrees}
  xTheta, zTheta: single; {in radians}
  k: single;
begin
	note('Title screen started');

  titleBackground.page.fillRect(tRect.create(0, 360-25, 640, 50), RGBA.create(25,25,50,128));
	titleBackground.page.fillRect(tRect.create(0, 360-24, 640, 48), RGBA.create(25,25,50,128));
	titleBackground.page.fillRect(tRect.create(0, 360-23, 640, 46), RGBA.create(25,25,50,128));

  titleBackground.blit(screen.canvas, 0, 0);

  music.play();
  screen.pageFlip();

  startClock := getSec;
  lastClock := startClock;

  while True do begin

  	if keyDown(key_1) then
    	VX_GHOST_MODE := not keyDown(key_leftshift);
  	if keyDown(key_2) then
    	VX_SHOW_TRACE_EXITS := not keyDown(key_leftshift);

  	{time keeping}
  	thisClock := getSec;
    elapsed := thisClock-lastClock;
    if keyDown(key_space) then
    	elapsed /= 100;
    gameTime += elapsed;
    lastClock := thisClock;
    inc(frameCount);
		
    {subRegion.blit(screen.canvas, 320-30, 360-30);}

    if mouse_b and $1 = $1 then begin
      xAngle := (mouse_x-320)/640*360;
      zAngle := (mouse_y-240)/480*360;
    end else begin
      xAngle := gameTime*50;
      zAngle := gameTime*150;
    end;

		xTheta := xAngle / 180 * 3.1415;
		zTheta := zAngle / 180 * 3.1415;

    if mouse_b and $2 = $2 then begin
    	{round to k-degree increments}
      k := 45;
			xTheta := round(xAngle/k)*k / 180 * 3.1415;
      zTheta := round(zAngle/k)*k / 180 * 3.1415;	
    end else begin
			xTheta := xAngle / 180 * 3.1415;
			zTheta := zAngle / 180 * 3.1415;
    end;

    screen.clearRegion(tRect.create(320-30, 360-30, 60, 60));

	  carVox.draw(screen.canvas, 320, 360, xTheta, 0, zTheta, 0.75);
    drawGUI();

		screen.copyRegion(tRect.create(0,10,250,25));
    screen.copyRegion(tRect.create(320-30, 360-30, 60, 60));

    if keyDown(key_p) then mainLoop();

  	if keyDown(key_q) or keyDown(key_esc) then break;
  end;
end;

procedure mainLoop();
var
	startClock,lastClock,thisClock: double;
  startTime: double;
  car: tCar;

begin
(*
	vgaDriver.setMode(320,240,32);
	note('Main loop started');

  car := tCar.create();
  car.pos := V3D.create(300,300,0);

  flipCanvas();

  startClock := getSec;
  lastClock := startClock;

  camX := 0;
  camY := 0;

  while True do begin

  	camX += trunc((car.pos.x-CamX)*0.1);
    camY += trunc((car.pos.y-CamY)*0.1);

    track.blit(canvas, -camX+320, -camY+240);
  	
  	{time keeping}
  	thisClock := getSec;
    elapsed := thisClock-lastClock;
    if keyDown(key_space) then
    	elapsed /= 100;
    gameTime += elapsed;
    lastClock := thisClock;
    inc(frameCount);

    car.update();

    car.draw();
    drawGUI();

    flipCanvas();

  	if keyDown(key_q) or keyDown(key_esc) then break;
  end;
*)
end;

begin

	{use svga driver}
	videoDriver := tVesaDriver.create();

  loadResources();

	videoDriver.setMode(640,480,32);
	S3D := tS3Driver.create();
  screen.create();

  initMouse();
  initKeyboard();

  titleScreen();

  videoDriver.setText();
  printLog();
end.
