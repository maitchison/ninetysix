program drawMap;

uses
  debug,
  test,
  vga,
  vesa,
  s3,
  utils,
  crt,
  uScreen,
  uColor,
  graph2d,
  graph32,
  timer;

var
  testPage: tPage;
  screen: tScreen;
  i: integer;
  dc: tDrawContext;

procedure runTest(dc: tDrawContext; tag: string);
var
  i: integer;
begin
  for i := 0 to 64-1 do begin
    timer.startTimer(tag);
    dc.drawImage(testPage, Point(rnd, rnd));
    timer.stopTimer(tag);
    if (i mod 4 = 0) then begin
      screen.markRegion(screen.bounds);
      screen.flipAll();
    end;
  end;
end;


begin
  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    fatal('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    fatal('Requires 1MB video card.');
  videoDriver.setTrueColor(800, 600);
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;

  testPage := tPage.Create(256, 256);
  makePageRandom(testPage);

  dc := screen.canvas.dc(bmBlit);
  runTest(dc, 'blit');

  dc := screen.canvas.dc(bmBlit);
  dc.tint := RGB(255, 128, 64);
  runTest(dc, 'tint');

  readkey;

  videoDriver.setText();
  logTimers();
  printLog(32);

  readkey;

end.
