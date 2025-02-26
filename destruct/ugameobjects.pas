unit uGameObjects;

interface

uses
  {$i units};

type

  tGameObjectStatus = (GO_EMPTY, GO_PENDING_REMOVAL, GO_ACTIVE);

  tGameObject = class
  public
    pos, vel: V2D;
    radius: integer;
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
    function  isActive: boolean;
    function  getWorldPixel(atX, atY: integer): RGBA;
    function  getBounds(xOffset:integer=0;yOffset: integer=0): tRect;
    procedure draw(screen: tScreen); virtual;
    procedure drawBounds(screen: tScreen);
    procedure update(elapsed: single); virtual;
    procedure markForRemoval();

    property sprite: tSprite read fSprite write setSprite;
    property xPos: integer read getX;
    property yPos: integer read getY;
  end;

  {todo: think about changing this to one big block of memory..
   perhaps with objects instead of classes.
   also.. I think remove append and just have static storage for n items
   }
  tGameObjectList = class
  public
    objects: array of tGameObject;
    // index of objects that are currently avaliable
    freeObjects: array of integer;
    // number of currently free objects
    numFreeObjects: integer;
    constructor create(maxObjects: integer);
    procedure append(o: tGameObject);
    procedure draw(screen: tScreen); virtual;
    procedure update(elapsed: single); virtual;
    function  nextFree(): tGameObject;
  end;

  tParticle = class(tGameObject)
  public
    solid: boolean;
  public
    procedure reset(); override;
    procedure update(elapsed: single); override;
    procedure draw(screen: tScreen); override;
  end;

var
  DEBUG_DRAW_BOUNDS: boolean = false;

implementation

uses
  uTank, uWeapon, terraNova, fx, game, template, res;

{----------------------------------------------------------}
{ tGameObjects }
{----------------------------------------------------------}

constructor tGameObjectList.create(maxObjects: integer);
begin
  inherited create();
  setLength(freeObjects, maxObjects);
  numFreeObjects := 0;
end;

procedure tGameObjectList.append(o: tGameObject);
begin
  setLength(objects, length(objects)+1);
  objects[length(objects)-1] := o;
end;

procedure tGameObjectList.draw(screen: tScreen);
var
  go: tGameObject;
begin
  for go in objects do
    if go.status = GO_ACTIVE then begin
      go.draw(screen);
      if DEBUG_DRAW_BOUNDS then go.drawBounds(screen);
    end;
end;

procedure tGameObjectList.update(elapsed: single);
var
  i: integer;
  go: tGameObject;
begin
  {remove tagged objects}
  for i := 0 to length(objects)-1 do begin
    go := objects[i];
    case go.status of
      GO_EMPTY: ;
      GO_PENDING_REMOVAL: begin
        freeObjects[numFreeObjects] := i;
        inc(numFreeObjects);
        go.status := GO_EMPTY;
      end;
      GO_ACTIVE: go.update(elapsed);
    end;
  end;
end;

{returns the next free object, or nil if there are none free}
function tGameObjectList.nextFree(): tGameObject;
begin
  if numFreeObjects = 0 then exit(nil);
  {requester must init this object... otherwise it'll be lost forever..
   only way around this is to trigger removal when active is set... but
   I don't like that much at all}
  dec(numFreeObjects);
  result := objects[freeObjects[numFreeObjects]];
  result.reset();
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
  pos := V2(0,0);
  vel := V2(0,0);
  radius := 1;
  sprite := nil;
  col := RGB(255,0,255);
  age := 0;
  ttl := 0;
  status := GO_ACTIVE;
end;

procedure tGameObject.markForRemoval();
begin
  status := GO_PENDING_REMOVAL;
end;

procedure tGameObject.setSprite(aSprite: tSprite);
var
  halfw,halfh: single;
begin
  fSprite := aSprite;
  {update radius}
  if assigned(fSprite) then begin
    halfw := fSprite.width/2;
    halfh := fSPrite.height/2;
    radius := ceil(sqrt(halfw*halfw+halfh*halfh));
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

function tGameObject.isActive: boolean; inline;
begin
  result := status = GO_ACTIVE;
end;

{gets pixel color of object given input co-ords as world co-ords}
function tGameObject.getWorldPixel(atX, atY: integer): RGBA;
begin
  fillchar(result, sizeof(result), 0);
  if not assigned(sprite) then exit;
  {todo: I think this is wrong}
  result := sprite.getPixel(atX-xPos+(sprite.pivot2x.x div 2), atY-yPos+(sprite.pivot2x.y div 2));
end;

{returns bounds for object (based on radius). Optional offset}
function tGameObject.getBounds(xOffset:integer=0;yOffset: integer=0): tRect;
begin
  if radius <= 0 then exit(Rect(xPos+xOffset, yPos+yOffset, 0, 0));
  result.init(
    xPos+xOffset-radius+1,
    yPos+yOffset-radius+1,
    radius*2-1,
    radius*2-1
  );
end;

procedure tGameObject.draw(screen: tScreen);
begin
  screen.canvas.putPixel(xPos+32, yPos, col);
  screen.markRegion(rect(xPos+32, yPos, 1, 1));
end;

procedure tGameObject.drawBounds(screen: tScreen);
var
  bounds: tRect;
begin
  screen.canvas.putPixel(xPos+32, yPos, col);
  if radius <= 1 then exit;
  bounds := getBounds(32, 0);
  screen.canvas.drawRect(bounds, col);
  screen.markRegion(bounds);
end;

procedure tGameObject.update(elapsed: single);
begin
  pos := pos + (vel * elapsed);
  age += elapsed;

  if ttl > 0 then begin
    if age >= ttl then
      status := GO_PENDING_REMOVAL;
  end;
end;

{--------------------------------------}

procedure tParticle.reset();
begin
  inherited reset();
  ttl := 1;
  col := RGB(255,0,0);
  solid := false;
end;

procedure tParticle.update(elapsed: single);
begin
  inherited update(elapsed);
  col.a := clamp(round(255*(1-(age/ttl))), 0, 255);
  if solid and terrain.isSolid(xPos, yPos) then
    markForRemoval();
end;

procedure tParticle.draw(screen: tScreen);
var
  r: tRect;
begin
  {todo: implement template based particles}

  //stub:

  r := particleTemplate.drawAdd(screen.canvas, 32+xPos, yPos, 1, col);
  screen.markRegion(r);
                       {
  if radius = 1 then begin
    screen.canvas.putPixel(32+xPos, yPos, col);
    screen.markPixel(32+xPos, yPos);
  end else
    drawMarker(screen, xPos, yPos, col);
  }
end;

begin
end.
