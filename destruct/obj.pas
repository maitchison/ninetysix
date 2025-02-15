unit obj;

interface

uses
  {$i units};

type

  tGameObjectStatus = (GO_EMPTY, GO_PENDING_DELETE, GO_ACTIVE);

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

  tGameObjectList = class
  public
    objects: array of tGameObject;
    procedure append(o: tGameObject);
    procedure draw(screen: tScreen);
    procedure update(elapsed: single);
    function  nextFree(): tGameObject;
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

implementation

uses
  uTank, uBullet, terra, fx;

{----------------------------------------------------------}
{ tGameObjects }
{----------------------------------------------------------}

procedure tGameObjectList.append(o: tGameObject);
begin
  setLength(objects, length(objects)+1);
  objects[length(objects)-1] := o;
end;

procedure tGameObjectList.draw(screen: tScreen);
var
  go: tGameObject;
begin
  for go in objects do if go.status = GO_ACTIVE then go.draw(screen);
end;

procedure tGameObjectList.update(elapsed: single);
var
  go: tGameObject;
begin
  {remove tagged objects}
  {note: in the future we'll add these to a stack of 'free' slots}
  for go in objects do if go.status = GO_PENDING_DELETE then
    go.status := GO_EMPTY;
  {update}
  for go in objects do if go.status = GO_ACTIVE then go.update(elapsed);
end;

{returns the next free object, or nill if there are none free}
function tGameObjectList.nextFree(): tGameObject;
var
  go: tGameObject;
begin
  result := nil;
  {note: we could make this much faster by maintaining a list of known
   expired elements. For small lists it's no problem though.}
  for go in objects do begin
    if go.status = GO_EMPTY then begin
      go.reset();
      exit(go);
    end;
  end;
end;

{----------------------------------------------------------}
{ tGameObject }
{----------------------------------------------------------}

constructor tGameObject.create();
begin
  inherited create();
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
  status := GO_PENDING_DELETE;
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
      status := GO_PENDING_DELETE;
  end;
  bounds.x := round(pos.x+offset.x);
  bounds.y := round(pos.y+offset.y);
end;

{--------------------------------------}

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

begin
end.
