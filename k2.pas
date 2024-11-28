unit k2;

{$CALLING REGISTER}
{$ASMMODE ATT}
{$MODE FPC}

interface

uses crt,dos,go32;

var
    oldint9h: tseginfo;
    newint9h: tseginfo;


type
	allkeys	=	array[0..225] of boolean;

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
	KeyPress	: allkeys;
	key_loop1		: integer;
	key_read	:	char;
	DosKey : boolean;

procedure initkeyboard;
procedure closekeyboard;
procedure key_init;
procedure key_close;
procedure close_key;
procedure init_key;
function keyPressed : boolean;
function readkey : char;

implementation

procedure close_key;
 begin key_Close; end;

procedure init_key;
 begin key_init; end;

{$F+}
procedure KeyboardHandler(Flags, cs, ip, ax, bx, cx, dx, si, di, ds, es, bp: word);
interrupt;


begin
    exit;
	ch := 	port[$60];
	if ch > 127 then
		keyPress[ch-128] := false
	else begin
		keyPress[ch] := true;
		key_HasBeenPressed := true;
		key_read := chr(ch);
     end;


	if ch = 225 then
		begin;
			Key_yeppause := true;
		end;
	if Key_yeppause then
		begin;
			inc(Key_pausecount);
			if ch > 127 then
				keyPress[ch-128] := false
					else keyPress[ch] := true;
			if Key_pausecount > 5 then
				begin
					keyPress[key_pause] := not keyPress[key_pause];
                         key_pausecount	:= 0;
					key_yeppause := false;
				end;

		end;


	Port[$20] := $20;
	if keyPress[key_f12] then begin
		key_close;
		asm mov ax,3; int 10h; end;
		halt;
	end;
end;
{$F-}


procedure kbhandle; assembler;
asm
    cli
    push ds
    push ax
    mov ax, cs:[int9_ds]
    mov ds, ax

    mov ax, ticker
    inc ax
    mov ds:[ticker], ax
    {pass}

    pop ax
    pop ds
    sti
    iret
end;




var seginfo, old_seginfo: tseginfo;


procedure initkeyboard;
begin
	if (dosKey = false) then exit; {already inited keyboard}
	writeln('hooking interupt');
	dosKey := false;
	while keypressed do readkey;
	repeat
	until (mem[$40:$17] and 1 = 0) and (mem[$40:$17] and 2 = 0) and
		(mem[$40:$17] and 4 = 0) and (mem[$40:$17] and 8 = 0);
	Key_pausecount := 0;
	Key_yeppause	:= false;
	for key_loop1 := 1 to 225 do
		keyPress[key_loop1] := false;

    seginfo.offset := @kbhandle;
    seginfo.segment := get_cs;


    get_pm_interrupt(9, old_seginfo);
	set_pm_interrupt(9, seginfo);

    writeln('keyboard up');

end;

procedure closekeyboard;

begin;
	exitProc := oldexit;
	if (dosKey = true) then exit; {already closed keyboard}
    writeln('keyboard shutting down');
    dosKey := true;
	set_pm_interrupt(9, old_seginfo);

end;

procedure key_init;

begin
	initkeyboard;
end;

procedure key_close;

begin
	closekeyboard;
end;

function readkey : char;
 begin
 if doskey then begin
	{use standard readkey if keyboard unit not installed}
	readkey := crt.readkey
	end else
	begin
	{my readkey (has a repeat rate (don't quite know why?)}
	repeat
	  until (not keyPressed);
	repeat
	  until keyPressed;
	{which key was pressed?}
	readkey := PORT2BIOS[ord(key_read)];
	end;
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
oldexit := exitproc;
exitProc := @closeKeyBoard;

key_hasbeenpressed := false;
dosKey := true;
keyPress[0] := false;

writeln('Keyboard initilised...');
end.
