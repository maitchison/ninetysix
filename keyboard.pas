{Non-blocking keyboard unit.}
unit keyboard;

{Example

program test

uses keyboard

begin
	Writeln('Press Q to continue.');
	repeat
  	until KeyPress[Key_q];
end;
}


{$CALLING REGISTER}
{$ASMMODE INTEL}
{$MODE FPC}

interface

uses
	debug,
  {todo: remove crt?}
	crt,
	dos,
  go32;

const
	Key_ESC	= 1;
	Key_1	= 2;
	Key_2	= 3;
	Key_3	= 4;
	Key_4	= 5;
	Key_5	= 6;
	Key_6	= 7;
	Key_7	= 8;
	Key_8	= 9;
	Key_9	= 10;
	Key_0	= 11;
	Key_Minus	= 12;
	Key_Equals= 13;
	Key_BackSpace	= 14;
	Key_Tab	= 15;
	Key_Q	= 16;
	Key_W	= 17;
	Key_E	= 18;
	Key_R	= 19;
	Key_T	= 20;
	Key_Y	= 21;
	Key_U	= 22;
	Key_I	= 23;
	Key_O	= 24;
	Key_P	= 25;
	Key_OpenSquareBracket	= 26;
	Key_CloseSquareBracket	= 27;
	Key_Enter = 28;
	Key_Control= 29;
	Key_A	= 30;
	Key_S	= 31;
	Key_D	= 32;
	Key_F	= 33;
	Key_G	= 34;
	Key_H	= 35;
	Key_J	= 36;
	Key_K	= 37;
	Key_L	= 38;
	Key_Colin	= 39;
	Key_Quote	= 40;
	Key_Squiggle	= 41;
	Key_LeftShift	= 42;
	Key_BackSlash	= 43;
	Key_Z	= 44;
	Key_X	= 45;
	Key_C	= 46;
	Key_V	= 47;
	Key_B	= 48;
	Key_N	= 49;
	Key_M	= 50;
	Key_Comma	= 51;
	Key_FullStop	= 52;
	Key_FowardSlash= 53;
	Key_RightShift	= 54;
	Key_Star	= 55;
	Key_Alt	= 56;
	Key_Space	= 57;
	Key_CapsLock	= 58;
	Key_F1	= 59;
	Key_F2	= 60;
	Key_F3	= 61;
	Key_F4	= 62;
	Key_F5	= 63;
	Key_F6	= 64;
	Key_F7	= 65;
	Key_F8	= 66;
	Key_F9	= 67;
	Key_F10	= 68;
	Key_NumLock	= 69;
	Key_ScrollLock = 70;
	Key_ControlBreak	= 70;
	Key_Home	= 71;
	Key_Up	= 72;
	Key_PageUp= 73;
	Key_OtherMinus	= 74;
	Key_Left	= 75;
	Key_Middle5	= 76;
	Key_Right	= 77;
	Key_Plus	= 78;
	Key_End	= 79;
	Key_Down	= 80;
	Key_PageDown	= 81;
	Key_Insert	= 82;
	Key_Delete	= 83;
	Key_F11	= 87;
	Key_F12	= 88;
	Key_pause	= 126;


procedure initKeyboard;
procedure closeKeyboard;
function keyDown(code: byte): boolean;
function readkey: char;
function keyPressed: boolean;


implementation

type
    TAllKeys = array[0..225] of bytebool;

var
	KeyPress: TAllkeys;
  oldint9h: tseginfo;
  newint9h: tseginfo;

{some bios keys}
const BIOS_CONTROL = #255;
	  BIOS_RIGHT_SHIFT = #255;
	  BIOS_ALT = #255;

const PORT2BIOS: array[1..126] of char = {converts what the port returns to
	bois scan codes}
	(
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
				'-','-','-','-','-','-','-','-','-');

var
	{	Required for cunning keyboard handler	}
	BIOSKeyboardHandler : procedure;
	Key_HasBeenPressed	: boolean;
	ch : byte;
	Key_yeppause	: boolean;
	Key_Pausecount	: integer;
	Key_oldkey	: byte;
	Key_olderkey	: byte;
  key_loop1   : integer;
	key_read	:	char;
	DosKey : boolean;
  EmergencyExit: boolean;

function keyDown(code: byte): boolean;
begin
	if dosKey then Error('Key query without keyboard init.');
  exit(keyPress[code]);
end;

{$F+}
procedure int9h_handler; assembler;
asm
    push eax
    push ebx
    push edi

    in  al, 60h
    cmp al, 127
    ja  @clearKey
    jmp @setKey

@setKey:
    mov edi, offset keyPress
    xor ebx, ebx
    mov bl, al
    mov al, 255
    mov byte [edi+ebx], al
    mov key_read, al
    jmp @done

@clearKey:
    sub al, 128
    mov edi, offset keyPress
    xor ebx, ebx
    mov bl, al
    mov al, 0
    mov byte [edi+ebx], al
    jmp @done

@done:

    mov al, 20h
    out 20h, al

@checkf12:
    mov edi, offset keyPress
    xor ebx, ebx
    mov bl, 58h
    mov al, [edi + ebx]
    cmp al, 0
    je @skipterminate


    {todo: soft close via flag, or ctrl-c}
    {todo: 'console' button (print a log or something maybe)}

@terminate:
    pop edi
    pop ebx
    pop eax

    // Emergancy Close
  	// A Heavy handed way to shutdown.
    int $1B

    iret

@skipterminate:

    // Best to call old handler I guess?
    {todo: check if I should be calling the old handler...}
    //jmp @callOld
@standardReturn:
    pop edi
    pop ebx
    pop eax
    iret

@callOld:
    pop edi
    pop ebx
    pop eax
    jmp cs:oldint9h
end;
{$F-}

procedure InitKeyboard;
begin
	Info('[init] Keyboard');
	if (dosKey = false) then exit; {already inited keyboard}
	dosKey := false;
	while keypressed do readkey;
	repeat
	until (mem[$40:$17] and 1 = 0) and (mem[$40:$17] and 2 = 0) and
		(mem[$40:$17] and 4 = 0) and (mem[$40:$17] and 8 = 0);
	Key_pausecount := 0;
	Key_yeppause	:= false;
	for key_loop1 := 1 to 225 do
		keyPress[key_loop1] := false;

  newint9h.offset := @int9h_handler;
  newint9h.segment := get_cs;
  get_pm_interrupt($9, oldint9h);
  set_pm_interrupt($9, newint9h);

end;

procedure CloseKeyboard();
begin
	if (dosKey = true) then exit; {already closed keyboard}
  Info('[close] Keyboard');
  dosKey := true;
  set_pm_interrupt($9, oldint9h);
end;


type TRegisters = record
	eax,ebx,ecx,edx: dword;
  esi,edi,ebp,esp: dword;
  es,ds,cs,ss: word;
  IP: dword;
  Flags: word;
end;

function readkey : char;
begin
	if doskey then
		{use standard readkey if keyboard unit not installed}
		exit(crt.readkey);
 	{my readkey (has a repeat rate (don't quite know why?)}
 	repeat
		until (not keyPressed);
 	repeat
  	until keyPressed;
 	readkey := PORT2BIOS[ord(key_read)];
end;

function key_pressed:boolean;
begin
	key_pressed := key_hasbeenpressed;
	key_hasbeenpressed := false;
end;

function keyPressed : boolean;
begin
	if dosKey then
    keyPressed := crt.keyPressed else
    keyPressed := key_pressed;
end;

begin

	key_hasbeenpressed := false;
	dosKey := true;

  keyPress[0] := False;	

  addExitProc(@CloseKeyboard);
end.
