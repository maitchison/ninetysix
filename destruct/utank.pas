unit uTank;

interface

uses
  {$i units},
  terraNova,
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
    damageSheet: array[0..15,0..15] of byte; {indicates where damage is}
    procedure fireProjectile();
    procedure fireLaser();
  public
    team: tTeam;
    weapons: array of tWeaponSpec;
    chassis: tChassis;
    cooldown: single;
    laserOn: single;
    laserMax: single;
    angle: single;
    power: single;
    health: single;
    lastProjectile: tProjectile;
    weaponIdx: integer;
    prevX, prevY: integer;
  protected
    procedure updateAnimation();
    procedure updateTankCollision(elapsed:single);
    procedure updateHeliCollision(elapsed:single);
    procedure setCore(atX, atY: integer; dType: tDirtType);
    function  isFlipped: boolean;
    procedure drawDamage(dc: tDrawContext);
  public
    function  weapon: tWeaponSpec;
    function  baseSprite: tSprite;
    procedure init(aPos: tPoint; aTeam: tTeam; aChassisType: tChassisType);
    function  isSelected: boolean;
    procedure clearTerrain();
    procedure applyChassis(aChassis: tChassis);
    procedure reset(); override;
    procedure update(elapsed: single); override;
    procedure draw(dc: tDrawContext); override;
    procedure applyControl(xAction, yAction: single; elapsed: single);
    procedure adjustAim(deltaAngle: single; deltaPower: single = 0);
    procedure takeDamage(atX,atY: integer; damage: single;sender: tObject=nil);
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
        tWeaponType.plasma,
        tWeaponType.pulseLaser,
        tWeaponType.lavaBomb,
        tWeaponType.blast
      ];
    )
  );

procedure respondToTankCellDamage(x,y: integer;damage: integer);

implementation

uses
  fx, res, game;

const
  DEBUG_SHOW_TANK_SUPPORT = false;

var
  damageColors: array[0..15,0..15] of RGBA;

{-----------------------------------------------------------}

{handles tile burning transfering to tank}
procedure respondToTankCellDamage(x,y: integer;damage: integer);
var
  obj: tGameObject;
  tank: tTank;
begin
  obj := game.getObjectAtPos(x,y);
  if not assigned(obj) then exit;
  if not (obj is tTank) then exit;
  tank := tTank(obj);
  tank.takeDamage(x,y,damage*0.15);
end;

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
  prevX := -99;
  prevY := -99;
  fillchar(damageSheet, sizeof(damageSheet), 0);
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
      if angle < 180-10 then spriteIdx += 10;
      if angle > 180+10 then spriteIdx += 5;
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
  case chassis.animationType of
    AT_NONE: ;
    AT_TANK: angle := 0;
    AT_HELI: angle := 180;
  end;
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

{this is quite slow... but it'll do the trick}
procedure tTank.drawDamage(dc: tDrawContext);
var
  xlp,ylp: integer;
  c: RGBA;
begin
  {todo: now that we have drawContext, we can draw to the underlying sprite.
   This means that every tank needs a copy of the tank graphic.}
  if not assigned(sprite) then exit;
  for ylp := 0 to sprite.height-1 do begin
    for xlp := 0 to sprite.width-1 do begin
      if damageSheet[ylp,xlp] = 0 then continue;
      if sprite.getPixel(xlp,ylp).a = 0 then continue;
      c := damageColors[xlp, ylp];
      c.a := damageSheet[ylp,xlp];
      dc.putPixel(Point(xPos+xlp-(sprite.pivot2x.x div 2),yPos+ylp-(sprite.pivot2x.y div 2)), c);
    end;
  end;
end;

function tTank.isFlipped: boolean;
begin
  result := (angle < 0) and (chassis.animationType = AT_TANK);
end;

procedure tTank.draw(dc: tDrawContext);
var
  markerColor: RGBA;
begin

  if not assigned(sprite) then exit;

  if isFlipped() then
    {todo: support flipped draw}
    sprite.drawFlipped(dc, xPos, yPos)
  else
    sprite.draw(dc, xPos, yPos);

  drawDamage(dc);

  {marker}
  if isSelected then
    markerColor.init(255, 255, 128)
  else
    markerColor.init(128,128,128);

  {draw target}
  drawMarker(
    dc,
    xPos + sin(angle*DEG2RAD) * power * 2,
    yPos - cos(angle*DEG2RAD) * power * 2,
    markerColor
  );
end;

{set tank core tiles at given location}
procedure tTank.setCore(atX, atY: integer; dType: tDirtType);
var
  dx,dy: integer;
  cell: tCellInfo;
  coreStart: integer;
begin

  cell.dType := dType;
  if dType = DT_EMPTY then
    cell.strength := 0
  else
    cell.strength := 255;

  case chassis.chassisType of
    CT_LAUNCHER: coreStart := 3;
    else coreStart := 1;
  end;

  for dy := coreStart to 4 do
    for dx := -4 to 4 do
      terrain.setCell(atX+dx, atY+dy, cell);
end;

procedure tTank.updateTankCollision(elapsed: single);
var
  support: integer;
  i, x, y, xlp, ylp: integer;
  bounds: tRect;
  hitPower: integer;
  p: tParticle;
  l: integer;
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
      for i := 1 to 2 do begin
        p := nextParticle();
        p.pos := V2(x, y);
        p.vel := V2(rnd-128, rnd-128) * 0.1;
        p.vel.y -= 10;
        p.solid := false;
        //p.col := terrain.dirtColor.getPixel(x, y);
        //if p.col.a = 0 then p.col := RGB(200,200,200);
        l := 70 + rnd(70);
        p.col := RGB(l,l,l);
        p.ttl := 0.25+(rnd/256)*0.35;
        p.radius := 1;
      end;
      {burn it}
      terrain.burn(x, bounds.bottom-3, 2, round(hitPower/support/16));
    end;
    vel.y := 0;
  end;

  {interaction with terrain}
  if (xPos <> prevX) or (yPos <> prevY) then begin
    setCore(prevX, prevY, DT_EMPTY);
    setCore(xPos, yPos, DT_TANKCORE);
    prevX := xPos;
    prevY := yPos;
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
  l: integer;
  grad: V2D;
  didCollide: boolean;
const
  padding = 16;
begin

  support := 0;
  bounds := Rect(xPos-8, yPos-8, 16, 16);

  {always falling a little bit}
  vel.y += (GRAVITY/4) * elapsed;

  {heli needs a full check}
  {todo could be faster if we trim the bounds to sprite}
  didCollide := false;
  for ylp := bounds.top+3 to bounds.bottom-3 do begin
    for xlp := bounds.left+3 to bounds.right-3 do begin
      if (getWorldPixel(xlp, ylp).a > 0) and (terrain.isSolid(xlp, ylp)) then begin
        {bump}
        delta := V2(xlp - xPos, 2 + ylp - yPos) * 20;
        didCollide := true;
        {create cloud}
        p := nextParticle();
        p.pos := V2(xlp + rnd(3)-1, ylp+rnd(3)-1);
        p.vel := V2(rnd-128, rnd-128) * 0.2;
        p.vel -= (delta * 0.2);
        p.solid := true;
        p.hasGravity := true;
        l := 64 + rnd(128);
        p.col := RGB(l,l,l);
        p.ttl := 0.2 + (rnd/256)*0.2;
        p.radius := 1;
      end;
    end;
  end;

  if didCollide then begin
    grad := terrain.getGradient(xPos,yPos,8).normed();
    vel += grad * elapsed * 3000;
  end;

  {soft and hard boundaries}
  pos.x := clamp(pos.x, 0, 256);
  if pos.x < padding then vel.x += (padding-pos.x) * 130 * elapsed;
  if pos.x > 256-padding then vel.x -= (pos.x-(256-padding)) * 130 * elapsed;
  if pos.y < (16+padding) then vel.y += ((16+padding)-pos.y) * 130 * elapsed;
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

  if (health <= 0) then begin
    explode();
    exit;
  end;

  {enforce a strict speed limit}
  vel.x := clamp(vel.x, -500, 500);
  vel.y := clamp(vel.y, -500, 500);

  {inherited update stuff}
  inherited update(elapsed);

  if cooldown > 0 then cooldown -= elapsed;
  if laserOn > 0 then begin
    fireLaser();
    laserOn -= elapsed;
  end;

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

function tTank.baseSprite: tSprite;
var
  baseIdx: integer;
begin
  baseIdx := chassis.baseSpriteIdx;
  if team = TEAM_2 then baseIdx += 16;
  result := sprites.sprites[baseIdx];
end;

{tank takes damage at given location in world space. Sender is who delt the damage}
procedure tTank.takeDamage(atX,atY: integer; damage: single; sender: tObject=nil);
var
  v: V2D;
  dx,dy: integer;
  intDamage: integer;
  gx,gy: integer;
  i: integer;
begin
  if damage <= 0 then exit;
  health -= damage;
  {indicate damage}
  damage *= 3;
  for i := 1 to 9 do begin
    dx := clamp(round(1.5*gaus)+atX-xPos+(sprite.pivot2x.x div 2), 0, 15);
    dy := clamp(round(1.5*gaus)+atY-yPos+(sprite.pivot2x.y div 2), 0, 15);
    if damage >= 1 then intDamage := round(damage) else begin
      intDamage := 0;
      if (rnd/255) < damage then intDamage := 1;
    end;
    damageSheet[dy, dx] := clamp(damageSheet[dy, dx]+intDamage, 0, 255);
  end;

  {todo: add debris}
  //v := (V2(atX, atY) - pos).normed() * 70;
end;

procedure tTank.fire();
begin
  if (weapon.pType = PT_LASER) then begin
    if (laserOn <= 0) and (cooldown <= 0) then begin
      mixer.play(sfx['plasma2'], 0.4);
      mixer.play(sfx['laser'], 0.7, SCS_OLDEST, 0.5);
      laserMax := weapon.cooldown * 0.75;
      laserOn := laserMax;
      cooldown := weapon.cooldown;
    end;
  end else
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

    if weapon.pType = PT_ROCKET then begin
      projectile.thrustTimer := power / 20;
      projectile.vel *= 0.1;
    end;

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
  laserLength: single;
  laserPower: single;
  t: single;
  delta: V2D;
begin
  t := 1-(laserOn / laserMax);
  laserLength := 150*clamp(t*2, 0, 1.0);
  laserPower := sin(t*pi);
  {need to do the following...}
  {1. find hit position}
  hit := traceRay(xPos, yPos, angle, round(laserLength), self, laserPower);
  if hit.didHit then begin
    delta := (V2(hit.x, hit.y) - pos).normed()*-50;
    makeSparks(hit.x, hit.y, 4, 10, delta.x, delta.y, 1);
    terrain.burn(hit.x, hit.y, 2, 10);
  end;
  {1. stretch draw the line}
end;

procedure tTank.explode();
begin
  if status <> GO_ACTIVE then exit;
  mixer.play(sfx['explode'], 0.6);
  makeExplosion(xPos, yPos, 20);
  doBump(xPos, yPos, 30, 50);
  markForRemoval();
  setCore(prevX, prevY, DT_EMPTY);
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
      vel *= 0.97;
      if (yAction = 0) and (xAction=0) then yAction += 0.05; // a bit of hover

      if yAction < 0 then speed := 250 else speed := 750;
      vel.y -= yAction * speed * elapsed;
      vel.x += xAction * 750 * elapsed;

      adjustAim(-xAction*100*elapsed);

    end;
  end;
end;

procedure tTank.adjustAim(deltaAngle: single; deltaPower: single = 0);
var
  pre,post: double;
begin
  if status <> GO_ACTIVE then exit;
  case chassis.animationType of
    AT_NONE: ;
    AT_TANK: begin
      angle := clamp(angle + deltaAngle, -90, 90);
      power := clamp(power + deltaPower, 2, 16);
    end;
    AT_HELI: begin
      angle := clamp(angle + deltaAngle, 180-45, 180+45);
    end;
  end;
end;

var
  x,y: integer;

begin
  for x := 0 to 15 do
    for y := 0 to 15 do
      damageColors[x,y] := RGB(rnd(30), rnd(10), rnd(10));
end.
