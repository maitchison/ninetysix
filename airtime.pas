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
  canvas: tPage;
  carVox: tVoxelSprite;

  {global time keeper}
  elapsed: double = 0;
  gameTime: double = 0;
  frameCount: dword = 0;

  carDrawTime: double = 0;

  S3D: tS3Driver;

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
	pos := V3D.create(320,240,0);
	zAngle := 0;
  tilt := 0;
end;

procedure tCar.draw();
var
	startTime: double;
begin
	startTime := getSec;
  carVox.draw(canvas, trunc(pos.x), trunc(pos.y), zAngle, 0, 0, 1.0);
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
	

procedure loadResources();
var
	startTime: double;
begin
	note('Loading title');
  startTime := getSec;
	background := tSprite.create(loadLC96('gfx\title.p96'));	
  note(format('Loaded background in %fs', [getSec-startTime]));

  carVox := tVoxelSprite.loadFromFile('gfx\car1', 32);

  {background}
  background := tSprite.create(loadLC96('gfx\title.p96'));	


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

procedure drawGUI();
var
	fps: double;
	tpf: double;
begin
	if elapsed > 0 then fps := 1.0 / elapsed else fps := -1;
  tpf := TRACE_COUNT;
	GUILabel(canvas, 10, 10, format('TPF: %f Car: %f ms', [tpf,carDrawTime*1000]));
end;

procedure mainLoop();
var
	startClock,lastClock,thisClock: double;
  startTime: double;
  car: tCar;
begin

	note('Main loop started');

  car := tCar.create();

  background.draw(canvas, 0, 0);
  music.play();
  flipCanvas();

  startClock := getSec;
  lastClock := startClock;

  while True do begin
  	
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

  note(format('FPS: %f',[frameCount / (getSec-startClock)]));
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
