unit game;

interface

uses
  {$i units},
  uBullet, uTank, obj;

type
  tHitInfo = record
    obj: tObject;     // nil if no hit, or we hit terrain.
    didHit: boolean;
    x,y: integer;
    procedure clear();
  end;

procedure updateAll(elapsed: single);
procedure drawAll(screen: tScreen);

function  nextBullet: tBullet;
function  nextParticle: tParticle;
function  getTank(id: integer;team: integer): tTank;

function  getObjectAtPos(x,y: integer): tGameObject;
function  traceRay(x1,y1: integer; angle: single; maxDistance: integer; ignore: tObject=nil): tHitInfo;

var
  screen: tScreen;

var
  tanks: tGameObjectList;

implementation

uses
  terra;

var
  updateAccumlator: single;

var
  particles: tGameObjectList;
  bullets: tGameObjectList;

{----------------------------------------------------------}

procedure tHitInfo.clear();
begin
  self.didHit := false;
  self.obj := nil;
  self.x := 0;
  self.y := 0;
end;

{returns first object that ray intersects with}
function traceRay(x1,y1: integer; angle: single; maxDistance: integer; ignore: tObject=nil): tHitInfo;
var
  x,y: single;
  rx,ry: integer;
  dx, dy: single;
  i: integer;
  go: tGameObject;
  p: tParticle;

  {mu=0, var=~1}
  function fakeGausian: single;
  var
    i: integer;
  begin
    result := 0;
    for i := 1 to 6 do
      result += rnd;
    result *= (1/256);
    result -= 3;
  end;

begin

  result.clear();
  dx := sin(angle*DEG2RAD);
  dy := -cos(angle*DEG2RAD);
  x := x1+0.5; y := y1+0.5;
  for i := 0 to maxDistance do begin
    rx := round(x); ry := round(y);

    if rnd > 128 then begin
      p := nextParticle();
      if assigned(p) then begin
        p.pos.x := x;
        p.pos.y := y;
        p.vel.x := fakeGausian * 20;
        p.vel.y := fakeGausian * 20;
        p.ttl := 0.1;
      end;
    end;

    if not terrain.isEmpty(rx-32, ry) then begin
      result.didHit := true;
      result.obj := nil;
      result.x := rx;
      result.y := ry;
      exit;
    end;
    go := getObjectAtPos(rx, ry);
    if assigned(go) and (go <> ignore) then begin
      result.didHit := true;
      result.obj := go;
      result.x := rx;
      result.y := ry;
      exit;
    end;
    x += dx;
    y += dy;
  end;
end;

{returns the object at given location}
function getObjectAtPos(x,y: integer): tGameObject;
var
  go: tGameObject;
  tank: tTank;
  c: RGBA;
begin
  result := nil;
  {todo: we should implement a grid system, and maybe bounding rects as well}
  {note: this would enable bullet collisions too}
  for go in tanks.objects do begin
    tank := tTank(go);
    if tank.status <> GO_ACTIVE then continue;
    c := tank.getWorldPixel(x, y);
    if c.a > 0 then
      exit(tank);
  end;
end;

function nextBullet: tBullet;
var
  go: tGameObject;
begin
  go := bullets.nextFree;
  if assigned(go) then
    result := tBullet(go)
  else begin
    result := tBullet.create();
    bullets.append(result);
  end;
end;

function nextParticle: tParticle;
var
  go: tGameObject;
begin
  go := particles.nextFree;
  if assigned(go) then
    result := tParticle(go)
  else begin
    result := tParticle.create();
    particles.append(result);
  end;
end;

function  getTank(id: integer;team: integer): tTank;
begin
  {todo: support multiple tanks per team}
  assert(id = 0);
  result := tTank(tanks.objects[team]);
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
  tanks := tGameObjectList.create();
  bullets := tGameObjectList.create();
  particles := tGameObjectList.create();
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
