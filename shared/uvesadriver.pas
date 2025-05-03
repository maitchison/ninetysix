{vesa screen driver}
unit uVesaDriver;

{$MODE delphi}

interface

uses
  uTest,
  uDebug,
  uUtils,
  uRect,
  go32,
  uVGADriver;

type tVesaInfo = packed record
  {----------- VBE 1.0 -----------------}
  Signature: array[1..4] of char;
  Version: word;
  OemStringPtr: dWord;
  Capabilities: dWord;
  VideoModePtr: dWord;
  TotalMemory: word; {in 64k blocks}
  {----------- VBE 2.0 -----------------}
  OemSoftwareRev: word;
  OemVendorNamePtr: dWord;
  OemProducNamePtr: dWord;
  OemProductRevPtr: dWord;
end;

type tVesaDriver = class(tVGADriver)
  private
    vesaInfo: tVesaInfo;
    mappedPhysicalAddress: dword;
    oemStr: string;
    vesaModes: array[0..64] of word;
    procedure allocateLFB(physicalAddress:dWord);
    function getVesaInfo(): tVesaInfo;
  public
    constructor create();
    procedure logInfo();
    procedure logModes();
    procedure setMode(mode: word); overload;
    function  tryMode(width, height, bpp: word): boolean; override;
    procedure setLogicalSize(width, height: word); override;
    procedure setDisplayStart(x, y: word;waitRetrace:boolean=false); override;
    function  vesaVersion: single;
    function  videoMemory: dword;
  end;

implementation

const
  VESA_MEMORYMODEL_TEXT=0;
  VESA_MEMORYMODEL_PLANAR=3;
  VESA_MEMORYMODEL_PACKED=4;
  VESA_MEMORYMODEL_DIRECT=6;


type tVesaModeInfo = packed record
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

{----------------------------------------------------------------}

{Allocates dos memory
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

{----------------------------------------------------------------}

constructor tVesaDriver.create();
var
  oemBuffer: array[0..256-1] of char;
  i: integer;
begin
  inherited create();
  vesaInfo := getVesaInfo();

  {oem string}
  fillchar(oemBuffer, sizeof(oemBuffer), 0);
  dosMemGet(
    word(vesaInfo.OemStringPtr shr 16),
    word(vesaInfo.OemStringPtr and $ffff),
    oemBuffer[0], 256
  );
  oemStr := '';
  for i := 0 to 32-1 do begin
    // i > 4 is a hack because for some reason dosbox-x has corrupt
    // inital 4 characters
    if (i > 4) and (oemBuffer[i] = #0) then break;
    oemStr += oemBuffer[i];
  end;

  {modes}
  dosMemGet(
    word(vesaInfo.VideoModePtr shr 16),
    word(vesaInfo.VideoModePtr),
    vesaModes, sizeof(vesaModes));

  {logging...}
  logInfo();
end;

procedure tVesaDriver.logInfo();
begin
  info(format('VESA v%f (%.2f MB) "%s"', [vesaVersion, videoMemory / 1024 / 1024, oemStr]));
end;

procedure tVesaDriver.logModes();
var
  i: integer;
  postfix: string;

begin

  for i := 0 to length(vesaModes)-1 do begin
    if vesaModes[i] = $FFFF then break;
    with getModeInfo(vesaModes[i]) do begin
      if memoryModel = VESA_MEMORYMODEL_TEXT then
        postfix := '(text)'
      else
        postfix := '';

      note(format('[%d] %dx%dx%d %s', [vesaModes[i], xResolution, yResolution, bitsPerPixel, postfix]));
    end;
  end;
end;

procedure tVesaDriver.allocateLFB(physicalAddress: dword);
var
  linearAddress: dword;
  LFBSize: dword;
begin

  if videoMemory = 0 then begin
    warning('Could not detect video memory size, assuming 1MB');
    LFBSize := 1024*1024;
  end else
    LFBSize := videoMemory;

  {this is a hack for my S3 card, which for some reason reports 1MB}
  {
  // while this works, it causes another problem, the memory just loops
  // so for now we'll try to stick to 1MB... owch... I guess that means
  // 16bit color
  if oemStr = 'S3 Incorporated. Trio64' then
    LFBSize := 2*1024*1024;
  }

  {Map to linear}
  linearAddress := get_linear_addr(physicalAddress, LFBSize);

  {Set Permissions}
  fLFB_SEG := Allocate_LDT_Descriptors(1);
  if not set_segment_base_address(fLFB_SEG, LinearAddress) then
    fatal('Error setting LFB segment base address.');
  if not set_segment_limit(fLFB_SEG, LFBSize-1) then
    fatal('Error setting LFB segment limit.');

  info('Mapped LFB to segment $' + HexStr(fLFB_SEG, 4));
  mappedPhysicalAddress := physicalAddress;
end;

function tVesaDriver.getVesaInfo(): tVesaInfo;
var
  sel,seg: word;
  regs: tRealRegs;
  info: tVesaInfo;
begin
  fillchar(info, sizeof(info), 0);
  dosAlloc(sel, seg, 512);
  info.signature := 'VBE2';
  dosmemput(seg, 0, info, sizeof(info));
  with regs do begin
    ax := $4F00;
    es := seg;
    di := 0;
    realintr($10, regs);
  end;
  dosMemGet(seg, 0, info, sizeof(info));
  dosFree(sel);
  result := info;
end;

{Set graphics mode. Once complete the framebuffer can be accessed via
 the LFB pointer}
function tVesaDriver.tryMode(width, height, bpp: word): boolean;
var
  mode, foundMode: word;
  rights: dword;
  physicalAddress: dWord;
  regs: tRealRegs;
  dosSeg, dosSel: word;
  mi: tVesaModeInfo;
begin

  foundMode := 0;
  for mode in vesaModes do begin
    if mode = $ffff then break;
    {My S3 card has 2MB, but reports 1MB. I don't seem to be able to
     access the 2nd MB and for some reason VBE still includes modes
     that require it. For this reason I disable any mode we don't have
     video memory for.}
    if (width*height*bpp div 8) > videoMemory then continue;
    mi := getModeInfo(mode);
    if (mi.xResolution = width) and (mi.yResolution = height) and (mi.bitsPerPixel=bpp) then begin
      foundMode := mode;
      break
    end;
  end;

  if foundMode = 0 then exit(false);
  info(format('Setting video mode: %dx%dx%d', [width, height, bpp]));
  setMode(foundMode);

  result := true;
end;

{Set graphics mode. Once complete the framebuffer can be accessed via
 the LFB pointer}
procedure tVesaDriver.setMode(mode: word);
var
  i: integer;
  vesaModes: array[0..64] of word;
  rights: dword;
  physicalAddress: dWord;
  regs: tRealRegs;
  dosSeg, dosSel: word;
  mi: tVesaModeInfo;
begin

  {we use $4000 to request LFB}
  mode := mode or $4000;

  {Set mode}
  with regs do begin
    ax := $4F02;
    bx := mode;
    realintr($10, regs);
  end;

  mi := getModeInfo(mode);

  {Find our physical address}
  physicalAddress := dword(mi.PhysBasePtr);

  if physicalAddress = 0 then begin
    setText();
    fatal('Could not find LFB address.');
  end;

  info('Physical address found at $'+HexStr(PhysicalAddress, 8));

  if mappedPhysicalAddress = 0 then begin
    {allocate for the first time}
    allocateLFB(physicalAddress);
  end else if mappedPhysicalAddress <> physicalAddress then begin
    {address moved, this is a bit weird}
    warning(format(
      'Physical address moved, was at $%s and is now at $%s $',
      [hexStr(mappedPhysicalAddress, 8), hexStr(physicalAddress, 8)]
    ));
    allocateLFB(physicalAddress);
  end;

  fPhysicalWidth := mi.xResolution;
  fPhysicalHeight := mi.yResolution;
  fLogicalWidth := mi.xResolution;
  fLogicalHeight := mi.yResolution;
  fBPP := mi.bitsPerPixel;
end;

{Sets the logical screen width, allowing for smooth scrolling}
procedure tVesaDriver.setLogicalSize(width, height: word);
var
  actualWidth: word;
begin
  if (width * height * bitsPerPixel div 8) > videoMemory then
    fatal(format('Logical size (%dx%dx%d) too large for video memory (%dKB)', [width, height, bitsPerPixel, videoMemory div 1024]));
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
  asm
    pusha
    xor cx, cx
    mov ax, $4F06
    mov bl, $01
    int $10
    mov [actualWidth], cx
    popa
  end;
  if actualWidth <> width then fatal(format(
    'Could not set logical size %d, instead got %d', [width, actualWidth]
    ));
end;

{Set display start address (in pixels)}
procedure tVesaDriver.setDisplayStart(x, y: word;waitRetrace:boolean=false);
var
  code: word;
begin
  if waitRetrace then code := $0080 else code := $0000;
  asm
    pusha

    mov ax, $4F07
    mov bx, [code]

    mov cx, [x]
    mov dx, [y]

    int $10
    popa
  end;
end;

function tVesaDriver.vesaVersion: single;
var
  majVer, minVer: single;
begin
  majVer := vesaInfo.version shr 8;
  minVer := (vesaInfo.version and $ff);
  while minVer >= 1 do minVer /= 10;
  result := majVer + minVer;
end;

{video memory in bytes}
function tVesaDriver.videoMemory: dword;
begin
  result := vesaInfo.totalMemory * 64 * 1024;
end;

{----------------------------------------------------------------}

begin
end.
