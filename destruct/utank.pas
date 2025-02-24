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
    CT_HEAVY
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
    team: integer;
    weapons: array of tWeaponSpec;
    chassis: tChassis;
    cooldown: single;
    angle: single;
    power: single;
    health: integer;
    lastProjectile: tProjectile;
    weaponIdx: integer;
  public
    function  weapon: tWeaponSpec;
    procedure init(aPos: tPoint; aTeam: integer; aChassisType: tChassisType);
    function  isSelected: boolean;
    procedure clearTerrain();
    procedure applyChassis(aChassis: tChassis);
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
    (tag: 'Null';       cType: CT_NULL;     health: 0;   spriteIdx: 0; defaultWeapons: []),
    (tag: 'Tank';       cType: CT_TANK;     health: 350; spriteIdx: 0;
      defaultWeapons: [
        tWeaponType.tracer,
        tWeaponType.blast,
        tWeaponType.smallDirt,
        tWeaponType.largeDirt
      ]
    ),
    (tag: 'Launcher';   cType: CT_LAUNCHER; health: 200; spriteIdx: 5;
      defaultWeapons: [
        tWeaponType.microNuke,
        tWeaponType.miniNuke
      ];
    ),
    (tag: 'Heavy Tank'; cType: CT_HEAVY;    health: 700; spriteIdx: 10;
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
procedure tTank.init(aPos: tPoint; aTeam: integer; aChassisType: tChassisType);
begin
  note('Initializing tank at position %s', [aPos.toString]);
  reset();
  status := GO_ACTIVE;
  pos.x := aPos.x;
  pos.y := aPos.y;
  team := aTeam;
  applyChassis(CHASSIS_DEF[aChassisType]);
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
  self.spriteIdx := aChassis.spriteIdx;
  setLength(self.weapons, length(aChassis.defaultWeapons));
  for i := 0 to length(aChassis.defaultWeapons)-1 do
    self.weapons[i] := WEAPON_SPEC[aChassis.defaultWeapons[i]];
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

  if angle < 0 then
    r := sprite.drawFlipped(screen.canvas, p.x, p.y)
  else
    r := sprite.draw(screen.canvas, p.x, p.y);

  screen.markRegion(r);

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

procedure tTank.update(elapsed: single);
var
  xlp: integer;
  x,y: integer;
  support: integer;
  hitPower: integer;
  p: tParticle;
  i: integer;
  bounds: tRect;
begin

  {inherited update stuff}
  inherited update(elapsed);
  if cooldown > 0 then cooldown -= elapsed;

  {animation}
  sprite := spriteSheet.sprites[spriteIdx + clamp(round((90-abs(angle)) * 5 / 90), 0, 4)];

  bounds := rect(xPos-8, yPos-8, 16, 16);

  {falling}
  support := 0;
  {todo: these insets should not be hard coded, better to check pixels of
   texture, or maybe specify as part of the tank}
  for xlp := bounds.left+3 to bounds.right-3 do begin
    if DEBUG_SHOW_TANK_SUPPORT then
      screen.canvas.putPixel(xlp, bounds.bottom-3, RGB(255,0,255));
    if terrain.isSolid(xlp, bounds.bottom-3) then inc(support);
  end;
  if support = 0 then
    vel.y := clamp(vel.y + 100 * elapsed, -800, 800)
  else begin
    if vel.y > 0 then begin
      hitPower := round(10*vel.y);
      {weaken blocks holding us up}
      y := bounds.bottom;
      for x := bounds.left+3 to bounds.right-3 do begin
        {make a little cloud}
        for i := 1 to 3 do begin
          p := nextParticle();
          p.pos := V2(x, y);
          p.vel := V2(rnd-128, rnd-128) * 0.2;
          p.solid := true;
          //p.col := terrain.dirtColor.getPixel(x, y);
          //if p.col.a = 0 then p.col := RGB(200,200,200);
          p.col := RGB(200,200,200);
          p.ttl := 0.5;
          p.radius := 2;
        end;
        {burn it}
        terrain.burn(x, bounds.bottom-3, 2, round(hitPower/support/16));
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

procedure tTank.adjust(deltaAngle, deltaPower: single);
var
  pre,post: double;
begin
  if status <> GO_ACTIVE then exit;
  angle := clamp(angle + deltaAngle, -90, 90);
  power := clamp(power + deltaPower, 2, 16);
end;


begin
end.
