{experimental 1d template for particles effeccts}
unit template;

{this works by usin a lookup on sqared distance. We calculate squared
distance using a single MMX instruction. This allows for very fast
scaled drawing of 1-d templates.

The default size for a template is 16, and it'll look a bit weird if we
scale too much above 32 (I think).

}

interface

uses
  graph32;

procedure drawTemplateAdd(dst: tPage; x,y: integer; radius: word; col: RGBA);

implementation

procedure drawTemplateAdd_REF(dst: tPage; x,y: integer; radius: word; col: RGBA);
var
  dx,dy: integer;
  r2, d2: integer;
  c: RGBA;
  v: single;
begin
  if radius <= 0 then exit;
  r2 := radius*radius;
  dec(radius); {radius=1 means 0..0}
  {todo: outside of radius trimming}
  for dy := -radius to + radius do begin
    for dx := -radius to +radius do begin
      d2 := dy*dy+dx*dx;
      if d2 >= r2 then continue;
      v := (1-(sqrt(d2) / radius)) * (col.a/255);
      c := dst.getPixel(x+dx, y+dy);
      c.init(
        round(c.r + col.r*v),
        round(c.g + col.g*v),
        round(c.b + col.b*v)
      );
      dst.setPixel(x+dx, y+dy, c);
    end;
  end;
end;

procedure drawTemplateAdd(dst: tPage; x,y: integer; radius: word; col: RGBA);
begin
  drawTemplateAdd_REF(dst, x, y, radius, col);
end;

begin
end.