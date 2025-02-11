unit gameObj;

interface

uses
  debug, test,
  vertex,
  sprite,
  utils,
  mixLib,
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
  public
    constructor create(); override;
    procedure clear(); override;
    procedure update(elapsed: single); override;
    procedure draw(screen: tScreen); override;
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
  resLib, terrain;

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
end;

procedure tTank.draw(screen: tScreen);
begin
  sprite.draw(screen.canvas, bounds.x, bounds.y);
  screen.markRegion(bounds);
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
    bullet.vel := V2(-100, 0);
    cooldown := 0.25;
    mixer.play(shootSFX);
  end;
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
  vel.y += 5.8 * elapsed;
  {move}
  inherited update(elapsed);
  {see if we're out of bounds}
  if (x < -32) or (x > 256+32) then
    markAsDeleted();
end;

procedure tBullet.draw(screen: tScreen);
var
  i: integer;
  c: RGBA;
begin
  c := self.col;
  c.a := c.a div 2;
  for i := -1 to 1 do begin
    screen.canvas.putPixel(x+i, y, c);
    screen.canvas.putPixel(x, y+i, c);
  end;
  note(bounds.toString);
  screen.markRegion(bounds);
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
