unit screen;

{$MODE delphi}

interface

uses
	test,
	debug,
  utils,
  graph2d,
  graph32,
  sprite,
  vga;

type

	tScreen = object

    {buffer to write into}
  	canvas: tPage;
    {sprite to use as background image}
    background: tSprite;
    {background color to use when clearing}
    backgroundColor: RGBA;

    {current offset for viewport}
    xOffset,yOffset: single;

    constructor create();

    {width of virtual screen}
    function width: word;
    {height of virtual screen}
    function height: word;

    {the currently visible region of the screen}
    function viewPort: tRect;

    {transfers region from canvas to video}
    procedure flipRegion(rect: tRect);
    procedure clearRegion(rect: tRect);

  end;


implementation

{-------------------------------------------------}

function tScreen.width: word;
begin
	result := canvas.width;
end;

function tScreen.height: word;
begin
	result := canvas.height;
end;

constructor tScreen.create();
begin
  canvas := tPage.create(videoDriver.width, videoDriver.height);	
end;

function tScreen.viewPort: tRect;
begin
	result := tRect.create(round(xOffset), round(yOffset), videoDriver.physicalWidth, videoDriver.logicalWidth);
end;

{clears region from canvas to screen.}
procedure tScreen.flipRegion(rect: tRect);
var
	y,yMin,yMax: integer;
  pixels: pointer;
  ofs,len: dword;
  lfb_seg: word;
begin
	{todo: support S3 upload (but maybe make sure regions are small enough
   to not cause stutter - S3 is about twice as fast.}

  rect.clip(tRect.create(canvas.width, canvas.height));
  if rect.area = 0 then exit;

  lfb_seg := videoDriver.LFB_SEG;
  if lfb_seg = 0 then exit;

  pixels := canvas.pixels;

  for y := rect.top to rect.bottom do begin
  	ofs := (rect.left + (y * canvas.width))*4;
    len := rect.width;
  	asm
    	pusha
    	push es
      mov es,  lfb_seg
      mov edi, ofs
      mov esi, pixels
      add esi, ofs
      mov ecx, len
      rep movsd
      pop es
      popa
      end;  	
  end;
end;

procedure tScreen.clearRegion(rect: tRect);
begin
end;


{-------------------------------------------------}


begin
end.
