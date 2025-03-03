program romdor;

uses
  debug,
  test,
  sbDriver,
  mixlib,
  vesa,
  keyboard,
  timer,
  vga,
  crt,
  mouse,
  uScreen,
  graph32,
  lc96,
  utils;

var
  screen: tScreen;

procedure setup();
begin
  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    fatal('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    fatal('Requires 1MB video card.');
  videoDriver.setTrueColor(800, 600);
  musicPlay('res\mordor.a96');
  initMouse();
  initKeyboard();
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;

end;

procedure titleScreen();
begin
  screen.background := tPage.load('res\title800.p96');
  screen.pageClear();
  screen.pageFlip();

  repeat
    musicUpdate();
  until keyDown(key_esc);

  freeAndNil(screen.background);
end;

begin

  autoHeapSize();

  textAttr := White + Blue*16;
  clrscr;

  debug.VERBOSE_SCREEN := llNote;

  runTestSuites();

  setup();

  titleScreen();

  videoDriver.setText();

  logTimers();

  printLog(32);

end.
