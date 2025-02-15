{special effects for game}
unit fx;

interface

uses
  {$i units},
  obj;

procedure drawMarker(screen: tScreen; atX,atY: single; col: RGBA);
procedure makeExplosion(atX, atY: single; power: single);
procedure makeSmoke(atX, atY: single; power: single; vel: single=10);
procedure makeSparks(atX, atY: single; radius: single; vel: single=25; vx: single=0; vy: single=0);

implementation

uses
  terra, game;

{----------------------------------------------------------}
{ helpers }
{----------------------------------------------------------}

procedure drawMarker(screen: tScreen; atX,atY: single; col: RGBA);
var
  x,y: integer;
  c: RGBA;
begin
  c := col;
  c.a := c.a div 2;
  x := round(atX);
  y := round(atY);

  screen.canvas.putPixel(x, y, col);

  screen.canvas.putPixel(x-1, y, c);
  screen.canvas.putPixel(x+1, y, c);
  screen.canvas.putPixel(x, y-1, c);
  screen.canvas.putPixel(x, y+1, c);

  screen.markRegion(rect(x-1, y-1, 3, 3));
end;

procedure makeExplosion(atX, atY: single; power: single);
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
  terrain.burn(round(atX-32), round(atY), round(radius+3), 25);
  for i := 0 to n-1 do begin
    p := nextParticle();
    z := (rnd/255);
    angle := rnd/255*360;
    p.pos := V2Polar(angle, z*radius/2) + V2(atX, atY);
    case clamp(round(z*3), 0, 2) of
      0: p.col := RGB($FFFEC729);
      1: p.col := RGB($FFF47817);
      2: p.col := RGB($FFC5361D);
    end;
    p.vel := V2Polar(angle, (0.5+z)*radius/2);
    {edit the terrain}
    terrain.burn(p.xPos-32, p.yPos, 3, 5);
  end;
end;

procedure makeSmoke(atX, atY: single; power: single; vel: single=10);
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
      0: p.col := RGB($FF3F3F3F);
      1: p.col := RGB($FFAFAFAF);
      2: p.col := RGB($FF7F7F7F);
    end;
    p.vel := V2Polar(angle, (vel+z));
    p.ttl := 0.5;
    p.solid := true;
    p.radius := 2;
  end;
end;

procedure makeSparks(atX, atY: single; radius: single; vel: single=25; vx: single=0; vy: single=0);
var
  i: integer;
  p: tParticle;
  n: integer;
  z: single;
  angle: single;
begin
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
    p.radius := 1;
  end;
end;

begin
end.
