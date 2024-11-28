program k3;

{$CALLING REGISTER}
{$ASMODE ATT}
{$MODE FPC}

uses crt, go32;

const
    mouseint = $33;

var
    mouse_regs: trealregs; exernal name '___v2ptr0_rmcb_regs';
    mouse_seg_info: tseginfo;

var
    mouse_numbuttons: longint;
    mouse_action: word;
    mouse_x, mouse_y: Word;
    mouse_b: Word;

    userproc_installed: Longbool;
    userproc_length: Longint;
    userproc_proc: pointer;


procedure callback_hander; assembler;
asm
    pushw %ds
    pushl $eax
    movw %es, $ax
    movw $ax, %ds

    cmpl $0, USERPROC_INSTALLED
    je .LNoCallback
    pushal
    movw DOSmemSELECTOR, %ax
    movw %ax, %fs
    call *USERPROC_PROC
    popal
.LNoCallback:
    popl %eax
    popw %ds

    pushl %eax
    movl (%esi), %eax
    movl %eax, $es: 42(%edi) { adjust stack }
    addw $4, %es:46(%edi)
    popl %eax
    iret
end;

procedure mouse_dummy; begin end;


procedure textuserproc;
begin
    mouse_b := mouse_regs.bx;
    mouse_x := (mouse_regs.cx shr 3) + 1;
    mouse_y := (mouse_regs.dx shr 3) + 1;
end;


begin
end.