{Unit for handling S3 Acceleration}
unit s3;

{$MODE objfpc}

interface

uses
  go32,
  debug,
  utils,
  crt,
  uColor,
  graph32,
  vga;

type
  tS3Driver = class

    fgColor: RGBA;
    bgColor: RGBA;

  public
    constructor create();

    procedure uploadScreen(pixels: pointer);
    procedure fillRect(x1,y1,width,height:int16);
  end;


procedure S3SetHardwareCursorLocation(x,y: int16);
procedure S3CopyRect(srcx,srcy,dstx,dsty,width,height:int16);
procedure S3Scissors(x1,y1,x2,y2:int16);
procedure S3SetLogicalWidth(width:word);
function  S3GetLogicalWidth(): word;
procedure S3SetFGColor(col: RGBA);
procedure S3SetBGColor(col: RGBA);
procedure S3SetCursorFGColor(col: RGBA);
procedure S3SetCursorBGColor(col: RGBA);

implementation

var
  HAS_MMIO: boolean = False;

const
  STATUS_0  = $03C2;
  STATUS_1  = $03DA;

  CRTC_ADR  = $03D4;
  CRTC_DATA = $03D5;


  ATR_ADR   = $03C0;
  ATR_DATA  = $03C1;

  CR = CRTC_ADR;


procedure WriteReg(Address: Word; Index, Value: byte);
var
  tmp: Byte;
begin
  if Address <> ATR_ADR then begin
    outportb(Address, Index);
    outportb(Address+1, Value);
  end else begin
    tmp := inportb(STATUS_1);
    outportb(ATR_ADR, (inportb(ATR_ADR) and $E0) or (Index and $1F));
    outportb(ATR_ADR, Value);
  end;
end;


function ReadReg(Address: Word; Index: byte): Byte;
var
  tmp: Byte;
begin
  if Address <> ATR_ADR then begin
    outportb(Address, Index);
    result := inportb(Address+1)
  end else begin
    tmp := inportb(STATUS_1);
    outportb(ATR_ADR, (inportb(ATR_ADR) and $E0) or (Index and $1F));
    result := inportb(ATR_ADR);
  end;
end;

function testVgaRegister(port, index, mask: integer): boolean;
var old, nw1, nw2: integer;
begin
  old := ReadReg(port, index);
  WriteReg(port, index ,old and mask);
  nw1 := ReadReg(port, index) and mask;
  WriteReg(port, index ,old or mask);
  nw2 := ReadReg(port, index) and mask;
  WriteReg(port, index ,old);

  result := (nw1 = 0) and (nw2 = mask);
end;

function S3Detect(): boolean;
var
  old: integer;
begin
  result := False;
  old := ReadReg(Cr, $38);
  WriteReg(CR, $38, 0);
  if (not TestVgaRegister(CR, $35, $F)) then begin
    WriteReg(CR, $38, $48);
    if (TestVgaRegister(CR, $35, $F)) then
      result := True;
  end;
end;

procedure S3UnlockRegs();
begin
  writeReg(CR, $38, $48);
  writeReg(CR, $39, $A0);
end;

procedure S3LockRegs();
begin
  writeReg(CR, $38, $00);
  writeReg(CR, $39, $00);
end;


procedure S3ForceEnhancedModeMappings();
begin
  S3UnlockRegs();
  WriteReg(CR, $31, ReadReg(CR, $31) or $09);
  S3LockRegs();
end;

procedure S3EnableLinearAddressing();
begin
  S3UnlockRegs();
  WriteReg(CR, $58, ReadReg(CR, $58) and $EC); // Disable LFB
  WriteReg(CR, $59, $03);
  WriteReg(CR, $5A, $00);
  //WriteReg(CR, $58, ReadReg(CR, $58) or %00001011);  // 4 MB
  WriteReg(CR, $58, ReadReg(CR, $58) or $11);  // 4 1B
  S3LockRegs();
end;


procedure S3EnableMMIO();
begin

  {
  Trio64 MMIO
  Set bits 4,3 to 10b
  Image writes made to A0000 to $A7FFF

  New MMIO (V+1)
  Set bits 4,3 to 01b

  But looks like we can do them both by setting 11b

  Also we want bit 5 to be 0
  }

  S3UnlockRegs();
  WriteReg(CR, $53, (ReadReg(CR, $53) and %11000111) or %00011000);
  S3LockRegs();
  HAS_MMIO := true;
end;

procedure S3DisableMMIO();
begin
  S3UnlockRegs();
  WriteReg(CR, $53, (ReadReg(CR, $53) and %11000111) or %00000000);
  S3LockRegs();
  HAS_MMIO := true;
end;

procedure S3SetClipping(x1,y1,x2,y2: int16);
begin
end;


CONST
{MMIO}
{
  FRGD_COLOR = 8124;
  FRGD_MIX = 8136;
  PIXEL_CNTL = 8140;
  ALT_CURXY = 8102;
  ALT_PCNT = 8148;
  CMD = 8118;
}
  BKGD_COLOR = $A2E8;
  FRGD_COLOR = $A6E8;
  FRGD_MIX = $BAE8;
  CUR_X = $86E8;
  CUR_Y = $82E8;

  DST_X = $8EE8;
  DST_Y = $8AE8;

  PIX_TRANS_A = $E2E8;
  PIX_TRANS_B = $E2EA;


  {BEE8}
  PIX_CNTL = $0A;
  MIN_AXIS_PCNT = $00; {height}
  SCISSORS_T = $01;
  SCISSORS_L = $02;
  SCISSORS_B = $03;
  SCISSORS_R = $04;


  MAJ_AXIS_PCNT = $96E8; {width}
  CMD = $9AE8;
  STATUS = $42E8;

procedure writew(addr:word;value:word); pascal;
begin
  asm
    mov dx, addr
    mov ax, value
    out dx, ax
  end;
end;

procedure writed(addr:word;value:dword); pascal;
begin
  asm
    mov dx, addr
    mov eax, value
    out dx, eax
  end;
end;

procedure writel(addr:word;value:dword); pascal;
begin
  asm
    {depends on flag, either we write twice, or we use eax...}
    mov dx, addr
    mov eax, value
    out dx, ax
    shr eax, 16
    out dx, ax
  end;
end;

procedure writew(addr:word;indx:word;value:word); pascal;
begin
  asm
    mov dx, addr
    mov ax, indx  {weird that we need to write a word here?}
    out dx, ax
    inc dx
    mov ax, value
    out dx, ax
  end;
end;

const
  MIX_CURRENT = %0000;
  MIX_ZERO = %0001;
  MIX_ONE  = %0010;
  MIX_NEW  = %0111;

  MIX_BG   = %00 shl 5;
  MIX_FG   = %01 shl 5;
  MIX_CPU  = %10 shl 5;
  MIX_DISPLAY = %11 shl 5;

  PCR_ONLY_FG = %00 shl 7;
  PCR_CPU_DATA = %10 shl 7;
  PCR_DISPLAY = %11 shl 7;

  CMD_ON           = $0001; {always on}
  CMD_MULTIPLANE   = $0002;
  CMD_LASTPOF     = $0004;
  CMD_RADIAL      = $0008;
  CMD_DRAW         = $0010;

  CMD_XNEG         = $0000;
  CMD_XPOS         = $0020;
  CMD_XMAJ         = $0000;
  CMD_YMAJ         = $0040;
  CMD_YNEG         = $0000;
  CMD_YPOS         = $0080;

  CMD_CPU          = $0100; {use CPU data}
  CMD_BUS_8        = $0000;
  CMD_BUS_16       = $0200;
  CMD_BUS_32       = $0400;
  CMD_BUS_X        = $0600; {used for accross the plane}

  CMD_SWAP         = $1000;

  CMD_NOP         = $0000;
  CMD_LINE        = $2000;
  CMD_FILL        = $4000;
  CMD_BLIT         = $C000;


{Wait for hardware to finish.}
procedure S3Wait(); inline;
CONST
  HW_BUSY = 1 SHL 9;
  ALL_FIFO_EMPTY = 1 SHL 10;
  TIMEOUT = 1*1000*1000;
var
  status: word;
  i: dword;

begin
  i := 0;
  repeat
    if i > TIMEOUT then
      halt(99);
    status := inportw(CMD);
    i += 1;
    {
      Bits 0-7 = FIFO status Trio32
      Bit 8 = Reserved
      Bit 9 = HW_BUSY
      Bit 10 = All FIFO empty
      Bits 11-15 = Additional FIFO status bits for Trio64}
    until
      ((status and ALL_FIFO_EMPTY) = ALL_FIFO_EMPTY) and
      ((status and HW_BUSY) = 0);
end;

procedure S3Scissors(x1,y1,x2,y2:int16);
begin
  S3Wait();
  writew($BEE8, SCISSORS_T SHL 12 + y1);
  writew($BEE8, SCISSORS_L SHL 12 + x1);
  writew($BEE8, SCISSORS_B SHL 12 + y2);
  writew($BEE8, SCISSORS_R SHL 12 + x2);
end;

{width in pixels, must be even and <= 2048}
procedure S3SetLogicalWidth(width:word);
var
  reg: byte;
begin
  {no support for widths this large}
  if (width) >= 4096 then exit;
  S3UnlockRegs();
  writeReg(CR, $13, (width shr 1) and $ff);
  reg := readReg(CR, $51) and %11001111;
  writeReg(CR, $51, reg or ((width shr 9) shl 4));
  S3LockRegs();
end;

function S3GetLogicalWidth(): word;
var
  regLow, regHigh: byte;
begin
  S3UnlockRegs();
  regLow := readReg(CR, $13);
  regHigh := (readReg(CR, $51) and %00110000) shr 4;
  S3LockRegs();
  result := ((regHigh shl 8) + regLow) * 2;
end;

procedure S3SetFGColor(col: RGBA);
begin
  S3UnlockRegs();
  s3wait();
  writed(FRGD_COLOR, col.to32);
  S3LockRegs();
end;

procedure S3SetBGColor(col: RGBA);
begin
  S3UnlockRegs();
  s3wait();
  writed(BKGD_COLOR, col.to32);
  S3LockRegs();
end;

procedure S3SetCursorFGColor(col: RGBA);
begin
  S3UnlockRegs();
  S3Wait();
  writeReg(CR, $4A, col.r);
  writeReg(CR, $4A, col.g);
  writeReg(CR, $4A, col.b);
  S3LockRegs();
end;

procedure S3SetCursorBGColor(col: RGBA);
begin
  S3UnlockRegs();
  S3Wait();
  writeReg(CR, $4B, col.r);
  writeReg(CR, $4B, col.g);
  writeReg(CR, $4B, col.b);
  S3LockRegs();
end;

procedure S3CopyRect(srcx,srcy,dstx,dsty,width,height:int16);
var
  x1,y1,x2,y2: int16;
  XPOS: boolean;
  YPOS: boolean;
  commandCode: word;

begin

  xPos := True;
  yPos := True;

  S3UnlockRegs();

  S3Wait;

  writew(FRGD_MIX, MIX_NEW + MIX_DISPLAY);

  {this part is taken from the manual (with some simplifications)}

  x1 := srcx;
  y1 := srcy;
  x2 := dstx;
  y2 := dsty;

  if srcx < dstx then begin
    XPOS := False;
    srcx := x1 + width - 1;
    dstx := x2 + width - 1;
  end;

  if srcy < dsty then begin
    YPOS := False;
    srcy := y1 + height - 1;
    dsty := y2 + height - 1;
  end;

  writew(CUR_X, srcx);
  writew(CUR_Y, srcy);
  writew(DST_X, dstx);
  writew(DST_Y, dsty);
  {note: width and height should both be -1, but some some reason this doesn't
   work... dosbox-x bug?}
  writew(MAJ_AXIS_PCNT, width-1);
  writew($BEE8, height - 1 + (MIN_AXIS_PCNT shl 12));

  writew($BEE8, $A000); {PIXEL_CNTL}

  S3Wait;

  commandCode := CMD_BLIT + CMD_DRAW + CMD_ON + CMD_XMAJ;

  if XPOS then commandCode += CMD_XPOS;
  if YPOS then commandCode += CMD_YPOS;

  writew(CMD, commandCode);

  S3LockRegs();

end;


{todo: look into doubleword CPU writes by setting bits 10-9 of the command register to 10b}
{copy from video memory to video memory}
(*
procedure S3Upload(); pascal;
begin

  S3UnlockRegs();

  S3Wait;

  {scissors}

  writew($BEE8, SCISSORS_T SHL 12 + 0);
  writew($BEE8, SCISSORS_L SHL 12 + 0);
  writew($BEE8, SCISSORS_B SHL 12 + 480);
  writew($BEE8, SCISSORS_R SHL 12 + 640);

  S3Wait;

  writew(FRGD_MIX, MIX_NEW + MIX_FG);
  writel(FRGD_COLOR, c);
  writew($BEE8, PCR_ONLY_FG + (PIX_CNTL shl 12));
  writew(CUR_X, x1);
  writew(CUR_Y, y1);
  writew($BEE8, height + (MIN_AXIS_PCNT shl 12));
  writew(MAJ_AXIS_PCNT, width);

  S3Wait;

  writew(CMD, %0100000010110001);

  S3LockRegs();

end; *)



var
  i: dword;
  startTime,endTime: double;
  callsPerSecond: double;
  cnt: integer;
  pixels: array[0..480-1, 0..640-1] of dword;


procedure UploadScreen_ASM();
var
  pixelsPtr: pointer;
  lfb_seg: word;
  pixelCnt: dword;
begin
  pixelsPtr := @pixels;
  lfb_seg := videoDriver.LFB_SEG;
  pixelCnt := videoDriver.physicalWidth * videoDriver.physicalHeight;
  asm
    push es
    push ds
    push esi
    push edi
    push ecx
    push eax

    mov es, [lfb_seg]
    mov edi, 0

    mov esi, PixelsPtr

    mov ecx, pixelCnt
    rep movsd

    pop eax
    pop ecx
    pop edi
    pop esi
    pop ds
    pop es

  end;
end;


procedure UploadScreen_MMX();
var
  pixelsPtr: pointer;
  lfb_seg: word;
begin
  pixelsPtr := @pixels;
  lfb_seg := videoDriver.LFB_SEG;
  asm
    push es
    push ds
    push esi
    push edi
    push ecx
    push eax

    mov ax, lfb_seg

    mov es, ax
    mov edi, 0

    mov esi, PixelsPtr

    mov ecx, 640*480
    shr ecx, 2

  @LOOP:

    movq mm0, ds:[esi]
    movq mm1, ds:[esi+8]
    movq es:[edi], mm0
    movq es:[edi+8], mm1
    add esi, 16
    add edi, 16

    dec ecx
    jnz @LOOP

    emms

    pop eax
    pop ecx
    pop edi
    pop esi
    pop ds
    pop es

  end;
end;

{uses ports and Image Transfer to upload... probably very slow...}
procedure UploadScreen_PORT();
var
  pixelsPtr: pointer;
begin

  pixelsPtr := @pixels;


  S3UnlockRegs();

  S3Wait;

  {scissors}

  writew($BEE8, SCISSORS_T SHL 12 + 0);
  writew($BEE8, SCISSORS_L SHL 12 + 0);
  writew($BEE8, SCISSORS_B SHL 12 + 480);
  writew($BEE8, SCISSORS_R SHL 12 + 640);

  S3Wait;

  writew(FRGD_MIX, MIX_NEW + MIX_CPU);
  writew($BEE8, $A000); {PIXEL_CNTL}

  writew(CUR_X, 0);
  writew(CUR_Y, 0);
  writew($BEE8, 480 + (MIN_AXIS_PCNT shl 12));
  writew(MAJ_AXIS_PCNT, 640);

  S3Wait;


  writew(
    CMD,
    CMD_FILL + CMD_BUS_32 + CMD_CPU + CMD_DRAW + CMD_ON +
    CMD_XPOS + CMD_YPOS
  );

  S3LockRegs();

  asm
    push es
    push ds
    push esi
    push edi
    push ecx
    push eax

    mov esi, PixelsPtr

    mov ecx, 640*480

  @LOOP:
    mov eax, ds:[esi]

    mov dx, PIX_TRANS_A
    out dx, ax
    shr eax, 16
    mov dx, PIX_TRANS_B
    out dx, ax

    add esi, 4

    dec ecx
    jnz @LOOP

    pop eax
    pop ecx
    pop edi
    pop esi
    pop ds
    pop es

  end;



end;

var
  MMIO_SEG: word;

{max is 32k bytes = 8k dwords}
procedure pushMMIO(p: pointer;cnt:dword); pascal;
begin
  asm
    push es
    push ds
    push esi
    push edi
    push ecx
    push eax

    {source}
    {ds is already set}
    mov esi, p

    {desintation}
    mov es, MMIO_SEG
    mov edi, 0

    mov ecx, cnt
    rep movsd

    pop eax
    pop ecx
    pop edi
    pop esi
    pop ds
    pop es

  end;

end;

procedure MapMMIO();
var
  VideoLinearAddress: DWord;
  rights: dword;
  base: dword;
begin
  MMIO_SEG := Allocate_LDT_Descriptors(1);
  {Map $A0000}
  VideoLinearAddress := get_linear_addr($A0000, 65536);
  set_segment_base_address(MMIO_SEG, VideoLinearAddress);
  set_segment_limit(MMIO_SEG, 65536-1);
end;

procedure S3SetHardwareCursorLocation(x,y: int16);
begin

  S3UnlockRegs();
  S3Wait;

  Port[$3D4] := $46;
  Port[$3D5] := (x shr 8) and $FF;
  Port[$3D4] := $47;
  Port[$3D5] := x and $FF;

  Port[$3D4] := $49;
  Port[$3D5] := y and $FF;
  {high order bits should be last, as this forces the update}
  Port[$3D4] := $48;
  Port[$3D5] := (y shr 8) and $FF;

  S3LockRegs();
end;


{-------------------------------------------------------------}

constructor tS3Driver.create();
begin
  info('[init] S3');
  {todo: implement s3 detection}
{  if not detectS3() then
    fatal('No S3 detected');}
  fgColor.init(255,255,255);
  bgColor.init(0,0,0);

  {enable MMIO}
  {todo: enable MMIO by default}
  {
  S3EnableMMIO();
  MapMMIO();
  }
end;

(*
  {scissors}
  writew($BEE8, SCISSORS_T SHL 12 + 0);
  writew($BEE8, SCISSORS_L SHL 12 + 0);
  writew($BEE8, SCISSORS_B SHL 12 + 480);
  writew($BEE8, SCISSORS_R SHL 12 + 640);
*)

{uses ports and Image Transfer to upload... using MMIO}
procedure tS3Driver.uploadScreen(pixels: pointer);
var
  counter: dword;
  i: dword;
const
  {number of pixels to transfer at a time, max is 8k}
  BLOCK_SIZE = 8*1024;
begin

  S3UnlockRegs();

  S3Wait;

  {scissors}

  writew($BEE8, SCISSORS_T SHL 12 + 0);
  writew($BEE8, SCISSORS_L SHL 12 + 0);
  writew($BEE8, SCISSORS_B SHL 12 + 480);
  writew($BEE8, SCISSORS_R SHL 12 + 640);

  S3Wait;

  writew(FRGD_MIX, MIX_NEW + MIX_CPU);
  writew($BEE8, $A000); {PIXEL_CNTL}

  writew(CUR_X, 0);
  writew(CUR_Y, 0);
  writew($BEE8, 480-1 + (MIN_AXIS_PCNT shl 12));
  writew(MAJ_AXIS_PCNT, 640-1);

  S3Wait;


  writew(
    CMD,
    CMD_FILL + CMD_BUS_32 + CMD_CPU + CMD_DRAW + CMD_ON +
    CMD_XPOS + CMD_YPOS
  );

  S3LockRegs();

  counter := 640*480;

  {640x480 = 37.5 8k blocks}

  while counter > 0 do begin
    if counter <= BLOCK_SIZE then begin
      pushMMIO(pixels, counter);
      counter := 0;
    end else begin
      pushMMIO(pixels, BLOCK_SIZE);
      counter -= BLOCK_SIZE;
      pixels += BLOCK_SIZE * 4;
    end;
  end;
end;



procedure tS3Driver.fillRect(x1,y1,width,height:int16);
begin

  if (width <= 0) or (height <= 0) then exit;

  S3UnlockRegs();
  S3Wait;
  writew(FRGD_MIX, MIX_NEW + MIX_FG);
  writed(FRGD_COLOR, fgColor.to32);
  writew($BEE8, $A000); {PIXEL_CNTL}
  writew(CUR_X, x1);
  writew(CUR_Y, y1);
  writew(MAJ_AXIS_PCNT, width-1);
  writew($BEE8, height - 1 + (MIN_AXIS_PCNT shl 12));
  S3Wait;
  (*
  writew(CMD,
    CMD_BLIT + CMD_DRAW + CMD_ON +
    CMD_XMAJ + {must be on}
    CMD_XPOS + CMD_YPOS
  {%0101010100110001}
  );
    *)
  writew(CMD,%0100000010110001);
  S3LockRegs();
end;


{-------------------------------------------------------------}

begin
end.
