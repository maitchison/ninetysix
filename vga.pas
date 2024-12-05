{vga video driver}
unit vga;

{$MODE delphi}

interface

uses
	debug,
  utils,
	go32,
  crt;

type
	tVideoDriver = class
  	
  protected
  	{the resolution of the screen}
    fPhysicalWidth,fPhysicalHeight:word;
    {logical dimensions, which may be larger when uing fullscreen scrolling}
    fLogicalWidth,fLogicalHeight:word;
    fBPP: word;
    fLFB_SEG: word;

    function getPhysicalWidth: word;
    function getPhysicalHeight: word;
    function getLogicalWidth: word;
    function getLogicalHeight: word;
    function getBPP: word;
    function getLFB_SEG: word;

  public
  	constructor create();

    {shortcut for logical dims}
		property width:word read getLogicalWidth;
    property height:word read getLogicalHeight;

		property logicalWidth:word read getLogicalWidth;
    property logicalHeight:word read getLogicalHeight;
		property physicalWidth:word read getPhysicalWidth;
    property physicalHeight:word read getPhysicalHeight;

		property BPP:word read getBPP;
		property LFB_SEG:word read getLFB_SEG;

  	procedure setMode(width, height, BPP: word); virtual; abstract;
  end;

	tVGADriver = class(tVideoDriver)
  	{basic VGA driver}
  	procedure setMode(width, height, BPP: word); override;
    procedure setText();
  end;

var
	screen: tVGADriver;

implementation

{todo: move to vga driver}
procedure SetDisplayStart(x, y: word); forward;
procedure SetDisplayPage(page: integer); forward;
procedure fSetMode(width, height, bpp: integer); forward;
procedure SetLogicalScreenSize(width, height: word); forward;
procedure fSetText(); forward;


CONST
	USE_80x50: boolean = True;


var
  myLFB_SEG: word;

  SCREEN_WIDTH: word;
  SCREEN_HEIGHT: word;
  SCREEN_BPP: word;

  {Used when logical screen is larger than physical screen.}
  PHYSICAL_WIDTH, PHYSICAL_HEIGHT: word;

{--------------------------------------------------------------}
{ tVideoDriver }
{--------------------------------------------------------------}

constructor tVideoDriver.create();
begin
	fPhysicalWidth := 0;
  fPhysicalHeight := 0;
	fLogicalWidth := 0;
  fLogicalHeight := 0;
  fBPP := 0;
  fLFB_SEG := 0;
end;

function tVideoDriver.getPhysicalWidth: word;
begin
	result := fPhysicalWidth;
end;

function tVideoDriver.getPhysicalHeight: word;
begin	
	result := fPhysicalHeight;
end;

function tVideoDriver.getLogicalWidth: word;
begin
	result := fLogicalWidth;
end;

function tVideoDriver.getLogicalHeight: word;
begin	
	result := fLogicalHeight;
end;

function tVideoDriver.getBPP: word;
begin
	result := fBPP;
end;

function tVideoDriver.getLFB_SEG: word;
begin
	result := fLFB_SEG;
end;

{--------------------------------------------------------------}
{ tVGADriver }
{--------------------------------------------------------------}

procedure tVGADriver.setMode(width, height, bpp: word);
begin
	{todo: switch to vga driver}
	fSetMode(width, height, bpp);
  self.fPhysicalWidth := width;
  self.fPhysicalHeight := height;
  self.fLogicalWidth := width;
  self.fLogicalHeight := height;
  self.fBpp := bpp;
  self.fLFB_SEG := myLFB_SEG;
  info(format('Setting mode to %dx%dx%d with LFB at %s', [width, height, bpp, fLFB_SEG, hexStr(pointer(self.LFB_SEG))]));

end;

procedure tVGADriver.setText();
begin
	fSetText();
end;

{--------------------------------------------------------------}

{todo: visa driver and S3 driver}

type TVesaModeInfo = packed record
  {Vesa 1.0}
  ModeAttributes: word;
  WinAAttributes: byte;
  WinBAttributes: byte;
  WinGranularity: word;
  WinSize: word;
  WinASegemnt: word;
  WinBSegment: word;
  WinFuncPtr: pointer;
  BytesPerScanLine: word;
  {Vesa 1.2}
  XResolution: word;
  YResolution: word;
  XCharSize: byte;
  YCharSize: byte;
  NumberOfPlanes: byte;
  BitsPerPixel: byte;
  NumberOfBanks: byte;
  MemoryModel: byte;
  BankSize: byte;
  NumberOfImagePanes: byte;
  Reserved1: byte;
  // direct color data}
	colorData: array[1..9] of byte;
  {Vesa 2.0}
  PhysBasePtr: Pointer;
  OffScreenMemOffset: dword;
  OffScreenMemSize: word;
  not_used: array[1..205] of byte;
end;

type TVesaInfo = packed record
  {----------- VBE 1.0 -----------------}
	Signature: array[1..4] of Char;
  Version: Word;
  OemStringPtr: dWord;
  Capabilities: dWord;
  VideoModePtr: dWord;
  TotalMemory: Word;
  {----------- VBE 2.0 -----------------}
  OemSoftwareRev: word;
  OemVendorNamePtr: dWord;
  OemProducNamePtr: dWord;
  OemProductRevPtr: dWord;
end;

var
  VesaInfo: TVesaInfo;
  Regs: tRealRegs;
  dosSel, dosSeg: word;

{Alllocates dos memory
seg:ofs, where ofs is always 0.
selector can be used to free the memory.
}
procedure dosAlloc(var selector: word; var segment: word; size: longint);
var
	ptr: longint;
begin
	ptr := global_dos_alloc(size);
  selector := word(ptr);
  segment := word(ptr shr 16);
end;

procedure dosFree(selector: word);
begin
	global_dos_free(selector);
end;


function getModeInfo(mode: word): TVesaModeInfo;
var
	regs: tRealRegs;
  sel, seg: word;
begin

  dosAlloc(sel, seg, sizeof(TVesaModeInfo));

	with regs do begin
  	ax := $4f01;
    cx := mode;
    es := seg;
    di := 0;
    realintr($10, regs);
  end;

  dosmemget(seg, 0, result, sizeof(TVesaModeInfo));

  dosFree(sel);

end;

{Sets the logical screen width, allowing for smooth horizontal scrolling}
procedure SetLogicalScreenSize(width, height: word);
begin
	asm
  	pusha

  	mov ax, $4F06
    mov bl, $00 // set display start during vsync

    mov cx, [width]

    int $10
    popa
  end;
  SCREEN_WIDTH := width;
  SCREEN_HEIGHT := height;	
end;


{Set display start address (in pixels)}
procedure SetDisplayStart(x, y: word);
begin
	asm
  	pusha

  	mov ax, $4F07
    mov bh, $00
    mov bl, $80 // set display start during vsync

    mov cx, [x]
    mov dx, [y]


    int $10
    popa
  end;
end;

{Set the display page (zero indexed)}
procedure SetDisplayPage(page: integer);
begin
	SetDisplayStart(0, SCREEN_HEIGHT*page);
end;	


{Set graphics mode. Once complete the framebuffer can be accessed via
 the LFB pointer}
procedure fSetMode(width, height, bpp: integer);
var
  i: integer;

  VesaModes: array[0..64] of word;
  Mode: word;
  Rights: dword;

  PhysicalAddress: dword;
  LinearAddress: dword;

  didWork: boolean;

const
	{S3 says we have a 64MB window here (even if only 4MB ram)}
	VIDEO_MEMORY = 64*1024*1024;

begin

	Info(Format('Setting video mode: %dx%dx%d', [width, height, bpp]));
	
  {vesa stuff}
	dosAlloc(dosSel, dosSeg, 512);
  VesaInfo.Signature := 'VBE2';
  dosmemput(dosSeg, 0, VesaInfo, sizeof(VesaInfo));
	
	with regs do begin
  	ax := $4F00;
    es := dosSeg;
    di := 0;
    realintr($10, regs);
  end;

  DosMemGet(dosSeg, 0, VesaInfo, sizeof(TVesaInfo));

  { get list of video modes }
  DosMemGet(
    word(VesaInfo.VideoModePtr shr 16),
    word(VesaInfo.VideoModePtr),
    VesaModes, sizeof(VesaModes));

  Mode := 0;
  for i := 0 to length(VesaModes) do begin
    if VesaModes[i] = $FFFF then break;
    with getModeInfo(VesaModes[i]) do begin
			Writeln(XResolution, ',', YResolution, ',', BitsPerPixel);
    	if (XResolution = width) and (YResolution = height) and (BitsPerPixel=bpp) then begin
        mode := VesaModes[i];
        break
      end;	
	  end;
  end;

  if Mode = 0 then
  	Error(Format('Error: graphics mode %dx%dx%d not available.', [width,height,bpp]));


  {Set mode}
	with regs do begin
  	ax := $4F02;
    bx := mode + $4000;
    realintr($10, regs);
  end;

  dosFree(dosSel);

  {Find our physical address}
  PhysicalAddress := dword(getModeInfo(mode).PhysBasePtr);
  if PhysicalAddress <> $E0000000 then
    Warn('Expecting physical address to be $E0000000 but found it at $'+HexStr(PhysicalAddress, 8));

  {Map to linear}
  LinearAddress := get_linear_addr(PhysicalAddress, VIDEO_MEMORY);

  {Set Permissions}
  myLFB_SEG := Allocate_LDT_Descriptors(1);
  if not set_segment_base_address(myLFB_SEG, LinearAddress) then
  	Error('Error setting LFB segment base address.');
	if not set_segment_limit(myLFB_SEG, VIDEO_MEMORY-1) then
	  Error('Error setting LFB segment limit.');

  Info('Mapped LFB to segment $' + HexStr(myLFB_SEG, 4));

  SCREEN_WIDTH := width;
  SCREEN_HEIGHT := height;
  PHYSICAL_WIDTH := width;
  PHYSICAL_HEIGHT := height;
  SCREEN_BPP := bpp;

end;


{Set text mode}
procedure fSetText();
begin
  {set mode, but only if we have to}
  asm
  	mov ax, $0F00
    int $10
    cmp al, $03
    je @SKIP  	
		mov ax,$03
	  int $10
  @SKIP:
	end;
  if USE_80x50 then
	asm
  	{switch to 8x8 font}
  	mov ax, $1112
    mov bl, 0
    int $10
  end else
end;

begin
	screen := tVGADriver.create();
end.
