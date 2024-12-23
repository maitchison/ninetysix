unit Mouse;

{todo: come back and clean this one up}

{$MODE fpc}


interface

uses
  debug,
  crt,
  go32,
  utils,
  vga;

var
  {These only update when UpdateMouse is called}
  MouseX, MouseY: Word;
  MouseButtons: Word;

var
  { current mouse x and y coordinates, updated automatically. }
  mouse_x, mouse_y : Word;
  { button state }
  mouse_b : Word;

procedure overrideBaseAddress(newAddress: word);
procedure initMouse();
procedure closeMouse();

implementation

uses s3;

procedure installMouseProc(userproc : pointer; userproclen : longint); forward;
procedure removeMouseProc; forward;
procedure userproc; forward;

var
  { supplied register structure to the callback }
  mouse_regs    : trealregs; external name '___v2prt0_rmcb_regs';
  userProcLength: int32;


const
  {This is around 2 MEGs into the video ram, which is safe for <= 800x600x32}
  DEFAULT_BASE_ADDRESS = 1920;
  BASE_ADDRESS: word = DEFAULT_BASE_ADDRESS;

function DetectMouse(): boolean; assembler;
asm
  mov ax, 0
  mov bx, 0
  mov cx, 0
  mov dx, 0
  int $33
  {If al is still zero then mouse is not present.}
end;

procedure SetBoundary(x1, y1, x2, y2: integer);
begin
  asm
    mov ax, $07
    mov cx, x1
    mov dx, x2
    int $33
    mov ax, $8
    mov cx, y1
    mov dx, y2
    int $33
  end;
end;

{Set mouse location.}
procedure SetPosition(x, y: word);
begin
  asm
    mov ax, $04
    mov cx, x
    mov dx, y
    int $33
  end;
end;

procedure UpdateMousePosition();
begin
  asm
    pusha
    mov ax, $03

    int $33
    mov MouseX, cx
    mov MouseY, dx
    mov MouseButtons, bx;
    popa
  end;
end;

procedure enableHardwareCursor();
var
  startAddress: word;
const
  S3_ENABLE = 1;
begin
  {enable cursor}
  Port[$3D4] := $45;
  Port[$3D5] := S3_ENABLE;

  {set start address}
  startAddress := 0;
  Port[$3D4] := $4C;
  Port[$3D5] := (BASE_ADDRESS shr 8) and $FF;
  Port[$3D4] := $4D;
  Port[$3D5] := BASE_ADDRESS and $FF;

end;

procedure updateHardwareCursor(mouse_x, mouse_y: word);
var
  counter: dword;
begin
  s3.S3SetHardwareCursorLocation(mouse_x, mouse_y);
end;

procedure writeBit(x,y: integer; value: boolean; plane: byte);
var
  Address: dword;
  WordAddress: dword;
  BitWithinWord: integer;
  BitMask: byte;
  b: byte;
  lfb_seg: word;
begin
  {The images are word interleaved.
  i.e. AND word 0, XOR word 0, AND word 1, XOR word 1, ... }

  wordAddress := ((y * 64 + x) div 16) * 2 + plane;
  bitWithinWord := (x mod 16);

  address := (BASE_ADDRESS * 1024) + wordAddress * 2;
  if bitWithinWord >= 8 then
    address += 1;

  bitMask := $80 shr (bitWithinWord mod 8);    // e.g. 00100000b
  lfb_seg := videoDriver.LFB_SEG;

  asm
    pusha
    push es

    mov es, lfb_seg
    mov edi, 0
    add edi, address
    mov al, es:[edi]
    mov b, al

    pop es
    popa
  end;

  if value then
    b := b or bitmask
  else
    b := b and (not bitmask);

  asm
    pusha
    push es
    mov es, LFB_SEG
    mov edi, address
    mov al, b
    mov es:[edi], al

    pop es
    popa
  end;

end;

procedure WriteCursorBit(x,y: integer;value:byte);
begin
  WriteBit(x,y,(value and 1) = 1, 0);
  WriteBit(x,y,(value and 2) = 2, 1);
end;

procedure SetHardwareCursorSprite();
{todo: allow this to use custom graphics}
const
  MouseCursor: array[0..15] of string[16] =
  (
    '*...............',
    '**..............',
    '*#*.............',
    '*##*............',
    '*###*...........',
    '*####*..........',
    '*#####*.........',
    '*######*........',
    '*#######*.......',
    '*########*......',
    '*#########*.....',
    '*###********....',
    '*##*............',
    '*#*.............',
    '**..............',
    '*...............'
  );
var
  x,y: integer;
  c: char;
const
  CURSOR_BACKGROUND = 0;
  CURSOR_SCREEN = 1;
  CURSOR_FOREGROUND = 2;
  CURSOR_NOT_SCREEN = 3;
begin

  for x := 0 to 63 do
    for y := 0 to 63 do begin
      if (x > 15) or (y > 15) then
        WriteCursorBit(x, y, CURSOR_SCREEN)
      else begin
        c := MouseCursor[y][x+1];
        if c = '.' then
          WriteCursorBit(x, y, CURSOR_SCREEN);
        if c = '*' then
          WriteCursorBit(x, y, CURSOR_BACKGROUND);
        if c = '#' then
          WriteCursorBit(x, y, CURSOR_FOREGROUND);
        if c = '_' then
          WriteCursorBit(x, y, CURSOR_NOT_SCREEN);
      end;
    end;
end;

{set start address for mouse cursor (real address is newAddress*1024)}
procedure overrideBaseAddress(newAddress: word);
begin
  BASE_ADDRESS := newAddress;
end;

{Call after mode set}
procedure InitMouse();
begin
  Info('[init] Mouse');
  DetectMouse();
  EnableHardwareCursor();
  SetHardwareCursorSprite();
  installMouseProc(@userproc, userProcLength);
  SetBoundary(0, 0, videoDriver.physicalWidth-1, videoDriver.physicalHeight-1);
  SetPosition(videoDriver.physicalWidth div 2, videoDriver.physicalHeight div 2);
end;

procedure CloseMouse();
begin
  Info('[close] Mouse');
  removeMouseProc();
end;

{--------------------------------------------------}


{See freepascal.org/docs-html/3.02/trl/go32/get_rm_callback.html}

{$ASMMODE ATT}

var
        { real mode 48 bit pointer to the callback }
        mouse_seginfo : tseginfo;

const
        mouseint = $33;

var
        { number of mouse buttons }
        mouse_numbuttons : longint;

        { bit mask for the action which triggered the callback }
        mouse_action : word;

        { is an additional user procedure installed }
        userproc_installed : Longbool;
        { length of additional user procedure }
        userproc_length : Longint;
        { pointer to user proc }
        userproc_proc : pointer;

{ callback control handler, calls a user procedure if installed }
procedure callback_handler; assembler;
asm
   pushw %ds
   pushl %eax
   movw %es, %ax
   movw %ax, %ds

   { give control to user procedure if installed }
   cmpl $0, USERPROC_INSTALLED
   je .LNoCallback
   pushal
   movw DOSmemSELECTOR, %ax
   movw %ax, %fs  { set fs for FPC }
   call *USERPROC_PROC
   popal
.LNoCallback:

   popl %eax
   popw %ds

   pushl %eax
   movl (%esi), %eax
   movl %eax, %es: 42(%edi) { adjust stack }
   addw $4, %es:46(%edi)
   popl %eax
   iret
end;

{ This dummy is used to obtain the length of the callback control
function. It has to be right after the callback_handler() function.
}
procedure mouse_dummy; begin end;

procedure userproc;
begin
  { the mouse_regs record contains the real mode registers now }
  mouse_b := mouse_regs.bx;
  mouse_x := mouse_regs.cx;
  mouse_y := mouse_regs.dx;
  UpdateHardwareCursor(mouse_x, mouse_y);
end;

procedure mouse_dummy2; begin end;

{ Description : Installs the mouse callback control handler and
handles all necessary mouse related initialization.
  Input : userproc - pointer to a user procedure, nil if none
          userproclen - length of user procedure
}
procedure installMouseProc(userproc : pointer; userproclen : longint);
var r : trealregs;
begin
  { mouse driver reset }
  r.eax := $0; realintr(mouseint, r);
  if (r.eax <> $FFFF) then begin
    error(format('Microsoft compatible mouse not found code:%d',[r.eax]));
  end;
  { obtain number of mouse buttons }
  if (r.bx = $ffff) then mouse_numbuttons := 2
  else mouse_numbuttons := r.bx;
  note(format(' -detected %d button mouse',[mouse_numbuttons]));
  { check for additional user procedure, and install it if
  available }
  if (userproc <> nil) then begin
    userproc_proc := userproc;
    userproc_installed := true;
    userproc_length := userproclen;
    { lock code for user procedure }
    lock_code(userproc_proc, userproc_length);
  end else begin
  { clear variables }
    userproc_proc := nil;
    userproc_length := 0;
    userproc_installed := false;
  end;
  { lock code & data which is touched in the callback handler }
  lock_data(mouse_x, sizeof(mouse_x));
  lock_data(mouse_y, sizeof(mouse_y));
  lock_data(mouse_b, sizeof(mouse_b));
  lock_data(mouse_action, sizeof(mouse_action));

  lock_data(userproc_installed, sizeof(userproc_installed));
  lock_data(userproc_proc, sizeof(userproc_proc));

  lock_data(mouse_regs, sizeof(mouse_regs));
  lock_data(mouse_seginfo, sizeof(mouse_seginfo));
  lock_code(@callback_handler, dword(@mouse_dummy)-dword(@callback_handler));
  { allocate callback (supply registers structure) }
  get_rm_callback(@callback_handler, mouse_regs, mouse_seginfo);
  { install callback }
  r.eax := $0c; r.ecx := $7f;
  r.edx := longint(mouse_seginfo.offset);
  r.es := mouse_seginfo.segment;
  realintr(mouseint, r);
  { show mouse cursor }
  r.eax := $01;
  realintr(mouseint, r);
end;

procedure removeMouseProc();
var
  r : trealregs;
begin

  { hide mouse cursor }
  r.eax := $02; realintr(mouseint, r);
  { remove callback handler }
  r.eax := $0c; r.ecx := 0; r.edx := 0; r.es := 0;
  realintr(mouseint, r);
  { free callback }
  free_rm_callback(mouse_seginfo);
  { check if additional userproc is installed, and clean up if
  needed }
  if (userproc_installed) then begin
    unlock_code(userproc_proc, userproc_length);
    userproc_proc := nil;
    userproc_length := 0;
    userproc_installed := false;
  end;
  { unlock used code & data }
  unlock_data(mouse_x, sizeof(mouse_x));
  unlock_data(mouse_y, sizeof(mouse_y));
  unlock_data(mouse_b, sizeof(mouse_b));
  unlock_data(mouse_action, sizeof(mouse_action));

  unlock_data(userproc_proc, sizeof(userproc_proc));
  unlock_data(userproc_installed, sizeof(userproc_installed));

  unlock_data(mouse_regs, sizeof(mouse_regs));
  unlock_data(mouse_seginfo, sizeof(mouse_seginfo));
  unlock_code(@callback_handler,
          dword(@mouse_dummy)-dword(@callback_handler));
  fillchar(mouse_seginfo, sizeof(mouse_seginfo), 0);

end;

initialization

  userProc_Installed := False;
  userProcLength := dword(@mouse_dummy2)-dword(@userProc);

  Mouse_X := 0;
  Mouse_Y := 0;
  Mouse_B := 0;

  {todo: remove}
  MouseX := 0;
  MouseY := 0;
  MouseButtons := 0;

finalization
  closeMouse();

end.
