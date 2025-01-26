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
    fWidth, fHeight: integer;
  public
    constructor create(aWidth, aHeight: integer);
    destructor destroy(); override;
    function  getRGB(x, y: int16): RGBA;
    procedure setValue(x, y: int16;value: word);
    procedure addValue(x, y: int16;value: integer);
    procedure blitTo(page: tPage;atX, atY: int16);
    procedure addTo(page: tPage;atX, atY: int16; shift: byte=0);
    procedure fade(factor: single=0.7);
    procedure clear(value: word);


    property width: integer read fWidth;
    property height: integer read fHeight;
  end;

implementation

var
  LUT: array[0..4096-1] of RGBA;

constructor tHDRPage.create(aWidth, aHeight: integer);
begin
  inherited create();
  fWidth := aWidth;
  fHeight := aHeight;
  data := getMem(fWidth*fHeight*2);
  clear(0);
end;

destructor tHDRPage.destroy();
begin
  freemem(data);
  inherited destroy();
end;

procedure tHDRPage.clear(value: word);
begin
  fillword(data^, fWidth*fHeight, value);
end;

procedure tHDRPage.setValue(x, y: int16;value: word);
begin
  if (word(x) >= fWidth) or (word(y) >= fHeight) then exit;
  data[x+y*fWidth] := value;
end;

function tHDRPage.getRGB(x, y: int16): RGBA;
var
  value: word;
begin
  if (word(x) >= fWidth) or (word(y) >= fHeight) then exit;
  result := LUT[data[x+y*fWidth] shr 4];
end;

procedure tHDRPage.addValue(x, y: int16;value: integer);
var
  ofs: integer;
begin
  if (word(x) >= fWidth) or (word(y) >= fHeight) then exit;
  ofs := x+y*fWidth;
  data[ofs] := clamp(data[ofs]+value, 0, 65535);
end;

procedure tHDRPage.blitTo(page: tPage;atX, atY: int16);
var
  y: integer;
  count: int32;
  dataPtr, pixelsPtr, lutPtr: pointer;
begin
  for y := 0 to fHeight-1 do begin
    count := fWidth;
    dataPtr := data + (y * fWidth);
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

procedure tHDRPage.addTo(page: tPage;atX, atY: int16; shift: byte=0);
var
  y: integer;
  count: int32;
  dataPtr, pixelsPtr, lutPtr: pointer;
begin
  shift := 1;
  for y := 0 to fHeight-1 do begin
    count := fWidth;
    dataPtr := data + (y * fWidth);
    pixelsPtr := page.pixels + (atX + ((atY+y) * page.width)) * 4;
    lutPtr := @LUT;
    {note: we could do this 2 pixels at a time if we wanted}
    asm
      pushad
      mov esi, dataPtr
      mov edi, pixelsPtr
      xor eax, eax
      mov ecx, count
      mov edx, lutPtr
      pxor mm5, mm5
    @LOOP:
      movzx eax, word ptr [esi]
      shr eax, 4
      mov eax, [edx+eax*4]        // eax = color
      movd  mm0, eax              // mm0 = 0000-rgba (src)
      movd  mm1, dword ptr [edi]  // mm1 = 0000-rgba (dst)
      paddusb mm0, mm1

      movd  [edi], mm0
      add esi, 2
      add edi, 4
      loop @LOOP
      popad
    end;
  end;

  asm
    emms;
  end;
end;

{reduce intensity of page}
procedure tHDRPage.fade(factor: single=0.7);
var
  ofs: integer;
  count: int32;
  dataPtr: pointer;
  value: word;
begin
  count := (fWidth*fHeight) div 4;
  dataPtr := data;
  value := round(clamp(factor, 0, 1)*32767);
  {mmx would help somewhat here. Also we could do a substract if we wanted}
  asm
    pushad
    mov   edi, dataPtr
    mov   ecx, count

    mov   ax,  value
    shl   eax, 16
    mov   ax,  value
    pxor  mm1, mm1
    movd  mm1, eax
    punpckldq mm1, mm1

  @LOOP:
    movq   mm0, [edi]     // mm0 = HDR value
    pmulhw mm0, mm1
    psllw  mm0, 1   // we loose 1 bit of precision doing this, but that's ok.

    movq   [edi], mm0
    add    edi, 8
    loop @LOOP
    popad
    emms
  end;
  (*
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
  *)
end;

var
  i: integer;
  v: single;

begin
  for i := 0 to 4096-1 do begin
    v := (i/4096);
    LUT[i].init(
      round(power(v, 0.5)*256),
      round(power(5*v, 0.7)*256),
      round(power(v, 0.6)*256),
      255);

  end;
end.
