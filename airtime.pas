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
  voxel,
  s3,
	sound;

var
	music: tSoundFile;

  background: tSprite;
  track: tSprite;
  canvas: tPage;
  carVox: tVoxelSprite;

  {global time keeper}
  elapsed: double = 0;
  gameTime: double = 0;
  frameCount: dword = 0;

  carDrawTime: double = 0;

  S3D: tS3Driver;

  camX, camY: int32;

{-------------------------------------------------}

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
	pos := V3D.create(SCREEN_WIDTH div 2,SCREEN_HEIGHT div 2,0);
	zAngle := 0;
  tilt := 0;
end;

procedure worldToScreen(pos: V3D; out dx: int16; out dy: int16);
begin
	dx := trunc(pos.x-camX)+SCREEN_WIDTH div 2;
	dy := trunc(pos.y-camY)+SCREEN_HEIGHT div 2;
end;

procedure tCar.draw();
var
	startTime: double;
  dx, dy: int16;
begin
	startTime := getSec;
  worldToScreen(pos, dx, dy);
  carVox.draw(canvas, dx, dy, zAngle, 0, tilt, 0.5);
  carDrawTime := getSec - startTime;
end;


procedure tCar.update();
begin
	{process input}
	if keyDown(key_left) then begin
  	zAngle -= elapsed;
  	tilt += elapsed*0.5;
  end;
	if keyDown(key_right) then begin
  	zAngle += elapsed;
  	tilt -= elapsed*0.5;
  end;
	if keyDown(key_up) then begin
  	pos += V3D.create(-50,0,0).rotated(0,0,zAngle) * elapsed;
  end;
  tilt *= 0.95;
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

  background := loadSprite('title');
  track := loadSprite('track1');

  carVox := tVoxelSprite.loadFromFile('gfx\car1', 32);
	music := tSoundFile.create('music\music2.wav');
end;

procedure flipCanvas();
var
	screenDWords: dword;
begin	
	{note: s3 upload is 2x faster, but causes stuttering on music}
  screenDWords := SCREEN_WIDTH*SCREEN_HEIGHT;
  asm
  	pusha
  	push es
    mov es,  LFB_SEG
    mov edi,  0
    mov esi, canvas.pixels
    mov ecx, screenDWords
    rep movsd
    pop es
    popa
    end;
end;

procedure drawGUI();
var
	fps: double;
	tpf: double;
begin
	if elapsed > 0 then fps := 1.0 / elapsed else fps := -1;
  tpf := VX_TRACE_COUNT;
	GUILabel(canvas, 10, 10, format('FPS:%f Car: %f ms', [fps,carDrawTime*1000]));
end;

procedure titleScreen();
var
	thisClock, startClock, lastClock: double;
  subRegion: tSprite;
begin
	{title really needs 640x480}
	setMode(640,480,32);
  canvas := tPage.create(SCREEN_WIDTH, SCREEN_HEIGHT);
	note('Title screen started');

  background.blit(canvas, 0, 0);
  subRegion := background;
  subRegion.rect.position.x := 320-50;
  subRegion.rect.position.y := 360-50;
  subRegion.rect.width := 100;
  subRegion.rect.height := 100;

  music.play();
  flipCanvas();

  startClock := getSec;
  lastClock := startClock;

  camX := 0;
  camY := 0;

  while True do begin

  	{time keeping}
  	thisClock := getSec;
    elapsed := thisClock-lastClock;
    if keyDown(key_space) then
    	elapsed /= 100;
    gameTime += elapsed;
    lastClock := thisClock;
    inc(frameCount);
		

    subRegion.blit(canvas, 320-50, 360-50);
    carVox.draw(canvas, 320, 360, gameTime, gameTime/2, gameTime/3, 1);

    drawGUI();

    flipCanvas();

  	if keyDown(key_q) or keyDown(key_esc) then break;
  end;
end;

procedure mainLoop();
var
	startClock,lastClock,thisClock: double;
  startTime: double;
  car: tCar;

begin

	note('Main loop started');

  car := tCar.create();

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
end;

begin

  loadResources();

	setMode(320,240,32);
	S3D := tS3Driver.create();
  canvas := tPage.create(SCREEN_WIDTH, SCREEN_HEIGHT);

  initMouse();
  initKeyboard();

  {mainLoop();}
  titleScreen();

  setText();
  printLog();
end.
