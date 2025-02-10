program destruct;

uses
  debug, test,
  graph32, vga, vesa, screen,
  timer,
  crt, //todo: remove
  keyboard,
  lc96,
  la96, mixlib,
  utils;

procedure titleScreen();
var
  screen: tScreen;
  exitFlag: boolean;
  musicReader: tLA96Reader;
begin

  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    error('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    error('Requires 1MB video card.');

  videoDriver.setTrueColor(320, 240);
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;

  {music}
  musicPlay('res\dance1.a96');

  {load background and refresh screen}
  screen.background := tPage.Load('res\title2_320.p96');

  screen.pageClear();
  screen.pageFlip();

  exitFlag := false;

  {main loop}
  repeat

    musicUpdate();

    startTimer('main');

    screen.clearAll();

    {fps:}
    {
    if assigned(getTimer('main')) then
      elapsed := getTimer('main').avElapsed
    else
      elapsed := -1;
    guiFPS.text := format('%f', [1/elapsed]);
    }

    {gui stuff}
    {
    gui.update(elapsed);
    gui.draw(screen);
    }

    screen.flipAll();

    stopTimer('main');

    if keyDown(key_esc) then exitFlag := true;

    idle();

  until exitFlag;

  videoDriver.setText();

end;

var
  i: integer;
  mode: string;

begin

  autoHeapSize();

  textAttr := White + Blue*16;
  clrscr;

  debug.VERBOSE_SCREEN := llNote;

  runTestSuites();
  initKeyboard();

  titleScreen();

  textAttr := LIGHTGRAY;
end.
