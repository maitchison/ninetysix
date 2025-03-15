program destruct;

uses
  uDebug,
  uTest,
  {$i gui.inc}
  {game specific}
  uTank,
  uWeapon,
  game,
  res,
  uGameObjects,
  terraNova,
  controller,
  {general}
  uRect,
  uColor,
  uGraph32,
  uVGADriver, uVESADriver,
  uInput,
  uInfo,
  uSprite,
  uInifile,
  uVertex,
  uMath,
  uTimer,
  fx,
  crt, //todo: remove
  cfd,
  uKeyboard,
  uLA96, uLP96,
  uMixer,
  uMouse,
  uFont,
  uScreen,
  uUtils;

type
  tPlayerGUI = class(tGuiComponent)
  public
    player: tController;
    sprite: tSprite;
  protected
    procedure doDraw(dc: tDrawContext); override;
  public
    constructor create(aPos: tPoint; aPlayer: tController);
  end;

  tGameState = (GS_LOADING, GS_TITLE, GS_BATTLE, GS_EXIT);
  tSubState = (SS_INIT, SS_PLAYING, SS_ENDING);

type
  tGlobalState = class
    state: tGameState;
    nextState: tGameState;
    subState: tSubState;
    roundTimer: single; {seconds round has been playing}
    endOfRoundTimer: single; {seconds until round terminates}
  end;


var
  gs: tGlobalState;
  gui: tGui;
  fpsLabel: tGuiLabel;
  startLabel, verLabel: tGuiLabel;
  player1Gui, player2Gui: tPlayerGUI;

{-------------------------------------------}

procedure tPlayerGUI.doDraw(dc: tDrawContext);
var
  weapon: tWeaponSpec;
begin
  dc.blendMode := bmBlit;
  sprite.draw(dc, bounds.x, bounds.y);
  weapon := player.tank.weapon;
  dc.blendMode := bmBlend;
  weapon.weaponSprite.draw(dc, bounds.x + 9, bounds.y + 9);
  font.textOut(dc.page, dc.offset.x+bounds.x + 20, dc.offset.y+bounds.y + 5, weapon.tag, RGB(255, 255, 255));
  dc.markRegion(bounds);
end;

constructor tPlayerGUI.create(aPos: tPoint; aPlayer: tController);
begin
  inherited create();
  player := aPlayer;
  sprite := tankGuiSprite;
  setBounds(Rect(aPos.x, aPos.y, sprite.width, sprite.height));
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
  gui := tGui.Create();
  fpsLabel := tGuiLabel.MakeText(Point(6, 6));
  fpsLabel.fontStyle.shadow := false;
  gui.append(fpsLabel);

  player1Gui := tPlayerGUI.Create(Point(0, 0), player1);
  player2Gui := tPlayerGUI.Create(Point(160, 0), player2);
  gui.append(player1Gui);
  gui.append(player2Gui);

  {title stuff}
  startLabel := tGuiLabel.MakeText(Point(160, 240-20));
  startLabel.fontStyle.centered := true;
  startLabel.fontStyle.shadow := true;
  startLabel.text := 'Press any key to start';
  gui.append(startLabel);

  verLabel := tGuiLabel.MakeText(Point(320-100, 6));
  verLabel.text := '0.3a (01/03/1996)';
  verLabel.textColor := RGB(228,228,238);
  verLabel.fontStyle.shadow := false;
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

  {todo: seperate out player and controller, so we can perm link to player1}
  if assigned(player1) then player1.free;
  if assigned(player2) then player2.free;
  player1 := tAIController.create(0);
  player2 := tAIController.create(5);
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
var
  dc: tDrawContext;
  p: tPoint;
begin
  dc := screen.getDC();
  dc.offset.x := 32;
  p := Point(input.mouseX-dc.offset.x, input.mouseY-dc.offset.y);

  if keyDown(key_f5) then debugShowWorldPixels(dc);
  if keyDown(key_f4) then
    screen.pageFlip();

  if keyDown(key_1) then
    terrain.burn(p.x, p.y, 20, 3);
  if keyDown(key_2) then
    terrain.putCircle(p.x, p.y, 20, DT_SAND);
  if keyDown(key_3) then
    terrain.putCircle(p.x, p.y, 15, DT_LAVA);
  if keyDown(key_4) then
    makeDust(p.x, p.y, 20, DT_SAND, 25.0, 0, 0, elapsed);
  if keyDown(key_8) then
    doBump(p.x, p.y, 30, 50);

  if keyDown(key_9) then
    makeSparks(p.x, p.y, 20, 100, 0, 0, round(1000*elapsed));

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

procedure doDraw(dc: tDrawContext);
var
  screenFade: single;
  y: integer;
  oldFlags: byte;
  backgroundDC: tDrawContext;
  screenDC: tDrawContext;
begin
  startTimer('draw');
  drawAll(dc);
  stopTimer('draw');

  startTimer('drawTerrain');
  backgroundDC := screen.getBackgroundDC();
  backgroundDC.offset := dc.offset;
  terrain.draw(backgroundDC);
  stopTimer('drawTerrain');

  {special case}
  if gs.state = GS_TITLE then begin
    oldFlags := dc.clearFlags;
    dc.clearFlags := 0; // turn this off, as otherwise it'd be slow
    for y := 0 to 240 do begin
      case y and $3 of
        0: dc.fillRect(rect(0,y,256,1), RGB(0,128,0,96));
        1: dc.fillRect(rect(0,y,256,1), RGB(0,128,0,64));
        2: dc.fillRect(rect(0,y,256,1), RGB(0,128,0,96));
        3: dc.fillRect(rect(0,y,256,1), RGB(0,128,0,64));
      end;
    end;
    dc.clearFlags := oldFlags;
    screen.markRegion(screen.bounds);
  end;

  startTimer('guiDraw');
  gui.draw(screen.getDC());
  stopTimer('guiDraw');

  {screen fading}
  screenFade := 0;
  if gs.roundTimer < 0.5 then
    screenFade := 1-(2*gs.roundTimer);
  if (gs.subState = SS_ENDING) and (gs.endOfRoundTimer > 0) then
    screenFade := 1.0-gs.endOfRoundTimer;

  screenFade := clamp(screenFade, 0.0, 1.0);
  if screenFade = 1.0 then begin
    dc.fillRect(screen.bounds, RGB(0,0,0));
  end else if screenFade > 0 then begin
    dc.fillRect(screen.bounds, RGB(0,0,0,round(255*screenFade)));
  end;

end;

procedure mainLoop();
var
  elapsed: single;
  dc: tDrawContext;
begin

  screen.background.clear(RGB(0,0,0));
  renderSky(terrain.sky);

  screen.pageClear();
  screen.pageFlip();

  setupGui();
  gs.state := GS_TITLE;
  gs.nextState := GS_TITLE;
  gs.subState := SS_INIT;

  dc := screen.getDC();
  dc.offset.x := 32;

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
        gs.endOfRoundTimer := 1.0;
        case gs.state of
          GS_TITLE: begin
            terrain.generate(-16);
            setupAIvsAI();
            {note: would make sense to have a 'scene' with it's own ui to handle this}
            player1Gui.isVisible := false;
            player2Gui.isVisible := false;
            startLabel.isVisible := true;
            verLabel.isVisible := true;
          end;
          GS_BATTLE: begin
            terrain.generate();
            setupHumanvsAI();
            player1Gui.isVisible := true;
            player2Gui.isVisible := true;
            startLabel.isVisible := false;
            verLabel.isVisible := false;
          end;
        end;
        {todo: it's annoying to do this, make 'player' and a 'controller'}
        player1Gui.player := player1;
        player2Gui.player := player2;
        gs.subState := SS_PLAYING;
      end;
    end;

    case gs.state of
      GS_TITLE: begin
        if (gs.subState=SS_PLAYING) and anyKeyDown then begin
          gs.subState := SS_ENDING;
          gs.nextState := GS_BATTLE;
        end;
        startLabel.textColor.init(round((sin(getSec)*64)+196), round((sin(2*getSec)*32)+128), 20);
      end;
      GS_BATTLE: begin
        doDebugKeys(elapsed);
      end;
    end;

    screen.clearAll();

    doUpdate(elapsed);
    doDraw(dc);

    screen.flipAll();

    {end of game detection}
    if (gs.subState = SS_PLAYING) and (playerCount(TEAM_1)=0) or (playerCount(TEAM_2)=0) then
      gs.subState := SS_ENDING;

    if (gs.subState = SS_ENDING) then begin
      gs.endOfRoundTimer -= elapsed;
      if gs.endOfRoundTimer <= 0 then begin
        gs.subState := SS_INIT;
        gs.state := gs.nextState;
      end;
    end;

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

  uDebug.VERBOSE_SCREEN := llNote;

  {setup gui}
  uGui.GUI_HQ := false;
  uGui.GUI_DOUBLEBUFFER := false;

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
