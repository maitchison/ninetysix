unit game;

interface

uses
  {$i units},
  crt,
  uWeapon, uTank, obj;

type
  tHitInfo = record
    obj: tObject;     // nil if no hit, or we hit terrain.
    didHit: boolean;
    x,y: integer;
    procedure clear();
  end;

procedure updateAll(elapsed: single);
procedure drawAll(screen: tScreen);

function  nextProjectile: tProjectile;
function  nextParticle: tParticle;

function  getObjectAtPos(x,y: integer; ignore: tGameObject=nil): tGameObject;
function  traceRay(x1,y1: integer; angle: single; maxDistance: integer; ignore: tObject=nil): tHitInfo;

procedure screenDone();
procedure screenInit();

var
  screen: tScreen;
  tanks: array of tTank;

implementation

uses
  terra;

var
  updateAccumlator: single;

var
  particles: tGameObjectList;
  projectiles: tGameObjectList;

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
function getObjectAtPos(x,y: integer; ignore: tGameObject=nil): tGameObject;
var
  tank: tTank;
  c: RGBA;
begin
  result := nil;
  {todo: we should implement a grid system, and maybe bounding rects as well}
  {note: this would enable projectile collisions too}
  for tank in tanks do begin
    if not tank.isActive then continue;
    if (tank = ignore) then continue;
    c := tank.getWorldPixel(x, y);
    if c.a > 0 then
      exit(tank);
  end;
end;

function nextProjectile: tProjectile;
var
  go: tGameObject;
begin
  go := projectiles.nextFree;
  if assigned(go) then
    result := tProjectile(go)
  else begin
    result := tProjectile.create();
    projectiles.append(result);
  end;
end;

function nextParticle: tParticle;
var
  go: tGameObject;
begin
  go := particles.nextFree();
  if assigned(go) then
    result := tParticle(go)
  else begin
    result := tParticle.create();
    particles.append(result);
  end;
end;

procedure updateAll(elapsed: single);
const
  stepSize = 1/180;
var
  tank: tTank;
begin
  // no reason for particles do do small updates
  particles.update(elapsed);

  updateAccumlator += elapsed;
  while updateAccumlator >= stepSize do begin
    for tank in tanks do if tank.isActive then tank.update(stepSize);
    projectiles.update(stepSize);
    updateAccumlator -= stepSize;
  end;
end;

procedure drawAll(screen: tScreen);
var
  tank: tTank;
begin
  for tank in tanks do if tank.isActive then tank.draw(screen);
  particles.draw(screen);
  projectiles.draw(screen);
end;

procedure screenInit();
begin
  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    fatal('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    fatal('Requires 1MB video card.');

  videoDriver.setTrueColor(320, 240);
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;
end;

procedure screenDone();
begin
  videoDriver.setText();
  textAttr := LIGHTGRAY;
end;

{----------------------------------------------------------}

procedure initObjects;
var
  i: integer;
  p: tParticle;
begin
  updateAccumlator := 0;
  projectiles := tGameObjectList.create(1*1024);
  particles := tGameObjectList.create(16*1024);

  {init our 10 tanks}
  setLength(tanks, 10);
  for i := 0 to length(tanks)-1 do begin
    tanks[i] := tTank.create();
    tanks[i].status := GO_EMPTY;
  end;

  {for performance reason init some empty objects}
  for i := 0 to 2*1024-1 do begin
    p := tParticle.create();
    p.markForRemoval();
    particles.append(p);
  end;

end;

procedure closeObjects;
var
  tank: tTank;
begin
  for tank in tanks do tank.free();
  setLength(tanks, 0);
  projectiles.free;
  particles.free;
end;

initialization
  initObjects();
finalization
  closeObjects();
end.
