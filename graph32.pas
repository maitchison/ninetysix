{2D graphics library}

{$MODE delphi}


unit graph32;

interface

uses
	test,
	debug,
  vga,
  utils,
  graph2d;

type
  TBMPHeader = packed record
    FileType: Word;
    FileSize: Cardinal;
    Reserved1: Word;
    Reserved2: Word;
    Offset: Cardinal;
  end;

  TBitmapInfoHeader = packed record
    Size: Cardinal;
    Width: Integer;
    Height: Integer;
    Planes: Word;
    BitsPerPixel: Word;
    Compression: Cardinal;
    SizeImage: Cardinal;
    XPelsPerMeter: Integer;
    YPelsPerMeter: Integer;
    ClrUsed: Cardinal;
    ClrImportant: Cardinal;

    function ByteCount(): Cardinal;
    function PixelCount(): Cardinal;
  end;

type
  	
  RGBA = packed record

	 	b,g,r,a: byte;

    constructor Create(r,g,b: integer;a: integer=255);

    class function Random(): RGBA; static;

		class operator add(a,b: RGBA): RGBA;
    class operator multiply(a: RGBA; b: single): RGBA;
		class operator equal(a,b: RGBA): boolean;

    function toString: shortString;

    procedure init(r,g,b: int32;a: int32=255);
    procedure gammaAdjust(v: single);
    procedure linearAdjust(v: single);
    procedure blend(other: RGBA; factor: single);
    procedure toLinear();
    procedure toSRGB();
    function to32(): uint32;
    function to16(): uint16;
    function to16_(): uint16;
    function to12(): uint16;
    function to12_(): uint16;

  end;

  pRGBA = ^RGBA;

  {32 Bit Float}
  RGBA32 = packed record
	 	b,g,r,a: single;

		class operator explicit(this: RGBA32): ShortString;
		class operator implicit(this: RGBA32): RGBA;
		class operator implicit(other: RGBA): RGBA32;

    function ToString(): ShortString;

    class operator add(a,b: RGBA32): RGBA32;
    class operator multiply(a: RGBA32; b: single): RGBA32;

  end;

  {16 bit signed integer}
  RGBA16 = packed record
  	b,g,r,a: int16;
	class operator explicit(this: RGBA16): RGBA;
	class operator explicit(this: RGBA16): RGBA32;
  end;

const
	ERR_COL: RGBA = (b:255;g:0;r:255;a:255);

type
	tPage = object
  	Width, Height, BPP: Word;
    Pixels: pointer;
    defaultColor: RGBA;

    destructor  Done();
    constructor Init(AWidth, AHeight: word);
		constructor InitReference(AWidth, AHeight: word;PixelData: Pointer);

    function GetPixel(x, y: integer): RGBA; inline; overload;
    function GetPixel(fx,fy: single): RGBA; overload;
    function GetPixelScaled(x, y, s: integer;doGamma: boolean=False): RGBA;
    procedure HLine(x1, y, x2: int16;c: RGBA); pascal;
    procedure PutPixel(atX, atY: int16;c: RGBA); inline; assembler; register;
    procedure SetPixel(atX, atY: int16;c: RGBA); inline; assembler; register;
    procedure Clear(c: RGBA);
		procedure FillRect(aRect: TRect; c: RGBA);
    procedure DrawRect(aRect: TRect; c: RGBA);
    function clone(): TPage;
    function asBytes: tBytes;
    function asRGBBytes: tBytes;
    procedure setTransparent(col: RGBA);

    function checkForAlpha: boolean;

	end;

function LoadBMP(const FileName: string): TPage;
procedure makePageRandom(page: tPage);

procedure assertEqual(a, b: RGBA); overload;
procedure assertEqual(a, b: tPage); overload;

implementation

{returns value v at brightness b [0..1] with gamma correction}
function gammaCorrect(v: byte; b: single): byte;
var
	value: single;
	linear: single;
  adjusted: single;
const
	GAMMA = 2.4;
begin
	{Just assume gamma=2.0 and no weird stuff}
  if b < 0 then exit(0);
  value := v / 255.0;
  if value <= 0.04045 then
  	linear := value / 12.92
  else
  	linear := Power((value + 0.055) / 1.055, GAMMA);

  linear := linear * b;

  if linear <= 0.0031308 then
		adjusted := 12.92 * linear
  else	
	  adjusted := 1.055 * power(linear, 1/GAMMA) - 0.055;
  result := clamp(round(adjusted * 255.0), 0, 255);
end;

function linearCorrect(v: byte; b: single): byte;
begin
  result := clamp(round(v * b), 0, 255);
end;

function linear(v: byte): single;
var
	value: single;
	linear: single;
const
	GAMMA = 2.4;
begin
  value := v / 255.0;
  if value <= 0.04045 then
  	linear := value / 12.92
  else
  	linear := power((value + 0.055) / 1.055, GAMMA);
  result := linear;
end;

function SRGB(linear: single): byte;
const
	GAMMA = 2.4;
var
	adjusted: single;
begin
  if linear <= 0.0031308 then
		adjusted := 12.92 * linear
  else	
	  adjusted := 1.055 * power(linear, 1/GAMMA) - 0.055;
  result := clamp(round(adjusted * 255.0), 0, 255);
end;


{----------------------------------------------}

Constructor RGBA.Create(r,g,b: integer;a: integer=255);
begin
	self.init(r,g,b,a);
end;

{Creates a random color}
class function RGBA.Random(): RGBA; static;
begin
	result.init(rnd, rnd, rnd);
end;


class operator RGBA.add(a, b: RGBA): RGBA;
begin
	{ignore alpha for the moment}
	result.init(a.r + b.r, a.g + b.g, a.b + b.b);
end;

class operator RGBA.multiply(a: RGBA; b: single): RGBA;
begin
	{ignore alpha for the moment}
	result.init(round(a.r*b), round(a.g*b), round(a.b*b));
end;

function RGBA.toString: shortString;
begin
	if a = 255 then
		result := format('(%d,%d,%d)', [r,g,b])
  else
  	result := format('(%d,%d,%d,%d)', [r,g,b,a]);
  	
end;

procedure RGBA.blend(other: RGBA; factor: single);
begin
	other.gammaAdjust(factor);
  self.gammaAdjust(1-factor);
  r += other.r;
  g += other.g;
  b += other.b;
end;

procedure RGBA.gammaAdjust(v: single);
begin
	r := gammaCorrect(r, v);
  g := gammaCorrect(g, v);
	b := gammaCorrect(b, v);
end;

procedure RGBA.linearAdjust(v: single);
begin
	r := linearCorrect(r, v);
  g := linearCorrect(g, v);
	b := linearCorrect(b, v);
end;

function RGBA.to32(): uint32;
begin
  result := (a shl 24) + (r shl 16) + (g shl 8) + b;
end;

function RGBA.to16(): uint16;
begin
	result := ((r shr 3) shl 11) + ((g shr 2) shl 5) + (b shr 3);
end;

function RGBA.to12(): uint16;
begin
	result := (r shr 4 shl 12) + (g shr 4 shl 7) + (b shr 4 shl 1);
end;

procedure RGBA.toLinear();
begin
  r := clamp(round(linear(r) * 255), 0, 255);
  g := clamp(round(linear(g) * 255), 0, 255);
  b := clamp(round(linear(b) * 255), 0, 255);
end;

procedure RGBA.toSRGB();
begin
	r := SRGB(r/255.0);
  g := SRGB(g/255.0);
  b := SRGB(b/255.0);
end;

function RGBA.to16_(): uint16;
begin
  result := quantize(r, 32) shl 11 + quantize(g, 64) shl 5 + quantize(b, 32);
end;

function RGBA.to12_(): uint16;
begin
  result := quantize(r, 16) shl 12 + quantize(g, 16) shl 7 + quantize(b, 16) shl 1;
end;

procedure RGBA.init(r,g,b: integer;a: integer=255);
begin
  self.r := clamp(r, 0, 255);
  self.g := clamp(g, 0, 255);
  self.b := clamp(b, 0, 255);
  self.a := clamp(a, 0, 255);
end;

class operator RGBA.equal(a,b: RGBA): boolean;
begin
	exit(pDword(@a)^=pDword(@b)^);
end;


{----------------------------------------------}

{generics might be a good idea?}

class operator RGBA16.explicit(this: RGBA16): RGBA;
begin
	{this will clamp results}
	result.init(this.r, this.g, this.b, this.a);
end;

class operator RGBA16.explicit(this: RGBA16): RGBA32;
begin
	result.r := this.r;
  result.g := this.g;
  result.b := this.b;
  result.a := this.a;
end;


{----------------------------------------------}

{todo: make this a 4 vector instead?}

class operator RGBA32.explicit(this: RGBA32): ShortString;
begin
	result := Format('(%f,%f,%f)', [this.r, this.g, this.b]);
end;

function RGBA32.ToString(): ShortString;
begin
	result := Format('%d,%d,%d', [self.r, self.g, self.b]);
end;

class operator RGBA32.implicit(this: RGBA32): RGBA;
begin
	result.init(trunc(this.r), trunc(this.g), trunc(this.b), trunc(this.a));
end;

class operator RGBA32.implicit(other: RGBA): RGBA32;
begin
	result.r := other.r;
  result.g := other.g;
  result.b := other.b;
  result.a := other.a;
end;

class operator RGBA32.add(a, b: RGBA32): RGBA32;
begin
	{ignore alpha for the moment}
	result.r := a.r + b.r;
  result.g := a.g + b.g;
  result.b := a.b + b.b;
  result.a := 255;
end;

class operator RGBA32.multiply(a: RGBA32; b: single): RGBA32;
begin
	{ignore alpha for the moment}
	result.r := a.r*b;
  result.g := a.g*b;
  result.b := a.b*b;
  result.a := 255;
end;

{----------------------------------------------}

{SizeImage is often zero, so calculate the number of bytes here.}
function TBitmapInfoHeader.ByteCount(): Cardinal;
begin
  result := PixelCount * BitsPerPixel div 8;
end;

{SizeImage is often zero, so calculate the number of bytes here.}
function TBitmapInfoHeader.PixelCount(): Cardinal;
begin
  result := Width * Height;
end;

{----------------------------------------------}

function intToStr(x: integer): String;
var s: string;
begin
	str(x, s);
  result := s;
end;

function LoadBMP(const FileName: string): TPage;
var
	FileHeader: TBMPHeader;
  InfoHeader: TBitmapInfoHeader;
  f: File;

  lineWidth: integer;
  x, y, i: integer;
  c: RGBA;
  linePadding: integer;
  lineData: Array of byte;

  BytesPerPixel: integer;

  BytesRead: int32;
  IOError: word;
begin
	FileMode := 0; {read only}
	Assign(F, FileName);
  {$I-}
  Reset(F, 1);
  {$I+}
  IOError := IOResult;
  if IOError <> 0 then
  	Error('Could not open file "'+FileName+'" '+GetIOError(IOError));

  BlockRead(F, FileHeader, SizeOf(TBMPHeader), BytesRead);
  if BytesRead <> SizeOf(TBMPHeader) then
  	Error('Error reading BMP Headed.');

  BlockRead(F, InfoHeader, SizeOf(TBitmapInfoHeader), BytesRead);
  if BytesRead <> Sizeof(TBitmapInfoHeader) then
  	Error('Error reading BMP Info Header.');

  if (FileHeader.FileType <> $4D42) then
  	Error(Format('Not a valid BMP file, found $%h, expected $%h', [FileHeader.FileType, $4D42]));

  if not (InfoHeader.BitsPerPixel in [8, 24, 32]) then
  	Error(
    	'Only 8, 24, and 32-bit BMP images are supported, but "'+FileName+'" is '+
      intToStr(InfoHeader.BitsPerPixel)+'-bit');

  result.Width := InfoHeader.Width;
  result.Height := InfoHeader.Height;
  result.BPP := InfoHeader.BitsPerPixel;

  BytesPerPixel := result.BPP div 8;
  LineWidth := result.Width * BytesPerPixel;
  while LineWidth mod 4 <> 0 do
  	inc(LineWidth);

  Seek(F, FileHeader.Offset);

  SetLength(LineData, LineWidth);

  result.Pixels := getMem(InfoHeader.PixelCount * 4);
  fillchar(result.pixels^, InfoHeader.PixelCount * 4, 255);

  for y := result.Height-1 downto 0 do begin
  	BlockRead(F, LineData[0], LineWidth, BytesRead);
  	for x := 0 to result.Width-1 do begin
	    {ignore alpha for the moment}
      case Result.BPP of      	
				8:
      		{assume 8bit is monochrome}
      		c.init(LineData[x], LineData[x], LineData[x], 255);
      	24:
			  	c.init(LineData[x*3+2], LineData[x*3+1], LineData[x*3+0], 255);
      	32:
			  	c.init(LineData[x*4+2], LineData[x*4+1], LineData[x*4+0], LineData[x*4+3]);
        else
        	Error('Invalid Bitmap depth '+IntToStr(Result.BPP));
      end;
			result.PutPixel(x, y, c);
    end;
  end;

  Close(F);

  {todo: don't store bitmap depth in result.bpp}
  result.BPP := 32;
end;


{----------------------------------------------------------------}
{ TPage }
{----------------------------------------------------------------}

constructor TPage.Init(AWidth, AHeight: word);
begin
	self.Width := AWidth;
  self.Height := AHeight;
  self.BPP := 32;
  self.Pixels := getMem(AWidth * AHeight * 4);
  self.defaultColor := ERR_COL;
  self.Clear(RGBA.Create(0,0,0));
end;

destructor tPage.Done();
begin
	if assigned(self.pixels) then
		freeMem(self.pixels, width*height*4);
  self.pixels := nil;
  self.width := 0;
  self.height := 0;
  self.bpp := 0;
end;

constructor tPage.InitReference(AWidth, AHeight: word;PixelData: Pointer);
{todo: support logical width}
begin
	self.Width := AWidth;
  self.Height := AHeight;
  self.BPP := 32;
  self.Pixels := PixelData;
end;


function TPage.GetPixel(x, y: Integer): RGBA; overload;
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

{Get pixel with interpolation}
function TPage.GetPixel(fx, fy: single): RGBA; overload;
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

function TPage.GetPixelScaled(x, y, s: integer;doGamma: boolean): RGBA;
var
	i,j: int32;
  factor: single;
  r,g,b: int32;
  c: RGBA;
begin
	result.init(0,0,0);
	if x < 0 then exit;
  if x >= 1024 shr s then exit;
	if y < 0 then exit;
  if y >= 1024 shr s then exit;
	r := 0;
  g := 0;
  b := 0;
	for i := 0 to (1 shl s)-1 do begin
	 for j := 0 to (1 shl s)-1 do begin
   	c := getPixel(x shl s+i, y shl s+j);
    if doGamma then c.toLinear;
    r += c.r;
    g += c.g;
    b += c.b;
  	end;
  end;
  result.init(r shr (s*2), g shr (s*2), b shr (s*2));
  if doGamma then result.toSRGB;
end;


procedure TPage.Clear(c: RGBA);
begin
	self.FillRect(TRect.Create(0, 0, self.Width, self.Height), c);
end;


procedure TPage.PutPixel(atX,atY: int16;c: RGBA); inline; assembler; register;
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

    cmp dx,  [esi].Width								// unsigned cmp will catch negative values.
    jge @Skip
    cmp cx,  [esi].Height
    jge @Skip

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

    cmp dx,  [esi].Width								// unsigned cmp will catch negative values.
    jge @SKIP
    cmp cx,  [esi].Height
    jge @SKIP

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

{Draw line from (x1,y) to (x2,y) inclusive at start and exclusive at end.}
procedure TPage.HLine(x1,y,x2: int16; c: RGBA); pascal;
var
	count: int32;
  ofs: dword;
begin

  if c.a = 0 then exit;

  {clipping}
	if word(y) >= self.Height then exit;
	if x1 < 0 then x1 := 0;
  if x2 > self.Width then x2 := self.Width;
  count := x2-x1;
  if count <= 0 then exit;

	ofs := (y * self.Width + x1) * 4;

  if c.a = 255 then begin
  	{fast, no blending, path}
    filldword((self.pixels+ofs)^, count, dword(c));
    exit;
  end;

  {alpha blending path}
	asm

  	push esi
    push edi
    push ecx

  	mov esi, self

    mov edi, [esi].Pixels
    add edi, ofs

    {we need a zero register to expand from byte to word}
    pxor 			mm0, mm0				// MM0 <-  0 0 0 0 | 0 0 0 0

    mov eax, c
    mov cl, c[3]

    {replicate alpha across the words}
    mov 			ch, cl
    shl				ecx, 8
    mov				cl, ch
    movd 			mm3, ecx
    punpcklbw mm3, mm0			  // MM3 <- 0 0 0 A | 0 A 0 A

    {replicate = 255-alpha accross the words}
    mov 			cl, 255
    sub				cl, ch
    mov				ch, cl
    shl				ecx, 8
    mov 		  cl, ch
    movd 			mm4, ecx
    punpcklbw mm4, mm0			// MM4 <- 0 `A 0 `A | 0 `A 0 `A}

    {expand and premultiply our source color}
    movd 			mm2, eax			// MM2 <-  0  0  0  0|  0 Rs Gs Bs
    punpcklbw mm2, mm0			// MM2 <-  0  0  0 Rs|  0 Gs  0 Bs
    pmullw 		mm2, mm3			// MM2 <-  0  A*Rs A*Gs A*bs

    mov ecx, count

  @LOOP:

    {read source pixel}
    mov edx, [edi]

    {do the blend}
    movd      mm1, edx      // MM1 <-  0  0  0  0|  0 Rd Gd Bd
    punpcklbw mm1, mm0      // MM1 <-  0  0  0 Rd|  0 Gd  0 Bd
    pmullw    mm1, mm4      // MM1 <-  0  (255-A)*Rd (255-A)*Gd (255-A)*bd
    paddw     mm1, mm2      // MM1 <- A*Rs+(255-A)*Rd ...
    psrlw			mm1, 8				// MM1 <- (A*Rs+(255-A)*Rd) / 256

    { note, we should have divided by 255 instead of 255 but I don't think
     anyone will notice. To reduce the error we could do a saturated subtract of 128
     which makes the expected error 0 over uniform input}
    packuswb	mm1, mm1			// MM1 = 0 0 0 0 | 0 R G B
    movd 			eax, mm1

	  mov dword ptr [edi], eax

    add edi, 4

    dec ecx
    jnz @LOOP

    pop ecx
  	pop esi
    pop edi

    emms

  end;
end;


procedure TPage.FillRect(aRect: TRect; c: RGBA);
var
	y: integer;
begin
	for y := aRect.top to aRect.bottom-1 do
  	self.Hline(aRect.left, y, aRect.right, c);
end;

procedure TPage.DrawRect(aRect: TRect; c: RGBA);
var
	x,y: integer;
begin
	for x := aRect.left to aRect.right-1 do begin
  	PutPixel(x,aRect.top,c);
  	PutPixel(x,aRect.bottom-1,c);
  end;
	for y := aRect.top to aRect.bottom-1 do begin
  	PutPixel(aRect.left,y,c);
  	PutPixel(aRect.right-1,y,c);    	
  end;
end;

function TPage.Clone(): TPage;
begin
	result.Width := self.width;
  result.Height := self.height;
  result.BPP := self.BPP;
  result.Pixels := getMem(self.width*self.height*4);
  move(self.pixels^, result.pixels^, self.width*self.height*4);
end;

{make a copy of page using RGBA}
function tPage.asBytes: tBytes;
begin
  if BPP <> 32 then Error('As bytes only supports BPP=32bit');
	result := nil;
  setLength(result, width*height*4);
  move(pixels^, result[0], width*height*4);	
end;

{make a copy of page using RGB}
function tPage.asRGBBytes: tBytes;
var
	i: int32;
begin
  if BPP <> 32 then Error('As bytes only supports BPP=32bit');
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


{-------------------------------------------------}

procedure makePageRandom(page: tPage);
var
	x,y: int32;
begin
	for y := 0 to page.height-1 do
  	for x := 0 to page.width-1 do
    	page.putPixel(x,y,RGBA.random);
end;


procedure assertEqual(a, b: RGBA); overload;
begin
	if (a.r <> b.r) or (a.g <> b.g) or (a.b <> b.b) or (a.a <> b.a) then
  	assertError(Format('Colors do not match, expecting %s but found %s', [a.toString, b.toString]));
end;

procedure assertEqual(a, b: tPage); overload;
var
	x,y: int32;
begin

  if (a.width <> b.width) or (a.height <> b.height) then
  	assertError(Format('Images differ in their dimensions, expected (%d,%d) but found (%d,%d)', [a.width, a.height, b.width, b.height]));
	if a.bpp <> b.bpp then begin
  	assertError(Format('Images differ in their bits per pixel, expected %d but found %d', [a.bpp, b.bpp]));
  end;
  for y := 0 to a.height-1 do
  	for x := 0 to a.width-1 do
      assertEqual(a.getPixel(x,y), b.getPixel(x,y));
end;

begin
end.
