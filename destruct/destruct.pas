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

  tGameState = (GS_LOADING, GS_TITLE, GS_BATTLE, GS_EXIT);
  tSubState = (SS_INIT, SS_PLAYING, SS_ENDING);

type
  tGlobalState = class
    state: tGameState;
    subState: tSubState;
    roundTimer: single; {seconds round has been playing}
    endOfRoundTimer: single; {seconds until round terminates}
  end;


var
  gs: tGlobalState;
  gui: tGuiComponents;
  fpsLabel: tGuiLabel;
  startLabel, verLabel: tGuiLabel;
  player1Gui, player2Gui: tPlayerGUI;

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

procedure setupGUI();
begin
  gui := tGuiComponents.create();
  fpsLabel := tGuiLabel.create(Point(6, 3));
  gui.append(fpsLabel);

  player1Gui := tPlayerGUI.create(Point(0, 0), player1);
  player2Gui := tPlayerGUI.create(Point(160, 0), player2);
  gui.append(player1Gui);
  gui.append(player2Gui);

  {title stuff}
  startLabel := tGuiLabel.create(Point(160, 224));
  startLabel.centered := true;
  startLabel.text := 'Press any key to start';
  gui.append(startLabel);

  verLabel := tGuiLabel.create(Point(320-66, 240-8));
  verLabel.text := '0.4a (28/02/1996)';
  verLabel.textColor := RGB(128,128,128);
  gui.append(verLabel);

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

{-------------------------------------------}

procedure setupAIvsAI();
var
  tank: tTank;
begin
  for tank in tanks do begin
    tank.reset();
    tank.status := GO_EMPTY;
  end;

  tanks[0].init(findNewTankPosition(1), TEAM_1, CT_TANK);
  tanks[1].init(findNewTankPosition(1), TEAM_1, CT_LAUNCHER);
  tanks[2].init(findNewTankPosition(1), TEAM_1, CT_HEAVY);

  tanks[5].init(findNewTankPosition(2), TEAM_2, CT_TANK);
  tanks[6].init(findNewTankPosition(2), TEAM_2, CT_LAUNCHER);
  tanks[7].init(findNewTankPosition(2), TEAM_2, CT_HEAVY);

  for tank in tanks do
    if tank.isActive then tank.clearTerrain();

  if assigned(player1) then player1.free;
  if assigned(player2) then player2.free;
  player1 := tAIController.create(0);
  player2 := tAIController.create(5);

  {todo: hide gui}
end;

procedure setupHumanVsAI();
var
  tank: tTank;
begin
  for tank in tanks do begin
    tank.reset();
    tank.status := GO_EMPTY;
  end;

  tanks[0].init(findNewTankPosition(1), TEAM_1, CT_TANK);
  tanks[1].init(findNewTankPosition(1), TEAM_1, CT_LAUNCHER);
  tanks[2].init(findNewTankPosition(1), TEAM_1, CT_HEAVY);

  tanks[5].init(findNewTankPosition(2), TEAM_2, CT_HELI);
  tanks[6].init(findNewTankPosition(2), TEAM_2, CT_LAUNCHER);
  tanks[7].init(findNewTankPosition(2), TEAM_2, CT_HEAVY);

  for tank in tanks do
    if tank.isActive then tank.clearTerrain();

  if assigned(player1) then player1.free;
  if assigned(player2) then player2.free;
  player1 := tAIController.create(0);
  player2 := tHumanController.create(5);

end;

{-------------------------------------------}

procedure doDebugKeys(elapsed: single);
begin
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

  if keydown(key_z) then elapsed := 0.001;
    DEBUG_DRAW_BOUNDS := keydown(key_b);

end;

procedure doUpdate(elapsed: single);
begin
  startTimer('update');
  updateAll(elapsed);
  stopTimer('update');
  startTimer('updateTerrain');
  terrain.update(elapsed);
  stopTimer('updateTerrain');
  startTimer('guiUpdate');
  gui.update(elapsed);
  stopTimer('guiUpdate');

  startTimer('controller');
  player1.process(elapsed);
  player2.process(elapsed);
  player1.apply(elapsed);
  player2.apply(elapsed);
  stopTimer('controller');

  gs.roundTimer += elapsed;
end;

procedure doDraw(elapsed: single);
var
  screenFade: single;
begin
  startTimer('draw');
  drawAll(screen);
  stopTimer('draw');

  startTimer('drawTerrain');
  terrain.draw(screen);
  stopTimer('drawTerrain');

  startTimer('guiDraw');
  gui.draw(screen);
  stopTimer('guiDraw');

  {screen fading}
  screenFade := 0;
  if gs.roundTimer < 0.5 then
    screenFade := 1-(2*gs.roundTimer);
  if gs.endOfRoundTimer > 0 then
    screenFade := gs.endOfRoundTimer * 0.5;

  screenFade := clamp(screenFade, 0.0, 1.0);
  if screenFade = 1.0 then begin
    screen.canvas.clear(RGB(0,0,0));
    screen.markRegion(screen.bounds);
  end else if screenFade > 0 then begin
    screen.canvas.fillRect(screen.bounds, RGB(0,0,0,round(255*screenFade)));
    screen.markRegion(screen.bounds);
  end;

end;

procedure mainLoop();
var
  elapsed: single;
begin

  screen.background.clear(RGB(0,0,0));
  renderSky(terrain.sky);

  screen.pageClear();
  screen.pageFlip();

  setupGui();
  gs.state := GS_TITLE;
  gs.subState := SS_INIT;

  repeat

    startTimer('main');
    musicUpdate();

    elapsed := clamp(getTimer('main').elapsed, 0.001, 0.10);

    {update ui}
    if elapsed > 0 then
      fpsLabel.text := format('%f', [1/getTimer('main').avElapsed]);

    {handle resets}
    case gs.subState of
      SS_INIT: begin
        gs.roundTimer := 0;
        gs.endOfRoundTimer := 0;

        case gs.state of
          GS_TITLE: begin
            screen.fx := FX_NONE;
            terrain.generate(-16);
            setupAIvsAI();
            {note: would make sense to have a 'scene' with it's own ui to handle this}
            player1Gui.visible := false;
            player2Gui.visible := false;
            startLabel.visible := true;
            verLabel.visible := true;
            screen.fx := FX_NOISE;
          end;
          GS_BATTLE: begin
            screen.fx := FX_NONE;
            terrain.generate();
            setupHumanvsAI();
            player1Gui.visible := true;
            player2Gui.visible := true;
            startLabel.visible := false;
            verLabel.visible := false;
          end;
        end;
        gs.subState := SS_PLAYING;
      end;
    end;

    {special case for title screen}

    screen.clearAll();

    doUpdate(elapsed);
    doDraw(elapsed);

    case gs.state of
      GS_TITLE: begin
        screen.canvas.fillRect(Rect(0,0,320,32),RGB(0,0,0));
        screen.canvas.fillRect(Rect(0,240-32,320,32),RGB(0,0,0));
      end;
    end;

    screen.flipAll();

    {end of game detection}
    if (playerCount(TEAM_1)=0) or (playerCount(TEAM_2)=0) then
      gs.endOfRoundTimer += elapsed;
    if gs.endOfRoundTimer >= 2.0 then
      gs.subState := SS_INIT;

    if keyDown(key_esc) then gs.state := GS_EXIT;

    idle();

    stopTimer('main');

  until gs.state = GS_EXIT;

end;

begin

  CALL_OLD_KBH := false;

  gs := tGlobalState.create();
  gs.state := GS_LOADING;

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

  mainLoop();

  screenDone();
  logTimers();
  freeResources();

  printLog(32);

end.
