unit uBullet;

interface

uses
  {$i units},
  obj;

type
  tBullet = class(tGameObject)
    owner: tGameObject;
    procedure reset(); override;
    procedure explode();
    procedure update(elapsed: single); override;
    procedure draw(screen: tScreen); override;
  end;

implementation

uses
  fx, res, uTank, game, terra;

procedure tBullet.reset();
begin
  inherited reset();
  col := RGB($ffffff86);
  offset.x := -1;
  offset.y := -1;
  bounds.width := 3;
  bounds.height := 3;
end;

procedure tBullet.explode();
begin
  mixer.play(explodeSFX, 0.3);
  makeExplosion(xPos, yPos, 10);
  //terrain.burn(xPos-32, yPos, 3, 30); // for bullets
  markAsDeleted();
end;

procedure tBullet.update(elapsed: single);
var
  c: RGBA;
  go: tGameObject;
  tank: tTank;
begin
  {gravity}
  vel.y += 58 * elapsed;
  {move}
  inherited update(elapsed);
  {see if we're out of bounds}
  if (xPos < 32) or (xPos > 256+32) or (yPos > 256) then begin
    markAsDeleted();
    exit;
  end;
  {check if we collided with tank}
  for go in tanks.objects do begin
    tank := tTank(go);
    if tank.status <> GO_ACTIVE then continue;
    {make sure we don't collide with ourself as soon as we fire}
    if (tank = self.owner) and (age < 0.10) then continue;
    c := tank.getWorldPixel(xPos, yPos);
    if c.a > 0 then begin
      tank.takeDamage(xPos, yPos, 100, owner);
      makeSparks(xPos, yPos, 3, 5, -vel.x, -vel.y);
      explode();
      exit;
    end;
  end;
  {check if we collided with terrain}
  if terrain.isSolid(xPos-32, yPos) then begin
    explode();
    exit;
  end;
end;

procedure tBullet.draw(screen: tScreen);
begin
  drawMarker(screen, xPos, yPos, col);
end;

{----------------------------------------------------------}

begin
end.
