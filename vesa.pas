{vesa screen driver}
unit vesa;

{$MODE delphi}

interface

uses
  test,
  debug,
  utils,
  graph2d,
  go32,
  vga;

type tVesaDriver = class(tVGADriver)
    fMappedPhysicalAddress: dword;
  protected
    procedure allocateLFB(physicalAddress:dWord);
  public
    procedure setMode(width, height, BPP: word); override;
    procedure setLogicalSize(width, height: word); override;
    procedure setDisplayStart(x, y: word); override;
  end;

implementation

{----------------------------------------------------------------}

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

type tVesaInfo = packed record
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
  vesaInfo: tVesaInfo;
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


{Set the display page (zero indexed)}
procedure SetDisplayPage(page: integer);
begin
{  SetDisplayStart(0, SCREEN_HEIGHT*page);}
end;


{----------------------------------------------------------------}

procedure tVesaDriver.allocateLFB(physicalAddress: dword);
const
  {S3 says we have a 64MB window here (even if only 4MB ram)}
  VIDEO_MEMORY = 64*1024*1024;
var
  linearAddress: dword;
begin

  {Map to linear}
  linearAddress := get_linear_addr(physicalAddress, VIDEO_MEMORY);

  {Set Permissions}
  fLFB_SEG := Allocate_LDT_Descriptors(1);
  if not set_segment_base_address(fLFB_SEG, LinearAddress) then
    error('Error setting LFB segment base address.');
  if not set_segment_limit(fLFB_SEG, VIDEO_MEMORY-1) then
    error('Error setting LFB segment limit.');

  info('Mapped LFB to segment $' + HexStr(fLFB_SEG, 4));
  fMappedPhysicalAddress := physicalAddress;

end;

{Set graphics mode. Once complete the framebuffer can be accessed via
 the LFB pointer}
procedure tVesaDriver.setMode(width, height, bpp: word);
var
  i: integer;
  vesaModes: array[0..63] of word;
  mode: word;
  rights: dword;
  physicalAddress: dWord;
begin

  info(format('Setting video mode: %dx%dx%d', [width, height, bpp]));

  {vesa stuff}
  dosAlloc(dosSel, dosSeg, 512);
  VesaInfo.Signature := 'VBE2';
  dosmemput(dosSeg, 0, vesaInfo, sizeof(vesaInfo));

  with regs do begin
    ax := $4F00;
    es := dosSeg;
    di := 0;
    realintr($10, regs);
  end;

  DosMemGet(dosSeg, 0, vesaInfo, sizeof(tVesaInfo));

  { get list of video modes }
  {todo: this looks wrong}
  DosMemGet(
    word(VesaInfo.VideoModePtr shr 16),
    word(VesaInfo.VideoModePtr),
    vesaModes, sizeof(vesaModes));

  Mode := 0;
  for i := 0 to length(VesaModes)-1 do begin
    if VesaModes[i] = $FFFF then break;
    with getModeInfo(VesaModes[i]) do begin
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
  physicalAddress := dword(getModeInfo(mode).PhysBasePtr);
  if physicalAddress <> $E0000000 then
    Warn('Expecting physical address to be $E0000000 but found it at $'+HexStr(PhysicalAddress, 8));

  if fMappedPhysicalAddress = 0 then begin
    {allocate for the first time}
    allocateLFB(physicalAddress);
  end else if fMappedPhysicalAddress <> physicalAddress then begin
    {address moved, this is a bit weird}
    Warn(format(
      'Physical address moved, was at $%s and is now at $%s $',
      [hexStr(fMappedPhysicalAddress, 8), hexStr(physicalAddress, 8)]
    ));
    allocateLFB(physicalAddress);
  end;

  fPhysicalWidth := width;
  fPhysicalHeight := height;
  fLogicalWidth := width;
  fLogicalHeight := height;
  fBpp := bpp;
end;

{Sets the logical screen width, allowing for smooth scrolling}
procedure tVesaDriver.setLogicalSize(width, height: word);
begin
  info(format('Setting logical size: %dx%d', [width, height]));
  asm
    pusha

    mov ax, $4F06
    mov bl, $00

    mov cx, [width]

    int $10
    popa
  end;
  fLogicalWidth := width;
  fLogicalHeight := height;
end;

{Set display start address (in pixels)}
procedure tVesaDriver.setDisplayStart(x, y: word);
begin
  asm
    pusha

    mov ax, $4F07
    mov bh, $00
    mov bl, $00 // not not wait for vsync

    mov cx, [x]
    mov dx, [y]


    int $10
    popa
  end;
end;


{----------------------------------------------------------------}

begin
end.
