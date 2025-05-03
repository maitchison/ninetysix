unit uColor;

interface

type

  RGBA = packed record

     b,g,r,a: byte;

    constructor create(r,g,b: integer;a: integer=255);

    class function Random(): RGBA; static;
    class function Lerp(a,b: RGBA; factor: single): RGBA; static;
    class function Blend(a,b: RGBA; alpha: byte): RGBA; inline; static;

    class operator add(a,b: RGBA): RGBA;
    class operator multiply(a: RGBA; b: single): RGBA; inline;
    class operator multiply(a,b: RGBA): RGBA; inline;
    class operator equal(a,b: RGBA): boolean;

    function toString: shortString;

    procedure init(r,g,b: int32;a: int32=255);
    procedure gammaAdjust(v: single);
    procedure linearAdjust(v: single);
    procedure lerp(other: RGBA; factor: single);
    procedure toLinear();
    procedure toSRGB();
    procedure from16(value: uint16);
    procedure from32(value: uint32);
    function to32(): uint32;
    function to16(): uint16;
    function to16_(): uint16;
    function to12(): uint16;
    function to12_(): uint16;
    function lumance(): byte;

    class function White(): RGBA; static;
    class function Black(): RGBA; static;
    class function Clear(): RGBA; static;

  end;

  pRGBA = ^RGBA;
  RGBAs = array[0..64*1024*1024-1] of RGBA;
  pRGBAs = ^RGBAs;


  {32 Bit Float}
  RGBA32 = packed record
     b,g,r,a: single;

    procedure init(r,g,b: single;a: single=1.0);

    class operator explicit(this: RGBA32): ShortString;

    function toGamma(): RGBA32;
    function toLinear(): RGBA32;

    function toString(): ShortString;
    procedure fromRGBA(c: RGBA);
    function toRGBA(): RGBA;

    class operator add(a,b: RGBA32): RGBA32;
    class operator multiply(a,b: RGBA32): RGBA32;
    class operator multiply(a: RGBA32; b: single): RGBA32;

  end;

  {16 bit signed integer}
  RGBA16 = packed record
    b,g,r,a: int16;
    class operator explicit(this: RGBA16): RGBA;
    class operator explicit(this: RGBA16): RGBA32;
  end;

function RGB(d: dword): RGBA; inline; overload;
function RGB(r,g,b: integer;a: integer=255): RGBA; inline; overload;
function RGBF(r,g,b: single;a: single=1.0): RGBA;
function toRGBA32(c: RGBA): RGBA32;
function toRGBA32L(c: RGBA): RGBA32;

implementation

uses
  uUtils;

{-------------------------------------------------------------}

function toRGBA32(c: RGBA): RGBA32;
begin
  result.fromRGBA(c);
end;

function toRGBA32L(c: RGBA): RGBA32;
begin
  result.fromRGBA(c);
  result := result.toLinear();
end;

function RGB(r,g,b: integer;a: integer=255): RGBA; inline;
begin
  result := RGBA.create(r,g,b,a);
end;

function RGBF(r,g,b: single;a: single=1.0): RGBA;
begin
  result := RGBA.create(round(r*255),round(g*255),round(b*255),round(a*255));
end;

function RGB(d: dword): RGBA; inline;
begin
  result.from32(d);
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

class function RGBA.White(): RGBA;
begin
  result := RGB(255,255,255);
end;

class function RGBA.Black(): RGBA;
begin
  result := RGB(0,0,0);
end;

class function RGBA.Clear(): RGBA;
begin
  result := RGB(0,0,0,0);
end;

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

class operator RGBA.multiply(a,b: RGBA): RGBA;
begin
  {
   we divide by 256 instead of 255, so add bias such that
   0*x=0
   255*255=255
  }
  result.r := (255+word(a.r)*b.r) shr 8;
  result.g := (255+word(a.g)*b.g) shr 8;
  result.b := (255+word(a.b)*b.b) shr 8;
  result.a := (255+word(a.a)*b.a) shr 8;
end;

function RGBA.toString: shortString;
begin
  if a = 255 then
    result := format('(%d,%d,%d)', [r,g,b])
  else
    result := format('(%d,%d,%d,%d)', [r,g,b,a]);

end;

procedure RGBA.lerp(other: RGBA; factor: single);
begin
  other.gammaAdjust(factor);
  self.gammaAdjust(1-factor);
  r += other.r;
  g += other.g;
  b += other.b;
end;

class function RGBA.Lerp(a,b: RGBA; factor: single): RGBA;
begin
  result.init(
    round(a.r * (1-factor)) + round(b.r * factor),
    round(a.g * (1-factor)) + round(b.g * factor),
    round(a.b * (1-factor)) + round(b.b * factor),
    round(a.a * (1-factor)) + round(b.a * factor)
  );
end;

{alpha 0->b, ahlpa 255->a}
class function RGBA.Blend(a,b: RGBA; alpha: byte): RGBA; inline;
var
  invAlpha: byte;
begin
  if alpha = 0 then exit(b);
  if alpha = 255 then exit(a);
  invAlpha := 255-alpha;
  result.r := (255 + word(a.r)*alpha + word(b.r)*invAlpha) shr 8;
  result.g := (255 + word(a.g)*alpha + word(b.g)*invAlpha) shr 8;
  result.b := (255 + word(a.b)*alpha + word(b.b)*invAlpha) shr 8;
  result.a := (255 + word(a.a)*alpha + word(b.a)*invAlpha) shr 8;
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

procedure RGBA.from16(value: uint16);
begin
  r := ((value shr 11) and $1f) shl 3;
  g := ((value shr 5) and $3f) shl 2;
  b := ((value shr 0) and $1f) shl 3;
  a := 255;
end;

procedure RGBA.from32(value: uint32);
begin
  move(value, self, 4);
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

function RGBA.lumance: byte; inline;
begin
  result := (int16(r)+int16(g)+int16(b)) div 3;
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

procedure RGBA32.init(r,g,b: single;a: single=1.0);
begin
  self.r := r;
  self.g := g;
  self.b := b;
  self.a := a;
end;

class operator RGBA32.explicit(this: RGBA32): ShortString;
begin
  result := Format('(%f,%f,%f)', [this.r, this.g, this.b]);
end;

function RGBA32.toLinear(): RGBA32;
begin
  result.r := power(self.r, 2.2);
  result.g := power(self.g, 2.2);
  result.b := power(self.b, 2.2);
  result.a := a;
end;

function RGBA32.toGamma(): RGBA32;
begin
  result.r := power(self.r, 1/2.2);
  result.g := power(self.g, 1/2.2);
  result.b := power(self.b, 1/2.2);
  result.a := a;
end;

procedure RGBA32.fromRGBA(c: RGBA);
begin
  init(c.r/255,c.g/255,c.b/255,c.a/255);
end;

function RGBA32.toRGBA(): RGBA;
begin
  result.init(round(r*255), round(g*255), round(b*255), round(a*255));
end;

function RGBA32.toString(): ShortString;
begin
  result := Format('%d,%d,%d', [self.r, self.g, self.b]);
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
  {pass through alpha for the moment}
  result.r := a.r*b;
  result.g := a.g*b;
  result.b := a.b*b;
  result.a := a.a;
end;

class operator RGBA32.multiply(a,b: RGBA32): RGBA32;
begin
  result.r := a.r*b.r;
  result.g := a.g*b.g;
  result.b := a.b*b.b;
  result.a := a.a*b.a;
end;

{----------------------------------------------}

function intToStr(x: integer): String;
var s: string;
begin
  str(x, s);
  result := s;
end;


begin
end.
