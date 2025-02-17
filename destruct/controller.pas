unit controller;

interface

uses
  {$i units},
  uTank,
  obj;

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
  public
    doFire: boolean;
    changeTank: integer;
    changeWeapon: integer;
    xVel, yVel: single;
    tank: tTank;
    target: tTank;
    constructor create(aTank: tTank);
    procedure reset(); virtual;
    procedure apply(elapsed: single);
    procedure process(); virtual;
  end;

  tNullController = class(tController)
  end;

  tHumanController = class(tController)
    procedure process(); override;
  end;

  tAIController = class(tController)
    solutionX, solutionY: single;
    state: tAIState;
    shotsFired: integer;
    procedure reset(); override;
    procedure process(); override;
  end;

implementation

uses
  game;

{--------------------------------------------}

constructor tController.create(aTank: tTank);
begin
  reset();
  tank := aTank;
end;

procedure tController.reset();
begin
  tank := nil;
  target := nil;
  changeWeaponCooldown := 0;
  changeTankCooldown := 0;
end;

procedure tController.apply(elapsed: single);
begin
  if doFire then tank.fire();
  tank.adjust(xVel * elapsed, yVel *elapsed);
  if (changeWeapon <> 0) then begin
    if (length(tank.weapons) > 0) and (changeWeaponCoolDown <= 0) then begin
      tank.weaponIdx := (tank.weaponIdx + changeWeapon) mod length(tank.weapons);
      if tank.weaponIdx < 0 then tank.weaponIdx += length(tank.weapons);
      changeWeaponCooldown := 0.5;
    end;
  end else
    changeWeaponCooldown := 0;
  changeWeaponCoolDown := maxf(0, changeWeaponCoolDown - elapsed);
  changeTankCoolDown := maxf(0, changeTankCoolDown - elapsed);
end;

procedure tController.process();
begin
  doFire := false;
  xVel := 0;
  yVel := 0;
  changeTank := 0;
  changeWeapon := 0;
end;

{--------------------------------------------}

procedure tHumanController.process();
begin
  inherited process();
  if keyDown(key_space) then doFire := true;
  if keyDown(key_left) then xVel := -100;
  if keyDown(key_right) then xVel := +100;
  if keyDown(key_up) then yVel := +10;
  if keyDown(key_down) then yVel := -10;
  if keyDown(Key_openSquareBracket) then changeWeapon := +1;
  if keyDown(Key_closeSquareBracket) then changeWeapon := -1;
end;

{--------------------------------------------}

procedure tAIController.reset();
begin
  solutionX := 0;
  solutionY := 0;
  shotsFired := 0;
  state := AI_SELECT_TARGET;
end;

procedure tAIController.process();
var
  delta, deltaX, deltaY: single;
begin
  inherited process();

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

  case state of
    AI_SELECT_TARGET: begin
      {hard code to tank2 for the moment}
      target := getTank(0, 1);
      if target.xPos > tank.xPos then solutionX := 45 else solutionX := -45;
      solutionY := 10;
      state := AI_AIMX;
    end;
    AI_AIMX: begin
      if target.status <> GO_ACTIVE then begin
        state := AI_IDLE;
        exit;
      end;
      delta := solutionX - tank.angle;
      xVel := clamp(delta*4, -50, 50);
      if abs(delta) < 1 then
        state := AI_AIMY;
    end;
    AI_AIMY: begin
      delta := solutionY - tank.power;
      yVel := clamp(delta, -5, 5);
      if abs(delta) < 0.1 then
        state := AI_FIRE;
    end;
    AI_FIRE: begin
      doFire := true;
      inc(shotsFired);
      state := AI_WAIT;
    end;
    AI_WAIT: begin
      case tank.lastProjectile.status of
        GO_EMPTY:
          // this shouldn't happen;
          state := AI_AIMX;
        GO_PENDING_DELETE: begin
          if tank.lastProjectile.vel.y < 0 then begin
            // we collided on the way up, so try to shoot over
            solutionY := clamp(solutionY + 2, 2, 16);
            if solutionX < 0 then solutionX += 10 else solutionX -= 10;
          end else begin
            // we collided on the way down so just adjust angle.
            deltaX := target.xPos - tank.lastProjectile.xPos;
            deltaY := target.yPos - tank.lastProjectile.yPos;
            solutionX += clamp(deltax/3 + deltay/5, -10, 10);
          end;
          state := AI_AIMX;
        end;
      end;
    end;
    AI_IDLE: begin
    end;
  end;
end;

begin
end.
