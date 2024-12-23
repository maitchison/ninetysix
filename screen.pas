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
  vga,
  s3;

const
  FG_FLIP  = 1;
  FG_CLEAR = 2;

type

  tScreenStats = record
    copyRegions: int32;
    copyCells: int32;
    clearRegions: int32;
    clearCells: int32;
    copyTime: single;
    clearTime: single;
    procedure reset();
  end;

  tScreen = class

  private
    fViewPort: tRect;
    // dirty grid
    // support for up to 1024x128
    // pixel -> grid is divide by 8
    flagGrid: array[0..127, 0..127] of byte;
    fgxMin,fgyMin,fgxMax,fgyMax: integer;
    s3Driver: tS3Driver;

  public
    canvas: tPage;
    background: tSprite;
    backgroundColor: RGBA;
    SHOW_DIRTY_RECTS: boolean;
    stats: tScreenStats;
    bounds: tRect;    // logical bounds of canvas

  private
    procedure copyLine(x1, x2, y: int32);
  public

    constructor create();

    function width: word;
    function height: word;

    {basic drawing commands}
    procedure hLine(x1, x2, y: int32;col: RGBA);

    procedure setViewPort(x,y: int32;waitRetrace: boolean=false);

    procedure reset();

    {copy commands}
    procedure copyRegion(rect: tRect);
    procedure clearRegion(rect: tRect);

    procedure pageFlip();
    procedure clear();

    {dirty handling}
    procedure flipAll();
    procedure clearAll();
    procedure markRegion(rect: tRect; flags:word=FG_FLIP+FG_CLEAR);

  end;

implementation

uses
  keyboard; {stub}

{-------------------------------------------------}

procedure tScreenStats.reset();
begin
  fillchar(self, sizeof(self), 0);
end;

{-------------------------------------------------}

constructor tScreen.Create();
begin
  inherited create();
  backgroundColor.init(0,0,0,255);
  background := nil;
  canvas := nil;
  SHOW_DIRTY_RECTS := false;
  s3Driver := tS3Driver.create();
  reset();
end;

{must be called whenever a resolution change occurs after creation.}
procedure tScreen.reset();
begin
  {todo: if assigned(canvas) then canvas.done;}
  if assigned(canvas) then canvas.Destroy;
  canvas := tPage.Create(videoDriver.width, videoDriver.height);

  fillchar(flagGrid, sizeof(flagGrid), 0);
  fgxMin := (canvas.width div 8)-1;
  fgyMin := (canvas.height div 8)-1;
  fgxMax := 0;
  fgyMax := 0;

  bounds := tRect.create(width, height);

  stats.reset();
end;

function tScreen.width: word;
begin
  result := canvas.width;
end;

function tScreen.height: word;
begin
  result := canvas.height;
end;

{copies region from canvas to screen.}
procedure tScreen.copyRegion(rect: tRect);
var
  y,yMin,yMax: int32;
  pixelsPtr: pointer;
  ofs,len: dword;
  lfb_seg: word;
begin
  {todo: support S3 upload (but maybe make sure regions are small enough
   to not cause stutter - S3 is about twice as fast.}
  rect.clipTo(bounds);
  if (rect.width <= 0) or (rect.height <= 0) then exit;

  lfb_seg := videoDriver.LFB_SEG;
  if lfb_seg = 0 then exit;

  pixelsPtr := canvas.pixels;

  // show debug regions
  if keyDown(key_f2) then begin
    s3Driver.fgColor := rgba.create(rnd,rnd,0);
    s3Driver.fillRect(rect.x, rect.y, rect.width, rect.height);
    exit;
  end;

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

      mov esi, pixelsPtr
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
  pixelsPtr: pointer;
  ofs,len: int32;
begin

  if (y < 0) or (y >= canvas.height) then exit;

  x1 := max(0, x1);
  x2 := min(canvas.width-1, x2);

  pixelsPtr := canvas.pixels;
  ofs := (x1 + (y * canvas.width))*4;
  len := x2-x1; {todo: check this is right}
  if len <= 0 then exit;

  asm
    push edi
    push eax
    push ecx

    mov edi, pixelsPtr
    add edi, ofs

    mov eax, col
    mov ecx, len
    rep stosd

    pop ecx
    pop eax
    pop edi
    end;
end;

{copy line background to canvas
Copy from x1, to x2 inclusive
}
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
procedure tScreen.markRegion(rect: tRect; flags:word=FG_FLIP+FG_CLEAR);
var
  x,y, x1,x2,y1,y2: integer;
begin
  rect.clipTo(bounds);

  x1 := rect.x div 8;
  y1 := rect.y div 8;
  x2 := (rect.right-1) div 8;
  y2 := (rect.bottom -1) div 8;

  for y := y1 to y2 do
    for x := x1 to x2 do
      flagGrid[x,y] := flags;

  fgxMin := min(x1, fgxMin);
  fgyMin := min(y1, fgyMin);
  fgxMax := max(x2, fgxMax);
  fgyMax := max(y2, fgyMax);

  if keyDown(key_f3) then begin
    s3Driver.fgColor := rgba.create(0,0,rnd);
    s3Driver.fillRect(rect.x, rect.y, rect.width, rect.height);
  end;

end;

{clears all parts of the screen marked for clearing
Also removes clear flag, and sets flip flag}
procedure tScreen.clearAll();
var
  x, y: integer;
  xStart, rle: integer;
  startTime: double;
begin
  stats.clearCells := 0; stats.clearRegions := 0;
  startTime := getSec;
  for y := fgyMin to fgyMax do begin
    rle := 0;
    for x := fgxMin to fgxMax do begin
      if (flagGrid[x,y] and FG_CLEAR) = FG_CLEAR then begin
        if rle = 0 then xStart := x;
        inc(stats.clearCells);
        inc(rle);
        flagGrid[x,y] := (flagGrid[x,y] xor FG_CLEAR) or FG_FLIP;
      end else begin
        if rle > 0 then begin
          clearRegion(tRect.create(xStart*8, y*8, 8*rle, 8));
          stats.clearRegions += 1;
          rle := 0;
        end;
      end;
    end;
    if rle > 0 then begin
      clearRegion(tRect.create(xStart*8, y*8, 8*rle, 8));
      stats.clearRegions += 1;
    end;
  end;
  stats.clearTime := getSec - startTime;
end;

{flips all valid regions}
{clears flip flag}
procedure tScreen.flipAll();
var
  x,y: integer;
  xStart, rle: integer;
  startTime: double;
begin
  stats.copyCells := 0; stats.copyRegions := 0;
  startTime := getSec;
  for y := fgYMin to fgYMax do begin
    rle := 0;
    for x := fgXMin to fgXMax do begin
      if (flagGrid[x,y] and FG_FLIP) = FG_FLIP then begin
        if rle = 0 then xStart := x;
        inc(stats.copyCells);
        inc(rle);
        flagGrid[x,y] := (flagGrid[x,y] xor FG_FLIP)
      end else begin
        if rle > 0 then begin
          copyRegion(tRect.create(xStart*8, y*8, 8*rle, 8));
          stats.copyRegions += 1;
          rle := 0;
        end;
      end;
    end;
    if rle > 0 then begin
      copyRegion(tRect.create(xStart*8, y*8, 8*rle, 8));
      stats.copyRegions += 1;
    end;
  end;
  stats.copyTime := getSec - startTime;
end;

{clears region on canvas with background color}
procedure tScreen.clearRegion(rect: tRect);
var
  x: int32;
  y,yMin,yMax: int32;
  paddingX,paddingY: int32;
begin

  rect.clipTo(bounds);
  if (rect.width <= 0) or (rect.height <= 0) then exit;

  if assigned(background) then begin
    {calculate padding}
    paddingX := (canvas.width - background.width) div 2;
    paddingY := (canvas.height - background.height) div 2;
  end;

  for y := rect.top to rect.bottom-1 do begin
    {support for background}
    if assigned(background) then begin
      {top alignment for the moment}
      if (y > canvas.height - (paddingY*2)) then
        hline(rect.left, rect.right-1, y, backgroundColor)
      else
        copyLine(rect.left, rect.right-1, y);

    end else
      hline(rect.left, rect.right-1, y, backgroundColor);
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

procedure tScreen.setViewPort(x,y: int32;waitRetrace: boolean=false);
begin
  if x < 0 then x := 0;
  if y < 0 then y := 0;
  if x > (canvas.width-videoDriver.physicalWidth) then
    x := (canvas.width-videoDriver.physicalWidth);
  if y > (canvas.height-videoDriver.physicalHeight) then
    y := (canvas.height-videoDriver.physicalHeight);
  videoDriver.setDisplayStart(x,y,waitRetrace);
end;

{-------------------------------------------------}

begin
end.
