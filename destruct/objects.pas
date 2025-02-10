unit objects;

interface

uses
  vertex,
  graph32, screen;

type

  tObjectStatus = (OS_EXPIRED, OS_ACTIVE);

  tObject = class
  public
    pos, vel: V2D;
    col: RGBA;
    ttl: single;
    status: tObjectStatus;
  public
    constructor create(); overload;
    constructor create(x,y: single); overload;
    procedure draw(screen: tScreen); virtual;
    procedure update(elapsed: single); virtual;
  end;

  tTank = class(tObject)
    constructor create(x,y: single);
  end;

  tBullet = class(tObject)
  end;

  tObjectList = class
    objects: array of tObject;
    procedure append(o: tObject);
    procedure draw(screen: tScreen);
    procedure update(elapsed: single);
  end;

implementation

uses terrain;

{----------------------------------------------------------}
{ tObjects }
{----------------------------------------------------------}

procedure tObjectList.append(o: tObject);
begin
  setLength(objects, length(objects)+1);
  objects[length(objects)-1] := o;
end;

procedure tObjectList.draw(screen: tScreen);
var
  o: tObject;
begin
  for o in objects do o.draw(screen);
end;

procedure tObjectList.update(elapsed: single);
var
  o: tObject;
begin
  for o in objects do o.update(elapsed);
end;

{----------------------------------------------------------}
{ tObject }
{----------------------------------------------------------}

constructor tObject.create();
begin
  ttl := 0;
  status := OS_ACTIVE;
  col := RGB(255,0,255);
end;

constructor tObject.create(x,y: single);
begin
  create();
  pos := V2(x,y);
end;

procedure tObject.draw(screen: tScreen);
begin
  screen.canvas.putPixel(round(pos.x), round(pos.y), col);
end;

procedure tObject.update(elapsed: single);
begin
  pos := pos + (vel * elapsed);
  if ttl > 0 then begin
    ttl -= elapsed;
    if ttl < 0 then
      status := OS_EXPIRED;
  end;
end;

{----------------------------------------------------------}
{ tTank }
{----------------------------------------------------------}

constructor tTank.create(x,y: single);
begin
  inherited create(x,y );
  col := RGB(255,0,0);
end;


{----------------------------------------------------------}
{ tBullet }
{----------------------------------------------------------}

begin
end.