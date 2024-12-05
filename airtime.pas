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

procedure mainLoop(); forward;

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
	pos := V3D.create(screen.width div 2,screen.height div 2,0);
	zAngle := 0;
  tilt := 0;
end;

procedure worldToScreen(pos: V3D; out dx: int16; out dy: int16);
begin
	dx := trunc(pos.x-camX)+screen.width div 2;
	dy := trunc(pos.y-camY)+screen.height div 2;
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

  background := loadSprite('title');
  track := loadSprite('track1');

  carVox := tVoxelSprite.loadFromFile('gfx\car1', 32);
	music := tSoundFile.create('music\music2.wav');
end;

procedure flipCanvas();
var
	screenDWords: dword;
  lfb_seg: word;
begin	
	{note: s3 upload is 2x faster, but causes stuttering on music}
  screenDWords := screen.width*screen.height;
  lfb_seg := screen.LFB_SEG;
  if lfb_seg = 0 then exit;
  asm
  	pusha
  	push es
    mov es,  lfb_seg
    mov edi,  0
    mov esi, canvas.pixels
    mov ecx, screenDWords
    rep movsd
    pop es
    popa
    end;
end;

procedure flipCanvasLines(y1,y2: int32);
var
	len: dword;
  ofs: dword;
  lfb_seg: word;
begin	
	{note: s3 upload is 2x faster, but causes stuttering on music}
  len := screen.width*(y2-y1);
  ofs := y1*screen.width*4;
  lfb_seg := screen.LFB_SEG;
  if lfb_seg = 0 then exit;
  asm
  	pusha
  	push es
    mov es,  lfb_seg
    mov edi, ofs
    mov esi, canvas.pixels
    add esi, ofs
    mov ecx, len
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
	screen.setMode(640,480,32);
  canvas := tPage.create(screen.width, screen.height);
	note('Title screen started');

	background.page.fillRect(tRect.create(0, 360-25, 640, 50), RGBA.create(25,25,50,128));
	background.page.fillRect(tRect.create(0, 360-24, 640, 48), RGBA.create(25,25,50,128));
	background.page.fillRect(tRect.create(0, 360-23, 640, 46), RGBA.create(25,25,50,128));


  background.blit(canvas, 0, 0);
  subRegion := background;
  subRegion.rect.position.x := 320-30;
  subRegion.rect.position.y := 360-30;
  subRegion.rect.width := 60;
  subRegion.rect.height := 60;

  music.play();
  flipCanvas();

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
		
    subRegion.blit(canvas, 320-30, 360-30);
    carVox.draw(canvas, 320, 360, gameTime, gameTime/2, gameTime*3, 0.75);

    drawGUI();

		flipCanvasLines(0,35);
		flipCanvasLines(360-30,360+30);

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

	screen.setMode(320,240,32);
  canvas := tPage.create(screen.width, screen.height);
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
end;

begin

	{use svga driver}
	screen := tVesaDriver.create();

  loadResources();

	screen.setMode(320,240,32);
	S3D := tS3Driver.create();
  canvas := tPage.create(screen.width, screen.height);

  {initMouse();}
  initKeyboard();

  titleScreen();

  screen.setText();
  printLog();
end.
