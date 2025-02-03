program vesaInfo;

uses
  crt,
  debug,
  vga,
  utils,
  screen,
  graph32,
  vesa;

var
  vesaInfo: tVesaInfo;
  screen: tScreen;
  driver: tVesaDriver;
  i: integer;
  LFB: word;

begin
  clrscr;
  debug.VERBOSE_SCREEN := llNote;
  driver := tVesaDriver.create();
  enableVideoDriver(driver);
  driver.logModes();
  driver.logInfo();

  {quick test}
  driver.setMode(800, 600, 16);

  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;

  for i := 0 to 100 do begin
    screen.canvas.clear(RGB(rnd,rnd,rnd));
    screen.pageFlip();
    delay(1);
  end;

  readkey;
  driver.setText();
  note('All done');

end.
