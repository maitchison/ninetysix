unit uWeapon;

interface

uses
  {$i units},
  uGameObjects;

type

  tProjectileType = (
    PT_NONE,
    PT_BULLET,
    PT_SHELL,
    PT_ROCKET,
    PT_PLASMA,
    PT_DIRT,
    PT_LASER
  );

  tProjectile = class(tGameObject)
    owner: tGameObject;
    pType: tProjectileType;
    damage: integer;
    procedure reset(); override;
    procedure hit(other: tGameObject = nil);
    procedure update(elapsed: single); override;
    procedure draw(screen: tScreen); override;
  end;

  {note: we're using a 1:1 for weapons and projectiles here, but
   I think that's just fine.}
  tWeaponSpec = record
    tag: string;
    spriteIdx: integer;
    damage: integer;
    pType: tProjectileType;
    cooldown: single;
    function projectileSprite: tSprite;
    function weaponSprite: tSprite;
    procedure applyToProjectile(projectile: tProjectile);
  end;

type
  {hmm.. we could index these by string no?}
  {$scopedenums on}
  tWeaponType = (
    null,
    tracer,
    blast,
    megaBlast,
    microNuke,
    miniNuke,
    smallDirt,
    largeDirt,
    plasma
  );

const

  WEAPON_SPEC: array[tWeaponType] of tWeaponSpec =
  (
    (tag: 'Null';         spriteIdx: 16*11 + 0;  damage: 0;    pType: PT_NONE;   cooldown: 1.0),
    (tag: 'Tracer';       spriteIdx: 16*11 + 0;  damage: 1;    pType: PT_BULLET; cooldown: 0.1),
    (tag: 'Blast';        spriteIdx: 16*11 + 1;  damage: 25;   pType: PT_SHELL;  cooldown: 1.0),
    (tag: 'Mega Blast';   spriteIdx: 16*11 + 2;  damage: 50;   pType: PT_SHELL;  cooldown: 2.0),
    (tag: 'Micro Nuke';   spriteIdx: 16*11 + 3;  damage: 500;  pType: PT_ROCKET; cooldown: 2.0),
    (tag: 'Mini Nuke';    spriteIdx: 16*11 + 7;  damage: 1000; pType: PT_ROCKET; cooldown: 4.0),
    (tag: 'Small Dirt';   spriteIdx: 16*11 + 8;  damage: 20;   pType: PT_DIRT;   cooldown: 1.0),
    (tag: 'Large Dirt';   spriteIdx: 16*11 + 9;  damage: 40;   pType: PT_DIRT;   cooldown: 4.0),
    (tag: 'Plasma';       spriteIdx: 16*11 + 11; damage: 75;   pType: PT_PLASMA; cooldown: 1.0)
  );


implementation

uses
  fx, res, uTank, game, terraNova;

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
  projectile.pType := pType;
end;

{-------------------------------------------------------}

procedure tProjectile.reset();
begin
  inherited reset();
  col := RGB($ffffff86);
  radius := 1;
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

procedure tProjectile.hit(other: tGameObject=nil);
var
  hitRadius: integer;
  dir: V2D;
  targetDamage: integer;
begin
  hitRadius := round(clamp(2, 2*sqrt(abs(damage)), 100));
  targetDamage := damage;

  case pType of
    PT_NONE:
      ;
    PT_BULLET: begin
      mixer.play(sfx['hit1'] , 0.8);
      terrain.burn(xPos, yPos, hitRadius, clamp(damage, 5, 80));
      if assigned(other) then
        makeSparks(xPos, yPos, 2, 10, -(vel.x/2), -(vel.y/2));
    end;
    PT_SHELL: begin
      mixer.play(sfx['explode'] , 0.10);
      terrain.burn(xPos, yPos, hitRadius, clamp(damage, 5, 80));
      makeExplosion(xPos, yPos, hitRadius);
    end;
    PT_ROCKET: begin
      mixer.play(sfx['explode'] , 0.3);
      terrain.burn(xPos, yPos, hitRadius, clamp(damage, 5, 80));
      makeExplosion(xPos, yPos, hitRadius);
      targetDamage := damage div 2;
      damagePlayers(xPos, yPos, hitRadius, damage div 2, owner);
    end;
    PT_PLASMA: begin
      mixer.play(sfx['plasma3'] , 0.3);
      terrain.burn(xPos, yPos, 2, 20);
      dir := vel.normed();
      terrain.burn(xPos+round(dir.x*2), yPos+round(dir.y*2), 2, 20);
      terrain.burn(xPos+round(dir.x*4), yPos+round(dir.y*4), 2, 20);
    end;
    PT_DIRT: begin
      mixer.play(sfx['dirt'] , 0.3);
      terrain.putCircle(xPos, yPos, damage, DT_WATER);
      targetDamage := 0;
    end;
    PT_LASER:
      ; // pass;
    else fatal('Invalid projectile type '+intToStr(ord(pType)));
  end;

  if (targetDamage > 0) and assigned(other) and (other is tTank) then begin
    tTank(other).takeDamage(xPos, yPos, targetDamage, owner);
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
  if pType <> PT_PLASMA then
    //open tyrian is 0.05*(FPS^2). If FPS=69.5, this gives us 241.5.
    vel.y += game.GRAVITY * elapsed;

  {move}
  inherited update(elapsed);

  {see if we're out of bounds}
  if (xPos < 0) or (xPos > 255) or (yPos > 255) then begin
    markForRemoval();
    exit;
  end;

  {particle effects}
  case pType of
    PT_ROCKET: begin
      dir := vel.normed();
      makeSmoke(xPos - round(dir.x*6), yPos - round(dir.y*6), 1, 4);
    end;
  end;

  {check if we collided with an object}
  if age < 0.1 then
    go := getObjectAtPos(xPos, yPos, self.owner)
  else
    go := getObjectAtPos(xPos, yPos);

  if assigned(go) then begin
    hit(go);
    exit;
  end;

  {check if we collided with terrain}
  if terrain.isSolid(xPos, yPos) then begin
    hit(nil);
    exit;
  end;
end;

procedure tProjectile.draw(screen: tScreen);
var
  angle: single;
  r: tRect;
begin
  r.init(0, 0, 0, 0);
  case pType of
    PT_NONE:
      ;
    PT_SHELL,
    PT_BULLET,
    PT_DIRT:
      r := sprite.draw(screen.canvas, xPos+32, yPos);
    PT_ROCKET,
    PT_PLASMA: begin
      angle := arcTan2(vel.y, vel.x) * RAD2DEG;
      angle := round(angle/45) * 45;
      r := sprite.drawRotated(screen.canvas, Point(xPos+32, yPos), angle, 1.0);
    end;
    else fatal('Invalid projectile type '+intToStr(ord(pType)));
  end;
  if r.width > 0 then
    screen.markRegion(r);
end;

{--------------------------------------}

begin
end.
