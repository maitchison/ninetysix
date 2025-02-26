unit uTank;

interface

uses
  {$i units},
  uWeapon, uGameObjects;

type

  tTank = class;

  tChassisType = (
    CT_NULL,
    CT_TANK,
    CT_LAUNCHER,
    CT_HEAVY,
    CT_HELI
  );

  tAnimationType = (
    AT_NONE, // static sprite
    AT_TANK, // tank with aim and flip
    AT_HELI  // helicopter animation
  );

  tChassis = record
    tag: string;
    chassisType: tChassisType;
    animationType: tAnimationType;
    health: integer;
    baseSpriteIdx: integer;
    defaultWeapons: array of tWeaponType;
  end;

  tTeam = (TEAM_1, TEAM_2);

  tTank = class(tGameObject)
  protected
    spriteSheet: tSpriteSheet;
    procedure fireProjectile();
    procedure fireLaser();
  public
    team: tTeam;
    weapons: array of tWeaponSpec;
    chassis: tChassis;
    cooldown: single;
    angle: single;
    power: single;
    health: integer;
    lastProjectile: tProjectile;
    weaponIdx: integer;
  protected
    procedure updateAnimation();
    procedure updateTankCollision(elapsed:single);
    procedure updateHeliCollision(elapsed:single);
  public
    function  weapon: tWeaponSpec;
    procedure init(aPos: tPoint; aTeam: tTeam; aChassisType: tChassisType);
    function  isSelected: boolean;
    procedure clearTerrain();
    procedure applyChassis(aChassis: tChassis);
    procedure reset(); override;
    procedure update(elapsed: single); override;
    procedure draw(screen: tScreen); override;
    procedure applyControl(xAction, yAction: single; elapsed: single);
    procedure adjustAim(deltaAngle, deltaPower: single);
    procedure takeDamage(atX,atY: integer; damage: integer;sender: tObject=nil);
    procedure explode();
    procedure fire();
  end;

const
  CHASSIS_DEF: array[tChassisType] of tChassis = (
    (
      tag: 'Null';
      chassisType: CT_NULL;
      animationType: AT_NONE;
      health: 0;
      baseSpriteIdx: 0;
      defaultWeapons: []
    ),
    (
      tag: 'Tank';
      chassisType: CT_TANK;
      animationType: AT_TANK;
      health: 350;
      baseSpriteIdx: 0;
      defaultWeapons: [
        tWeaponType.tracer,
        tWeaponType.blast,
        tWeaponType.smallDirt,
        tWeaponType.largeDirt
      ]
    ),
    (
      tag: 'Launcher';
      chassisType: CT_LAUNCHER;
      animationType: AT_TANK;
      health: 200;
      baseSpriteIdx: 5;
      defaultWeapons: [
        tWeaponType.microNuke,
        tWeaponType.miniNuke
      ];
    ),
    (
      tag: 'Heavy Tank';
      chassisType: CT_HEAVY;
      animationType: AT_TANK;
      health: 700;
      baseSpriteIdx: 10;
      defaultWeapons: [
        tWeaponType.blast,
        tWeaponType.megaBlast,
        tWeaponType.plasma
      ];
    ),
    (
      tag: 'Helicopter';
      chassisType: CT_HELI;
      animationType: AT_HELI;
      health: 700;
      baseSpriteIdx: 16*8;
      defaultWeapons: [
        tWeaponType.blast,
        tWeaponType.megaBlast,
        tWeaponType.plasma
      ];
    )
  );

implementation

uses
  fx, terraNova, res, game;

const
  DEBUG_SHOW_TANK_SUPPORT = false;

{-----------------------------------------------------------}

{initializes tank to given chassis and team.
 yPosition defaults to ground level.}
procedure tTank.init(aPos: tPoint; aTeam: tTeam; aChassisType: tChassisType);
begin
  note('Initializing tank at position %s', [aPos.toString]);
  reset();
  status := GO_ACTIVE;
  pos.x := aPos.x;
  pos.y := aPos.y;
  team := aTeam;
  applyChassis(CHASSIS_DEF[aChassisType]);
end;

{selects corect sprite for tank}
procedure tTank.updateAnimation();
var
  spriteIdx: integer;
  angleFrame: integer;
begin
  spriteIdx := chassis.baseSpriteIdx;
  if team = TEAM_2 then spriteIdx += 16;

  case chassis.animationType of
    AT_NONE: ;
    AT_TANK: begin
      spriteIdx += clamp(round((90-abs(angle)) * 5 / 90), 0, 4);
    end;
    AT_HELI: begin
      spriteIdx += (gameTick div 8) and $3;
    end;
  end;

  sprite := spriteSheet.sprites[spriteIdx];

end;

function tTank.isSelected: boolean;
begin
  result :=
    (assigned(player1) and (player1.tank = self)) or
    (assigned(player2) and (player2.tank = self));
end;

{remove and terrain around this tank}
procedure tTank.clearTerrain();
begin
  terrain.burn(xPos, yPos, 10, 100);
  // per pixel version
  (*
  if not assigned(sprite) then exit;
  for y := 0 to sprite.height-1 do begin
    for x := 0 to sprite.width-1 do begin
      if sprite.getPixel(x, y).a = 0 then continue;
      {note: this should be -sprite.pivot... but it seems to not be set?}
      terrain.burn(x + xPos-8, y + yPos-8, 4, 50);
    end;
  end;
  *)
end;

procedure tTank.applyChassis(aChassis: tChassis);
var
  i: integer;
begin
  self.chassis := aChassis;
  self.health := aChassis.health;
  setLength(self.weapons, length(aChassis.defaultWeapons));
  for i := 0 to length(aChassis.defaultWeapons)-1 do
    self.weapons[i] := WEAPON_SPEC[aChassis.defaultWeapons[i]];
  self.updateAnimation();
end;

procedure tTank.reset();
begin
  inherited reset();
  weaponIdx := 0;
  angle := 0;
  power := 10;
  health := 500;
  fillchar(chassis, sizeof(chassis), 0);
  col := RGB(255,255,255);
  spriteSheet := res.sprites;
  sprite := nil; // will be set on update
end;

procedure tTank.draw(screen: tScreen);
var
  p: tPoint;
  r: tRect;
  markerColor: RGBA;
begin

  if not assigned(sprite) then exit;

  p := Point(xPos+32, yPos);

  if (angle > 0) and (chassis.animationType = AT_TANK) then
    r := sprite.drawFlipped(screen.canvas, p.x, p.y)
  else
    r := sprite.draw(screen.canvas, p.x, p.y);

  screen.markRegion(r);

  {marker}
  if isSelected then
    markerColor.init(255, 255, 128)
  else
    markerColor.init(128,128,128);

  {draw target}
  drawMarker(
    screen,
    xPos + sin(angle*DEG2RAD) * power * 2,
    yPos - cos(angle*DEG2RAD) * power * 2,
    markerColor
  );
end;

procedure tTank.updateTankCollision(elapsed: single);
var
  support: integer;
  i, x, y, xlp, ylp: integer;
  bounds: tRect;
  hitPower: integer;
  p: tParticle;
  fallSpeed: single;
begin

  support := 0;
  bounds := Rect(xPos-8, yPos-8, 16, 16);

  {todo: these insets should not be hard coded, better to check pixels of
   texture, or maybe specify as part of the tank}
  for xlp := bounds.left+3 to bounds.right-3 do begin
    if DEBUG_SHOW_TANK_SUPPORT then
      screen.canvas.putPixel(xlp, bounds.bottom-3, RGB(255,0,255));
    if terrain.isSolid(xlp, bounds.bottom-3) then inc(support);
  end;

  if support = 0 then begin
    vel.y += GRAVITY * elapsed;
    exit;
  end;

  {falling...}
  if vel.y > 0 then begin
    hitPower := round(10*vel.y);
    {weaken blocks holding us up}
    y := bounds.bottom;
    for x := bounds.left+3 to bounds.right-3 do begin
      {make a little cloud}
      for i := 1 to 1 do begin
        p := nextParticle();
        p.pos := V2(x, y);
        p.vel := V2(rnd-128, rnd-128) * 0.2;
        p.solid := true;
        //p.col := terrain.dirtColor.getPixel(x, y);
        //if p.col.a = 0 then p.col := RGB(200,200,200);
        p.col := RGB(128,128,128);
        p.ttl := 0.25;
        p.radius := 1;
      end;
      {burn it}
      terrain.burn(x, bounds.bottom-3, 2, round(hitPower/support/16));
    end;
    vel.y := 0;
  end;
end;

procedure tTank.updateHeliCollision(elapsed: single);
var
  support: integer;
  i, x, y, xlp, ylp: integer;
  bounds: tRect;
  hitPower: integer;
  p: tParticle;
  dx,dy: integer;
  delta: V2D;
begin

  support := 0;
  bounds := Rect(xPos-8, yPos-8, 16, 16);

  {always falling a little bit}
  vel.y += (GRAVITY/4) * elapsed;

  {heli needs a full check}
  {todo could be faster if we trim the bounds to sprite}
  for ylp := bounds.top+3 to bounds.bottom-3 do begin
    for xlp := bounds.left+3 to bounds.right-3 do begin
      if (getWorldPixel(xlp, ylp).a > 0) and (terrain.isSolid(xlp, ylp)) then begin
        {bump}
        delta := V2(xlp - xPos, ylp - yPos) * 0.5;
        vel -= delta;

        {create cloud}
        p := nextParticle();
        p.pos := V2(xlp, ylp);
        p.vel := V2(rnd-128, rnd-128) * 0.1;
        p.vel -= delta;
        p.solid := false;
        p.col := RGB(128,128,128);
        p.ttl := 0.25;
        p.radius := 1;
      end;
    end;
  end;
end;

procedure tTank.update(elapsed: single);
var
  xlp: integer;
  x,y: integer;
  support: integer;
  hitPower: integer;
  p: tParticle;
  i: integer;
  bounds: tRect;
  drag: V2D;
begin

  {enforce a strict speed limit}
  vel.x := clamp(vel.x, -500, 500);
  vel.y := clamp(vel.y, -500, 500);

  {inherited update stuff}
  inherited update(elapsed);

  if cooldown > 0 then cooldown -= elapsed;

  updateAnimation();
  case chassis.animationType of
    AT_NONE: ;
    AT_TANK: updateTankCollision(elapsed);
    AT_HELI: updateHeliCollision(elapsed);
  end;
end;

{---------------}

function tTank.weapon(): tWeaponSpec;
begin
  if length(weapons) = 0 then
    result := WEAPON_SPEC[tWeaponType.null]
  else
    result := weapons[weaponIdx];
end;

{tank takes damage at given location in world space. Sender is who delt the damage}
procedure tTank.takeDamage(atX,atY: integer; damage: integer; sender: tObject=nil);
var
  v: V2D;
begin
  health -= damage;

  {todo: add debris}
  v := (V2(atX, atY) - pos).normed() * 70;

  if health < 0 then begin
    explode();
  end;
end;

procedure tTank.fire();
begin
  fireProjectile();
end;

procedure tTank.fireProjectile();
var
  projectile: tProjectile;
  pVel: single;
begin
  if status <> GO_ACTIVE then exit;
  if cooldown <= 0 then begin
    projectile := nextProjectile();
    weapon.applyToProjectile(projectile);
    projectile.pos := pos;
    if weapon.pType = PT_PLASMA then pVel := 200 else pVel := power * 20;
    projectile.vel := V2(sin(angle*DEG2RAD) * pVel, -cos(angle*DEG2RAD) * pVel);
    projectile.pos += projectile.vel.normed*6;
    projectile.owner := self;
    cooldown := weapon.cooldown;

    {todo: these should be part of the projectile spec}
    case weapon.pType of
      PT_BULLET: mixer.play(sfx['launch4'], 0.2);
      PT_SHELL: mixer.play(sfx['launch2'], 0.2);
      PT_ROCKET: mixer.play(sfx['launch3'], 0.2);
      PT_PLASMA: mixer.play(sfx['plasma1'], 0.2);
      PT_DIRT: mixer.play(sfx['launch1'], 0.2);
    end;

    lastProjectile := projectile;
  end;
end;

procedure tTank.fireLaser();
var
  hit: tHitInfo;
begin
  {need to do the following...}
  {1. find hit position}
  hit := traceRay(xPos, yPos, angle, 100, self);
  if hit.didHit then begin
    makeSparks(hit.x, hit.y, 3, 5, 0, 0);
    terrain.burn(hit.x, hit.y, 2, 10);
  end;
  {1. stretch draw the line}
end;

procedure tTank.explode();
begin
  if status <> GO_ACTIVE then exit;
  mixer.play(sfx['explode'], 0.6);
  makeExplosion(xPos, yPos, 20);
  markForRemoval();
end;

procedure tTank.applyControl(xAction, yAction: single; elapsed: single);
var
  speed: single;
  drag: single;
begin
  {check for nans}
  if (xAction <> xAction) or (yAction <> yAction) then exit;

  xAction := clamp(xAction, -1, 1);
  yAction := clamp(yAction, -1, 1);

  case chassis.animationType of
    AT_NONE: ;
    AT_TANK: adjustAim(xAction * 100 * elapsed, yAction * 10 * elapsed);
    AT_HELI: begin
      {custom heli logic}

      {drag}
      {
      drag := sign(vel.x) * (elapsed * -150);
      if abs(drag) >= abs(vel.x) then vel.x := 0 else vel.x += drag;
      drag := vel.y * (elapsed * -25);
      if abs(drag) >= abs(vel.y) then vel.y := 0 else vel.y += drag;
      }
      vel *= 0.95;

      if yAction < 0 then speed := 750 else speed := 1000;
      vel.y -= yAction * speed * elapsed;
      vel.x += xAction * 750 * elapsed;

    end;
  end;
end;

procedure tTank.adjustAim(deltaAngle, deltaPower: single);
var
  pre,post: double;
begin
  if status <> GO_ACTIVE then exit;
  angle := clamp(angle + deltaAngle, -90, 90);
  power := clamp(power + deltaPower, 2, 16);
end;


begin
end.
