unit game;

interface

uses
  {$i units},
  uBullet, uTank, obj;

procedure updateAll(elapsed: single);
procedure drawAll(screen: tScreen);
function nextBullet: tBullet;

implementation

var
  updateAccumlator: single;

var
  particles: tGameObjectList<tParticle>;
  bullets: tGameObjectList<tBullet>;
  tanks: tGameObjectList<tTank>;

{----------------------------------------------------------}

function nextBullet: tBullet;
begin
  result := bullets.nextFree;
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
  tanks := tGameObjectList<tTank>.create();
  bullets := tGameObjectList<tBullet>.create();
  particles := tGameObjectList<tParticle>.create();
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
