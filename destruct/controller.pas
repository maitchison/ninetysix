unit controller;

interface

uses
  {$i units},
  uTank,
  {$ifdef debug} mouse, {$endif}
  uGameObjects;

type
  tAIState = (
    AI_SELECT_TARGET,
    AI_AIMX,
    AI_AIMY,
    AI_FIRE,
    AI_WAIT,
    AI_IDLE
  );

type
  tController = class
  protected
    changeWeaponCooldown: single;
    changeTankCooldown: single;
    procedure cycleWeapon(delta: integer);
    procedure cycleTank(delta: integer);
  public
    doFire: boolean;
    changeTank: integer;
    changeWeapon: integer;
    xAction, yAction: single;
    tankIdx: integer;
    target: tTank;
    constructor create(aTankIdx: integer);
    procedure reset(); virtual;
    function  tank: tTank;
    procedure apply(elapsed: single);
    procedure process(elapsed: single); virtual;
  end;

  tNullController = class(tController)
  end;

  tHumanController = class(tController)
    procedure process(elapsed: single); override;
  end;

  tAIController = class(tController)
    solutionX, solutionY: single;
    state: tAIState;
    stateTimer: single;
    shotsFired: integer;
    errorX, errorY: integer;
    switchDelay, tickTimer: single;
    function firingSolution(dst: tPoint; v: single): single;
    procedure reset(); override;
    procedure process(elapsed: single); override;
  end;

implementation

uses
  game;

{--------------------------------------------}

constructor tController.create(aTankIdx: integer);
begin
  inherited create();
  reset();
  tankIdx := aTankIdx;
end;

procedure tController.reset();
begin
  tankIdx := 0;
  target := nil;
  changeWeaponCooldown := 0;
  changeTankCooldown := 0;
end;

procedure tController.cycleWeapon(delta: integer);
begin
  if (length(tank.weapons) <= 0) then exit;
  if (changeWeaponCoolDown > 0) then exit;
  tank.weaponIdx := (tank.weaponIdx + delta) mod length(tank.weapons);
  if tank.weaponIdx < 0 then tank.weaponIdx += length(tank.weapons);
  changeWeaponCooldown := 0.5;
end;

procedure tController.cycleTank(delta: integer);
var
  originalTank: tTank;
  i: integer;
  tankIsGood: boolean;
begin
  if (length(tanks.objects) <= 0) then exit;
  if (changeTankCoolDown > 0) then exit;

  changeTankCooldown := 0.5;

  originalTank := tanks[tankIdx];
  i := tankIdx;
  repeat
    inc(i);
    if i >= length(tanks.objects) then i := 0;
    if tanks[i] = originalTank then
      {we are the only valid tank}
      exit;
    tankIsGood := tanks[i].isActive and (tanks[i].team = originalTank.team);
    until tankIsGood;
  tankIdx := i;
end;

procedure tController.apply(elapsed: single);
begin

  {sometimes these are nan}
  if (xAction <> xAction) or (yAction <> yAction) then exit;

  if doFire then tank.fire();
  {this doesn't feel right... we should just set the control actions and
   not apply them. Then remove elapsed I think?}
  tank.applyControl(xAction, yAction, elapsed);

  if (changeWeapon <> 0) then
    cycleWeapon(changeWeapon)
  else
    changeWeaponCooldown := 0;

  if (changeTank <> 0) then
    cycleTank(changeTank)
  else
    changeTankCooldown := 0;

  changeWeaponCoolDown := maxf(0, changeWeaponCoolDown - elapsed);
  changeTankCoolDown := maxf(0, changeTankCoolDown - elapsed);
end;

procedure tController.process(elapsed: single);
begin
  doFire := false;
  xAction := 0;
  yAction := 0;
  changeTank := 0;
  changeWeapon := 0;
end;

function tController.tank: tTank;
begin
  if word(tankIdx) >= 10 then
    fatal('Invalid tank index, found %d', [tankIdx]);
  result := tanks[tankIdx];
end;

{--------------------------------------------}

procedure tHumanController.process(elapsed: single);
begin
  inherited process(elapsed);
  if keyDown(key_space) then doFire := true;
  if keyDown(key_left) then xAction := -100;
  if keyDown(key_right) then xAction := +100;
  if keyDown(key_up) then yAction := +100;
  if keyDown(key_down) then yAction := -100;
  if keyDown(Key_openSquareBracket) then changeWeapon := +1;
  if keyDown(Key_closeSquareBracket) then changeWeapon := -1;
  if keyDown(Key_n) then changeTank := +1;
end;

{--------------------------------------------}

procedure tAIController.reset();
begin
  inherited reset();
  solutionX := 0;
  solutionY := 0;
  shotsFired := 0;
  state := AI_SELECT_TARGET;
  stateTimer := 0;
  switchDelay := 0;
  errorX := 0;
  errorY := 0;
end;

{returns the angle tank should fire at to hit dst from src, assuming given power
 if no solution then return 0 (which would mean firing directly up)}
function tAIController.firingSolution(dst: tPoint; v: single): single;
var
  dX,dY: single;
  z1,z2,A,g: single;
  det: single;
  sln1, sln2: single;
  takeHighShot: boolean;

begin
  {balastic path is a parabola, parameterized by

    v_initial = -cos(theta)*vel
    v_t = v_initial + gravity * t
    y_t = 0.5 * gravity * t^2 + v_initial * t
    x_t = sin(theta) * t

    we know x_0, y_0, x_final, y_final and vel... so solve to find theta.
  }
  if not assigned(tank) then exit(0);
  dX := abs(dst.x-tank.pos.x);
  dY := (dst.y-tank.pos.y);
  g := game.GRAVITY;
  A := g * (dX*dX) / (2*v*v);
  det := (dX*dX) - (4 * A * (A-dY));
  if det < 0 then begin
    result := 0; // no solution!
    exit;
  end;

  z1 := (-dX + sqrt(det)) / (2*A);
  z2 := (-dX - sqrt(det)) / (2*A);
  //{solution has theta=0 being -> but we want it ^}
  sln1 := clamp(-(90+radToDeg(arcTan(z1))), -150.0, 150.0);
  sln2 := clamp(-(90+radToDeg(arcTan(z2))), -150.0, 150.0);

  {use the high shot, not the low shot}
  takeHighShot := not keyDown(key_x);
  if takeHighShot then
    {take high shot}
    if abs(sln1) < abs(sln2) then result := sln1 else result := sln2
  else
    {take low shot}
    if abs(sln1) > abs(sln2) then result := sln1 else result := sln2;

  if dst.x > tank.pos.x then result := -result;
end;

procedure tAIController.process(elapsed: single);
var
  delta: single;
  otherTeam: tTeam;
begin
  inherited process(elapsed);

  {work on an iterative firing solution}
  {
  How this works:
    The AI first select as target.
    It then starts with an intiail guess at a firing solution.
    It then applys a guess and check strategy as follows...
      Fire a bullet
      See where the bullet lands.
      If it collides doing up, then increase power and tilt up.
      If it collides when going down, then adjust angle based of if
        we were left or right of target.

    Note: we could update this so that we also take shots while waiting.
  }

  if tickTimer > 1 then begin
    // ticks occur every second}
    tickTimer := 0;
    errorX := round((rnd-128)/16);
    errorY := round((rnd-128)/16);
    case rnd(16) of
      0: begin changeTank := +1; doFire := false; target := nil; exit; end;
      1: changeWeapon := +1;
      2: target := nil;
    end;
  end;

  if not assigned(target) then begin
    stateTimer := 0;
    if tank.team = TEAM_1 then
      otherTeam := TEAM_2
    else
      otherTeam := TEAM_1;

    target := randomTank(otherTeam);

    switchDelay := rnd(10);

    if not assigned(target) then begin
      {nothing to shoot, stand at attention}
      delta := 0 - tank.angle;
      xAction := clamp(delta*100, -1, 1);
      exit;
    end;
    solutionY := 8+rnd(5);
    {todo: random weapon here?}
  end;

  stateTimer += elapsed;
  tickTimer += elapsed;

  {just fire all the time basically}
  doFire := (xAction < 10) and (yAction < 1) and (stateTimer > 1) and (abs(tank.angle)>1);
  solutionX := firingSolution(Point(errorX+target.xPos, errorY+target.yPos), 20*solutionY);
  delta := solutionX - tank.angle;
  xAction := clamp(delta*100, -1, 1);
  delta := solutionY - tank.power;
  yAction := clamp(delta*10, -1, 1);
end;

begin
end.
