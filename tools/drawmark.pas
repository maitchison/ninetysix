program drawMap;

uses
  uDebug,
  uTest,
  uVGADriver,
  uVESADriver,
  uUtils,
  crt,
  uScreen,
  uColor,
  uRect,
  uGraph32,
  uTimer;

var
  testPage: tPage;
  screen: tScreen;
  i: integer;
  dc: tDrawContext;

const
  ITERATIONS = 16;

procedure runFillTest(dc: tDrawContext; tag: string);
var
  i: integer;
  col: RGBA;
  backend: tDrawBackend;
begin
  for backend in [dbREF, dbMMX] do begin
    dc.backend := backend;
    for i := 0 to ITERATIONS-1 do begin
      col.init(rnd, rnd, rnd, rnd);
      startTimer(tag+'_'+BACKEND_NAME[backend]);
      dc.fillRect(Rect(rnd, rnd, 256, 256), col);
      stopTimer(tag+'_'+BACKEND_NAME[backend]);
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
  for backend in [dbREF, dbMMX] do begin
    dc.backend := backend;
    for i := 0 to ITERATIONS-1 do begin
      startTimer(tag+'_'+BACKEND_NAME[backend]);
      dc.drawImage(testPage, Point(rnd, rnd));
      stopTimer(tag+'_'+BACKEND_NAME[backend]);
      if (i mod 4 = 0) then begin
        screen.markRegion(screen.bounds);
        screen.flipAll();
      end;
    end;
  end;
end;

procedure runStretchTest(dc: tDrawContext; tag: string);
var
  i: integer;
  backend: tDrawBackend;
begin
  for backend in [dbREF, dbMMX] do begin
    dc.backend := backend;
    for i := 0 to (ITERATIONS div 2)-1 do begin
      startTimer(tag+'_'+BACKEND_NAME[backend]);
      dc.stretchSubImage(testPage, Rect(rnd, rnd, 256, 256), Rect(0,0,32,32));
      stopTimer(tag+'_'+BACKEND_NAME[backend]);
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

  videoDriver.setText();
  runTestSuites();

  videoDriver.setTrueColor(800, 600);
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;

  testPage := tPage.Create(256, 256);
  makePageRandom(testPage);

  startTimer('flip'); stopTimer('flip');

  dc := screen.canvas.getDC(bmBlit);
  runFillTest(dc, 'fill_blit');

  dc := screen.canvas.getDC(bmBlend);
  runFillTest(dc, 'fill_blend');

  dc := screen.canvas.getDC(bmBlit);
  runDrawTest(dc, 'draw_blit');

  dc := screen.canvas.getDC(bmBlit);
  dc.tint := RGB(255,128,64);
  runDrawTest(dc, 'draw_tint');

  dc := screen.canvas.getDC(bmBlend);
  dc.tint := RGB(255,128,64,128);
  runDrawTest(dc, 'blend');

  {this tests the fast path for a=255 pixels, as well as no tint}
  dc := screen.canvas.getDC(bmBlend);
  runDrawTest(dc, 'blend_fast');

  {this tests the fast path for a=255 pixels, as well as no tint}
  dc := screen.canvas.getDC(bmBlit);
  dc.textureFilter := tfNearest;
  runStretchTest(dc, 'stretch_nearest');

  dc := screen.canvas.getDC(bmBlit);
  dc.textureFilter := tfLinear;
  runStretchTest(dc, 'stretch_linear');

  videoDriver.setText();
  logTimers();
  printLog(32);

  readkey;

end.
