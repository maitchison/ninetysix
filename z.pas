program z;

{$CALLING REGISTER}
{$ASMMODE ATT}
{$MODE FPC}


uses go32, crt;

var
    r: trealregs;
    i: integer;
    axreg: Word;
    key: byte;
    counter: Word;
    oldint21h: tseginfo;
    newint21h: tseginfo;

{some bios keys}
const BIOS_CONTROL = #255;
	  BIOS_RIGHT_SHIFT = #255;
	  BIOS_ALT = #255;


const PORT2BIOS: array[0..127] of char = {converts what the port returns to
	bois scan codes}
	(
    #0,
	{1: Key_ESC} #27,
	{2: Key_1} '1','2','3','4','5','6','7','8','9','0',
	{12: Key_Minus} '-','=',
	{14: Key_BackSpace} #8,
	{15: Key_Tab} #7,
	{16: Key_Q} 'q','w','e','r','t','y','u','i','o','p','[',']',#13,BIOS_CONTROL,
				'a','s','d','f','g','h','j','k','l',';','''','~','/','\',
				'z','x','c','v','b','n','m',',','.','/',BIOS_RIGHT_SHIFT,
				'*',BIOS_ALT,' ',
				'-','-','-','-','-','-','-','-','-','-',
				'-','-','-','-','-','-','-','-','-','-',
				'-','-','-','-','-','-','-','-','-','-',
				'-','-','-','-','-','-','-','-','-','-',
				'-','-','-','-','-','-','-','-','-','-',
				'-','-','-','-','-','-','-','-','-','-',
				'-','-','-','-','-','-','-','-','-','-');

(*
procedure int21h_handler(Flags, cs, ip, ax, bx, cx, dx, si, di, ds, es, bp: word);
interrupt;

begin
    counter := counter + 1;
    {pass}
end; *)

procedure int21h_handler; assembler;
asm

    inc counter

    inb $0x60, %al
    andb $0x7F, %al
    movb %al, key

    movb $0x20, %al
    outb %al, $0x20


    {jmp .LCallOld}

    iret
.LCallOld:
    ljmp %cs:oldint21h
end;

procedure resume;
begin
    writeln('press a key');
    readkey;
end;

begin

    clrscr;

    { first }
    {
    r.ah := $30;
    r.al := $01;
    realintr($21, r);
    Writeln('Dos v', r.al, '.', r.ah, ' detected');
    }

    { our own }
    {

    asm
        movb $0x30, %ah
        movb $0x01, %al
        int $0x21
        movw %ax, axreg
    end;

    Writeln('Dos v', lo(axreg), '.', hi(axreg), ' detected');
    }

    { overwrite }

    newint21h.offset := @int21h_handler;
    newint21h.segment := get_cs;
    get_pm_interrupt($9, oldint21h);
    set_pm_interrupt($9, newint21h);

    for i := 0 to 200 do begin;
        writeln(PORT2BIOS[key]);
        delay(50);
    end;



    { second }
    {

    r.ah := $30;
    r.al := $01;
    realintr($21, r);
    Writeln('Dos v', r.al, '.', r.ah, ' detected');


    asm
        movb $0x30, %ah
        movb $0x01, %al
        int $0x21
        movw %ax, axreg
    end;

    Writeln('Dos v', lo(axreg), '.', hi(axreg), ' detected');
    }

    { reset }

    set_pm_interrupt($9, oldint21h);

    writeln(counter);


    { cleanup }

    { read keys}



end.
