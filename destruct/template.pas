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
  sysInfo,
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
      if v < 255 then continue;
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

procedure drawTemplateAdd_ASM(dst: tPage; template: tPage8; originX,originY: integer; bounds: tRect; col: RGBA);
var
  x,y: integer;
  c: RGBA;
  v: word;
  templatePtr, pagePtr: pointer;
  width,height: integer;
  len, alpha: byte;
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

    len := bounds.width;
    alpha := col.a;

    asm
      pushad

      xor ecx, ecx
      mov cl, LEN
      mov ch, ALPHA     // ecx = 0 | 0 | a | len

      mov esi, TEMPLATEPTR
      mov edi, PAGEPTR

    @XLOOP:

      mov edx, COL      // edx = a | r | g | b

      mov al, [esi]
      mul ch            // ax = template.a * col.a
      mov bl, ah        // bl = (template.a * col.a) div 256
      test ah, ah
      jz @SKIP

    @MIX_B:
      mov al, dl
      mul bl
      mov dl, ah
      ror edx, 8        // save and store new value
    @MIX_G:
      mov al, dl
      mul bl
      mov dl, ah
      ror edx, 8        // save and store new value
    @MIX_R:
      mov al, dl
      mul bl
      mov dl, ah
      rol edx, 16       // save and restore the ARGB order

      // edx is now c ARGB multiplied by alpha

      mov eax, [edi]

    @ADD_B:
      add dl, al
      jnc @SKIP_B
      mov dl, 255
    @SKIP_B:
      ror edx, 8
      ror eax, 8
    @ADD_G:
      add dl, al
      jnc @SKIP_G
      mov dl, 255
    @SKIP_G:
      ror edx, 8
      ror eax, 8
    @ADD_R:
      add dl, al
      jnc @SKIP_R
      mov dl, 255
    @SKIP_R:
      rol edx, 16

      mov [edi], edx

    @SKIP:
      inc esi
      add edi,4

      dec cl
      jnz @XLOOP

      popad
    end;
  end;
end;

procedure drawTemplateAdd_MMX(dst: tPage; template: tPage8; originX,originY: integer; bounds: tRect; col: RGBA);
var
  y: integer;
  templatePtr, pagePtr: pointer;
  len, alpha: word;
begin
  len := bounds.width;
  alpha := col.a div 2; // due to sign we need to divide this by two...
  for y := bounds.top to bounds.bottom-1 do begin
    pagePtr := dst.getAddress(bounds.left, y);
    templatePtr := template.getAddress(bounds.left-originX, y-originY);
    asm
      pushad

      movzx ecx, word ptr LEN

      mov esi, TEMPLATEPTR
      mov edi, PAGEPTR

      {setup}

      pxor      mm0, mm0

      movd      mm6, COL
      punpcklbw mm6, mm0

      movzx     eax, ALPHA
      movd      mm7, eax
      punpcklwd mm7, mm7
      punpckldq mm7, mm7

      {

        (these are all 16bit 4-vectors)

        MM0             all zeros
        MM1 tmp
        MM2 tmp
        MM3 tmp
        MM4
        MM5             template  AAAA
        MM6             col       ARGB
        MM7             col       AAAA
      }

    @XLOOP:

      {mm5 <- template AAAA }
      movzx     eax, byte ptr [esi]
      movd      mm5, eax
      punpcklwd mm5, mm5
      punpckldq mm5, mm5

      {mm1 <- template*col AAAA}
      movq      mm1, mm7
      pmullw    mm1, mm5

      {if value is too low then skip it}
      movd      eax, mm1
      test      ah, ah
      jz        @SKIP

      {mm1 <- (col*template.a*col.a) div 65536}
      pmulhw    mm1, mm6
      psllw     mm1, 1      // we had to halve col.a so adjust for it here.

      {mm2 <- screen ARGB}
      movd      mm2, [edi]
      punpcklbw mm2, mm0

      {mm1 <- screen + template ARGB}
      paddw     mm1, mm2

      {mm1 <- screen + template ARGB (as bytes, and saturated)}
      packuswb  mm1, mm1
      movd      [edi], mm1

    @SKIP:
      inc esi
      add edi,4

      dec ecx
      jnz @XLOOP

      popad
    end;
  end;

  asm
    emms;
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

  result.init(0,0,0,0);

  if (col.a = 0) then exit;

  template := mipMaps[size];

  width := template.width-1;
  height := template.height-1;

  xPos := x-(width div 2);
  yPos := y-(height div 2);
  bounds := Rect(xPos, yPos, width, height);
  bounds.clipTo(dst.bounds);
  result := bounds;

  if cpuInfo.hasMMX then
    drawTemplateAdd_MMX(dst, template, xPos, yPos, bounds, col)
  else
    drawTemplateAdd_ASM(dst, template, xPos, yPos, bounds, col);

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
