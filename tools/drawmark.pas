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

const
  BACKEND_NAME: array[tDrawBackend] of string = ('ref','asm','mmx');

const
  ITERATIONS = 16;

procedure runFillTest(dc: tDrawContext; tag: string);
var
  i: integer;
  col: RGBA;
  backend: tDrawBackend;
begin
  for backend in [dbREF, dbASM, dbMMX] do begin
    dc.backend := backend;
    for i := 0 to ITERATIONS-1 do begin
      col.init(rnd, rnd, rnd, rnd);
      timer.startTimer(tag+'_'+BACKEND_NAME[backend]);
      dc.fillRect(Rect(rnd, rnd, 256, 256), col);
      timer.stopTimer(tag+'_'+BACKEND_NAME[backend]);
      if (i mod 4 = 0) then begin
        screen.markRegion(screen.bounds);
        screen.flipAll();
      end;
    end;
  end;
end;

procedure runDrawTest(dc: tDrawContext; tag: string);
var
  i: integer;
  backend: tDrawBackend;
begin
  for backend in [dbREF, dbASM, dbMMX] do begin
    dc.backend := backend;
    for i := 0 to ITERATIONS-1 do begin
      timer.startTimer(tag+'_'+BACKEND_NAME[backend]);
      dc.drawImage(testPage, Point(rnd, rnd));
      timer.stopTimer(tag+'_'+BACKEND_NAME[backend]);
      if (i mod 4 = 0) then begin
        screen.markRegion(screen.bounds);
        screen.flipAll();
      end;
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

  startTimer('flip'); stopTimer('flip');

  dc := screen.canvas.dc(bmBlit);
  runFillTest(dc, 'fill_blit');
  readkey;


  dc := screen.canvas.dc(bmBlend);
  runFillTest(dc, 'fill_blend');
  readkey;

    {
    dc := screen.canvas.dc(bmBlit);
    dc.backend := backend;
    runDrawTest(dc, 'draw_blit_'+BACKEND_NAME[backend]);
    }


  videoDriver.setText();
  logTimers();
  printLog(32);

  readkey;

end.
