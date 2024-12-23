{Replacement for CPU (no sysutils)}
unit cpu;

interface

function getCPUIDSupport: boolean;
function getMMXSupport: boolean;
function getCPUName(): string;

implementation

uses utils;

function getCPUIDSupport: boolean; assembler;
  {copied from from cpu.pp}
  asm
    push  ebx
    pushfd
    pushfd
    pop   eax
    mov   ebx, eax
    xor   eax, $200000
    push  eax
    popfd
    pushfd
    pop   eax
    popfd
    and   eax, $200000
    and   ebx, $200000
    cmp   eax, ebx
    setnz al
    pop   ebx
  end;

function getMMXSupport: boolean; assembler;
  asm
    push  ebx
    push  ecx
    push  edx

    call  getCPUIDSupport
    jz    @NoCPUID

    mov   eax, 1
    cpuid
    test  edx, (1 shl 23)
    jz    @NoMMX

  @HasMMX:
    mov   al, 1
    jmp   @Done

  @NoMMX:
  @NoCPUID:
    mov   al, 0

  @Done:
    pop   edx
    pop   ecx
    pop   ebx
  end;

function getCPUName(): string;
var
  reax: dword;
  cpuName: string;
  family, model, stepping: word;
begin
  if not getCPUIDSUpport then exit('');

  asm
    pushad
    mov eax, 1
    cpuid
    mov [reax], eax
    popad
    end;

  family := (reax shr 8) and $f;
  model := (reax shr 4) and $f;
  stepping :=(reax shr 0) and $f;

  case family of
    3: cpuName := '386';
    4: case model of
      0,1,4: cpuName := '486DX';
      2: cpuName := '486SX';
      3: cpuName := '486DX2';
      5: cpuName := '486SX2';
      7: cpuName := '486DX4';
      else cpuName := '486';
    end;
    5: case model of
      3: cpuName := 'Pentium Overdrive';
      4: cpuName := 'Pentium MMX';
      else cpuName := 'Pentium';
    end;
    6: case model of
      1: cpuName := 'Pentium Pro';
      3: cpuName := 'Pentium II';
      6: cpuName := 'Pentium III';
      else cpuName := 'Pentium Pro/II/III';
    end;
    else cpuName := 'Unknown ('+intToStr(family)+')';
  end;
  result := cpuName;
end;


begin
end.
