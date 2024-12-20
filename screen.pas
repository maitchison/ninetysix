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

  private
    fViewPort: tRect;

  public
    canvas: tPage;
    background: tSprite;
    backgroundColor: RGBA;
    SHOW_DIRTY_RECTS: boolean;

  private
    procedure copyLine(x1, x2, y: int32);
  public

    constructor create(); // todo: change to init

    function width: word;
    function height: word;
    function rect: tRect;

    {basic drawing commands}
    procedure hLine(x1, x2, y: int32;col: RGBA);

    procedure setViewPort(x,y: int32);

    procedure reset();

    {copy commands}
    procedure copyRegion(rect: tRect);
    procedure clearRegion(rect: tRect);

    procedure pageFlip();
    procedure clear();

    procedure waitVSync();

    {dirty handling}
    procedure flipAll();
    procedure clearAll();
    procedure markRegion(rect: tRect);

  end;

implementation

uses
  keyboard; {stub}

var
  {todo: change to 8x8 grid}
  previousDirtyRegions: array[0..63] of tRect;
  dirtyRegions: array[0..63] of tRect;
  drCounter: integer = 0;
  prevDrCounter: integer = 0;

{-------------------------------------------------}

constructor tScreen.Create();
begin
  backgroundColor.init(0,0,0,255);
  background := nil;
  canvas := nil;
  SHOW_DIRTY_RECTS := false;
  reset();
end;

{must be called whenever a resolution change occurs after creation.}
procedure tScreen.reset();
begin
  {todo: if assigned(canvas) then canvas.done;}
  if assigned(canvas) then canvas.Destroy;
  canvas := tPage.Create(videoDriver.width, videoDriver.height);
end;

function tScreen.width: word;
begin
  result := canvas.width;
end;

function tScreen.height: word;
begin
  result := canvas.height;
end;

function tScreen.rect(): tRect;
begin
  result := tRect.create(width, height);
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

  lfb_seg := videoDriver.LFB_SEG;
  if lfb_seg = 0 then exit;

  pixels := canvas.pixels;

  for y := rect.top to rect.bottom-1 do begin
    ofs := (rect.left + (y * canvas.width))*4;
    len := rect.width;
    asm
      push es
      push edi
      push esi
      push ecx

      mov es,  lfb_seg
      mov edi, ofs

      mov esi, pixels
      add esi, ofs

      mov ecx, len
      rep movsd

      pop ecx
      pop esi
      pop edi
      pop es
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
  x2 := min(canvas.width-1, x2);

  pixels := canvas.pixels;
  ofs := (x1 + (y * canvas.width))*4;
  len := x2-x1; {todo: check this is right}
  if len <= 0 then exit;

  asm
    push edi
    push eax
    push ecx

    mov edi, pixels
    add edi, ofs

    mov eax, col
    mov ecx, len
    rep stosd

    pop ecx
    pop eax
    pop edi
    end;
end;

{copy line background to canvas}
procedure tScreen.copyLine(x1, x2, y: int32);
var
  canvasPixels,backgroundPixels: pointer;
  ofs,len: int32;
begin

  if not assigned(background) then
    error('background not assigned');
  if background.page.width <> canvas.width then
    error(format('background width must match canvas, %d != %d ', [background.page.width, canvas.width]));

  if (y < 0) or (y >= canvas.height) then exit;

  x1 := max(0, x1);
  x2 := min(canvas.width-1, x2);

  canvasPixels := canvas.pixels;
  backgroundPixels := background.page.pixels;
  ofs := (x1 + (y * canvas.width))*4;
  len := (x2-x1)+1;
  if len <= 0 then exit;

  asm
    pushad
    push edi
    push esi
    push eax
    push ecx

    mov edi, canvasPixels
    add edi, ofs

    mov esi, backgroundPixels
    add esi, ofs

    mov ecx, len
    rep movsd

    pop ecx
    pop eax
    pop esi
    pop edi
    popad
    end;
end;

{indicates that region should fliped this frame, and cleared next frame}
procedure tScreen.markRegion(rect: tRect);
begin
  if drCounter >= high(dirtyRegions) then
    error('Sorry, too many dirty regions');
  dirtyRegions[drCounter] := rect;
  if SHOW_DIRTY_RECTS then
    canvas.drawRect(rect, RGBA.create(255,0,255));
  inc(drCounter);

end;

{clears all parts of the screen marked previously and removes dirty}
procedure tScreen.clearAll();
var
  i: integer;
begin
  for i := 0 to drCounter-1 do
    clearRegion(dirtyRegions[i]);
  move(dirtyRegions, previousDirtyRegions, sizeof(dirtyRegions));
  prevDrCounter := drCounter;
  fillchar(dirtyRegions, sizeof(dirtyRegions), 0);
  drCounter := 0;
end;


procedure tScreen.flipAll();
var
  i: integer;
begin
  for i := 0 to drCounter-1 do
    self.copyRegion(dirtyRegions[i]);
  {unfortunately we also have to flip any previous regions as these will have
   been cleared. Switcing to a grid system will resolve the overlap with this.}
  for i := 0 to prevDrCounter-1 do
    self.copyRegion(previousDirtyRegions[i]);
end;

procedure tScreen.waitVSync();
var
  counter: int32;
begin
  {will throw an overflow error if too slow}
  counter := 0;
  {wait until out of trace}
  while (portb[$03DA] and $8) <> 0 do inc(counter);
  {wait until start of retrace}
  while (portb[$03DA] and $8) = 8 do inc(counter);

end;

{clears region on canvas with background color}
procedure tScreen.clearRegion(rect: tRect);
var
  x: int32;
  y,yMin,yMax: int32;
  paddingX,paddingY: int32;
begin
  {todo: support S3 upload (but maybe make sure regions are small enough
   to not cause stutter - S3 is about twice as fast.}

  rect.clip(tRect.create(canvas.width, canvas.height));
  if rect.area = 0 then exit;

  if assigned(background) then begin
    {calculate padding}
    paddingX := (canvas.width - background.width) div 2;
    paddingY := (canvas.height - background.height) div 2;
  end;

  for y := rect.top to rect.bottom do begin
    {support for background}
    if assigned(background) then begin
      {top alignment for the moment}
      if (y > canvas.height - (paddingY*2)) then
        hline(rect.left, rect.right, y, backgroundColor)
      else
        copyLine(rect.left, rect.right, y);

    end else
      hline(rect.left, rect.right, y, backgroundColor);
  end;

end;

{upload the entire page to video memory}
procedure tScreen.pageFlip();
begin
  copyRegion(tRect.create(canvas.width, canvas.height));
end;

procedure tScreen.clear();
begin
  clearRegion(tRect.create(canvas.width, canvas.height));
end;

procedure tScreen.setViewPort(x,y: int32);
begin
  if x < 0 then x := 0;
  if y < 0 then y := 0;
  if x > (canvas.width-videoDriver.physicalWidth) then
    x := (canvas.width-videoDriver.physicalWidth);
  if y > (canvas.height-videoDriver.physicalHeight) then
    y := (canvas.height-videoDriver.physicalHeight);
  videoDriver.setDisplayStart(x,y);
end;

{-------------------------------------------------}

begin
  fillchar(dirtyRegions, sizeof(dirtyRegions), 0);
  fillchar(previousDirtyRegions, sizeof(previousDirtyRegions), 0);
end.
