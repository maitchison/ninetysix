unit obj;

interface

uses
  debug, test,
  vertex,
  sprite,
  utils,
  mixLib,
  myMath,
  graph2d,
  graph32,
  screen;

type

  tGameObjectStatus = (GO_EXPIRED, GO_ACTIVE);

  tGameObject = class
  public
    pos, vel: V2D;
    bounds: tRect;
    offset: V2D;
    fSprite: tSprite;
    col: RGBA;
    age: single;
    ttl: single;
    status: tGameObjectStatus;
  protected
    function getX: integer;
    function getY: integer;
    procedure setSprite(aSprite: tSprite);
  public
    constructor create(); virtual;
    procedure reset(); virtual;
    function  getWorldPixel(atX, atY: integer): RGBA;
    procedure draw(screen: tScreen); virtual;
    procedure update(elapsed: single); virtual;
    procedure markAsDeleted();

    property sprite: tSprite read fSprite write setSprite;
    property xPos: integer read getX;
    property yPos: integer read getY;
  end;

  tGameObjectList<T: tGameObject> = class
  public
    objects: array of T;
    procedure append(o: T);
    procedure draw(screen: tScreen);
    procedure update(elapsed: single);
    function  nextFree(): T;
  end;

  tTank = class(tGameObject)
  public
    id: integer;
    cooldown: single;
    angle: single;
    power: single;
    health: integer;
  public
    constructor create(); override;
    procedure reset(); override;
    procedure update(elapsed: single); override;
    procedure draw(screen: tScreen); override;
    procedure adjust(deltaAngle, deltaPower: single);
    procedure takeDamage(atX,atY: integer; damage: integer;sender: tTank=nil);
    procedure explode();
    procedure fire();
  end;

  tBullet = class(tGameObject)
    owner: tTank;
    procedure reset(); override;
    procedure explode();
    procedure update(elapsed: single); override;
    procedure draw(screen: tScreen); override;
  end;

  tParticle = class(tGameObject)
  public
    solid: boolean;
    radius: integer;
  public
    procedure reset(); override;
    procedure update(elapsed: single); override;
    procedure draw(screen: tScreen); override;
  end;

{may as well put globals here}
var
  tanks: tGameObjectList<tTank>;
  bullets: tGameObjectList<tBullet>;
  particles: tGameObjectList<tParticle>;

procedure updateAll(elapsed: single);
procedure drawAll(screen: tScreen);

implementation

uses
  res, terra, controller;

var
  updateAccumlator: single;

{----------------------------------------------------------}
{ helpers }
{----------------------------------------------------------}

procedure drawMarker(screen: tScreen; atX,atY: single; col: RGBA);
var
  x,y: integer;
  c: RGBA;
begin
  c := col;
  c.a := c.a div 2;
  x := round(atX);
  y := round(atY);

  screen.canvas.putPixel(x, y, col);

  screen.canvas.putPixel(x-1, y, c);
  screen.canvas.putPixel(x+1, y, c);
  screen.canvas.putPixel(x, y-1, c);
  screen.canvas.putPixel(x, y+1, c);

  screen.markRegion(rect(x-1, y-1, 3, 3));
end;

procedure makeExplosion(atX, atY: single; power: single);
var
  i: integer;
  p: tParticle;
  radius: single;
  n: integer;
  z: single;
  angle: single;
begin

  n := round(power * power);
  radius := power;
  terrain.burn(round(atX-32), round(atY), round(radius+3), 25);
  for i := 0 to n-1 do begin
    p := particles.nextFree();
    z := (rnd/255);
    angle := rnd/255*360;
    p.pos := V2Polar(angle, z*radius/2) + V2(atX, atY);
    case clamp(round(z*3), 0, 2) of
      0: p.col := RGB($FFFEC729);
      1: p.col := RGB($FFF47817);
      2: p.col := RGB($FFC5361D);
    end;
    p.vel := V2Polar(angle, (0.5+z)*radius/2);
    {edit the terrain}
    terrain.burn(p.xPos-32, p.yPos, 3, 5);
  end;
end;

procedure makeSmoke(atX, atY: single; power: single; vel: single=10);
var
  i: integer;
  p: tParticle;
  radius: single;
  n: integer;
  z: single;
  angle: single;
begin
  n := round(power * power);
  radius := power;
  for i := 0 to n-1 do begin
    p := particles.nextFree();
    z := (rnd/255);
    angle := rnd/255*360;
    p.pos := V2Polar(angle, z*radius);
    p.pos += V2(atX, atY);
    case clamp(round(z*3), 0, 2) of
      0: p.col := RGB($FF3F3F3F);
      1: p.col := RGB($FFAFAFAF);
      2: p.col := RGB($FF7F7F7F);
    end;
    p.vel := V2Polar(angle, (vel+z));
    p.ttl := 0.5;
    p.solid := true;
    p.radius := 2;
  end;
end;

procedure makeSparks(atX, atY: single; radius: single; vel: single=25; vx: single=0; vy: single=0);
var
  i: integer;
  p: tParticle;
  n: integer;
  z: single;
  angle: single;
begin
  n := round(radius * radius);
  for i := 0 to n-1 do begin
    p := particles.nextFree();
    z := (rnd/255);
    angle := rnd/255*360;
    p.pos := V2Polar(angle, z*radius);
    p.pos += V2(atX, atY);
    case rnd mod 3 of
      0: p.col := RGB($FFFEC729);
      1: p.col := RGB($FFF47817);
      2: p.col := RGB($FFC5361D);
    end;
    p.vel := V2Polar(angle, (vel+z)) + V2(vx, vy);
    p.ttl := 0.25;
    p.solid := true;
    p.radius := 1;
  end;
end;

{----------------------------------------------------------}
{ tGameObjects }
{----------------------------------------------------------}

procedure tGameObjectList<T>.append(o: T);
begin
  setLength(objects, length(objects)+1);
  objects[length(objects)-1] := o;
end;

procedure tGameObjectList<T>.draw(screen: tScreen);
var
  go: tGameObject;
begin
  for go in objects do if go.status = GO_ACTIVE then go.draw(screen);
end;

procedure tGameObjectList<T>.update(elapsed: single);
var
  go: tGameObject;
begin
  for go in objects do if go.status = GO_ACTIVE then go.update(elapsed);
end;

{returns the next free object, or creats a new one of there are none free}
function tGameObjectList<T>.nextFree(): T;
var
  go: T;
begin
  {note: we could make this much faster by maintaining a list of known
   expired elements. For small lists it's no problem though.}
  for go in objects do begin
    if go.status = GO_EXPIRED then begin
      go.reset();
      exit(go);
    end;
  end;

  {ok we had none free, so create one}
  result := T.create();
  append(result);
end;

{----------------------------------------------------------}
{ tGameObject }
{----------------------------------------------------------}

constructor tGameObject.create();
begin
  reset();
end;

procedure tGameObject.reset();
begin
  fillchar((pByte(self) + sizeof(Pointer))^, self.InstanceSize - sizeof(Pointer), 0);
  status := GO_ACTIVE;
  col := RGB(255,0,255);
end;

procedure tGameObject.markAsDeleted();
begin
  status := GO_EXPIRED;
end;

procedure tGameObject.setSprite(aSprite: tSprite);
begin
  fSprite := aSprite;
  if assigned(fSprite) then begin
    bounds.width := fSprite.width;
    bounds.height := fSprite.height;
    offset.x := -fSprite.width div 2;
    offset.y := -fSprite.height div 2;
  end;
end;

function tGameObject.getX: integer; inline;
begin
  result := round(pos.x);
end;

function tGameObject.getY: integer; inline;
begin
  result := round(pos.y);
end;

{gets pixel color of object given input co-ords as world co-ords}
function tGameObject.getWorldPixel(atX, atY: integer): RGBA;
begin
  fillchar(result, sizeof(result), 0);
  if not assigned(sprite) then exit;
  result := sprite.getPixel(atX-bounds.x, atY-bounds.y);
end;

procedure tGameObject.draw(screen: tScreen);
begin
  screen.canvas.putPixel(xPos, yPos, col);
  screen.markRegion(rect(xPos, yPos, 1, 1));
end;

procedure tGameObject.update(elapsed: single);
begin
  pos := pos + (vel * elapsed);
  age += elapsed;
  if ttl > 0 then begin
    if age >= ttl then
      status := GO_EXPIRED;
  end;
  bounds.x := round(pos.x+offset.x);
  bounds.y := round(pos.y+offset.y);
end;

{----------------------------------------------------------}
{ tTank }
{----------------------------------------------------------}

constructor tTank.create();
begin
  inherited create();
  col := RGB(255,255,255);
  sprite := sprites['Tank'];
end;

procedure tTank.reset();
begin
  inherited reset();
  power := 10;
  health := 750;
end;

procedure tTank.draw(screen: tScreen);
begin
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
        if terrain.isSolid(xPos-32, yPos) then begin
          {make a little cloud}
          for i := 1 to 3 do begin
            p := particles.nextFree();
            p.pos := V2(xPos, yPos);
            p.vel := V2(rnd-128, rnd-128) * 0.2;
            p.solid := true;
            p.col := terrain.terrain.getPixel(xPos-32, yPos);
            p.ttl := 0.5;
            p.radius := 2;
          end;
          {burn it}
          terrain.burn(xlp-32, bounds.bottom, 3, round(hitPower/support));
        end;
      end;
      vel.y := 0;
    end;
  end;
end;

{tank takes damage at given location in world space. Sender is who delt the damage}
procedure tTank.takeDamage(atX,atY: integer; damage: integer; sender: tTank=nil);
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
var
  bullet: tBullet;
begin
  if status <> GO_ACTIVE then exit;
  if cooldown <= 0 then begin
    bullet := bullets.nextFree();
    bullet.pos := pos;
    bullet.vel := V2(sin(angle*DEG2RAD) * power * 10, -cos(angle*DEG2RAD) * power * 10);
    bullet.pos += bullet.vel.normed*6;
    bullet.owner := self;
    cooldown := 0.25;
    mixer.play(shootSFX, 0.2);
  end;
end;

procedure tTank.explode();
begin
  if status = GO_EXPIRED then exit;
  mixer.play(explodeSFX, 1.0);
  makeExplosion(xPos, yPos, 20);
  markAsDeleted();
end;

procedure tTank.adjust(deltaAngle, deltaPower: single);
begin
  if status <> GO_ACTIVE then exit;
  angle := clamp(angle + deltaAngle, -90, 90);
  power := clamp(power + deltaPower, 2, 16);
end;

{----------------------------------------------------------}
{ tBullet }
{----------------------------------------------------------}

procedure tBullet.reset();
begin
  inherited reset();
  col := RGB($ffffff86);
  offset.x := -1;
  offset.y := -1;
  bounds.width := 3;
  bounds.height := 3;
end;

procedure tBullet.explode();
begin
  mixer.play(explodeSFX, 0.3);
  makeExplosion(xPos, yPos, 10);
  //terrain.burn(xPos-32, yPos, 3, 30); // for bullets
  markAsDeleted();
end;

procedure tBullet.update(elapsed: single);
var
  c: RGBA;
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
  for tank in tanks.objects do begin
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

procedure tBullet.draw(screen: tScreen);
begin
  drawMarker(screen, xPos, yPos, col);
end;

{----------------------------------------------------------}

procedure tParticle.reset();
begin
  inherited reset();
  radius := 0;
  ttl := 1;
  col := RGB(255,0,0);
  radius := 1;
  solid := false;
end;

procedure tParticle.update(elapsed: single);
begin
  inherited update(elapsed);
  col.a := clamp(round(255*(1-(age/ttl))), 0, 255);
  if solid and terrain.isSolid(xPos-32, yPos) then begin
    pos -= vel * elapsed;
    vel.x := -vel.x * 0.8;
    vel.y := -vel.y * 0.8;
  end;
end;

procedure tParticle.draw(screen: tScreen);
begin
  if radius = 1 then
    inherited draw(screen)
  else
    drawMarker(screen, xPos, yPos, col);
end;

procedure updateAll(elapsed: single);
const
  stepSize = 0.01;
begin
  updateAccumlator += elapsed;
  while updateAccumlator >= stepSize do begin
    tanks.update(stepSize);
    bullets.update(stepSize);
    particles.update(stepSize);
    updateAccumlator -= stepSize;
  end;
end;

procedure drawAll(screen: tScreen);
begin
  tanks.draw(screen);
  bullets.draw(screen);
  particles.draw(screen);
end;

{----------------------------------------------------------}


procedure initObjects;
begin
  updateAccumlator := 0;
  tanks := tGameObjectList<tTank>.create();
  bullets := tGameObjectList<tBullet>.create();
  particles := tGameObjectList<tParticle>.create();
end;

procedure closeObjects;
begin
  tanks.free;
  bullets.free;
  particles.free;
end;

initialization
  initObjects();
finalization
  closeObjects();
end.
