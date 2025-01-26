{stores HDR 16-bit mono-chromatic buffers}
unit hdr;

{
HDR buffer maps from 16bit integers (0..65535) to RGB values, where
typically the brigness is proportional to sqrt(value). I.e. closer to
linear space than to gamma space.
}

interface

uses
  graph32,
  utils;

type
  tHDRPage = class
  private
    data: pWord;
    width,height: integer;
  public
    constructor create(aWidth, aHeight: integer);
    destructor destroy(); override;
    function  getRGB(x, y: int16): RGBA;
    procedure setValue(x, y: int16;value: word);
    procedure addValue(x, y: int16;value: integer);
    procedure blitTo(page: tPage;atX, atY: int16);
    procedure fade();
  end;

implementation

var
  LUT: array[0..4096-1] of RGBA;

constructor tHDRPage.create(aWidth, aHeight: integer);
begin
  inherited create();
  self.width := aWidth;
  self.height := aHeight;
  data := getMem(width*height*2);
end;

destructor tHDRPage.destroy();
begin
  freemem(data);
  inherited destroy();
end;

procedure tHDRPage.setValue(x, y: int16;value: word);
begin
  if (word(x) >= width) or (word(y) >= height) then exit;
  data[x+y*width] := value;
end;

function tHDRPage.getRGB(x, y: int16): RGBA;
var
  value: word;
begin
  if (word(x) >= width) or (word(y) >= height) then exit;
  result := LUT[data[x+y*width] shr 4];
end;

procedure tHDRPage.addValue(x, y: int16;value: integer);
var
  ofs: integer;
begin
  if (word(x) >= width) or (word(y) >= height) then exit;
  ofs := x+y*width;
  data[ofs] := clamp(data[ofs]+value, 0, 65535);
end;

procedure tHDRPage.blitTo(page: tPage;atX, atY: int16);
var
  y: integer;
  count: int32;
  dataPtr, pixelsPtr, lutPtr: pointer;
begin
  for y := 0 to height-1 do begin
    count := width;
    dataPtr := data + (y * width);
    pixelsPtr := page.pixels + (atX + ((atY+y) * page.width)) * 4;
    lutPtr := @LUT;
    asm
      pushad
      mov esi, dataPtr
      mov edi, pixelsPtr
      mov ecx, count
      mov ebp, lutPtr
      xor eax, eax
    @LOOP:
      movzx eax, word ptr [esi]
      shr eax, 4
      mov eax, [ebp+eax*4]
      mov [edi], eax
      add esi, 2
      add edi, 4
      loop @LOOP
      popad
    end;
  end;
end;

{reduce intensity of page}
procedure tHDRPage.fade();
var
  ofs: integer;
  count: int32;
  dataPtr: pointer;
begin
  count := width*height;
  dataPtr := data;
  {mmx would help somewhat here. Also we could do a substract if we wanted}
  asm
    pushad
    mov edi, dataPtr
    mov ecx, count
  @LOOP:
    mov ax, [edi]
    shr ax, 1
    mov [edi], ax
    add edi, 2
    loop @LOOP
    popad
  end;
end;

var
  i: integer;
  v: single;

begin
  for i := 0 to 4096-1 do begin
    v := sqrt(i/4096);
    LUT[i].init(round(256*v), 50+round(512*v), round(384*v), round(512*v));
  end;
end.
