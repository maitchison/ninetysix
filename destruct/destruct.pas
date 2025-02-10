program destruct;

uses
  debug, test,
  graph32, vga, vesa, screen,
  myMath,
  timer,
  crt, //todo: remove
  keyboard,
  lc96,
  la96, mixlib,
  utils;

var
  screen: tScreen;

  terrain: array[0..255, 0..255] of byte;

procedure titleScreen();
var
  exitFlag: boolean;
begin

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

end;

procedure renderSky(page: tPage);
var
  dx, dy, x, y, i, j: integer;
  cx,cy: integer;
  r: single;
  a: integer;
  theta: single;
const
  sky1: array of dword = [
    $2f1628,
    $2d1929,
    $2b1d2f,
    $282c40,
    $285978,
    $ce8363,
    $fdfc86
  ];

  function cmap(z: single): RGBA;
  begin
    if z < 0 then z := 0;
    if z > 1 then z := 1;
    z *= 6;
    result := RGBA.Lerp(RGB(sky1[floor(z)]), RGB(sky1[ceil(z)]), frac(z));
    result.a := 255;
  end;

begin
  cx := page.width div 2;
  cy := page.height * 5;
  for y := 0 to page.height-1 do begin
    for x := 0 to page.width-1 do begin
      if (x < 32) or (x > page.width-31) then begin
        page.setPixel(x,y, RGB(0,0,0));
        continue;
      end;
      dx := x-cx;
      dy := y-cy;
      r := sqrt(sqr(dx) + sqr(dy)) / page.height;
      theta := arcTan2(dy, dx);
      r += 0.003*sin(3+theta*97) - 0.007*cos(2+theta*3) + 0.005*sin(1+theta*23);
      page.putPixel(x,y, cmap(5-r));
    end;
  end;
  {stars}
  for i := 0 to 300 do begin
    x := cx + (rnd()-128)*2;
    y := rnd() mod 200;
    a := 255-(y*2);
    page.putPixel(x,y,RGB(255,255,255,a));
    for j := -1 to 1 do begin
      page.putPixel(x+j,y,RGB(255,255,255,a div 2));
      page.putPixel(x,y+j,RGB(255,255,255,a div 2));
    end;
  end;
end;

procedure generateTerrain();
var
  mapHeight: array[0..255] of integer;
  x,y: integer;
begin
  fillchar(terrain, sizeof(terrain), 0);
  for x := 0 to 255 do
    mapHeight[x] := 128 + round(30*sin(3+x*0.0197) - 67*cos(2+x*0.003) + 15*sin(1+x*0.023));
  for y := 0 to 255 do
    for x := 0 to 255 do begin
      if y > mapHeight[x] then terrain[y,x] := 1;
    end;
end;

procedure drawTerrain();
var
  c: RGBA;
  x,y: integer;
begin
  c.from32($8d7044);
  for y := 0 to 255 do
    for x := 0 to 255 do
      if terrain[y,x] <> 0 then screen.canvas.setPixel(32+x,y,c);
end;


procedure battleScreen();
var
  exitFlag: boolean;
begin

  {music}
  musicPlay('res\dance1.a96');

  screen.background := tPage.Load('res\title2_320.p96');
  renderSky(screen.background);

  screen.pageClear();
  screen.pageFlip();


  exitFlag := false;

  generateTerrain();

  {main loop}
  repeat

    musicUpdate();

    startTimer('main');

    screen.clearAll();
    drawTerrain();
    screen.flipAll();

    stopTimer('main');

    if keyDown(key_esc) then exitFlag := true;

    idle();

  until exitFlag;

end;

procedure screenInit();
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
end;

procedure screenDone();
begin
  videoDriver.setText();
  textAttr := LIGHTGRAY;
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

  screenInit();
  battleScreen();
  screenDone();

end.
