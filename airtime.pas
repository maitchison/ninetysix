{Airtime game}
program airtime;

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
	sound;

var
	music: tSoundFile;

  background: tSprite;
  canvas: tPage;
  carSprite: tSprite;

  {global time keeper}
  elapsed: double = 0;
  frameCounter: dword = 0;


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

  note('Loading music');
	music := tSoundFile.create('music\music2.wav');
end;

procedure flipCanvas();
begin
  {flip page}
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

procedure pageFlip();
begin
  asm
  	pushad
  	push es
    mov es,  LFB_SEG
    mov edi,  0
    mov esi, canvas.pixels
    mov ecx, 640*480
    rep movsd
    pop es
    popad
    end;
end;

procedure drawCar();
begin
	carSprite.draw(canvas,320, 240);
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
  pageFlip();

  startClock := getSec;
  lastClock := startClock;

  while True do begin
  	
  	{time keeping}
  	thisClock := getSec;
    elapsed := thisClock-lastClock;
    lastClock := thisClock;
    inc(frameCounter);

  	drawCar();
 		if frameCounter and $f = 0 then
	    drawGUI();

    pageFlip();

  	if keyDown(key_q) or keyDown(key_esc) then break;
  end;

  note(format('FPS: %f',[frameCounter / (getSec-startClock)]));
end;

begin

  loadResources();

	setMode(640,480,32);
  canvas := tPage.create(SCREEN_WIDTH, SCREEN_HEIGHT);

  initMouse();
  initKeyboard();

  mainLoop();

  setText();
  printLog();
end.
