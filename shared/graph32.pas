{2D graphics library}

{$MODE delphi}

unit graph32;

interface

uses
  test,
  debug,
  vga,
  resource,
  sysTypes,
  sysInfo,
  uColor,
  utils,
  graph2d;

const
  ERR_COL: RGBA = (b:255;g:0;r:255;a:255);

type

  tBlendMode = (
    bmNone,   // skip
    bmBlit,   // src
    bmBlend   // alpha*src + (1-alpha)*dst
  );
  tDrawBackend = (dbREF, dbASM, dbMMX);

  tPage = class;

  tDrawContext = record
    page: tPage;
    offset: tPoint;
    clip: tRect;
    blendMode: tBlendMode;
    tint: RGBA;  {used to modulate src color before write}
    backend: tDrawBackend;
    procedure applyTransform(var p: tPoint); inline;
    procedure applyTransformInv(var p: tPoint); inline;
    procedure applyTint(var col: RGBA); inline;
    function  smartBM(col: RGBA): tBlendMode;
    function  hasTint: boolean; inline;

    {dispatch}
    procedure blitCol(pixels: pRGBA;len: int32;col: RGBA);
    procedure blendCol(pixels: pRGBA;len: int32;col: RGBA);
    procedure blitImage(dstPixels, srcPixels: pointer; dstX, dstY, srcX, srcY, width, height: int32);
    procedure tintImage(dstPixels, srcPixels: pointer; dstX, dstY, srcX, srcY, width, height: int32; tint: RGBA);
    procedure blendImage(dstPixels, srcPixels: pointer; dstX, dstY, srcX, srcY, width, height: int32; tint: RGBA);

    {basic drawing API}
    procedure putPixel(pos: tPoint; col: RGBA);
    procedure hLine(pos: tPoint;len: int32;col: RGBA);
    procedure vLine(pos: tPoint;len: int32;col: RGBA);
    procedure drawSubImage(src: tPage; pos: tPoint; srcRect: tRect);
    {constructed}
    procedure drawImage(src: tPage; pos: tPoint);
    procedure fillRect(rect: tRect; col: RGBA);
    procedure drawRect(rect: tRect; col: RGBA);
  end;

  {page using 32bit RGBA color}
  tPage = class(tResource)
    width, height: word;
    isRef: boolean;
    pixels: pointer;
    defaultColor: RGBA;

    constructor Create(); overload;
    destructor  destroy(); override;
    constructor create(aWidth, aHeight: word); overload;
    constructor createAsReference(aWidth, aHeight: word;pixelData: Pointer);

    function  dc(blendMode: tBlendMode = bmBlend): tDrawContext;
    function  getAddress(x, y: integer): pointer; inline;
    function  getPixel(x, y: integer): RGBA; inline;
    function  getPixelF(fx,fy: single): RGBA;
    procedure putPixel(atX, atY: int16;c: RGBA); inline; assembler; register;
    procedure setPixel(atX, atY: int16;c: RGBA); inline; assembler; register;
    procedure clear(c: RGBA);

    function  clone(): tPage;
    function  asBytes: tBytes;
    function  asRGBBytes: tBytes;
    function  scaled(aWidth, aHeight: integer): tPage;
    function  resized(aWidth, aHeight: integer): tPage;
    procedure resize(aWidth, aHeight: integer);
    function  bounds(): tRect; inline;

    procedure setTransparent(col: RGBA);
    function  checkForAlpha: boolean;

    class function Load(filename: string): tPage;
  end;

  {page stored as 8bit lumance}
  tPage8 = class(tResource)
    width, height: word;
    pixels: pointer;
    constructor Create(); overload;
    destructor  destroy(); override;
    constructor create(aWidth, aHeight: word); overload;
    function    getAddress(x, y: integer): pointer; inline;
    procedure   putValue(x, y: integer;v: byte);
    function    getValue(x, y: integer): byte;
    class function Load(filename: string): tPage8;
  end;

  tImageLoaderProc = function(filename: string): tPage;

  tGFXLibrary = class(tResourceLibrary)
  protected
    function getGFXByTag(aTag: string): tPage;
  public
    function addResource(filename: string): tResource; override;
    property items[tag: string]: tPage read getGFXByTag; default;
  end;

procedure makePageRandom(page: tPage);

procedure assertEqual(a, b: RGBA;msg: string=''); overload;
procedure assertEqual(a, b: tPage); overload;

implementation

uses
  sprite,
  bmp;

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
end;

constructor tPage.create(aWidth, aHeight: word); overload;
begin
  create();
  self.width := AWidth;
  self.height := AHeight;
  self.pixels := getMem(dword(aWidth) * aHeight * 4);
  self.clear(RGBA.Create(0,0,0));
end;

constructor tPage.CreateAsReference(aWidth, aHeight: word;pixelData: Pointer);
{todo: support logical width}
begin
  create();
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
function tPage.dc(blendMode: tBlendMode = bmBlend): tDrawContext;
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
function TPage.getPixelF(fx, fy: single): RGBA;
var
  x,y: integer;
  fracX, fracY: single;
  c1,c2,c3,c4: RGBA;
  p1,p2,p3,p4: single;
begin
  {todo: make asm and fast (maybe even MMX)}
  result.init(255,0,255);
  if (fx < 0) or (fy < 0) or (fx > width-1) or (fy > height-1) then exit;
  x := Trunc(fx);
  y := Trunc(fy);
  fracX := fx - x;
  fracY := fy - y;
  c1 := self.getPixel(x, y);
  c2 := self.getPixel(x+1, y);
  c3 := self.getPixel(x,   y+1);
  c4 := self.getPixel(x+1, y+1);

  p1 := (1-fracX) * (1-fracY);
  p2 := fracX * (1-fracY);
  p3 := (1-fracX) * fracY;
  p4 := fracX * fracY;

  result := (c1 * p1) + (c2 * p2) + (c3 * p3) + (c4 * p4);
end;

procedure tPage.clear(c: RGBA);
begin
  filldword(pixels^, width*height, c.to32);
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

    mov al,  byte ptr c[2]
    mul cl
    mov dl,  ah
    mov al,  byte ptr [edi+2]
    mul ch
    add dl,  ah
    shl edx, 8

    mov al,  byte ptr c[1]
    mul cl
    mov dl,  ah
    mov al,  byte ptr [edi+1]
    mul ch
    add dl,  ah
    shl edx, 8

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

{returns true if any of the pixels have any transparency.}
function tPage.checkForAlpha: boolean;
var
  x,y: int32;
begin
  for y := 0 to height-1 do
    for x := 0 to width-1 do
      if getPixel(x,y).a <> 255 then exit(True);
  exit(False);
end;

function tPage.resized(aWidth, aHeight: integer): tPage;
var
  new: tPage;
  s: tSprite;
begin
  new := tPage.create(aWidth, aHeight);
  s := tSprite.create(self);
  s.blit(new, 0, 0);
  s.free();
  result := new;
end;

procedure tPage.resize(aWidth, aHeight: integer);
var
  tmp: tPage;
  s: tSprite;
begin
  tmp := self.clone();
  self.width := aWidth;
  self.height := aHeight;
  freemem(self.pixels);
  getMem(self.pixels, aWidth*aHeight*4);
  fillchar(self.pixels^, aWidth*aHeight*4, 0);
  s := tSprite.create(tmp);
  s.blit(self, 0, 0);
  s.free();
  note(hexStr(tmp));
  tmp.free();
end;

function tPage.bounds(): tRect; inline;
begin
  result := Rect(0,0,width,height);
end;

function tPage.scaled(aWidth, aHeight: integer): tPage;
var
  new: tPage;
  s: tSprite;
begin
  new := tPage.create(aWidth, aHeight);
  s := tSprite.create(self);
  s.drawStretched(new, rect(aWidth, aHeight));
  s.free();
  result := new;
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
    debug.fatal('No image loader for file "'+filename+'"');
end;

{-------------------------------------------------}

constructor tPage8.create();
begin
  inherited create();
  self.width := 0;
  self.height := 0;
  self.pixels := nil;
end;

destructor tPage8.destroy();
begin
  if assigned(self.pixels) then begin
    freeMem(self.pixels);
    self.pixels := nil;
  end;
  inherited destroy();
end;

constructor tPage8.create(aWidth, aHeight: word);
begin
  create();
  self.width := aWidth;
  self.height := aHeight;
  self.pixels := getMem(aWidth * aHeight);
  fillchar(self.pixels^, aWidth * aHeight, 0);
end;

procedure tPage8.putValue(x, y: integer;v: byte);
begin
  if dword(x) >= width then exit;
  if dword(y) >= height then exit;
  pByte(pixels + (x+y*width))^ := v;
end;

function tPage8.getValue(x, y: integer): byte;
begin
  if dword(x) >= width then exit(0);
  if dword(y) >= height then exit(0);
  result := pByte(pixels + (x+y*width))^;
end;

{returns address in memory of given pixel. If out of bounds, returns nil}
function tPage8.getAddress(x, y: integer): pointer; inline;
begin
  if (dword(x) >= self.width) or (dword(y) >= self.height) then exit(nil);
  result := pixels + (y * width + x);
end;

class function tPage8.Load(filename: string): tPage8;
var
  page: tPage;
  x,y: integer;
begin
  page := tPage.load(filename);
  result := tPage8.create(page.width, page.height);
  for y := 0 to page.height-1 do
    for x := 0 to page.width-1 do
      result.putValue(x, y, page.getPixel(x,y).lumance);
  page.free();
end;

{-------------------------------------------------}
{ dispatch}

procedure tDrawContext.blitCol(pixels: pRGBA;len: int32;col: RGBA);
begin
  case backend of
    dbREF: blitCol_REF(pixels, len, col);
    dbASM: blitCol_ASM(pixels, len, col);
    dbMMX: blitCol_MMX(pixels, len, col);
  end;
end;

procedure tDrawContext.blendCol(pixels: pRGBA;len: int32;col: RGBA);
begin
  case backend of
    dbREF: blendCol_REF(pixels, len, col);
    dbASM: blendCol_REF(pixels, len, col); // no ASM version yet
    dbMMX: blendCol_MMX(pixels, len, col);
  end;
end;

procedure tDrawContext.blitImage(dstPixels, srcPixels: pointer; dstX, dstY, srcX, srcY, width, height: int32);
begin
  case backend of
    dbREF: blitImage_REF(dstPixels, srcPixels, dstX, dstY, srcX, srcY, width, height);
    dbASM: blitImage_ASM(dstPixels, srcPixels, dstX, dstY, srcX, srcY, width, height);
    dbMMX: blitImage_MMX(dstPixels, srcPixels, dstX, dstY, srcX, srcY, width, height);
  end;
end;

procedure tDrawContext.tintImage(dstPixels, srcPixels: pointer; dstX, dstY, srcX, srcY, width, height: int32; tint: RGBA);
begin
  tintImage_MMX(dstPixels, srcPixels, dstX, dstY, srcX, srcY, width, height, tint);
end;

procedure tDrawContext.blendImage(dstPixels, srcPixels: pointer; dstX, dstY, srcX, srcY, width, height: int32; tint: RGBA);
begin
  blendImage_MMX(dstPixels, srcPixels, dstX, dstY, srcX, srcY, width, height, tint);
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

procedure tDrawContext.putPixel(pos: tPoint;col: RGBA);
begin
  applyTransform(pos);
  if not clip.isInside(pos.x, pos.y) then exit;
  applyTint(col);

  case smartBM(col) of
    bmBlit: page.setPixel(pos.x, pos.y, col);
    bmBlend: page.putPixel(pos.x, pos.y, col);
  end;
end;

procedure tDrawContext.hLine(pos: tPoint;len: int32;col: RGBA);
var
  endPos: tPoint;
  i: integer;
  pixels: pointer;
begin
  applyTransform(pos);
  endPos := Point(pos.x+len, pos.y);
  pos := clip.clipPoint(pos);
  endPos := clip.clipPoint(endPos);
  len := endPos.x - pos.x;
  if len <= 0 then exit;

  applyTint(col);
  pixels := page.getAddress(pos.x, pos.y);

  case smartBM(col) of
    bmBlit: blitCol(pixels, len, col);
    bmBlend: blendCol(pixels, len, col);
  end;
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
    bmNone: ;
    bmBlit: for i := 0 to len-1 do page.setPixel(pos.x, pos.y+i, col);
    bmBlend: for i := 0 to len-1 do page.putPixel(pos.x, pos.y+i, col);
  end;
end;

procedure tDrawContext.drawSubImage(src: tPage; pos: tPoint; srcRect: tRect);
var
  dstRect: tRect;
  srcOffset: tPoint;
begin

  applyTransform(pos);

  dstRect := Rect(pos.x, pos.y, src.width, src.height);
  dstRect.clipTo(clip);
  if dstRect.isEmpty then exit;
  srcRect.width := dstRect.width;
  srcRect.height := dstRect.height;
  srcRect.pos += (pos - dstRect.pos); // might be the wrong way around..?

  case blendMode of
    bmNone: ;
    bmBlit: begin
      if hasTint then
        tintImage(page, src, dstRect.x, dstRect.y, srcRect.x, srcRect.y, srcRect.width, srcRect.height, tint)
      else
        blitImage(page, src, dstRect.x, dstRect.y, srcRect.x, srcRect.y, srcRect.width, srcRect.height);
      end;
    bmBlend:
      blendImage(page, src, dstRect.x, dstRect.y, srcRect.x, srcRect.y, srcRect.width, srcRect.height, tint);
  end;
end;

{----------------------}
{ Constructed: draw commands built from base commands }
{----------------------}

procedure tDrawContext.drawImage(src: tPage; pos: tPoint);
begin
  drawSubImage(src, pos, src.bounds);
end;

procedure tDrawContext.fillRect(rect: tRect; col: RGBA);
var
  pos: tPoint;
  y: integer;
begin
  {transform, then clip, then restore... only for performance reasons}
  applyTransform(rect.pos);
  rect.clipTo(clip);
  if rect.isEmpty then exit;
  applyTransformInv(rect.pos);
  for y := rect.top to rect.bottom-1 do
    hLine(Point(rect.left, y), rect.width, col);
end;

procedure tDrawContext.drawRect(rect: tRect; col: RGBA);
begin
  hLine(rect.topLeft, rect.width, col);
  hLine(Point(rect.left, rect.bottom-1), rect.width, col);
  vLine(Point(rect.left, rect.top+1), rect.height-2, col);
  vLine(Point(rect.right-1, rect.top+1), rect.height-2, col);
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
    procedure run; override;
  end;

procedure tGraph32Test.run();
var
  a,b: RGBA;
  page8: tPage8;
begin
  {test RGBA}
  a.init(0, 64, 128);
  b.from16(a.to16);
  assertEqual(a,b);
  {test page 8}
  {just make sure we can allocate and deallocate}
  page8 := tPage8.create(16,16);
  page8.destroy();
end;

{--------------------------------------------------------}

initialization
  tGraph32Test.create('Graph32');
end.
