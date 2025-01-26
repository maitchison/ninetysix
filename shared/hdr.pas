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
    procedure addTo(page: tPage;atX, atY: int16);
    procedure mulTo(page: tPage;atX, atY: int16);
    procedure fade(factor: single=0.7);
    procedure clear(value: word);


    property width: integer read fWidth;
    property height: integer read fHeight;
  end;

const
  // lookup table will be 64k / (1 shl LUT_SHIFT)
  // 0 = full 64 lookup, 2 = 16k lookup, 4 = 4k lookup etc...
  LUT_SHIFT = 4;

var
  HDR_LUT: array[0..(65536 shr LUT_SHIFT)-1] of RGBA;

implementation


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
  result := HDR_LUT[data[x+y*fWidth] shr 2];
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
    dataPtr := pointer(data) + (y * 2*fWidth);
    pixelsPtr := page.pixels + (atX + ((atY+y) * page.width)) * 4;
    lutPtr := @HDR_LUT;
    asm
      pushad
      mov esi, dataPtr
      mov edi, pixelsPtr
      mov ecx, count
      mov ebp, lutPtr
      xor eax, eax
    @LOOP:
      movzx eax, word ptr [esi]
      shr eax, LUT_SHIFT
      mov eax, [ebp+eax*4]
      mov [edi], eax
      add esi, 2
      add edi, 4
      loop @LOOP
      popad
    end;
  end;
end;

procedure tHDRPage.addTo(page: tPage;atX, atY: int16);
var
  y: integer;
  count: int32;
  dataPtr, pixelsPtr, lutPtr: pointer;
begin
  for y := 0 to fHeight-1 do begin
    count := fWidth;
    dataPtr := pointer(data) + (y * 2*fWidth);
    pixelsPtr := page.pixels + (atX + ((atY+y) * page.width)) * 4;
    lutPtr := @HDR_LUT;
    {note: we could do this 2 pixels at a time if we wanted}
    asm
      cli
      pushad
      mov esi, dataPtr
      mov edi, pixelsPtr
      xor eax, eax
      mov ecx, count
      mov edx, lutPtr
      pxor mm5, mm5
    @LOOP:
      movzx eax, word ptr [esi]
      shr eax, LUT_SHIFT
      mov eax, [edx+eax*4]        // eax = color
      movd  mm0, eax              // mm0 = 0000-rgba (src)
      movd  mm1, dword ptr [edi]  // mm1 = 0000-rgba (dst)
      paddusb mm0, mm1

      movd  [edi], mm0
      add esi, 2
      add edi, 4
      loop @LOOP
      popad
      emms
      sti
    end;
  end;
end;

{multiples destination by (1-(8*value/65536))}
procedure tHDRPage.mulTo(page: tPage;atX, atY: int16);
var
  y: integer;
  count: int32;
  dataPtr, pixelsPtr, lutPtr: pointer;
begin
  for y := 0 to fHeight-1 do begin
    count := fWidth;
    dataPtr := pointer(data) + (y * 2*fWidth);
    pixelsPtr := page.pixels + (atX + ((atY+y) * page.width)) * 4;
    lutPtr := @HDR_LUT;
    {note: we could do this 2 pixels at a time if we wanted}
    {note2: we could integrate add and mul together fairly easily...}
    asm
      cli
      pushad
      mov esi, dataPtr
      mov edi, pixelsPtr
      xor eax, eax
      mov ecx, count
      mov edx, lutPtr

      pxor mm5, mm5

    @LOOP:
      movzx     eax, word ptr [esi]
      shr       eax, LUT_SHIFT
      mov       eax, [edx+eax*4]        // eax = color
      bswap     eax
      not       al
      shl       ax, 8
      shr       ax, 1                   // ax = alpha * 128

      movd      mm0, eax
      punpcklwd mm0, mm0
      punpckldq mm0, mm0                // mm0 = value (0..32k)

      movd      mm1, dword ptr [edi]    // mm1 = 0000-rgba (dst)
      punpcklbw mm1, mm5                // mm1 = 0r0g-0b0a (dst)
      psllw     mm1, 1                  // mm1 = 0r0g-0b0a (dst) (*2)
      // note: to avoid signs we divide value by 2 and multiply dst by 2
      pmulhw    mm1, mm0                // mm1 = 0r0g-0b0a (dst * value)

      packuswb  mm1, mm1                // mm1 = rgba-rgba

      movd  [edi], mm1
      add esi, 2
      add edi, 4
      loop @LOOP
      popad
      emms
      sti
    end;
  end;
end;


{reduce intensity of page}
procedure tHDRPage.fade(factor: single=0.7);
var
  count: int32;
  dataPtr: pointer;
  value: word;
  y: integer;
begin
  value := round(clamp(factor, 0, 1)*32767);
  for y := 0 to fHeight-1 do begin
    count := fWidth;
    dataPtr := pointer(data) + (y * fWidth * 2);
    asm
      cli
      pushad
      mov   edi, dataPtr
      mov   ecx, count
      shr   ecx, 2          // we do 4 values at a time

      mov   ax,  value
      shl   eax, 16
      mov   ax,  value
      pxor  mm1, mm1
      movd  mm1, eax
      punpckldq mm1, mm1

    @LOOP:
      movq   mm0, [edi]     // mm0 = HDR value

      // we only have a signed multiply... so divide both operands by
      // two so that we're never negative. We loose some precision doing
      // this, but I think it's ok.
      // note: alternatively we could try and correct the signed multiply
      // but it's a pain and requires conditionals. (if a < 0 then result +=a etc)
      psrlw  mm0, 1
      pmulhw mm0, mm1
      // multipler was already /2 so we need to *4 to adjust for everything.
      psllw  mm0, 2

      movq   [edi], mm0
      add    edi, 8
      loop @LOOP

      popad
      emms
      sti
    end;
  end;
end;

var
  i: integer;
  v: single;

begin
  for i := 0 to (65536 shr LUT_SHIFT)-1 do begin
    v := (i/(65536 shr LUT_SHIFT));
    HDR_LUT[i].init(
      round(power(v, 1.0)*255),
      round((v*100)+power(v, 0.5)*255),
      round(power(v, 0.7)*255),
      round(power(v, 0.5)*255)
    )
  end;
end.
