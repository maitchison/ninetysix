{used to prototype music}
program music;

uses
  screen,
  graph32,
  debug,
  test,
  utils,
  sbDriver,
  mouse,
  keyboard,
  sprite,
  sound;

var
  sfx: tSoundFile;

  background: tSprite;
  canvas: tPage;

procedure loadResources();
begin
  note('Loading graphics');
  background := tSprite.create(loadBMP('e:\airtime\title_640.bmp'));
  note('Loading music');
  sfx := tSoundFile.create('music\music2.wav');
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

procedure mainLoop();
begin
  note('Main loop started');

  background.draw(canvas, 0, 0);

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


  while True do begin

    if keyDown(key_q) or keyDown(key_esc) then break;

  end;
end;

begin

  loadResources();

  setMode(640,480,32);
  canvas := tPage.create(SCREEN_WIDTH, SCREEN_HEIGHT);

  initKeyboard();
  initMouse();

  mainLoop();

  setText();
  printLog();
end.
