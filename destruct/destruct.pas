program destruct;

uses
  debug, test,
  graph32, vga, vesa, screen,
  resLib,
  sprite, inifile,
  vertex,
  terrain, gameObj,
  myMath,
  timer,
  crt, //todo: remove
  keyboard,
  lc96,
  la96, mixlib,
  utils;

var
  screen: tScreen;

procedure titleScreen();
var
  exitFlag: boolean;
begin

  {load background and refresh screen}
  screen.background := titleGFX;

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
  c: RGBA;
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
      if (x < 32) or (x >= page.width-32) then begin
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
  c := RGB(255,255,255);
  for i := 0 to 300 do begin
    x := cx + (rnd()-128)*2;
    y := rnd() mod 200;
    a := 255-(y*2);
    if (x < 32) or (x >= page.width-32) then continue;

    c := RGB(255-(rnd div 2), 255-(rnd div 4), 255, a);

    page.putPixel(x,y,c);

    c.a := c.a div 2;
    for j := -1 to 1 do begin
      page.putPixel(x+j,y,c);
      page.putPixel(x,y+j,c);
    end;
  end;
end;

procedure battleScreen();
var
  exitFlag: boolean;
  bullet: tBullet;
  tank1, tank2: tTank;
  elapsed: single;
begin

  screen.background := tPage.create(screen.width, screen.height);
  renderSky(screen.background);

  screen.pageClear();
  screen.pageFlip();

  exitFlag := false;

  generateTerrain();

  {setup players}
  tank1 := tTank.create();
  tank2 := tTank.create();
  tank1.pos := V2(100, 150);
  tank2.pos := V2(200, 150);
  tanks.append(tank1);
  tanks.append(tank2);

  {main loop}
  repeat

    musicUpdate();

    startTimer('main');

    elapsed := clamp(getTimer('main').elapsed, 0.01, 0.10);

    {input}
    if keyDown(key_space) then
      tank2.fire();
    if keyDown(key_left) then
      tank2.adjust(-90*elapsed, 0);
    if keyDown(key_right) then
      tank2.adjust(+90*elapsed, 0);
    if keyDown(key_up) then
      tank2.adjust(0, +10*elapsed);
    if keyDown(key_down) then
      tank2.adjust(0, -10*elapsed);

    screen.clearAll();
    drawTerrain(screen);

    tanks.update(elapsed);
    bullets.update(elapsed);
    tanks.draw(screen);
    bullets.draw(screen);

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

  loadResources();

  screenInit();
  musicPlay('res\dance1.a96');
  battleScreen();
  screenDone();

end.
