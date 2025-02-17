unit uTank;

interface

uses
  {$i units},
  uBullet, obj;

type

  tTank = class;

  {$scopedenums on}
  tChassisType = (
    null,
    tank,
    launcher,
    heavy
  );

  tChassis = record
    tag: string;
    cType: tChassisType;
    health: integer;
    spriteIdx: integer;
    defaultWeapons: array of tWeaponType;
  end;

  tTank = class(tGameObject)
  protected
    spriteSheet: tSpriteSheet;
    spriteIdx: word;
    procedure fireProjectile();
    procedure fireLaser();
  public
    weapons: array of tWeaponSpec;
    chassis: tChassis;
    id: integer;
    cooldown: single;
    angle: single;
    power: single;
    health: integer;
    lastProjectile: tProjectile;
    weaponIdx: integer;
  public
    class function FromChassis(aChassis: tChassis): tTank; static;
    function  weapon: tWeaponSpec;
    procedure reset(); override;
    procedure update(elapsed: single); override;
    procedure draw(screen: tScreen); override;
    procedure adjust(deltaAngle, deltaPower: single);
    procedure takeDamage(atX,atY: integer; damage: integer;sender: tObject=nil);
    procedure explode();
    procedure fire();
  end;

const
  CHASSIS_DEF: array[tChassisType] of tChassis = (
    (tag: 'Null';       cType: tChassisType.null;     health: 0;   spriteIdx: 0; defaultWeapons: [];),
    (tag: 'Tank';       cType: tChassisType.tank;     health: 750; spriteIdx: 0; defaultWeapons: [tWeaponType.tracer, tWeaponType.blast, tWeaponType.megaBlast]),
    (tag: 'Launcher';   cType: tChassisType.launcher; health: 500; spriteIdx: 5; defaultWeapons: [];),
    (tag: 'Heavy Tank'; cType: tChassisType.heavy;    health: 100; spriteIdx: 10;defaultWeapons: [];)
  );

implementation

uses
  fx, terra, res, game;

{-----------------------------------------------------------}

class function tTank.FromChassis(aChassis: tChassis): tTank;
var
  i: integer;
begin
  result := tTank.create();
  result.reset();
  result.chassis := aChassis;
  result.health := aChassis.health;
  result.spriteIdx := aChassis.spriteIdx;
  setLength(result.weapons, length(aChassis.defaultWeapons));
  for i := 0 to length(aChassis.defaultWeapons)-1 do
    result.weapons[i] := WEAPON_SPEC[aChassis.defaultWeapons[i]];
end;

procedure tTank.reset();
begin
  inherited reset();
  weaponIdx := 0;
  angle := 0;
  power := 10;
  spriteIdx := 0;
  health := 500;
  fillchar(chassis, sizeof(chassis), 0);
  col := RGB(255,255,255);
  spriteSheet := res.sprites;
  sprite := spriteSheet.sprites[spriteIdx]; // will be set on update
end;

procedure tTank.draw(screen: tScreen);
begin
  if angle < 0 then
    sprite.drawFlipped(screen.canvas, bounds.x, bounds.y)
  else
    sprite.draw(screen.canvas, bounds.x, bounds.y);

  screen.markRegion(bounds);
  {draw target}
  drawMarker(
    screen,
    xPos + sin(angle*DEG2RAD) * power * 2,
    yPos - cos(angle*DEG2RAD) * power * 2,
    RGB(255,128,128)
  );
end;

procedure tTank.update(elapsed: single);
var
  xlp: integer;
  support: integer;
  hitPower: integer;
  p: tParticle;
  xPos, yPos: integer;
  i: integer;
begin

  {inherited update stuff}
  inherited update(elapsed);
  if cooldown > 0 then cooldown -= elapsed;

  {animation}
  sprite := spriteSheet.sprites[spriteIdx + clamp(round((90-abs(angle)) * 5 / 90), 0, 4)];

  {falling}
  support := 0;
  for xlp := bounds.left+1 to bounds.right-1 do
    if terrain.isSolid(xlp-32, bounds.bottom) then inc(support);
  if support = 0 then
    vel.y := clamp(vel.y + 100 * elapsed, -800, 800)
  else begin
    if vel.y > 0 then begin
      hitPower := round(10*vel.y);
      {weaken blocks holding us up}
      yPos := bounds.bottom;
      for xPos:= bounds.left+1 to bounds.right-1 do begin
        {make a little cloud}
        for i := 1 to 3 do begin
          p := nextParticle();
          p.pos := V2(xPos, yPos);
          p.vel := V2(rnd-128, rnd-128) * 0.2;
          p.solid := true;
          p.col := terrain.terrain.getPixel(xPos-32, yPos);
          if p.col.a = 0 then p.col := RGB(200,200,200);
          p.ttl := 0.5;
          p.radius := 2;
        end;
        {burn it}
        terrain.burn(xlp-32, bounds.bottom, 2, round(hitPower/(bounds.width-2)));

      end;
      vel.y := 0;
    end;
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
begin
  if status <> GO_ACTIVE then exit;
  if cooldown <= 0 then begin
    projectile := nextProjectile();
    weapon.applyToProjectile(projectile);
    projectile.pos := pos;
    projectile.vel := V2(sin(angle*DEG2RAD) * power * 10, -cos(angle*DEG2RAD) * power * 10);
    projectile.pos += projectile.vel.normed*6;
    projectile.owner := self;
    cooldown := weapon.cooldown;
    mixer.play(shootSFX, 0.2); // todo: custom SFX for weapons
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
    terrain.burn(hit.x-32, hit.y, 2, 10);
  end;
  {1. stretch draw the line}
end;

procedure tTank.explode();
begin
  if status <> GO_ACTIVE then exit;
  mixer.play(explodeSFX, 1.0);
  makeExplosion(xPos, yPos, 20);
  markAsEmpty();
end;

procedure tTank.adjust(deltaAngle, deltaPower: single);
begin
  if status <> GO_ACTIVE then exit;
  angle := clamp(angle + deltaAngle, -90, 90);
  power := clamp(power + deltaPower, 2, 16);
end;


begin
end.
