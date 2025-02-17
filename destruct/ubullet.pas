unit uBullet;

interface

uses
  {$i units},
  obj;

type

  tProjectile = class(tGameObject)
    owner: tGameObject;
    procedure reset(); override;
    procedure explode();
    procedure update(elapsed: single); override;
    procedure draw(screen: tScreen); override;
  end;

  tProjectileType = (
    PT_NONE,
    PT_SHELL,
    PT_ROCKET,
    PT_PLASMA,
    PT_DIRT,
    PT_LASER  // special case
  );

  {note: we're using a 1:1 for weapons and projectiles here, but
   I think that's just fine.}
  tWeaponSpec = record
    tag: string;
    spriteIdx: integer; // by convention, subtract 16 from this to get the UI sprite
    damage: integer;
    projectileType: tProjectileType;
    rechargeTime: single;
  end;

type
  {$scopedenums on}
  tWeaponType = (
    null      = 0,
    tracer    = 1,
    blast     = 2,
    megaBlast = 3
  );

const

  WEAPON_SPEC: array[tWeaponType] of tWeaponSpec =
  (
    (tag: 'Null';         spriteIdx: 0;          damage: 0;    projectileType: PT_NONE;   rechargeTime: 1.0),
    (tag: 'Tracer';       spriteIdx: 16*11 + 0;  damage: 1;    projectileType: PT_SHELL;  rechargeTime: 1.0),
    (tag: 'Blast';        spriteIdx: 16*11 + 1;  damage: 100;  projectileType: PT_SHELL;  rechargeTime: 1.0),
    (tag: 'Mega Blast';   spriteIdx: 16*11 + 2;  damage: 200;  projectileType: PT_ROCKET; rechargeTime: 1.0)
{    (tag: 'Micro Nuke';   spriteIdx: 16*11 + 3;  damage: 500;  projectileType: PT_ROCKET; rechargeTime: 1.0),
    (tag: 'Mini Nuke';    spriteIdx: 16*11 + 7;  damage: 1000; projectileType: PT_ROCKET; rechargeTime: 1.0),
    (tag: 'Small Dirt';   spriteIdx: 16*11 + 8;  damage: 0;    projectileType: PT_DIRT;   rechargeTime: 1.0),
    (tag: 'Large Dirt';   spriteIdx: 16*11 + 9;  damage: 0;    projectileType: PT_DIRT;   rechargeTime: 1.0),
    (tag: 'Plasma';       spriteIdx: 16*11 + 11; damage: 200;  projectileType: PT_PLASMA; rechargeTime: 1.0)}
  );


implementation

uses
  fx, res, uTank, game, terra;

procedure tProjectile.reset();
begin
  inherited reset();
  col := RGB($ffffff86);
  offset.x := -1;
  offset.y := -1;
  bounds.width := 3;
  bounds.height := 3;
end;

procedure tProjectile.explode();
begin
  mixer.play(explodeSFX, 0.3);
  makeExplosion(xPos, yPos, 10);
  //terrain.burn(xPos-32, yPos, 3, 30); // for bullets
  markAsDeleted();
end;

procedure tProjectile.update(elapsed: single);
var
  c: RGBA;
  go: tGameObject;
  tank: tTank;
begin
  {gravity}
  vel.y += 58 * elapsed;
  {move}
  inherited update(elapsed);
  {see if we're out of bounds}
  if (xPos < 32) or (xPos > 256+32) or (yPos > 256) then begin
    markAsDeleted();
    exit;
  end;
  {check if we collided with tank}
  for go in tanks.objects do begin
    tank := tTank(go);
    if tank.status <> GO_ACTIVE then continue;
    {make sure we don't collide with ourself as soon as we fire}
    if (tank = self.owner) and (age < 0.10) then continue;
    c := tank.getWorldPixel(xPos, yPos);
    if c.a > 0 then begin
      tank.takeDamage(xPos, yPos, 100, owner);
      makeSparks(xPos, yPos, 3, 5, -vel.x, -vel.y);
      explode();
      exit;
    end;
  end;
  {check if we collided with terrain}
  if terrain.isSolid(xPos-32, yPos) then begin
    explode();
    exit;
  end;
end;

procedure tProjectile.draw(screen: tScreen);
begin
  drawMarker(screen, xPos, yPos, col);
end;

{--------------------------------------}

begin
end.
