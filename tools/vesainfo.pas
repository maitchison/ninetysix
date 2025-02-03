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
  mode: word;

begin
  clrscr;
  debug.VERBOSE_SCREEN := llNote;
  driver := tVesaDriver.create();
  enableVideoDriver(driver);
  driver.logModes();
  driver.logInfo();

  if paramCount = 1 then begin
    mode := strToInt(paramStr(1));
    {quick test}
    driver.setMode(mode);
    screen := tScreen.create();
    screen.scrollMode := SSM_COPY;
    for i := 0 to 10 do begin
      screen.canvas.clear(RGB(rnd,rnd,rnd));
      screen.pageFlip();
    end;
    readkey;
    driver.setText();
    note('All done');
  end;

end.
