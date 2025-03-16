unit uGameObjects;

interface

uses
  {$i units},
  terraNova,
  template;

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
    hasGravity: boolean;
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
    procedure draw(const dc: tDrawContext); virtual;
    procedure drawBounds(dc: tDrawContext);
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
    procedure draw(dc: tDrawContext); virtual;
    procedure update(elapsed: single); virtual;
    function  nextFree(): tGameObject;
  end;

  tParticle = class(tGameObject)
  public
    solid: boolean;
    burn: integer;
    blend: tTemplateDrawMode;
    cell: tCellInfo; {will create this kind of particle on contact}
  public
    procedure reset(); override;
    procedure update(elapsed: single); override;
    procedure draw(const dc: tDrawContext); override;
  end;

var
  DEBUG_DRAW_BOUNDS: boolean = false;

implementation

uses
  uTank, uWeapon, fx, game, res;

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

procedure tGameObjectList.draw(dc: tDrawContext);
var
  go: tGameObject;
begin
  for go in objects do
    if go.status = GO_ACTIVE then begin
      go.draw(dc);
      if DEBUG_DRAW_BOUNDS then go.drawBounds(dc);
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
  hasGravity := false;
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

procedure tGameObject.draw(const dc: tDrawContext);
begin
  dc.putPixel(Point(xPos, yPos), col);
end;

procedure tGameObject.drawBounds(dc: tDrawContext);
begin
  dc.putPixel(Point(xPos, yPos), col);
  if radius <= 1 then exit;
  dc.drawRect(getBounds(), col);
end;

procedure tGameObject.update(elapsed: single);
begin
  pos := pos + (vel * elapsed);
  age += elapsed;

  if hasGravity then
    vel.y += elapsed * GRAVITY;

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
  burn := 0;
  blend := TDM_BLEND;
  cell.dType := DT_EMPTY;
  cell.strength := 0;
end;

procedure tParticle.update(elapsed: single);
var
  factor: single;
begin
  inherited update(elapsed);
  factor := age/ttl;

  col.a := clamp(round(255*(1-factor)), 0, 255);

  if solid and (not terrain.isEmpty(xPos, yPos)) then begin
    if burn > 0 then
      terrain.burn(xPos, yPos, 1, burn);
    if cell.dType <> DT_EMPTY then
      terrain.putDirt(xPos, yPos, cell);
    markForRemoval();
  end;
end;

procedure tParticle.draw(const dc: tDrawContext);
var
  r: tRect;
  dx,dy: integer;
begin
  if radius <= 0 then exit;

  // faster special case for radius=1
  if (radius = 1) and (blend = TDM_BLEND) then begin
    {it's a little faster to do this directly than to go via DC}
    dx := xPos+dc.offset.x;
    dy := yPos+dc.offset.y;
    dc.page.putPixel(dx, dy, col);
    dc.markRegion(Rect(dx, dy, 1, 1));
    exit;
  end;
  {todo: hmm... update this so that DC understand page8? prob not...}
  r := particleTemplate.draw(dc.page, dc.offset.x+xPos, dc.offset.y+yPos, radius-1, col, blend);
  dc.markRegion(r);
end;

begin
end.
