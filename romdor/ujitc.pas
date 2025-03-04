{dynamic function construction}
unit uJITC;

interface

{
  todo:
    [ ] do not use constants for things like width,height, and destPtr
    [ ] create version that outputs nasm, and then build in FPC
    [ ] in the future do make a custom putPixel for each tPage,
        this would be cool.

}

uses
  utils,
  list;

type

  tBlendMode = (bmBlit, bmBlend);

  tDrawContext = record
    dstPointer: pointer;
    width, height: word;
    blend: tBlendMode;
    hasMMX: boolean;
  end;

  tJITC = class
    code: tStringList;
    wasRegModified: array[0..7] of boolean; {used for auto push/pop}
    procedure comment(s: string);
    procedure nasm(s: string;comment:string='');
    procedure UMUL_Constant(c: dword);
    procedure BLEND();
    procedure build();
    procedure compile_tPage_putPixel(dc: tDrawContext);

  end

implementation

constructor tJITC.create(s: string);
begin
  code := tStringList.create();
end;

{inline asm}
procedure tJITC.nasm(s: string;comment:string='');
begin
  if comment <> '' then
    code.append(pad(s,40)+'//'+s);
  else
    code.append(s);
end;

procedure tJITC.comment(s: string);
begin
  code.append('//'+s);
end;

{
 unsigned multiply by constant
 eax <- eax * c
 edx <- corupted
}
procedure tJITC.UMUL_Constant(c: dword);
begin
  if isPowerOfTwo(c) then begin
    nasm('shl eax, '+intToStr(round(log2(c))));
  end else begin
    nasm('mov edx, '+intToStr(c));
    nasm('mul edx');
  end;
end;

{
  Perform alpha blending (no MMX)

  inputs:
    edx: drawColor
    edi: pixelsPtr
  output:
    ebx: destroyed
    ecx: outColor
}
procedure BLEND();
  procedure doBlend();
  begin
    nasm('xor eax, eax');
    nasm('mov al,  bl');
    nasm('shl eax, 16');
    nasm('mov al,  cl');
    nasm('imul eax, ecx');
    nasm('shr eax, 8');
    nasm('mov dl, al');
    nasm('shr eax, 16');
    nasm('add dl, al');
  end;
begin
  comment('blending');
  comment(' - [setup]');
  nasm('push ebx');
  nasm('push esi');

  nasm('xor ecx, ecx');
  nasm('mov cl, 255');
  nasm('sub cl, dl');
  nasm('shr ecx, 16');
  nasm('mov cl, dl');
  nasm('mov esi, ecx');
  nasm('bswap edx');
  nasm('mov ecx, edx');

  {
    eax = tmp
    ebx = scr ARGB
    ecx = dst ARGB
    edx = output
    esi = 0|1-A|0|A|
  }

  {we perform two 8-bit multiplies with one 32bit multiply}
  comment(' - [blue]');
  doBlend();
  comment(' - [green]');
  nasm('shl edx, 8');
  nasm('ror ebx, 8');
  nasm('ror ecx, 8');
  doBlend();
  comment(' - [red]');
  nasm('shl edx, 8');
  nasm('ror ebx, 8');
  nasm('ror ecx, 8');
  doBlend();
  {todo: alpha}

  nasm('mov ecx, edx');
  nasm('bswap ecx');

  nasm('pop ebx');
  nasm('pop esi');
end;


procedure tJITC.build();
var
  line: string;
begin
  {write out the code}
  for line in code do
    writeln(line);
end;

procedure tJITC.compile_tPage_putPixel(dc: tDrawContext);
begin

  {

  todo:
    - auto push/pop
    - special cases for addressing
    - remove 'self' and have this compiled in, then no stack

  inputs:
    eax = x
    edx = y
    ecx = col

  modifies
    eax (not preserved)
    ecx (not preserved)
    edx (not preserved)
    edi preserved

  outputs:
    none
  }

  comment('bounds');
  nasm('cmp eax, '+intToStr(dc.width));
  nasm('jae @EndProc');
  nasm('cmp edx, '+intToStr(dc.height));
  nasm('jae @EndProc');

  comment('push');
  nasm('push edi');

  comment('addressing');
  nasm('mov edi, eax');
  nasm('mov eax, edx');
  UMUL_Constant(dc.width);
  nasm('add edi, eax');
  nasm('shl edi, 2');
  nasm('add edi, '+intToStr(dc.dstPointer));

  comment('blend');
  case blend of
    bmBlit: ;
    bmBlend: begin
      comment(' - alpha test');
      nasm('mov edx, ecx');
      nasm('bswap edx');
      nasm('cmp dl,  255');
      nasm('je @Direct');
      nasm('cmp dl,  0');
      nasm('je @Skip');
      BLEND_486();
    end;

  comment('write');
  nasm('@Direct:');
  nasm('mov [edi], ecx');
  nasm('@Skip:');

  nasm('pop edi');
  nasm('@EndProc:');

  end;
end;

begin
end.