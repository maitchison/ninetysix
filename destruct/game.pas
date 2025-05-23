unit game;

interface

uses
  {$i units},
  crt,
  uTank,
  uGameObjects,
  uWeapon,
  template,
  terraNova,
  controller;

type
  tHitInfo = record
    obj: tObject;     // nil if no hit, or we hit terrain.
    didHit: boolean;
    x,y: integer;
    procedure clear();
  end;

  tTankEnumerator = record
    private
      fIndex: Integer;
      fArray: array of tGameObject;
      function GetCurrent: tTank;
    public
      function moveNext: boolean;
      property current: tTank read getCurrent;
    end;

  tTankList = class(tGameObjectList)
    function  getTank(idx: integer): tTank;
    property  items[index: int32]: tTank read getTank; default;
    function  getEnumerator(): tTankEnumerator;
  end;

procedure updateAll(elapsed: single);
procedure drawAll(dc: tDrawContext);

function  nextProjectile: tProjectile;
function  nextParticle: tParticle;

procedure debugShowWorldPixels(dc: tDrawContext);
function  getObjectAtPos(x,y: integer; ignore: tGameObject=nil): tGameObject;
function  traceRay(x1,y1: integer; angle: single; maxDistance: integer; ignore: tObject=nil;power:single=0): tHitInfo;

procedure damagePlayers(x, y: integer; radius: integer; damage: integer;sender: tGameObject=nil);
function  randomTank(aTeam: tTeam): tTank;
function  playerCount(aTeam: tTeam): integer;

procedure screenDone();
procedure screenInit();

var
  screen: tScreen;
  tanks: tTankList;
  player1, player2: tController;
  terrain: tTerrain;
  gameTick: dword;

const
  GRAVITY = 241.5;

implementation

var
  updateAccumlator: single;


var
  particles: tGameObjectList;
  projectiles: tGameObjectList;

{----------------------------------------------------------}

function tTankEnumerator.moveNext: boolean;
begin
  inc(fIndex);
  result := fIndex < length(fArray);
end;

function tTankEnumerator.getCurrent: tTank;
begin
  result := tTank(fArray[fIndex]);
end;

function tTankList.getTank(idx: integer): tTank;
var
  go: tGameObject;
begin
  go := objects[idx];
  {$ifdef DEBUG}
  assert(go is tTank, 'Object is not a tTank');
  {$endif}
  result := tTank(go);
end;

function tTankList.getEnumerator(): tTankEnumerator;
begin
  result.fArray := objects;
  result.fIndex := -1;
end;

{----------------------------------------------------------}

procedure tHitInfo.clear();
begin
  self.didHit := false;
  self.obj := nil;
  self.x := 0;
  self.y := 0;
end;

{returns a random tank belonging to given team, or nil if there are none}
function randomTank(aTeam: tTeam): tTank;
var
  teamTanks: tIntList;
  i: integer;
begin
  teamTanks.clear();
  for i := 0 to length(tanks.objects)-1 do
    if (tanks[i].team = aTeam) and tanks[i].isActive then
      teamTanks.append(i);
  if teamTanks.len = 0 then exit(nil);
  result := tanks[teamTanks[rnd(teamTanks.len)]];
end;

{returns number of players left alive on team}
function playerCount(aTeam: tTeam): integer;
var
  tank: tGameObject;
begin
  result := 0;
  for tank in tanks.objects do
    if (tTank(tank).team = aTeam) and tank.isActive then
      inc(result);
end;

{damage all players within area, using linear falloff
 sender is who caused the damage (if any).}
procedure damagePlayers(x, y: integer; radius: integer; damage: integer;sender: tGameObject=nil);
var
  tank: tTank;
  distance: single;
begin
  for tank in tanks do begin
    distance := V2(x-tank.xPos, y-tank.yPos).abs;
    if distance > radius then continue;
    tank.takeDamage(tank.xPos, tank.yPos, round(damage * (1-(distance / radius))), sender);
  end;

end;

{returns first object that ray intersects with}
{also adds particles, if power > 0}
function traceRay(x1,y1: integer; angle: single; maxDistance: integer; ignore: tObject=nil;power: single=0): tHitInfo;
var
  x,y: single;
  rx,ry: integer;
  dx, dy: single;
  i: integer;
  go: tGameObject;
  p: tParticle;

begin

  result.clear();
  dx := sin(angle*DEG2RAD);
  dy := -cos(angle*DEG2RAD);
  x := x1+0.5; y := y1+0.5;
  for i := 0 to maxDistance do begin
    rx := round(x); ry := round(y);
    if word(rx) > 255 then break;

    if rnd < (64*power) then begin
      p := nextParticle();
      if assigned(p) then begin
        p.pos.x := x;
        p.pos.y := y;
        p.col.init(255,round(70*power),round(30*power));
        p.blend := TDM_ADD;
        p.radius := 1;
        p.vel.x := gaus * 20;
        p.vel.y := gaus * 20;
        p.ttl := 0.1;
      end;
    end;

    if terrain.isSolid(rx, ry) then begin
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

procedure debugShowWorldPixels(dc: tDrawContext);
var
  x,y: integer;
begin
  for y := 0 to 255 do
    for x := 0 to 255 do
      if assigned(getObjectAtPos(x,y)) then
        dc.putPixel(Point(x, y), RGB(255,0,255));
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
    inc(gameTick);
  end;
end;

procedure drawAll(dc: tDrawContext);
var
  tank: tTank;
begin
  tanks.draw(dc);
  particles.draw(dc);
  projectiles.draw(dc);
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
  screen.background := tPage.create(screen.width, screen.height);
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
  t: tTank;
begin
  updateAccumlator := 0;
  projectiles := tGameObjectList.create(1*1024);
  particles := tGameObjectList.create(16*1024);

  {init our 10 tanks}
  tanks := tTankList.create(10);
  for i := 0 to 10-1 do begin
    t := tTank.create();
    t.status := GO_EMPTY;
    tanks.append(t);
  end;

  {for performance reason init some empty objects}
  for i := 0 to 2*1024-1 do begin
    p := tParticle.create();
    p.markForRemoval();
    particles.append(p);
  end;

  player1 := nil;
  player2 := nil;

  terrain := tTerrain.create();
  terrain.onCellDamage := uTank.respondToTankCellDamage();

end;

procedure closeObjects;
var
  tank: tTank;
begin
  tanks.free;
  projectiles.free;
  particles.free;
  terrain.free;
end;

initialization
  initObjects();
finalization
  closeObjects();
end.
