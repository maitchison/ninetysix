{vga video driver}
unit uVgaDriver;

{$MODE delphi}

interface

uses
  uDebug,
  uUtils,
  crt,
  go32,
  uRect;

type
  tVideoDriver = class

  protected
    {the resolution of the screen}
    fPhysicalWidth,fPhysicalHeight:word;
    fBPP: word;
    fLFB_SEG: word;

    function getPhysicalWidth: word;
    function getPhysicalHeight: word;
    function getLogicalWidth: word;
    function getLogicalHeight: word;
    function getLFB_SEG: word;

  public

    //stub: public
    {logical dimensions, which may be larger when uing fullscreen scrolling}
    fLogicalWidth,fLogicalHeight:word;

    constructor create();

    property width:word read getLogicalWidth;
    property height:word read getLogicalHeight;

    property logicalWidth:word read getLogicalWidth;
    property logicalHeight:word read getLogicalHeight;
    property physicalWidth:word read getPhysicalWidth;
    property physicalHeight:word read getPhysicalHeight;

    property bitsPerPixel:word read fBPP;
    property LFB_SEG:word read getLFB_SEG;

    procedure waitVSYNC(); virtual;
    function  tryMode(width, height, bpp: word): boolean; virtual;
    procedure setMode(width, height, bpp: word);
    procedure setTrueColor(width, height: word; maxBPP: byte=32);
    procedure setLogicalSize(width, height: word); virtual;
    procedure setDisplayStart(x, y: word;waitRetrace:boolean=false); virtual;
    procedure setText(); virtual;
    function  isText(): boolean;
  end;

  tVGADriver = class(tVideoDriver)
    {basic VGA driver}
    procedure waitVSYNC(); override;
    function tryMode(width, height, bpp: word): boolean; override;
    procedure setText(); override;
  end;

function videoDriver(): tVideoDriver;
procedure enableVideoDriver(newVideoDriver: tVideoDriver);

CONST
  USE_80x50: boolean = True;

implementation

var
  fVideoDriver: tVideoDriver = nil;

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

function tVideoDriver.getLFB_SEG: word;
begin
  result := fLFB_SEG;
end;

function tVideoDriver.isText(): boolean;
begin
  {educated guess}
  result := (fPhysicalWidth * fPhysicalHeight) < 32000;
end;

procedure tVideoDriver.setMode(width, height, bpp: word);
begin
  if not tryMode(width, height, bpp) then
    fatal(format('Mode %dx%dx%d not supported by VGA driver',[width, height, bpp]));
end;

{this will select the best true color mode}
procedure tVideoDriver.setTrueColor(width, height: word; maxBPP: byte=32);
begin
  if (maxBPP >= 24) and tryMode(width, height, 24) then exit;
  if (maxBPP >= 32) and tryMode(width, height, 32) then exit;
  if (maxBPP >= 16) and tryMode(width, height, 16) then exit;
  if (maxBPP >= 15) and tryMode(width, height, 15) then exit;
  fatal(format('Could not set true color video mode (%dx%d) [maxBPP=%d]', [width, height, maxBPP]));
end;

{-----------------------------}
{ abstract stub methods }

procedure tVideoDriver.waitVSYNC();
begin
end;

procedure tVideoDriver.setDisplayStart(x, y: word;waitRetrace:boolean=false);
begin
end;

function tVideoDriver.tryMode(width, height, bpp: word): boolean;
begin
  exit(false);
end;

procedure tVideoDriver.setLogicalSize(width, height: word);
begin
end;

procedure tVideoDriver.setText();
begin
end;

{--------------------------------------------------------------}
{ tVGADriver }
{--------------------------------------------------------------}

function tVGADriver.tryMode(width, height, bpp: word): boolean;
begin
  {VGA knows only one mode}
  if not ((width = 320) and (height = 200) and (bpp = 8)) then
    exit(false);
  asm
    mov ax, $0013
    int $10
    end;
  self.fPhysicalWidth := width;
  self.fPhysicalHeight := height;
  self.fLogicalWidth := width;
  self.fLogicalHeight := height;
  self.fBpp := bpp;
  result := true;
end;

procedure tVGADriver.waitVSYNC();
begin
  {wait until out (previous partial) vsync pulse, this will be a short wait}
  repeat until (portb[$03DA] and $8) = 0;
  {wait until start of new vsync pulse, this is a long wait}
  repeat until (portb[$03DA] and $8) = 8;
end;

procedure tVGADriver.setText();
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

  if USE_80x50 then begin
    asm
      {switch to 8x8 font}
      mov ax, $1112
      mov bl, 0
      int $10
    end;
    fPhysicalHeight := 50;
  end else begin
    asm
      {switch to 16x8 font}
      mov ax, $1114
      mov bl, 0
      int $10
    end;
    fPhysicalHeight := 25;
  end;

  fPhysicalWidth := 80;
  fLogicalWidth := fPhysicalWidth;
  fLogicalHeight := fPhysicalHeight;
end;

{--------------------------------------------------------------}

procedure enableVideoDriver(newVideoDriver: tVideoDriver);
begin
  if assigned(fVideoDriver) then
    fVideoDriver.free;
  fVideoDriver := newVideoDriver;
end;

function videoDriver(): tVideoDriver;
begin
  result := fVideoDriver;
end;

{--------------------------------------------------------------}

initialization
  if not assigned(fVideoDriver) then
    enableVideoDriver(tVGADriver.create());
finalization
  enableVideoDriver(nil);
end.
