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
    ttl: single;
    status: tGameObjectStatus;
  protected
    function getX: integer;
    function getY: integer;
    procedure setSprite(aSprite: tSprite);
  public
    constructor create(); virtual;
    procedure clear(); virtual;
    procedure draw(screen: tScreen); virtual;
    procedure update(elapsed: single); virtual;
    procedure markAsDeleted();

    property sprite: tSprite read fSprite write setSprite;
    property x: integer read getX;
    property y: integer read getY;
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
    cooldown: single;
    angle: single;
    power: single;
  public
    constructor create(); override;
    procedure clear(); override;
    procedure update(elapsed: single); override;
    procedure draw(screen: tScreen); override;
    procedure adjust(deltaAngle, deltaPower: single);

    procedure fire();
  end;

  tBullet = class(tGameObject)
    procedure clear(); override;
    procedure update(elapsed: single); override;
    procedure draw(screen: tScreen); override;
  end;

{may as well put globals here}
var
  tanks: tGameObjectList<tTank>;
  bullets: tGameObjectList<tBullet>;


implementation

uses
  res, terra;

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
  screen.canvas.putPixel(x, y-1, c);
  screen.canvas.putPixel(x+1, y, c);
  screen.canvas.putPixel(x, y+1, c);
  screen.markRegion(rect(x-1, y-1, 3, 3));
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
      go.clear();
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
  clear();
end;

procedure tGameObject.clear();
begin
  ttl := 0;
  status := GO_ACTIVE;
  col := RGB(255,0,255);
  sprite := nil;
  pos := V2(0,0);
  vel := V2(0,0);
  offset := V2(0, 0);
  bounds := rect(0, 0, 0, 0);
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

procedure tGameObject.draw(screen: tScreen);
begin
  screen.canvas.putPixel(round(pos.x), round(pos.y), col);
end;

procedure tGameObject.update(elapsed: single);
begin
  pos := pos + (vel * elapsed);
  if ttl > 0 then begin
    ttl -= elapsed;
    if ttl < 0 then
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

procedure tTank.clear();
begin
  inherited clear();
  cooldown := 0;
  angle := 0;
  power := 10;
end;

procedure tTank.draw(screen: tScreen);
begin
  sprite.draw(screen.canvas, bounds.x, bounds.y);
  screen.markRegion(bounds);
  {draw target}
  drawMarker(
    screen,
    x + sin(angle*DEG2RAD) * power * 2,
    y - cos(angle*DEG2RAD) * power * 2,
    RGB(255,128,128)
  );

end;

procedure tTank.update(elapsed: single);
begin
  inherited update(elapsed);
  if cooldown > 0 then cooldown -= elapsed;
end;

procedure tTank.fire();
var
  bullet: tBullet;
begin
  if cooldown <= 0 then begin
    bullet := bullets.nextFree();
    bullet.pos := pos;
    bullet.vel := V2(sin(angle*DEG2RAD) * power * 10, -cos(angle*DEG2RAD) * power * 10);
    cooldown := 0.25;
    mixer.play(shootSFX);
  end;
end;

procedure tTank.adjust(deltaAngle, deltaPower: single);
begin
  angle := clamp(angle + deltaAngle, -90, 90);
  power := clamp(power + deltaPower, 2, 16);
end;

{----------------------------------------------------------}
{ tBullet }
{----------------------------------------------------------}

procedure tBullet.clear();
begin
  inherited clear();
  col := RGB($ffffff86);
  offset.x := -1;
  offset.y := -1;
  bounds.width := 3;
  bounds.height := 3;
end;

procedure tBullet.update(elapsed: single);
begin
  {gravity}
  vel.y += 58 * elapsed;
  {move}
  inherited update(elapsed);
  {see if we're out of bounds}
  if (x < -32) or (x > 256+32) or (y > 256) then
    markAsDeleted();
  {check if we collided with terrain}
  if terrain.terrain.getPixel(x-32, y).a > 0 then
    markAsDeleted();
end;

procedure tBullet.draw(screen: tScreen);
begin
  drawMarker(screen, x, y, col);
end;

{----------------------------------------------------------}


procedure initObjects;
begin
  tanks := tGameObjectList<tTank>.create();
  bullets := tGameObjectList<tBullet>.create();
end;

procedure closeObjects;
begin
  tanks.free;
  bullets.free;
end;

initialization
  initObjects();
finalization
  closeObjects();
end.
