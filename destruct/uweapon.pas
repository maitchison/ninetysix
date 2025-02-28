unit uWeapon;

interface

uses
  {$i units},
  template,
  terraNova,
  uGameObjects;

type

  tProjectileType = (
    PT_NONE,
    PT_BULLET,
    PT_SHELL,
    PT_ROCKET,
    PT_PLASMA,
    PT_DIRT,
    PT_LAVA,
    PT_LASER
  );

  tProjectile = class(tGameObject)
    owner: tGameObject;
    pType: tProjectileType;
    dType: tDirtType;
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
    dType: tDirtType;
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
    lavaBomb,
    plasma
  );

const

  DT_NONE = DT_EMPTY;

  WEAPON_SPEC: array[tWeaponType] of tWeaponSpec =
  (
    (tag: 'Null';         spriteIdx: 16*11 + 0;  damage: 0;    pType: PT_NONE;   dType: DT_NONE; cooldown: 1.0),
    (tag: 'Tracer';       spriteIdx: 16*11 + 0;  damage: 1;    pType: PT_BULLET; dType: DT_NONE; cooldown: 0.1),
    (tag: 'Blast';        spriteIdx: 16*11 + 1;  damage: 25;   pType: PT_SHELL;  dType: DT_NONE; cooldown: 1.0),
    (tag: 'Mega Blast';   spriteIdx: 16*11 + 2;  damage: 50;   pType: PT_SHELL;  dType: DT_NONE; cooldown: 2.0),
    (tag: 'Micro Nuke';   spriteIdx: 16*11 + 3;  damage: 500;  pType: PT_ROCKET; dType: DT_NONE; cooldown: 2.0),
    (tag: 'Mini Nuke';    spriteIdx: 16*11 + 7;  damage: 1000; pType: PT_ROCKET; dType: DT_NONE; cooldown: 4.0),
    (tag: 'Small Dirt';   spriteIdx: 16*11 + 8;  damage: 100;  pType: PT_DIRT;   dType: DT_DIRT; cooldown: 1.0),
    (tag: 'Large Dirt';   spriteIdx: 16*11 + 9;  damage: 500;  pType: PT_DIRT;   dType: DT_SAND; cooldown: 2.5),
    (tag: 'Lava Bomb';    spriteIdx: 16*11 + 2;  damage: 100;  pType: PT_DIRT;   dType: DT_LAVA; cooldown: 1.0),
    (tag: 'Plasma';       spriteIdx: 16*11 + 13; damage: 75;   pType: PT_PLASMA; dType: DT_NONE; cooldown: 1.0)
  );


implementation

uses
  fx, res, uTank, game;

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
  projectile.dType := dType;
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
  grad: V2D;
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
      {todo: before burn turn half of pixels into particles}
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
      grad := terrain.getGradient(xPos, yPos);
      makeDust(xPos, yPos, round(sqrt(damage)), dType, 25.0, grad.x*25, grad.y*25, 1.0);
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
  p: tParticle;
begin
  {gravity}
  if pType <> PT_PLASMA then
    //open tyrian is 0.05*(FPS^2). If FPS=69.5, this gives us 241.5.
    vel.y += game.GRAVITY * elapsed;

  {edge bouncing}
  if pType in [PT_PLASMA] then begin
    if pos.x+(vel.x*elapsed) < 0 then
      vel.x := -vel.x;
    if pos.x+(vel.x*elapsed) > 255 then
      vel.x := -vel.x;
    if pos.y+(vel.y*elapsed) < 0 then
      vel.y := -vel.y;
  end;

  {move}
  inherited update(elapsed);

  {see if we're out of bounds}
  if (word(xPos) > 255) or (word(yPos) > 255) then begin
    markForRemoval();
    exit;
  end;

  {particle effects}
  case pType of
    PT_PLASMA: begin
      p := nextParticle();
      p.pos := V2(xPos, yPos);
      case rnd(3) of
        0: p.col := RGB($FF367EFF);
        1: p.col := RGB($FF2049FF);
        2: p.col := RGB($FF5A84FF);
      end;
      p.radius := 2;
      p.ttl := 0.1;
      p.blend := TDM_BLEND;
    end;
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
  if terrain.isSolid(xPos, yPos) then
    hit(nil);
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
    PT_PLASMA,
    PT_DIRT:
      r := sprite.draw(screen.canvas, xPos+VIEWPORT_X, yPos+VIEWPORT_Y);
    PT_ROCKET: begin
      angle := arcTan2(vel.y, vel.x) * RAD2DEG;
      r := sprite.drawRotated(screen.canvas, Point(xPos+VIEWPORT_X, yPos+VIEWPORT_Y), angle, 0.75);
    end;
    else fatal('Invalid projectile type '+intToStr(ord(pType)));
  end;
  if r.width > 0 then
    screen.markRegion(r);
end;

{--------------------------------------}

begin
end.
