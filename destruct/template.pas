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
  myMath,
  resource,
  graph2d,
  graph32;

type
  tTemplate = class(tResource)
    mipMaps: array of tPage8; // prescaled versions
    page: tPage8; // our base template;
    constructor create(); overload;
    destructor  destroy(); override;

    procedure   buildMipMaps();
    function    getValue(atX,atY,size: single): single;

    function    drawAdd(dst: tPage; x,y: integer; size: word; col: RGBA): tRect;

    class function Load(filename: string): tTemplate;
  end;

implementation

{-------------------------------------------------------------------}

procedure drawTemplateAdd_REF(dst: tPage; template: tPage8; originX,originY: integer; bounds: tRect; col: RGBA);
var
  x,y: integer;
  c: RGBA;
  v: word;
  templatePtr, pagePtr: pointer;
  width,height: integer;
begin
  {for centering we have all images stored with 1 pixel padding on lower right
   i.e. a 3x3 template would be 4x4

   ***-
   ***-
   ***-
   ----
  }
  templatePtr := template.pixels;

  for y := bounds.top to bounds.bottom-1 do begin
    pagePtr := dst.getAddress(bounds.left, y);
    templatePtr := template.getAddress(bounds.left-originX, y-originY);
    for x := bounds.left to bounds.right-1 do begin
      v := pByte(templatePtr)^ * col.a;
      //if v = 0 then continue;
      c := pRGBA(pagePtr)^;
      c.init(
        c.r + (dword(col.r*v) shr 16),
        c.g + (dword(col.g*v) shr 16),
        c.b + (dword(col.b*v) shr 16)
      );
      pRGBA(pagePtr)^ := c;
      inc(pagePtr, 4);
      inc(templatePtr);
    end;
  end;
end;

{-------------------------------------------------------------------}

constructor tTemplate.create();
begin
  inherited create();
  self.page := nil;
  self.mipMaps := nil;
end;

destructor tTemplate.destroy();
var
  mipMap: tPage8;
begin
  if assigned(self.page) then freeAndNil(self.page);
  if length(self.mipMaps) > 0 then
    for mipMap in self.mipMaps do
      mipMap.free();
  setLength(self.mipMaps, 0);
  inherited destroy();
end;


{
radius 1 =
   *
radius 2 =
   *
  ***
   *
}
function tTemplate.drawAdd(dst: tPage; x,y: integer; size: word; col: RGBA): tRect;
var
  i: integer;
  width, height: integer;
  template: tPage8;
  xPos, yPos: integer;
  bounds: tRect;
begin

  template := mipMaps[size];

  width := template.width-1;
  height := template.height-1;

  xPos := x-(width div 2);
  yPos := y-(height div 2);
  bounds := Rect(xPos, yPos, width, height);
  bounds.clipTo(dst.bounds);

  drawTemplateAdd_REF(dst, template, xPos, yPos, bounds, col);
  result := bounds;
end;

{returns the average value in a rect centered at x,y and of width size.
 uses a sort of gamma correction}
function tTemplate.getValue(atX,atY,size: single): single;
var
  totalSquaredValue: single;
  totalArea: single;
  xFactor,yFactor,factor: single;
  x,y: integer;
  top,left,bottom,right: single;

  function getFactor(v: integer; a,b: single): single;
  begin
    if v = floor(a) then exit(1-frac(a));
    if v = ceil(b) then exit(frac(b));
    exit(1);
  end;

begin
  top := atY - (size / 2);
  bottom := atY + (size / 2);
  left := atX - (size / 2);
  right := atX + (size / 2);
  totalSquaredValue := 0;
  totalArea := 0;
  for y := floor(top) to ceil(bottom) do begin
    yFactor := getFactor(y, top, bottom);
    for x := floor(left) to ceil(right) do begin
      xFactor := getFactor(x, left, right);
      factor := xFactor * yFactor;
      totalArea += factor;
      // factor on outside or inside?
      totalSquaredValue += factor * sqr(page.getValue(x,y));
    end;
  end;
  result := sqrt(totalSquaredValue / totalArea);
end;


procedure tTemplate.buildMipMaps();
var
  i: integer;
  x,y: integer;
  v: single;
  radius: integer;
  width: integer;
  debugStr: string;
  normFactor: single;
begin
  assert(assigned(page));
  assertEqual(page.width, page.height);
  setLength(mipMaps, 16);

  for i := 0 to 15 do begin
    note('Mips:%d', [i]);
    radius := (i*2)+1; {1,3,5...}
    width := radius + 1;
    mipMaps[i] := tPage8.create(width, width);
    {normalize so that centre value is 255}
    normFactor := 255/getValue(page.width/2, page.height/2, page.width/radius);
    for y := 0 to radius-1 do begin
      //debugStr := '';
      for x := 0 to radius-1 do begin
        v := getValue(page.width*(0.5+x)/radius, page.height*(0.5+y)/radius, page.width/radius);
        mipMaps[i].putValue(x,y,clamp(round(normFactor*v), 0, 255));
        //debugStr += intToStr(mipMaps[i].getValue(x,y))+' ';
      end;
      //note(debugStr);
    end;
  end;
end;

class function tTemplate.Load(filename: string): tTemplate;
begin
  result := tTemplate.create();
  result.page := tPage8.Load(filename);
  result.buildMipMaps();
end;


{-------------------------------------------------------------------}

begin
end.
