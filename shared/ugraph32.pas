{2D graphics library}

{$MODE delphi}

unit uGraph32;

interface

uses
  uTest,
  uDebug,
  uVgaDriver,
  uUtils,
  uRect,
  uResource,
  uTypes,
  uInfo,
  uTimer,
  uColor;

type

  tBlendMode = (
    bmNone,   // skip
    bmBlit,   // src
    bmBlend   // alpha*src + (1-alpha)*dst
  );

  tTextureFilter = (
    tfNearest,
    tfLinear
  );

  tDrawBackend = (dbREF, dbASM, dbMMX);

  tPage = class;

  tMarkRegionProc = procedure(const rect: tRect; flags: byte) of object;

  tColorSpace = (
    csRGB,    // standard ARGB color
    csRUV     // a sort of fake YUV format (r, r-g, r-b)
  );

  tDrawContext = record
    page: tPage;
    offset: tPoint;
    clip: tRect;
    blendMode: tBlendMode;
    tint: RGBA;  {used to modulate src color before write}
    backend: tDrawBackend;
    textureFilter: tTextureFilter;
    clearFlags: byte;
    markRegionHook: tMarkRegionProc;
    procedure applyTransform(var p: tPoint); inline;
    procedure applyTransformInv(var p: tPoint); inline;
    procedure applyTint(var col: RGBA); inline;
    function  smartBM(col: RGBA): tBlendMode;
    function  hasTint: boolean; inline;
    procedure markRegion(const rect: tRect); inline;
    {dispatch}
    procedure doDrawRect(dstPage: tPage;aRect: tRect;col: RGBA;blendmode: tBlendMode);
    procedure doDrawImage(dstPixels, srcPixels: pointer; dstX, dstY: int32; srcRect: tRect; tint: RGBA; blendMode: tBlendMode);
    procedure doStretchImage(dstPage, srcPage: tPage; dstRect: tRect; srcX, srcY, srcDx, srcDy: single; tint: RGBA; filter: tTextureFilter; blendMode: tBlendMode);
    {basic drawing API}
    procedure putPixel(pos: tPoint; col: RGBA);
    procedure hLine(pos: tPoint;len: int32;col: RGBA);
    procedure vLine(pos: tPoint;len: int32;col: RGBA);
    procedure drawSubImage(src: tPage; pos: tPoint; srcRect: tRect);
    procedure stretchSubImage(src: tPage; pos: tPoint; scaleX, scaleY: single; srcRect: tRect); overload;
    procedure stretchSubImage(src: tPage; dstRect: tRect; srcRect: tRect); overload;
    {constructed}
    procedure drawImage(src: tPage; pos: tPoint);
    procedure inOutDraw(src: tPage; pos: tPoint; border: integer; innerBlendMode, outerBlendMode: tBlendMode);
    procedure fillRect(dstRect: tRect; col: RGBA);
    procedure drawRect(dstRect: tRect; col: RGBA);
    procedure stretchImage(src: tPage; dstRect: tRect);
  end;

  {page using 32bit RGBA color}
  tPage = class(tResource)
    width, height: word;
    isRef: boolean;
    pixels: pointer;
    defaultColor: RGBA;
    colorSpace: tColorSpace;

    constructor Create(); overload;
    destructor  destroy(); override;
    constructor create(aWidth, aHeight: word); overload;
    constructor createAsReference(aWidth, aHeight: word;pixelData: Pointer);

    function  getDC(blendMode: tBlendMode = bmBlend): tDrawContext;
    function  getAddress(x, y: integer): pointer; inline;
    function  getPixel(x, y: integer): RGBA; inline;
    function  getPixelF(fx,fy: single): RGBA;
    procedure putPixel(atX, atY: int16;c: RGBA); inline; assembler; register;
    procedure setPixel(atX, atY: int16;c: RGBA); inline; assembler; register;
    procedure clear(c: RGBA); overload;
    procedure clear(); overload;

    function  clone(): tPage;
    function  asBytes: tBytes;
    function  asRGBBytes: tBytes;
    function  scaled(aWidth, aHeight: integer): tPage;
    function  resized(aWidth, aHeight: integer): tPage;
    procedure resize(aWidth, aHeight: integer);
    function  bounds(): tRect; inline;

    procedure convertColorSpace(aNewColorSpace: tColorSpace);

    procedure setTransparent(col: RGBA);
    function  detectBPP: byte;

    class function Load(filename: string): tPage;
  end;

  tImageLoaderProc = function(filename: string): tPage;

  tGFXLibrary = class(tResourceLibrary)
  protected
    function getGFXByTag(aTag: string): tPage;
  public
    function getWithDefault(aTag: string;aDefault: tPage): tPage;
    function addResource(filename: string): tResource; override;
    property items[tag: string]: tPage read getGFXByTag; default;
  end;

const
  ERR_COL: RGBA = (b:255;g:0;r:255;a:255);
  BACKEND_NAME: array[tDrawBackend] of string = ('ref','asm','mmx');

procedure makePageRandom(page: tPage);

procedure assertEqual(a, b: RGBA;msg: string=''); overload;
procedure assertEqual(a, b: tPage); overload;

implementation

uses
  uKeyboard; {stub}

{$include graph32_REF.inc}
{$include graph32_ASM.inc}
{$include graph32_MMX.inc}

{-------------------------------------------------------------}

function tGFXLibrary.getGFXByTag(aTag: string): tPage;
var
  res: tResource;
begin
  res := getByTag(aTag);
  assert(res is tPage);
  result := tPage(res);
end;

function tGFXLibrary.getWithDefault(aTag: string;aDefault: tPage): tPage;
begin
  if hasResource(aTag) then
    exit(self[aTag])
  else
    exit(aDefault);
end;

function tGFXLibrary.addResource(filename: string): tResource;
var
  res: tResource;
begin
  res := inherited addResource(filename);
  assert((res is tPage) or (res is tLazyResource));
  result := res;
end;

{----------------------------------------------------------------}
{ TPage }
{----------------------------------------------------------------}

constructor tPage.create(); overload;
begin
  inherited create();
  self.width := 0;
  self.height := 0;
  self.pixels := nil;
  self.defaultColor := ERR_COL;
  self.isRef := false;
  self.colorSpace := csRGB;
end;

constructor tPage.create(aWidth, aHeight: word); overload;
begin
  Create();
  self.width := AWidth;
  self.height := AHeight;
  self.pixels := getMem(dword(aWidth) * aHeight * 4);
  self.clear();
end;

constructor tPage.CreateAsReference(aWidth, aHeight: word;pixelData: Pointer);
{todo: support logical width}
begin
  Create();
  self.width := AWidth;
  self.height := AHeight;
  self.pixels := PixelData;
  self.isRef := true;
end;

destructor tPage.destroy();
begin
  if (not self.isRef) and assigned(self.pixels) then
    freeMem(self.pixels, width*height*4);
  self.pixels := nil;
  self.width := 0;
  self.height := 0;
  self.isRef := false;
  inherited destroy();
end;

{gets a default draw context for this page. best to call this once and cache it}
function tPage.getDC(blendMode: tBlendMode = bmBlend): tDrawContext;
begin
  result.page := self;
  result.blendMode := blendMode;
  result.clip := bounds;
  result.offset := Point(0,0);
  result.tint := RGB(255,255,255,255);
  if cpuInfo.hasMMX then
    result.backend := dbMMX
  else
    result.backend := dbASM;
  result.textureFilter := tfNearest;
  result.markRegionHook := nil;
  result.clearFlags := 0;
end;

{returns address in memory of given pixel. If out of bounds, returns nil}
function tPage.getAddress(x, y: integer): pointer; inline;
begin
  if (x < 0) or (y < 0) or (x >= self.width) or (y >= self.height) then
    exit(nil);
  result := pixels + ((y * width + x) shl 2);
end;

{todo: this could be much faster...}
function tPage.getPixel(x, y: Integer): RGBA; inline;
var
  address: dword;
  col: RGBA;
begin
  if (x < 0) or (y < 0) or (x >= self.width) or (y >= self.height) then
    exit(self.defaultColor);
  address := dword(pixels) + (y * Width + x) shl 2;
  asm
    push edi
    push eax

    mov edi, address
    mov eax, [edi]
    mov col, eax

    pop eax
    pop edi
  end;
  result := col;
end;

{get pixel with interpolation}
function tPage.getPixelF(fx, fy: single): RGBA;
var
  x,y: integer;
  fracX, fracY, invFracX, invFracY: byte;
  c1,c2,c3,c4: RGBA;
  p1,p2,p3,p4: dword;
  pData: pointer;
begin

  {scaled integer version: 161}

  {shouldn't be needed...}
  if fx < 0 then fx := 0;
  if fy < 0 then fy := 0;
  if fx > width-1 then fx := width-1;
  if fy > height-1 then fy := height-1;
  {if (fx < 0) or (fy < 0) or (fx >= width-1) or (fy >= height-1) then
    exit(RGB(255, 0, 255));}

  x := trunc(fx);
  y := trunc(fy);

  fracX := round((fx - x)*255);
  fracY := round((fy - y)*255);
  invFracX := 255-fracX;
  invFracY := 255-fracY;

  pData := getAddress(x, y);
  c1 := pRGBA(pData)^;
  c2 := pRGBA(pData+4)^;
  c3 := pRGBA(pData+width*4)^;
  c4 := pRGBA(pData+width*4+4)^;

  p1 := invFracX*invFracY;
  p2 := fracX*invFracY;
  p3 := invFracX*fracY;
  p4 := fracX*fracY;

  result.r := (65535 + dword(c1.r)*p1 + dword(c2.r)*p2 + dword(c3.r)*p3+dword(c4.r)*p4) shr 16;
  result.g := (65535 + dword(c1.g)*p1 + dword(c2.g)*p2 + dword(c3.g)*p3+dword(c4.g)*p4) shr 16;
  result.b := (65535 + dword(c1.b)*p1 + dword(c2.b)*p2 + dword(c3.b)*p3+dword(c4.b)*p4) shr 16;
  result.a := (65535 + dword(c1.a)*p1 + dword(c2.a)*p2 + dword(c3.a)*p3+dword(c4.a)*p4) shr 16;

end;

procedure tPage.clear(c: RGBA);
begin
  filldword(pixels^, width*height, c.to32);
end;

procedure tPage.clear();
begin
  clear(RGBA.Black);
end;

procedure tPage.putPixel(atX,atY: int16;c: RGBA); inline; assembler; register;
{
Standard (Screen)
--------------------
1.59M: (per second) start.
1.71M: Switched to register (not worth it I guess?)
2.07M: Write to buffer instead of screen

Standard (Buffer)
--------------------
2.07M:

Blending (Screen)
--------------------
0.30M: Start
0.52M: Initial MMX version (without EMMS)

Blending (Buffer)
--------------------
1.01M: Start
1.61M: Initial MMX version (without EMMS)

}

asm
    {We also modified eax, and edx, but apparently these are safe to
     modifiy (only ebx needs to be preserved?)}

    {eax = self,
     cx = atY,
     dx = atX,
     stack1 = RGBA}


    push edi
    push esi
    push ebx

    mov esi, eax

    cmp dx,  [esi].Width                // unsigned cmp will catch negative values.
    jae @Skip
    cmp cx,  [esi].Height
    jae @Skip

    movzx edi, dx

    mov ax,  [esi].Width
    mul cx
    shl edx, 16
    movzx eax, ax
    or  edx, eax
    add edi, edx

    shl edi, 2

    add edi, [esi].[Pixels]

    {check for alpha channel}
    mov eax, c
    mov cl,  byte ptr c[3]
    cmp cl,  255
    je @Direct
    cmp cl,  0
    je @Skip

    {perform mixing}
    mov ch,  255
    sub ch,  cl
  @BLEND_A:
    {super complicated... it's a shame we have to do this}
    {ok, for the moment just or them together...}
    mov dl,  byte ptr c[3]
    or dl,  byte ptr [edi+3]
    shl edx, 8
  @BLEND_B:
    mov al,  byte ptr c[2]
    mul cl
    mov dl,  ah
    mov al,  byte ptr [edi+2]
    mul ch
    add dl,  ah
    shl edx, 8
  @BLEND_G:
    mov al,  byte ptr c[1]
    mul cl
    mov dl,  ah
    mov al,  byte ptr [edi+1]
    mul ch
    add dl,  ah
    shl edx, 8
  @BLEND_R:
    mov al,  byte ptr c[0]
    mul cl
    mov dl,  ah
    mov al,  byte ptr [edi+0]
    mul ch
    add dl,  ah

    mov eax, edx

  @Direct:
    mov dword ptr [edi], eax

  @Skip:

    pop ebx
    pop esi
    pop edi

  end;

{sets the pixel, no alpha blending}
procedure TPage.setPixel(atX,atY: int16;c: RGBA); inline; assembler; register;
asm
    push edi
    push esi
    push ebx

    mov esi, eax

    cmp dx,  [esi].Width                // unsigned cmp will catch negative values.
    jae @SKIP
    cmp cx,  [esi].Height
    jae @SKIP

    movzx edi, dx

    mov ax,  [esi].Width
    mul cx
    shl edx, 16
    movzx eax, ax
    or  edx, eax
    add edi, edx

    shl edi, 2

    add edi, [esi].[Pixels]

    mov eax, c
    mov dword ptr [edi], eax

  @SKIP:

    pop ebx
    pop esi
    pop edi
  end;

{deep copy of page}
function tPage.clone(): tPage;
begin
  result := tPage.create();
  result.width := self.width;
  result.height := self.height;
  result.pixels := getMem(self.width*self.height*4);
  result.isRef := false;
  result.defaultColor := self.defaultColor;
  result.colorSpace := self.colorSpace;
  move(self.pixels^, result.pixels^, self.width*self.height*4);
end;

{make a copy of page using RGBA}
function tPage.asBytes: tBytes;
begin
  result := nil;
  setLength(result, width*height*4);
  move(pixels^, result[0], width*height*4);
end;

{make a copy of page using RGB}
function tPage.asRGBBytes: tBytes;
var
  i: int32;
begin
  result := nil;
  setLength(result, width*height*3);
  for i := 0 to width*height-1 do begin
    result[i*3+0] := pRGBA(pixels+i*4)^.r;
    result[i*3+1] := pRGBA(pixels+i*4)^.g;
    result[i*3+2] := pRGBA(pixels+i*4)^.b;
  end;
end;

{returns detected BPP which will be
 8 if grayscale
 24 if RGB with alpha=255
 32 otherwise
}
function tPage.detectBPP: byte;
var
  x,y: int32;
  hasColor: boolean;
  c: RGBA;
begin
  hasColor := false;
  for y := 0 to height-1 do begin
    for x := 0 to width-1 do begin
      c := getPixel(x,y);
      if c.a <> 255 then exit(32);
      case colorSpace of
        csRGB: if (c.r <> c.g) or (c.r <> c.b) then hasColor := True;
        csRUV: if (c.g <> 0) or (c.b <> 0) then hasColor := True;
      end;
    end;
  end;

  if hasColor then exit(24) else exit(8)
end;

function tPage.resized(aWidth, aHeight: integer): tPage;
begin
  result := tPage.create(aWidth, aHeight);
  result.getDC(bmBlit).drawImage(self, Point(0, 0));
  result.colorSpace := self.colorSpace;
end;

procedure tPage.resize(aWidth, aHeight: integer);
var
  tmp: tPage;
begin
  tmp := self.clone();
  self.width := aWidth;
  self.height := aHeight;
  freeMem(self.pixels);
  getMem(self.pixels, aWidth*aHeight*4);
  getDC(bmBlit).drawImage(tmp, Point(0, 0));
  tmp.free;
end;

function tPage.bounds(): tRect; inline;
begin
  result := Rect(0, 0, width, height);
end;

function tPage.scaled(aWidth, aHeight: integer): tPage;
begin
  result := tPage.create(aWidth, aHeight);
  result.getDC().stretchImage(self, result.bounds);
  result.colorSpace := self.colorSpace;
end;

{Sets all instances of this color to transparent}
procedure tPage.setTransparent(col: RGBA);
var
  x,y: integer;
begin
  for y := 0 to height-1 do
    for x := 0 to width-1 do
      if getPixel(x,y) = col then
        setPixel(x,y, RGBA.create(0,0,0,0));
end;

procedure convertRUVtoRGB_REF(page: tPage);
var
  pixelsPtr: pRGBA;
  i: integer;
  c: RGBA;
begin
  pixelsPtr := page.pixels;
  for i := 0 to page.width*page.height-1 do begin
    c := pixelsPtr^;
    c.g := byte(c.g+c.r);
    c.b := byte(c.b+c.r);
    pixelsPtr^ := c;
    inc(pixelsPtr);
  end;
end;

procedure convertRGBtoRUV_REF(page: tPage);
var
  pixelsPtr: pRGBA;
  i: integer;
  c: RGBA;
begin
  pixelsPtr := page.pixels;
  for i := 0 to page.width*page.height-1 do begin
    c := pixelsPtr^;
    c.g := byte(c.g-c.r);
    c.b := byte(c.b-c.r);
    pixelsPtr^ := c;
    inc(pixelsPtr);
  end;
end;

procedure tPage.convertColorSpace(aNewColorSpace: tColorSpace);
var
  x,y: integer;
  c: RGBA;
begin
  startTimer('convert');
  if (colorSpace = csRGB) and (aNewColorSpace = csRUV) then begin
    convertRGBtoRUV_REF(self);
  end else if (colorSpace = csRUV) and (aNewColorSpace = csRGB) then begin
    convertRUVtoRGB_REF(self);
  end else
    fatal('Invalid color space conversion');
  colorSpace := aNewColorSpace;
  stopTimer('convert');
end;

class function tPage.Load(filename: string): tPage;
var
  proc: tResourceLoaderProc;
  res: tResource;
  startTime: double;
begin
  proc := getResourceLoader(extractExtension(filename));
  if assigned(proc) then begin
    startTime := getSec;
    res := proc(filename);
    if not (res is tPage) then fatal('Resources is of invalid type');
    result := tPage(res);
    note(' - loaded %s (%dx%d) in %.2fs', [filename, result.width, result.height, getSec-startTime]);
  end else
    fatal('No image loader for file "'+filename+'"');
end;

{-------------------------------------------------}
{ dispatch}

procedure tDrawContext.doDrawRect(dstPage: tPage;aRect: tRect;col: RGBA;blendmode: tBlendMode);
begin
  case backend of
    dbREF: drawRect_REF(dstPage, aRect, col, blendMode);
    dbASM: drawRect_REF(dstPage, aRect, col, blendMode);
    dbMMX: drawRect_MMX(dstPage, aRect, col, blendMode);
  end;
end;

procedure tDrawContext.doDrawImage(dstPixels, srcPixels: pointer; dstX, dstY: int32; srcRect: tRect; tint: RGBA; blendMode: tBlendMode);
begin
  case backend of
    dbREF: drawImage_REF(dstPixels, srcPixels, dstX, dstY, srcRect, tint, blendMode);
    dbASM: drawImage_REF(dstPixels, srcPixels, dstX, dstY, srcRect, tint, blendMode);
    dbMMX: drawImage_MMX(dstPixels, srcPixels, dstX, dstY, srcRect, tint, blendMode);
  end;
end;

procedure tDrawContext.doStretchImage(dstPage, srcPage: tPage; dstRect: tRect; srcX, srcY, srcDx, srcDy: single; tint: RGBA; filter: tTextureFilter; blendMode: tBlendMode);
begin
  case backend of
    dbREF: stretchImage_REF(dstPage, srcPage, dstRect, srcX, srcY, srcDx, srcDy, tint, filter, blendMode);
    dbASM: stretchImage_REF(dstPage, srcPage, dstRect, srcX, srcY, srcDx, srcDy, tint, filter, blendMode);
    dbMMX: stretchImage_MMX(dstPage, srcPage, dstRect, srcX, srcY, srcDx, srcDy, tint, filter, blendMode);
  end;
end;

{-------------------------------------------------}

procedure tDrawContext.applyTransform(var p: tPoint); inline;
begin
  p.x += offset.x;
  p.y += offset.y;
end;

procedure tDrawContext.applyTransformInv(var p: tPoint); inline;
begin
  p.x -= offset.x;
  p.y -= offset.y;
end;

procedure tDrawContext.applyTint(var col: RGBA); inline;
begin
  if int32(tint) <> -1 then col := col * tint;
end;

{figure out the blend mode based on alpha etc.}
function tDrawContext.smartBM(col: RGBA): tBlendMode;
begin
  result := blendMode;
  if (result = bmBlend) then begin
    if col.a = 0 then result := bmNone;
    if col.a = 255 then result := bmBlit;
  end;
end;

function tDrawContext.hasTint: boolean; inline;
begin
  result := int32(tint) <> -1;
end;

procedure tDrawContext.markRegion(const rect: tRect); inline;
begin
  if (clearFlags <> 0) and assigned(markRegionHook) then markRegionHook(rect, clearFlags);
end;

procedure tDrawContext.putPixel(pos: tPoint;col: RGBA);
begin
  applyTransform(pos);
  if not clip.isInside(pos.x, pos.y) then exit;
  applyTint(col);
  case smartBM(col) of
    bmNone: exit;
    bmBlit: page.setPixel(pos.x, pos.y, col);
    bmBlend: page.putPixel(pos.x, pos.y, col);
  end;
  markRegion(Rect(pos.x, pos.y, 1, 1));
end;

procedure tDrawContext.fillRect(dstRect: tRect; col: RGBA);
var
  y: integer;
  pixels: pointer;
  stride: dword;
  len: dword;
begin

  applyTransform(dstRect.pos);
  dstRect.clipTo(clip);
  if dstRect.isEmpty then exit;

  applyTint(col);
  doDrawRect(page, dstRect, col, smartBM(col));
  markRegion(dstRect);
end;

procedure tDrawContext.vLine(pos: tPoint;len: int32;col: RGBA);
var
  endPos: tPoint;
  i: integer;
begin
  applyTransform(pos);
  endPos := Point(pos.x, pos.y+len);
  pos := clip.clipPoint(pos);
  endPos := clip.clipPoint(endPos);
  len := endPos.y - pos.y;
  if len <= 0 then exit;

  applyTint(col);

  case smartBM(col) of
    bmNone: exit;
    bmBlit: for i := 0 to len-1 do page.setPixel(pos.x, pos.y+i, col);
    bmBlend: for i := 0 to len-1 do page.putPixel(pos.x, pos.y+i, col);
  end;

  markRegion(Rect(pos.x, pos.y, 1, len));
end;

procedure tDrawContext.drawSubImage(src: tPage; pos: tPoint; srcRect: tRect);
var
  dstRect: tRect;
  srcOffset: tPoint;
begin

  if blendMode = bmNone then exit;

  applyTransform(pos);

  dstRect := Rect(pos.x, pos.y, srcRect.width, srcRect.height);
  dstRect.clipTo(clip);
  if dstRect.isEmpty then exit;
  srcRect.width := dstRect.width;
  srcRect.height := dstRect.height;
  srcRect.pos -= (pos - dstRect.pos);

  doDrawImage(page, src, dstRect.x, dstRect.y, srcRect, tint, blendMode);
  markRegion(dstRect);
end;

procedure tDrawContext.stretchSubImage(src: tPage; dstRect: tRect; srcRect: tRect);
var
  srcX1, srcY1, srcX2, srcY2: single;
  scaleX, scaleY: single;
  delta: integer;
  bottomRight: tPoint;
begin

  applyTransform(dstRect.pos);
  bottomRight := dstRect.bottomRight;
  dstRect.clipTo(clip);

  {todo: support negative width and height}
  scaleX := srcRect.width / dstRect.width;
  scaleY := srcRect.height / dstRect.height;

  {transform src rect based on clipping}
  srcX1 := (scaleX/2) + srcRect.left + ((dstRect.x - dstRect.pos.x) * scaleX);
  srcY1 := (scaleY/2) + srcRect.top + ((dstRect.y - dstRect.pos.y) * scaleY);

  doStretchImage(
    page, src,
    dstRect,
    srcX1, srcY1, scaleX, scaleY,
    tint, textureFilter, blendMode
  );

  markRegion(dstRect);

end;

{----------------------}
{ Constructed: draw commands built from base commands }
{----------------------}

procedure tDrawContext.hLine(pos: tPoint;len: int32;col: RGBA);
begin
  fillRect(Rect(pos.x, pos.y, len, 1), col);
end;

procedure tDrawContext.stretchSubImage(src: tPage; pos: tPoint; scaleX, scaleY: single; srcRect: tRect);
var
  dstRect: tRect;
begin
  dstRect.x := pos.x;
  dstRect.y := pos.y;
  dstRect.width := round(srcRect.width * scaleX);
  dstRect.height := round(srcRect.height * scaleY);
  self.stretchSubImage(src, dstRect, srcRect);
end;

procedure tDrawContext.drawImage(src: tPage; pos: tPoint);
begin
  drawSubImage(src, pos, src.bounds);
end;

{draw inside and outside region with different blending modes.
 this can dramatically improve performance when blitting an image that
 has transpariency only on the edges, e.g. a window frame

 It can also be used to efficently draw an image with a large
 transparent center
 }
procedure tDrawContext.inOutDraw(src: tPage; pos: tPoint; border: integer; innerBlendMode, outerBlendMode: tBlendMode);
var
  srcRect: tRect;
  oldBlendMode: tBlendMode;
begin
  srcRect := src.bounds;
  oldBlendMode := blendMode;

  {todo: this would be faster if we called eveything directly, and did
   clipping and regionMarking here instead}

  blendMode := innerBlendMode;
  drawSubImage(src,
    pos + Point(border, border),
    Rect(border, border, srcRect.width-border*2, srcRect.height-border*2)
  );

  blendMode := outerBlendMode;
  drawSubImage(src,
    pos,
    Rect(0, 0, srcRect.width, border)
  );
  drawSubImage(src,
    pos + Point(0, srcRect.height-border),
    Rect(0, srcRect.height-border, srcRect.width, border)
  );
  drawSubImage(src,
    pos + Point(0, border),
    Rect(0, border, border, srcRect.height-border*2)
  );
  drawSubImage(src,
    pos + Point(srcRect.width-border, border),
    Rect(srcRect.width-border, border, border, srcRect.height-border*2)
  );

  blendMode := oldBlendMode;
end;

procedure tDrawContext.stretchImage(src: tPage; dstRect: tRect);
begin
  stretchSubImage(src, dstRect, src.bounds);
end;

procedure tDrawContext.drawRect(dstRect: tRect; col: RGBA);
begin
  hLine(dstRect.topLeft, dstRect.width, col);
  hLine(Point(dstRect.left, dstRect.bottom-1), dstRect.width, col);
  vLine(Point(dstRect.left, dstRect.top+1), dstRect.height-2, col);
  vLine(Point(dstRect.right-1, dstRect.top+1), dstRect.height-2, col);
end;

{-------------------------------------------------}

procedure makePageRandom(page: tPage);
var
  x,y: int32;
begin
  for y := 0 to page.height-1 do
    for x := 0 to page.width-1 do
      page.putPixel(x,y,RGBA.random);
end;

procedure assertEqual(a, b: RGBA;msg: string=''); overload;
begin
  if (a.r <> b.r) or (a.g <> b.g) or (a.b <> b.b) or (a.a <> b.a) then
    assertError(Format('Colors do not match, expecting %s but found %s %s', [a.toString, b.toString, msg]));
end;

procedure assertEqual(a, b: tPage); overload;
var
  x,y: int32;
begin

  if (a.width <> b.width) or (a.height <> b.height) then
    assertError(Format('Images differ in their dimensions, expected (%d,%d) but found (%d,%d)', [a.width, a.height, b.width, b.height]));
  for y := 0 to a.height-1 do
    for x := 0 to a.width-1 do
      assertEqual(a.getPixel(x,y), b.getPixel(x,y), format('at %d,%d ',[x, y]));
end;

{-------------------------------------------------}

type
  tGraph32Test = class(tTestSuite)
    procedure testColorConversion;
    procedure run; override;
  end;

procedure tGraph32Test.testColorConversion();
var
  pageA, pageB: tPage;
begin
  pageA := tPage.create(32,32);
  makePageRandom(pageA);
  pageB := pageA.clone();

  pageA.convertColorspace(csRUV);
  pageA.convertColorspace(csRGB);
  assertEqual(pageA, pageB);

  pageA.free;
  pageB.free;
end;

procedure tGraph32Test.run();
var
  page, img: tPage;
  dc: tDrawContext;
  backend: tDrawBackend;

  {make sure page is pink (255,0,255,255) except for single pixel at location,
   of given color}
  procedure assertSinglePixel(dc: tDrawContext; x,y: integer; c: RGBA);
  var
    i,j: integer;
    status: string;
  begin
    for j := 0 to page.height-1 do begin
      for i := 0 to page.width-1 do begin
        status := format('-> at [%d,%d] backend:%s', [i,j, BACKEND_NAME[dc.backend]]);
        if (i=x) and (j=y) then
          assertEqual(c, dc.page.getPixel(i,j), status)
        else
          assertEqual(RGB(255,0,255,255), dc.page.getPixel(i,j), status);
      end;
    end;
  end;

begin

  testColorConversion();

  {test our core drawing routines}
  page := tPage.create(4,4);
  img := tPage.create(1,1);
  img.clear(RGB(255,128,64,32));
  for backend in [dbREF, dbASM, dbMMX] do begin

    dc := page.getDC(bmBlit);
    dc.backend := backend;

    {putPixel}
    page.clear(RGB(255,0,255));
    dc.putPixel(Point(1,1),RGB(1,2,3,4));
    dc.putPixel(Point(-1,-1),RGB(1,2,3,4));
    dc.putPixel(Point(5,5),RGB(1,2,3,4));
    assertSinglePixel(dc, 1, 1, RGB(1,2,3,4));

    {blit}
    page.clear(RGB(255,0,255));
    dc.drawImage(img, Point(1,1));
    dc.drawImage(img, Point(-1,-1));
    dc.drawImage(img, Point(5,5));
    assertSinglePixel(dc, 1, 1, RGB(255,128,64,32));

    {tint}
    page.clear(RGB(255,0,255));
    dc.tint := RGB(128,255,255);
    dc.drawImage(img, Point(1,1));
    dc.drawImage(img, Point(-1,-1));
    dc.drawImage(img, Point(5,5));
    assertSinglePixel(dc, 1, 1, RGB(128,128,64,32));

    {blend}
    page.clear(RGB(255,0,255));
    dc.blendMode := bmBlend;
    dc.tint := RGB(128,255,255);
    dc.drawImage(img, Point(1,1));
    dc.drawImage(img, Point(-1,-1));
    dc.drawImage(img, Point(5,5));
    assertSinglePixel(dc, 1, 1,
      RGB(
        round(128*(32/255)+255*(223/255)),
        round(128*(32/255)+0*(223/255)),
        round(64*(32/255)+255*(223/255)),
        round(32*(32/255)+255*(223/255))
      )
    );
  end;

end;

{--------------------------------------------------------}

initialization
  tGraph32Test.create('Graph32');
end.
