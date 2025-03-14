{special effects for game}
unit fx;

interface

uses
  {$i units},
  template,
  terraNova,
  uGameObjects;

procedure drawMarker(dc: tDrawContext; atX,atY: single; col: RGBA);
procedure doBump(atX, atY: integer; radius: integer;power: single);
procedure makeExplosion(atX, atY: single; power: single);
procedure makeSmoke(atX, atY: single; power: single; vel: single=10;vx: single=0; vy: single=0);
procedure makeDust(atX, atY: integer; radius: integer; dType: tDirtType; vel: single=25.0; vx: single=0; vy: single=0;density: single = 1.0);
procedure makeElectricSparks(atX, atY: single; radius: single; vel: single=25.0; vx: single=0; vy: single=0; n: integer=-1);
procedure makeSparks(atX, atY: single; radius: single; vel: single=25.0; vx: single=0; vy: single=0;n: integer=-1);

implementation

uses
  game;

{----------------------------------------------------------}
{ helpers }
{----------------------------------------------------------}

procedure drawMarker(dc: tDrawContext; atX,atY: single; col: RGBA);
var
  x,y: integer;
  c: RGBA;
begin
  x := round(atX);
  y := round(atY);

  dc.putPixel(Point(x, y), col);
  c := col;
  c.a := c.a div 2;
  dc.putPixel(Point(x-1, y), c);
  dc.putPixel(Point(x+1, y), c);
  dc.putPixel(Point(x, y-1), c);
  dc.putPixel(Point(x, y+1), c);
end;

{turns cells into dust particles}
procedure doBump(atX, atY: integer; radius: integer;power: single);
var
  i: integer;
  p: tParticle;
  z: single;
  angle: single;
  dx,dy: integer;
  x,y: integer;
  r2,d2: integer;
  cell, emptyCell: tCellInfo;
  decay: integer;
  impact: single;
  factor: single;
begin
  r2 := radius*radius;
  emptyCell.dType := DT_EMPTY;
  emptyCell.strength := 0;
  for dy := -radius to + radius do begin
    for dx := -radius to +radius do begin
      d2 := (dx*dx)+(dy*dy);
      if d2 > r2 then continue;
      cell := terrain.getCell(atX+dx, atY+dy);
      if cell.dType in [DT_EMPTY, DT_BEDROCK, DT_TANKCORE, DT_ROCK] then continue;
      decay := TERRAIN_DECAY[cell.dType];
      if decay < 1 then decay := 1;
      if (cell.dType = DT_LAVA) then decay := 4;
      z := 1-(sqrt(d2)/radius);
      impact := power * z;
      if 2*decay*impact < (cell.strength) then continue;

      terrain.setCell(atX+dx, atY+dy, emptyCell);
      p := nextParticle();
      p.pos.x := atX + dx;
      p.pos.y := atY + dy;

      p.vel := V2(dx,dy).normed()*10;
      p.vel += V2((rnd-128) * 0.1, (rnd-128) * 0.1);
      p.vel.y += -75;

      {make edges of explosion less serious}
      factor := minf(z*2, 1.0);
      p.vel *= factor;

      p.ttl := 10;
      p.solid := true;
      p.radius := 1;
      p.cell := cell;
      p.col := terrain.getCellColor(p.cell);
      p.hasGravity := true;
    end;
  end;
end;


procedure makeExplosion(atX, atY: single; power: single);
var
  i: integer;
  p: tParticle;
  radius, r2: single;
  inv256: single;
  n: integer;
  z: single;
  angle: single;
  dx, dy, d, d2: single;
begin
  n := round(power * power);
  radius := power;
  r2 := radius * radius;
  inv256 := 1/256;
  startTimer('burn');
  terrain.burn(round(atX), round(atY), round(radius*1.1+1), 25);
  stopTimer('burn');
  startTimer('explosion');
  for i := 0 to n-1 do begin
    p := nextParticle();
    {todo: check these /128 are multiplies}
    dx := (rnd-128) / 128 * radius;
    dy := (rnd-128) / 128 * radius;
    d2 := dx*dx + dy*dy;
    if d2 > r2 then continue;
    d := sqrt(d2);
    p.pos.x := atX+dx;
    p.pos.y := atY+dy;
    p.radius := 1;
    p.ttl := 0.25+(rnd/256)*0.25 + (d2/r2);
    case clamp(round(d/radius*3), 0, 2) of
      0: p.col := RGB($FFFEC729);
      1: p.col := RGB($FFF47817);
      2: p.col := RGB($FFC5361D);
    end;
    p.vel := V2(dx, dy).normed() * (0.5 + sqrt(d)) + V2(rnd-128, rnd-128) * 0.1;
    p.blend := TDM_BLEND;
  end;
  stopTimer('explosion');
  note('Explosion took explode:%fms burn:%fms', [1000*getTimer('explosion').elapsed, 1000*getTimer('burn').elapsed]);
end;

procedure makeSmoke(atX, atY: single; power: single; vel: single=10;vx: single=0;vy: single=0);
var
  i: integer;
  p: tParticle;
  radius: single;
  n: integer;
  z: single;
  angle: single;
begin
  n := round(power * power);
  radius := power;
  for i := 0 to n-1 do begin
    p := nextParticle();
    z := (rnd/255);
    angle := rnd/255*360;
    p.pos := V2Polar(angle, z*radius);
    p.pos += V2(atX, atY);
    case clamp(round(z*3), 0, 2) of
      0: p.col := RGB(200,200,200);
      1: p.col := RGB(170,170,170);
      2: p.col := RGB(128,128,128);
    end;
    p.vel := V2Polar(angle, (vel+z)) + V2(vx, vy);
    p.ttl := 0.15 + 0.1*(rnd/256);
    p.solid := false;
    p.hasGravity := false;
    p.radius := 2+rnd(2);
    p.blend := TDM_BLEND
  end;
end;

procedure makeSparks(atX, atY: single; radius: single; vel: single=25.0; vx: single=0; vy: single=0; n: integer=-1);
var
  i: integer;
  p: tParticle;
  z: single;
  angle: single;
begin
  if n < 0 then
    n := round(radius * radius);
  for i := 0 to n-1 do begin
    p := nextParticle();
    z := (rnd/255);
    angle := rnd/255*360;
    p.pos := V2Polar(angle, z*radius);
    p.pos += V2(atX, atY);
    case rnd mod 3 of
      0: p.col := RGB($FFFEC729);
      1: p.col := RGB($FFF47817);
      2: p.col := RGB($FFC5361D);
    end;
    p.vel := V2Polar(angle, (vel+z)) + V2(vx, vy);
    p.ttl := 0.25;
    p.solid := true;
    p.hasGravity := false;
    p.burn := 0;
    p.radius := 1;
    p.blend := TDM_BLEND;
  end;
end;

procedure makeElectricSparks(atX, atY: single; radius: single; vel: single=25.0; vx: single=0; vy: single=0; n: integer=-1);
var
  i: integer;
  p: tParticle;
  z: single;
  angle: single;
begin
  if n < 0 then
    n := round(radius * radius);
  for i := 0 to n-1 do begin
    p := nextParticle();
    z := (rnd/255);
    angle := rnd/255*360;
    p.pos := V2Polar(angle, z*radius);
    p.pos += V2(atX, atY);
    case rnd mod 3 of
      0: p.col := RGB($FFAFDFFF);
      1: p.col := RGB($FF2049FF);
      2: p.col := RGB($FF5A84FF);
    end;
    p.vel := V2Polar(angle, (vel+z)) + V2(vx, vy);
    p.ttl := 2.0;
    p.solid := true;
    p.hasGravity := true;
    p.burn := 3;
    p.radius := 1;
    p.blend := TDM_BLEND;
  end;
end;

procedure makeDust(atX, atY: integer; radius: integer; dType: tDirtType; vel: single=25.0; vx: single=0; vy: single=0; density: single=1.0);
var
  i: integer;
  p: tParticle;
  z: single;
  angle: single;
  dx,dy: integer;
  x,y: integer;
  r2,d2: integer;
begin
  r2 := radius*radius;
  for dy := -radius to + radius do begin
    for dx := -radius to +radius do begin
      d2 := (dx*dx)+(dy*dy);
      if (rnd/255) > density then continue;
      if d2 > r2 then continue;
      if terrain.isSolid(atX+dx, atY+dy) then continue;
      p := nextParticle();
      p.pos.x := atX + dx;
      p.pos.y := atY + dy;
      z := sqrt(d2)/sqrt(r2);
      p.vel := V2(dx, dy).normed() * (vel * z);
      p.vel += V2(vx, vy);
      p.vel += V2(rnd-128, rnd-128) * 0.1;
      p.ttl := 10;
      p.solid := true;
      p.radius := 1;
      p.cell.dType := dType;
      p.cell.strength := 200 + rnd(40);
      p.col := terrain.getCellColor(p.cell);
      p.hasGravity := true;
    end;
  end;
end;

begin
end.
