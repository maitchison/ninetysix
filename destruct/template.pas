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
  graph2d,
  graph32;

procedure drawTemplateAdd(dst: tPage; template: tPage8; x,y: integer; radius: word; col: RGBA);

implementation

procedure drawTemplateAdd_REF(dst: tPage; template: tPage8; atX,atY: integer; col: RGBA);
var
  x,y: integer;
  c: RGBA;
  v: word;
  templatePtr, pagePtr: pointer;
  width,height: integer;
  xPos, yPos: integer;
  xLen,yLen: integer;
  bounds: tRect;
begin
  {for centering we have all images stored with 1 pixel padding on lower right
   i.e. a 3x3 template would be 4x4

   ***-
   ***-
   ***-
   ----
  }
  templatePtr := template.pixels;
  width := template.width-1;
  height := template.height-1;

  xPos := atX-(width div 2);
  yPos := atY-(height div 2);
  bounds := rect(xPos, yPos, width, height);
  bounds.clipTo(dst.bounds);

  for y := bounds.top to bounds.bottom-1 do begin
    pagePtr := dst.getAddress(bounds.left-xPos, y-ypos);
    for x := bounds.left to bounds.right-1 do begin
      v := pByte(templatePtr)^ * col.a;
      //if v = 0 then continue;
      c := pRGBA(pagePtr)^;
      c.init(
        c.r + word(col.r*v) shr 16,
        c.g + word(col.g*v) shr 16,
        c.b + word(col.b*v) shr 16
      );
      c.r := 255;
      c.a := 128;
      pRGBA(pagePtr)^ := c;
      inc(pagePtr, 4);
      inc(templatePtr);
    end;
  end;
end;

procedure drawTemplateAdd(dst: tPage; template: tPage8; x,y: integer; radius: word; col: RGBA);
begin
  drawTemplateAdd_REF(dst, template, x, y, col);
end;

begin
end.