program destruct;

uses
  debug, test,
  {game specific}
  uTank, uWeapon, game, res, uGameObjects, terraNova, controller,
  {general}
  graph2d, graph32, vga, vesa,
  sysInfo,
  sprite, inifile,
  vertex,
  myMath,
  timer,
  ui,
  fx,
  crt, //todo: remove
  cfd,
  keyboard,
  lc96, la96,
  mixlib,
  mouse,
  font, uScreen,
  utils;

type
  tPlayerGUI = class(tGuiComponent)
  public
    player: tController;
    sprite: tSprite;
  protected
    procedure doDraw(screen: tScreen); override;
  public
    constructor create(aPos: tPoint; aPlayer: tController);
  end;


{-------------------------------------------}

procedure tPlayerGUI.doDraw(screen: tScreen);
var
  weapon: tWeaponSpec;
begin
  sprite.blit(screen.canvas, bounds.x, bounds.y);
  weapon := player.tank.weapon;
  weapon.weaponSprite.draw(screen.canvas, bounds.x + 9, bounds.y + 9);
  font.textOut(screen.canvas, bounds.x + 20, bounds.y + 5, weapon.tag, RGB(255, 255, 255));
  screen.markRegion(bounds);
end;

constructor tPlayerGUI.create(aPos: tPoint; aPlayer: tController);
begin
  inherited create();
  player := aPlayer;
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
  startLabel := tGuiLabel.create(Point(160, 224));
  startLabel.centered := true;
  startLabel.text := 'Press any key to start';
  gui.append(startLabel);

  verLabel := tGuiLabel.create(Point(320-66, 240-8));
  verLabel.text := '0.3a (28/02/1996)';
  verLabel.textColor := RGB(128,128,128);
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

procedure cfdScreen();
var
  cg: tCFDGrid;
  fpsLabel, densityLabel: tGuiLabel;
  gui: tGuiComponents;
  elapsed: single;
  ofsX, ofsY: integer;
  timeUntilNextUpdate: single;
begin
  //cg := tDiffusionGrid.create();
  cg := tMethod2Grid.create();
  //cg := tLatticeBoltzmannGrid.create();
  cg.init();


  gui := tGuiComponents.create();
  fpsLabel := tGuiLabel.create(Point(10, 10));
  gui.append(fpsLabel);
  densityLabel := tGuiLabel.create(Point(10, 200));
  gui.append(densityLabel);


  ofsX := (320-128) div 2;
  ofsY := (240-128) div 2;

  timeUntilNextUpdate := 0;

  {main loop}
  repeat
    startTimer('main');

    screen.clearAll();

    elapsed := clamp(getTimer('main').elapsed, 0.001, 1.0);

    gui.update(elapsed);
    gui.draw(screen);

    if (MOUSE_B = 1) then
      cg.addDensity(mouse_x-ofsX, mouse_y-ofsY, clamp(100*elapsed, 0, 1))
    else
      densityLabel.text := format('%.3f', [cg.getDensity(mouse_x-ofsX, mouse_y-ofsY)]);

    timeUntilNextUpdate -= elapsed;
    if timeUntilNextUpdate <= 0 then begin
      startTimer('cfd');
      cg.update();
      stopTimer('cfd');
      fpsLabel.text := format('CFD: %fms', [1000*getTimer('cfd').avElapsed]);
      timeUntilNextUpdate := 1/30;
    end;

    cg.draw(screen, ofsX, ofsY);

    screen.pageFlip();
    stopTimer('main');
  until keyDown(key_esc);

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
function findNewTankPosition(team: integer): tPoint;
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
      xPos := xlp + tank.xPos;
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
    result.x := xStart+random(108)
  else
    result.x := options[random(numOptions)];

  {find y pos}
  result.y := 255-terrain.getTerrainHeight(result.x)-5;

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
  testSprite: tSprite;
  m: tMatrix4x4;
  player1Gui,
  player2Gui: tPlayerGUI;
  sky: tPage;
begin

  screen.background := tPage.create(screen.width, screen.height);
  renderSky(terrain.sky);

  //testSprite := tSprite.create(titleGFX.scaled(255,255));
  //testSprite := tSprite.create(titleGFX);
  testSprite := tSprite.create(sprites.page);

  screen.pageClear();
  screen.pageFlip();

  exitFlag := false;

  terrain.generate();

  {setup players}
  for tank in tanks do begin
    tank.reset();
    tank.status := GO_EMPTY;
  end;

  tanks[0].init(findNewTankPosition(1), TEAM_1, CT_TANK);
  tanks[1].init(findNewTankPosition(1), TEAM_1, CT_LAUNCHER);
  tanks[2].init(findNewTankPosition(1), TEAM_1, CT_HEAVY);

  tanks[5].init(findNewTankPosition(2), TEAM_2, CT_HELI);
  //tanks[5].init(findNewTankPosition(2), TEAM_2, CT_TANK);
{  tanks[6].init(findNewTankPosition(2), TEAM_2, CT_LAUNCHER);
  tanks[7].init(findNewTankPosition(2), TEAM_2, CT_HEAVY);}

  for tank in tanks do
    if tank.isActive then tank.clearTerrain();

  {setup controllers}
  player1 := tAIController.create(0);
  player2 := tHumanController.create(5);

  {setup gui}
  gui := tGuiComponents.create();
  fps := tGuiLabel.create(Point(6, 20));
  gui.append(fps);

  player1Gui := tPlayerGUI.create(Point(0, 0), player1);
  gui.append(player1Gui);
  player2Gui := tPlayerGUI.create(Point(160, 0), player2);
  gui.append(player2Gui);

  {main loop}
  repeat

    musicUpdate();
    startTimer('main');
    elapsed := clamp(getTimer('main').elapsed, 0.001, 0.10);

    if keydown(key_z) then elapsed := 0.001;
    DEBUG_DRAW_BOUNDS := keydown(key_b);

    {update ui}
    if elapsed > 0 then
      fps.text := format('%f', [1/getTimer('main').avElapsed]);

    {stub:}
    //player1.process(elapsed);
    player2.process(elapsed);
    //player1.apply(elapsed);
    player2.apply(elapsed);

    screen.clearAll();

    startTimer('update');
    updateAll(elapsed);
    stopTimer('update');

    startTimer('draw');
    drawAll(screen);
    stopTimer('draw');

    startTimer('updateTerrain');
    terrain.update(elapsed);
    stopTimer('updateTerrain');

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

    {debug}
    if keyDown(key_f5) then debugShowWorldPixels(screen);
    if keyDown(key_f4) then
      screen.pageFlip();

    if keyDown(key_1) then
      terrain.burn(mouse_x-VIEWPORT_X, mouse_y-VIEWPORT_Y, 20, 3);
    if keyDown(key_2) then
      terrain.putCircle(mouse_x-VIEWPORT_X, mouse_y-VIEWPORT_Y, 20, DT_SAND);
    if keyDown(key_3) then
      terrain.putCircle(mouse_x-VIEWPORT_X, mouse_y-VIEWPORT_Y, 20, DT_LAVA);
    if keyDown(key_4) then
      makeDust(mouse_x-VIEWPORT_X, mouse_y-VIEWPORT_Y, 20, DT_SAND, 25.0, 0, 0, elapsed);
    if keyDown(key_8) then
      doBump(mouse_x-VIEWPORT_X, mouse_y-VIEWPORT_Y, 30, 50);


    if keyDown(key_9) then
      makeSparks(mouse_x-VIEWPORT_X, mouse_y-VIEWPORT_Y, 20, 100, 0, 0, round(1000*elapsed));

    screen.flipAll();

    stopTimer('main');

    if keyDown(key_esc) then exitFlag := true;

    idle();

  until exitFlag;

end;

var
  i: integer;
  mode: string;

begin

  CALL_OLD_KBH := false;

  {show useful stuff}
  cpuInfo.printToLog();
  logDPMIInfo();

  autoHeapSize();

  textAttr := White + Blue*16;
  clrscr;

  debug.VERBOSE_SCREEN := llNote;

  runTestSuites();
  initKeyboard();

  loadResources();

  screenInit();
  musicPlay('res\dance1.a96');
  initMouse();
  titleScreen();
  battleScreen();
  //cfdScreen();
  screenDone();

  logTimers();
  freeResources();

  printLog(32);

end.
