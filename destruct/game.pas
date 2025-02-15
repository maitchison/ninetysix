unit game;

interface

uses
  {$i units},
  uBullet, uTank, obj;

procedure updateAll(elapsed: single);
procedure drawAll(screen: tScreen);

function  nextBullet: tBullet;
function  nextParticle: tParticle;
function  getTank(id: integer;team: integer): tTank;

var
  tanks: tGameObjectList;

implementation

var
  updateAccumlator: single;

var
  particles: tGameObjectList;
  bullets: tGameObjectList;

{----------------------------------------------------------}

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
