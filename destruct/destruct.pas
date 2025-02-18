program destruct;

uses
  debug, test,
  {game specific}
  uTank, uWeapon, game, res, uGameObjects, terra, controller,
  {general}
  graph2d, graph32, vga, vesa,
  sprite, inifile,
  vertex,
  myMath,
  timer,
  ui,
  crt, //todo: remove
  keyboard,
  lc96, la96,
  mixlib,
  font, uScreen,
  utils;

type
  tTankGUI = class(tGuiComponent)
  public
    tank: tTank;
    sprite: tSprite;
  protected
    procedure doDraw(screen: tScreen); override;
  public
    constructor create(aPos: tPoint; aTank: tTank);
  end;

{-------------------------------------------}

procedure tTankGUI.doDraw(screen: tScreen);
var
  weapon: tWeaponSpec;
begin
  sprite.blit(screen.canvas, bounds.x, bounds.y);
  //screen.canvas.fillRect(bounds, RGB($FF730200));
  //screen.canvas.drawRect(bounds, RGB($FFFFB93C));
  weapon := tank.weapon;
  weapon.weaponSprite.draw(screen.canvas, bounds.x, bounds.y);
  textOutHalf(screen.canvas, bounds.x + 20, bounds.y + 3, weapon.tag, RGB(255, 255, 255));
  screen.markRegion(bounds);
end;

constructor tTankGUI.create(aPos: tPoint; aTank: tTank);
begin
  inherited create();
  tank := aTank;
  sprite := tankGuiSprite;
  bounds := Rect(aPos.x, aPos.y, sprite.width, sprite.height);
end;

{-------------------------------------------}

procedure titleScreen();
var
  exitFlag: boolean;
  gui: tGuiComponents;
  startLabel,verLabel: tGuiLabel;
  elapsed: single;
begin

  {load background and refresh screen}
  screen.background := tPage.create(320,240);
  tSprite.create(titleGFX).blit(screen.background, 0, -16);

  screen.background.fillRect(Rect(0,0,320,24),RGB(0,0,0));
  screen.background.fillRect(Rect(0,240-24,320,24),RGB(0,0,0));

  {setup gui}
  gui := tGuiComponents.create();
  startLabel := tGuiLabel.create(Point(160, 218));
  startLabel.centered := true;
  startLabel.text := 'Press any key to start';
  gui.append(startLabel);

  verLabel := tGuiLabel.create(Point(320-75, 26));
  verLabel.text := '0.1a (12/02/1996)';
  verLabel.halfSize := true;
  verLabel.textColor := RGB(255,255,255);
  gui.append(verLabel);

  screen.pageClear();

  exitFlag := false;

  {main loop}
  repeat

    musicUpdate();
    startTimer('main');
    screen.clearAll();

    elapsed := clamp(getTimer('main').elapsed, 0.001, 0.10);

    startLabel.textColor := RGB(
      round((sin(getSec)*64)+196),
      round((sin(2*getSec)*32)+128),
      20
    );
    gui.update(elapsed);
    gui.draw(screen);

    screen.flipAll();

    stopTimer('main');

    if anyKeyDown then exitFlag := true;

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

{look for a good place to put a new tank}
function findNewTankPosition(team: integer): integer;
var
  mask: array[0..255] of boolean;
  options: array[0..255] of byte;
  numOptions: integer;
  xStart: integer;
  xlp: integer;
  xPos: integer;
  tank: tTank;
begin

  fillchar(mask, sizeof(mask), true);
  for tank in tanks do begin
    if not tank.isActive then continue;
    for xlp := -12 to +12 do begin
      xPos := xlp + (tank.xPos);
      if (xPos < 0) or (xPos > 255) then continue;
      mask[xPos] := false;
    end;
  end;

  if team = 1 then xStart := 10 else xStart := 128+10;

  numOptions := 0;
  for xlp := xStart to xStart + 108 do begin
    if not mask[xlp] then continue;
    options[numOptions] := xlp;
    inc(numOptions);
  end;

  if numOptions = 0 then
    exit(xStart+random(108))
  else
    exit(options[random(numOptions)]);

end;

procedure battleScreen();
var
  exitFlag: boolean;
  go: tGameObject;
  tank: tTank;
  elapsed: single;
  gui: tGuiComponents;
  fps: tGuiLabel;
  xlp,ylp: integer;
  control1, control2: tController;
  testSprite: tSprite;
  m: tMatrix4x4;
  tank2Gui: tTankGUI;
begin

  screen.background := tPage.create(screen.width, screen.height);
  renderSky(screen.background);

  //testSprite := tSprite.create(titleGFX.scaled(255,255));
  //testSprite := tSprite.create(titleGFX);
  testSprite := tSprite.create(sprites.page);

  screen.pageClear();
  screen.pageFlip();

  exitFlag := false;

  terrain := tTerrain.create();
  terrain.generate();

  {setup players}
  for tank in tanks do begin
    tank.reset();
    tank.status := GO_EMPTY;
  end;

  tanks[0].init(findNewTankPosition(1), 1, CT_TANK);
  tanks[1].init(findNewTankPosition(1), 1, CT_LAUNCHER);
  tanks[2].init(findNewTankPosition(1), 1, CT_HEAVY);

  tanks[5].init(findNewTankPosition(2), 2, CT_TANK);
  tanks[6].init(findNewTankPosition(2), 2, CT_LAUNCHER);
  tanks[7].init(findNewTankPosition(2), 2, CT_HEAVY);

  for tank in tanks do
    if tank.status = GO_ACTIVE then
      tank.clearTerrain();

  {setup controllers}
  //control1 := tAIController.create(tank1);
  //control2 := tHumanController.create(tank2);

  {setup gui}
  gui := tGuiComponents.create();
  fps := tGuiLabel.create(Point(10, 10));
  gui.append(fps);

  tank2Gui := tTankGUI.create(Point(160, 0), tanks[5]);
  gui.append(tank2Gui);

  {main loop}
  repeat

    musicUpdate();
    startTimer('main');
    elapsed := clamp(getTimer('main').elapsed, 0.001, 0.10);

    if keydown(key_z) then elapsed := 0.001;

    {update ui}
    if elapsed > 0 then
      fps.text := format('%f', [1/elapsed]);

{    control1.process();
    control2.process();
    control1.apply(elapsed);
    control2.apply(elapsed);}

    screen.clearAll();

    startTimer('update');
    updateAll(elapsed);
    stopTimer('update');
    startTimer('draw');
    drawAll(screen);
    stopTimer('draw');

    startTimer('drawTerrain');
    terrain.draw(screen);
    stopTimer('drawTerrain');

    {gui}
    startTimer('guiUpdate');
    gui.update(elapsed);
    stopTimer('guiUpdate');
    startTimer('guiDraw');
    gui.draw(screen);
    stopTimer('guiDraw');

    screen.flipAll();

    stopTimer('main');

    if keyDown(key_esc) then exitFlag := true;

    idle();

  until exitFlag;

  terrain.free();

end;

var
  i: integer;
  mode: string;

begin

  CALL_OLD_KBH := false;

  autoHeapSize();

  textAttr := White + Blue*16;
  clrscr;

  debug.VERBOSE_SCREEN := llNote;

  runTestSuites();
  initKeyboard();

  loadResources();

  screenInit();
  musicPlay('res\dance1.a96');
  //titleScreen();
  battleScreen();
  screenDone();

  freeResources();
  logTimers();

  printLog(32);

end.
