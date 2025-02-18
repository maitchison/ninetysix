unit uBullet;

interface

uses
  {$i units},
  obj;

type

  {$scopedenums on}
  tProjectileType = (
    none,
    shell,
    rocket,
    plasma,
    dirt,
    laser// special case
  );

  tProjectile = class(tGameObject)
    owner: tGameObject;
    projectileType: tProjectileType;
    sprite: tSprite;
    damage: integer;
    procedure reset(); override;
    procedure hit();
    procedure update(elapsed: single); override;
    procedure draw(screen: tScreen); override;
  end;

  {note: we're using a 1:1 for weapons and projectiles here, but
   I think that's just fine.}
  tWeaponSpec = record
    tag: string;
    spriteIdx: integer;
    damage: integer;
    projectileType: tProjectileType;
    cooldown: single;
    function projectileSprite: tSprite;
    function weaponSprite: tSprite;
    procedure applyToProjectile(projectile: tProjectile);
  end;

type
  {hmm.. we could index these by string no?}
  {$scopedenums on}
  tWeaponType = (
    null      = 0,
    tracer    = 1,
    blast     = 2,
    megaBlast = 3,
    microNuke = 4,
    miniNuke  = 5
  );

const

  WEAPON_SPEC: array[tWeaponType] of tWeaponSpec =
  (
    (tag: 'Null';         spriteIdx: 16*11 + 0;  damage: 0;    projectileType: tProjectileType.none;   cooldown: 1.0),
    (tag: 'Tracer';       spriteIdx: 16*11 + 0;  damage: 1;    projectileType: tProjectileType.shell;  cooldown: 0.1),
    (tag: 'Blast';        spriteIdx: 16*11 + 1;  damage: 25;   projectileType: tProjectileType.shell;  cooldown: 1.0),
    (tag: 'Mega Blast';   spriteIdx: 16*11 + 2;  damage: 50;   projectileType: tProjectileType.shell;  cooldown: 2.0),
    (tag: 'Micro Nuke';   spriteIdx: 16*11 + 3;  damage: 500;  projectileType: tProjectileType.rocket; cooldown: 2.0),
    (tag: 'Mini Nuke';    spriteIdx: 16*11 + 7;  damage: 1000; projectileType: tProjectileType.rocket; cooldown: 4.0)
{    (tag: 'Small Dirt';   spriteIdx: 16*11 + 8;  damage: 0;    projectileType: PT_DIRT;   cooldown: 1.0),
    (tag: 'Large Dirt';   spriteIdx: 16*11 + 9;  damage: 0;    projectileType: PT_DIRT;   cooldown: 1.0),
    (tag: 'Plasma';       spriteIdx: 16*11 + 11; damage: 200;  projectileType: PT_PLASMA; cooldown: 1.0)}
  );


implementation

uses
  fx, res, uTank, game, terra;

{-------------------------------------------------------}

function tWeaponSpec.projectileSprite: tSprite;
begin
  result := sprites.sprites[spriteIdx];
end;

function tWeaponSpec.weaponSprite: tSprite;
begin
  // by convention, subtract 16 from this to get the UI sprite
  result := sprites.sprites[spriteIdx-16];
end;

procedure tWeaponSpec.applyToProjectile(projectile: tProjectile);
begin
  projectile.sprite := projectileSprite;
  projectile.damage := damage;
  projectile.projectileType := projectileType;
end;

{-------------------------------------------------------}

procedure tProjectile.reset();
begin
  inherited reset();
  col := RGB($ffffff86);
  offset.x := -1;
  offset.y := -1;
  bounds.width := 3;
  bounds.height := 3;
end;

procedure playRandomHit();
var
  hitSnd: tSoundEffect;
  volume: single;
  pitch: single;
begin
  case rnd mod 3 of
    0: hitSnd := sfx['hit1'];
    1: hitSnd := sfx['hit5'];
    2: hitSnd := sfx['hit6'];
  end;
  volume := 0.7 + (rnd/256) * 0.2;
  pitch := 0.9 + (rnd/256) * 0.2;
  mixer.play(hitSnd, volume, SCS_NEXTFREE, pitch);
end;

procedure tProjectile.hit();
var
  radius: integer;
begin
  radius := round(clamp(2, 2*sqrt(abs(damage)), 100));
  case projectileType of

    tProjectileType.none: ;

    tProjectileType.shell: begin
      if damage = 1 then
        {special case for tracer}
        playRandomHit()
      else
        mixer.play(sfx['explode'] , 0.3);
      terrain.burn(xPos-32, yPos, radius, clamp(damage, 5, 80));
      if damage > 10 then
        makeExplosion(xPos, yPos, radius);
    end;

    tProjectileType.rocket: begin
      mixer.play(sfx['explode'] , 0.3);
      terrain.burn(xPos-32, yPos, radius, clamp(damage, 5, 80));
      makeExplosion(xPos, yPos, radius);
    end;

    tProjectileType.plasma:
      ; // niy
    tProjectileType.dirt:
      ; // niy
    tProjectileType.laser:
      ; // pass;
    else fatal('Invalid projectile type '+intToStr(ord(projectileType)));
  end;

  markForRemoval();
end;

procedure tProjectile.update(elapsed: single);
var
  c: RGBA;
  go: tGameObject;
  tank: tTank;
  dir: V2D;
begin
  {gravity}
  vel.y += 58 * elapsed;
  {move}
  inherited update(elapsed);
  {see if we're out of bounds}
  if (xPos < 32) or (xPos > 256+32) or (yPos > 256) then begin
    markForRemoval();
    exit;
  end;

  {particle effects}
  case projectileType of
    tProjectileType.rocket: begin
      dir := vel.normed();
      makeSmoke(xPos - round(dir.x*6), yPos - round(dir.y*6), 1, 4);
    end;
  end;

  {check if we collided with tank}
  for go in tanks.objects do begin
    tank := tTank(go);
    if tank.status <> GO_ACTIVE then continue;
    {make sure we don't collide with ourself as soon as we fire}
    if (tank = self.owner) and (age < 0.10) then continue;
    c := tank.getWorldPixel(xPos, yPos);
    if c.a > 0 then begin
      tank.takeDamage(xPos, yPos, self.damage, owner);
      makeSparks(xPos, yPos, 2, 10, -(vel.x/2), -(vel.y/2));
      hit();
      exit;
    end;
  end;
  {check if we collided with terrain}
  if terrain.isSolid(xPos-32, yPos) then begin
    hit();
    exit;
  end;
end;

procedure tProjectile.draw(screen: tScreen);
var
  bounds: tRect;
  angle: single;
begin
  bounds.init(0,0,0,0);
  case projectileType of
    tProjectileType.none: ;
    tProjectileType.shell:
      bounds := sprite.draw(screen.canvas, xPos, yPos);
    tProjectileType.rocket: begin
      angle := arcTan2(vel.y, vel.x) * RAD2DEG;
      sprite.drawRotated(screen.canvas, V3(xPos, yPos, 0), angle, 1.0);
      {todo: drawRotated should return rect}
      {also, this rect is too large}
      bounds := sprite.srcRect;
      bounds.x := xPos - sprite.pivot.x;
      bounds.y := yPos - sprite.pivot.y;
    end;
    else fatal('Invalid projectile type '+intToStr(ord(projectileType)));
  end;
  if bounds.width > 0 then
    screen.markRegion(bounds);
end;

{--------------------------------------}

begin
end.
