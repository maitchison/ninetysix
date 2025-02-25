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
  debug,
  test,
  utils,
  graph32;

procedure drawTemplateAdd(dst: tPage; x,y: integer; radius: word; col: RGBA);

implementation

var
  {returns F(sqr(16*x)) * 255; for x=0..1}
  LOOKUP: array[0..1, 0..255] of byte;

procedure drawTemplateAdd_REF(dst: tPage; x,y: integer; radius: word; col: RGBA);
var
  dx,dy: integer;
  r2, d2: integer;
  c: RGBA;
  f: integer;
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
      //v := (1-(sqrt(d2) / radius)) * (col.a/255);
      f := clamp(round((d2/r2)*16 * (col.a/255)), 0, 255);
      v := LOOKUP[0, f] / 255;
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

procedure generateLookups();
var
  i: integer;
  x: single;
  f: single;
begin
  for i := 0 to 255 do begin
    x := (i/255);
    f := 1-x;
    // quadratic falloff
    LOOKUP[0, i] := clamp(round(sqr(16*f)), 0, 255);
    note(intToStr(LOOKUP[0, i]));
  end;
end;

begin
  generateLookups();
end.