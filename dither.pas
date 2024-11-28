// Test dithering to see if we can get away with 16bit
//

{$MODE delphi}


uses
	crt,
  math,
  graph32,
  time,
  screen;

type RGB = packed record
	b,g,r,a: byte; {to match BMP :( }

  procedure init(r,g,b: integer);
  procedure gammaAdjust(v: single);
  procedure linearAdjust(v: single);
  procedure toLinear();
  procedure toSRGB();
  function to32(): uint32;
  function to16(): uint16;
  function to16_(): uint16;
  function to12(): uint16;
  function to12_(): uint16;

  end;


type
	ByteArray = array[0..1024*1024*4-1] of byte;
  pByteArray = ^ByteArray;

var
	image: array[0..1024-1, 0..1024-1] of RGB;

procedure putPixel(x,y: uint16;col: uint16); inline; assembler; stdcall; overload;
asm
  	push es
    push eax
    push edi

  	mov ax, LFB
    mov es, ax

    {is this really faster than imul?}
    xor eax, eax
    xor edx, edx
    mov dx, SCREEN_WIDTH
    mov ax, y
    mul dx
    shl edx, 16
    add edx, eax
    mov edi, edx

    xor eax, eax
    mov ax, x
    add edi, eax
    shl edi, 1

    mov ax, col
    mov es:[edi], ax

    pop edi
    pop eax
    pop es
  	end;

procedure putPixel(x,y: uint16;col: uint32); inline; assembler; stdcall; overload;
asm
  	push es
    push edx
    push eax
    push edi

  	mov ax, LFB
    mov es, ax

    {is this really faster than imul?}
    xor eax, eax
    xor edx, edx
    mov dx, SCREEN_WIDTH
    mov ax, y
    mul dx
    shl edx, 16
    add edx, eax
    mov edi, edx

    xor eax, eax
    mov ax, x
    add edi, eax
    shl edi, 2

    mov eax, col
    mov es:[edi], eax

    pop edi
    pop eax
    pop edx
    pop es
  	end;

function clip(x, a, b: integer): integer;
begin
	if x < a then exit(a);
  if x > b then exit(b);
  exit(x);
end;


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
  	linear := power((value + 0.055) / 1.055, GAMMA);

  linear *= b;

  if linear <= 0.0031308 then
		adjusted := 12.92 * linear
  else	
	  adjusted := 1.055 * power(linear, 1/GAMMA) - 0.055;
  result := clip(round(adjusted * 255.0), 0, 255);
end;

function linearCorrect(v: byte; b: single): byte;
begin
  result := clip(round(v * b), 0, 255);
end;


procedure RGB.gammaAdjust(v: single);
begin
	r := gammaCorrect(r, v);
  g := gammaCorrect(g, v);
	b := gammaCorrect(b, v);
end;

procedure RGB.linearAdjust(v: single);
begin
	r := linearCorrect(r, v);
  g := linearCorrect(g, v);
	b := linearCorrect(b, v);
end;

function RGB.to32(): uint32;
begin
  result := (r shl 16) + (g shl 8) + b;
end;

function RGB.to16(): uint16;
begin
	result := ((r shr 3) shl 11) + ((g shr 2) shl 5) + (b shr 3);
end;

function RGB.to12(): uint16;
begin
	result := (r shr 4 shl 12) + (g shr 4 shl 7) + (b shr 4 shl 1);
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
  result := clip(round(adjusted * 255.0), 0, 255);
end;


procedure RGB.toLinear();
begin
	r := clip(round(linear(r) * 255), 0, 255);
  g := clip(round(linear(g) * 255), 0, 255);
  b := clip(round(linear(b) * 255), 0, 255);
end;

procedure RGB.toSRGB();
begin
	r := SRGB(r/255.0);
  g := SRGB(g/255.0);
  b := SRGB(b/255.0);
end;

var
	SEED: byte;

function rnd(): byte; assembler;
asm
	RDTSC
  	
  mul ah
  // this is needed to remove patterns caused by exact timing
  // of certian operations.
  add al, SEED
  mov SEED, ah
  mov @result, al
  end;

{quantize an input value.
Input is 0..255
Output is 0..levels-1
}
function quantize(value, levels: byte): byte;
var
	z: uint16;
	quotient, remainder: uint16;
  roll: uint16;
begin
  z := value * (levels-1);
  quotient := z shr 8;
  remainder := z and $FF;
  roll := 0;
  if rnd < remainder then roll := 1;
  result := (quotient + roll)
end;

function RGB.to16_(): uint16;
begin
  result := quantize(r, 32) shl 11 + quantize(g, 64) shl 5 + quantize(b, 32);
end;

function RGB.to12_(): uint16;
begin
  result := quantize(r, 16) shl 12 + quantize(g, 16) shl 7 + quantize(b, 16) shl 1;
end;

procedure RGB.init(r,g,b: integer);
begin
	self.r := clip(r, 0, 255);
	self.g := clip(g, 0, 255);
	self.b := clip(b, 0, 255);
end;

procedure gradient_standard();
var
	x,y: uint16;
 	col: RGB;
  factor: single;
begin
  for x := 0 to SCREEN_WIDTH-1 do begin
  	factor := x / SCREEN_WIDTH;
    col.init(255,255,255);
    col.linearAdjust(factor);
		for y := SCREEN_HEIGHT-50 to SCREEN_HEIGHT-1 do begin
      putPixel(x, y, col.to32);
  	end;
    col.init(255,255,255);
    col.gammaAdjust(factor);
		for y := SCREEN_HEIGHT-100 to SCREEN_HEIGHT-50 do begin
      putPixel(x, y, col.to32);
  	end;
  end;	
end;

var i: integer;


procedure load_gfx();
var
	imageBytes: pByteArray;
begin
	getMem(imageBytes, 1024*1024*4);
  fillchar(imageBytes^, 1024*1024*4, 0);
	loadBMP('sea_hag.bmp', imageBytes^);
  move(imageBytes^, image, 1024*1024*4);
  freemem(imageBytes);
end;

function getPixel(x, y: integer): RGB;
begin
	result.init(0,0,0);
	if x < 0 then exit;
  if x >= 1024 then exit;
	if y < 0 then exit;
  if y >= 1024 then exit;
	result := image[1023-y, x];
end;

function getPixelScaled(x, y, s: integer;doGamma: boolean): RGB;
var
	i,j: int32;
  factor: single;
  r,g,b: int32;
  c: RGB;
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
	//factor := (255-abs(x - y)) / 255;
  result.init(r shr (s*2), g shr (s*2), b shr (s*2));
  if doGamma then result.toSRGB;
  // result.gammaAdjust(factor);

end;


procedure draw_image(doGamma: boolean);
var
	x, y: integer;
begin
	for y := 0 to SCREEN_HEIGHT-1 do begin
  	if y >= 512 then continue;
		for x := 0 to SCREEN_WIDTH-1 do begin
	  	if x >= 512 then continue;
  	    putpixel(x, y, getPixelScaled(x, y, 5, doGamma).to32);
    end;
  end;
end;

begin


	load_gfx();

	set_mode(800, 600, 32);

	draw_image(false);
  draw_image(true);

  for i := 0 to 1 do begin
	  gradient_standard();
  end;

	// Gradient in 16-bit

  // Gradient in 32-bit

  // Image in 16-bit

  // Image in 32-bit

  readkey;

	text_mode();

  writeln(lfb);
  	

end.
