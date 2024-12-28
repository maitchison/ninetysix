{vga video driver}
unit vga;

{$MODE delphi}

interface

uses
  debug,
  utils,
  go32,
  graph2d,
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

    property width:word read getLogicalWidth;
    property height:word read getLogicalHeight;

    property logicalWidth:word read getLogicalWidth;
    property logicalHeight:word read getLogicalHeight;
    property physicalWidth:word read getPhysicalWidth;
    property physicalHeight:word read getPhysicalHeight;

    property BPP:word read getBPP;
    property LFB_SEG:word read getLFB_SEG;

    procedure waitVSYNC(); virtual; abstract;
    procedure setMode(width, height, BPP: word); virtual; abstract;
    procedure setLogicalSize(width, height: word); virtual; abstract;
    procedure setDisplayStart(x, y: word;waitRetrace:boolean=false); virtual; abstract;
    procedure setText(); virtual; abstract;
    function  isText(): boolean;
  end;

  tVGADriver = class(tVideoDriver)
    {basic VGA driver}
    procedure waitVSYNC(); override;
    procedure setMode(width, height, BPP: word); override;
    procedure setText(); override;
  end;

var
  videoDriver: tVideoDriver = nil;

implementation

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

function tVideoDriver.isText(): boolean;
begin
  {educated guess}
  result := (fPhysicalWidth * fPhysicalHeight) < 32000;
end;

{--------------------------------------------------------------}
{ tVGADriver }
{--------------------------------------------------------------}

procedure tVGADriver.setMode(width, height, bpp: word);
begin
  {VGA knows only one mode}
  if (width = 320) and (height = 200) and (bpp = 8) then begin
    asm
      mov ax, $0013
      int $10
      end;
    self.fPhysicalWidth := width;
    self.fPhysicalHeight := height;
    self.fLogicalWidth := width;
    self.fLogicalHeight := height;
    self.fBpp := bpp;
  end else begin
    error(format('Mode %dx%dx%d not supported by VGA driver',[width, height, bpp]));
  end;
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
  end else
    fPhysicalHeight := 25;

  fPhysicalWidth := 80;
  fLogicalWidth := fPhysicalWidth;
  fLogicalHeight := fPhysicalHeight;
end;

{--------------------------------------------------------------}

begin
  if not assigned(videoDriver) then
    videoDriver := tVGADriver.create();
end.
