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

  	canvas: tPage;
    background: tSprite;
    backgroundColor: RGBA;

    {current offset for viewport}
    xOffset,yOffset: single;

    constructor create();

    function width: word;
    function height: word;
    function viewPort: tRect;

    {basic drawing commands}
    procedure hLine(x1, x2, y: int32;col: RGBA);

    {copy cmmands}
    procedure copyRegion(rect: tRect);
    procedure clearRegion(rect: tRect);
    procedure pageFlip();

  end;


implementation

{-------------------------------------------------}

constructor tScreen.create();
begin
  canvas := tPage.create(videoDriver.width, videoDriver.height);
  backgroundColor.init(0,0,0,255);
  background := nil;	
end;

function tScreen.width: word;
begin
	result := canvas.width;
end;

function tScreen.height: word;
begin
	result := canvas.height;
end;

function tScreen.viewPort: tRect;
begin
	result := tRect.create(round(xOffset), round(yOffset), videoDriver.physicalWidth, videoDriver.logicalWidth);
end;

{copies region from canvas to screen.}
procedure tScreen.copyRegion(rect: tRect);
var
	y,yMin,yMax: int32;
  pixels: pointer;
  ofs,len: dword;
  lfb_seg: word;
begin
	{todo: support S3 upload (but maybe make sure regions are small enough
   to not cause stutter - S3 is about twice as fast.}

  rect.clip(tRect.create(canvas.width, canvas.height));
  if rect.area = 0 then exit;
  note('b');

  lfb_seg := videoDriver.LFB_SEG;
  if lfb_seg = 0 then exit;

  note('copy region starting');

  pixels := canvas.pixels;

  for y := rect.top to rect.bottom-1 do begin
  	ofs := (rect.left + (y * canvas.width))*4;
    len := rect.width;
  	asm
    	pushad
    	push es

      mov es,  lfb_seg
      mov edi, ofs

      mov esi, pixels
      add esi, ofs

      mov ecx, len
      rep movsd

      pop es
      popad
    end;  	
  end;
end;

{draw line from x1,y -> x2,y, including final point}
procedure tScreen.hLine(x1, x2, y: int32;col: RGBA);
var
	pixels: pointer;
  ofs,len: int32;
begin

	if (y < 0) or (y >= canvas.height) then exit;
	x1 := max(0, x1);
  x2 := min(0, canvas.width-1);

  pixels := canvas.pixels;
  ofs := (x1 + (y * canvas.width))*4;
  len := (x2-x1)+1;
  if len <= 0 then exit;

	asm
  	pushad
    push es

    mov edi, pixels
    add edi, ofs

    mov eax, col
    mov ecx, len
    rep stosd

    pop es
    popad
    end;
end;

{clears region on canvas with background color}
procedure tScreen.clearRegion(rect: tRect);
var
	y,yMin,yMax: integer;
begin
	{todo: support S3 upload (but maybe make sure regions are small enough
   to not cause stutter - S3 is about twice as fast.}

  rect.clip(tRect.create(canvas.width, canvas.height));
  if rect.area = 0 then exit;

  for y := rect.top to rect.bottom do begin
  	hline(rect.left, rect.right, y, backgroundColor);
  end;

end;

{upload the entire page to video memory}
procedure tScreen.pageFlip();
begin
	copyRegion(tRect.create(canvas.width, canvas.height));
end;

{-------------------------------------------------}


begin
end.
