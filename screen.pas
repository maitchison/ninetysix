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
  timer,
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
    procedure reset();
  end;

  tScreenScrollMode = (
    SSM_OFFSET,  // just update the screen offset
    SSM_COPY     // copy region using S3
  );

  tScreen = class

  private
    viewport: tRect;
    // dirty grid
    // support for up to 2048x2048
    // pixel -> grid is divide by 8
    flagGrid: array[0..256-1, 0..256-1] of byte;
    clearBounds, flipBounds: tRect;
    s3Driver: tS3Driver;

  public
    canvas: tPage;
    background: tPage;
    backgroundColor: RGBA;
    SHOW_DIRTY_RECTS: boolean;
    stats: tScreenStats;
    bounds: tRect;    // logical bounds of canvas
    scrollMode: tScreenScrollMode;

  private
    procedure copyLine(x1, x2, y: int32);
  public

    constructor create();

    function width: word;
    function height: word;

    {basic drawing commands}
    procedure hLine(x1, x2, y: int32;col: RGBA);

    function  getViewPort(): tRect;
    procedure setViewPort(x,y: int32);

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

procedure transferLineToScreen(canvas: tPage; x,y: int32; yDest: integer);
var
  lfb_seg: word;
  srcOffset,dstOffset: dword;
  pixelCnt: dword;
begin
  lfb_seg := videoDriver.LFB_SEG;
  dstOffset := (yDest * canvas.width)*4;
  srcOffset := dword(canvas.pixels) + ((x + y * videoDriver.logicalWidth) * 4);
  pixelCnt := videoDriver.physicalWidth;
  asm
    cli
    pushad
    push es

    mov es, [lfb_seg]
    mov edi, dstOffset

    mov esi, srcOffset

    mov ecx, pixelCnt
    rep movsd

    pop es
    popad
    sti
  end;

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
  scrollMode := SSM_OFFSET;
  viewport := tRect.create(0,0);
  reset();
end;

{must be called whenever a resolution change occurs after creation.}
procedure tScreen.reset();
begin
  {todo: if assigned(canvas) then canvas.done;}
  if assigned(canvas) then canvas.Destroy;
  canvas := tPage.Create(videoDriver.width, videoDriver.height);

  fillchar(flagGrid, sizeof(flagGrid), 0);
  clearBounds.init(256, 256, -256, -256);
  flipBounds.init(256, 256, -256, -256);

  viewport := tRect.create(0, 0, videoDriver.physicalWidth, videoDriver.physicalHeight);
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
  srcOfs,dstOfs,len: dword;
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
  if keyDown(key_f8) then begin
    s3Driver.fgColor := rgba.create(rnd,rnd,0);
    s3Driver.fillRect(rect.x, rect.y, rect.width, rect.height);
    exit;
  end;

  for y := rect.top to rect.bottom-1 do begin
    srcOfs := (rect.left + (y * canvas.width))*4;
    dstOfs := (rect.left + (y * canvas.width))*4;
    if scrollMode = SSM_COPY then
      dstOfs += videoDriver.logicalWidth * videoDriver.physicalHeight * 4;
    len := rect.width;
    asm
      push es
      push edi
      push esi
      push ecx

      mov es,  lfb_seg
      mov edi, dstOfs

      mov esi, pixelsPtr
      add esi, srcOfs

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
  if background.width <> canvas.width then
    error(format('background width must match canvas, %d != %d ', [background.width, canvas.width]));

  if (y < 0) or (y >= canvas.height) then exit;

  x1 := max(0, x1);
  x2 := min(canvas.width-1, x2);

  canvasPixels := canvas.pixels;
  backgroundPixels := background.pixels;
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

  if (flags and FG_FLIP = FG_FLIP) then begin
    flipBounds.expandToInclude(tPoint.create(x1, y1));
    flipBounds.expandToInclude(tPoint.create(x2, y2));
  end;
  if (flags and FG_CLEAR = FG_CLEAR) then begin
    clearBounds.expandToInclude(tPoint.create(x1, y1));
    clearBounds.expandToInclude(tPoint.create(x2, y2));
  end;

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
begin
  stats.clearCells := 0; stats.clearRegions := 0;
  startTimer('clear');
  for y := clearBounds.top to clearBounds.bottom do begin
    rle := 0;
    for x := clearBounds.left to clearBounds.right do begin
      if (flagGrid[x,y] and FG_CLEAR) = FG_CLEAR then begin
        if rle = 0 then xStart := x;
        inc(stats.clearCells);
        inc(rle);
        flagGrid[x,y] := (flagGrid[x,y] xor FG_CLEAR) or FG_FLIP;
        flipBounds.expandToInclude(tPoint.create(x, y));
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
  clearBounds.init(256,256,-256, -256);
  stopTimer('clear');
end;

{flips all valid regions}
{clears flip flag}
procedure tScreen.flipAll();
var
  x,y: integer;
  xStart, rle: integer;
begin
  startTimer('flip');
  stats.copyCells := 0; stats.copyRegions := 0;

  case scrollMode of
    SSM_COPY: begin
      for y := 0 to videoDriver.physicalHeight-1 do
        transferLineToScreen(canvas, viewport.x, viewport.y+y, y);
      end;
    SSM_OFFSET: begin
      videoDriver.setDisplayStart(viewport.x,viewport.y);
      for y := flipBounds.top to flipBounds.bottom do begin
        rle := 0;
        for x := flipBounds.left to flipBounds.right do begin
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
      flipBounds.init(256,256,-256, -256);
    end;
    else Error('Invalid copy mode');
  end;
  stopTimer('flip');
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

  {debugging}
  if keyDown(key_f7) then begin
    canvas.fillRect(rect, rgba.create(rnd, 0, 0));
    exit;
  end;

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

function tScreen.getViewPort(): tRect;
begin
  result := viewport;
end;

{update the viewport coordinates. Will be applied when flipAll is called}
procedure tScreen.setViewPort(x,y: int32);
begin
  if x < 0 then x := 0;
  if y < 0 then y := 0;
  if x > (canvas.width-videoDriver.physicalWidth) then
    x := (canvas.width-videoDriver.physicalWidth);
  if y > (canvas.height-videoDriver.physicalHeight) then
    y := (canvas.height-videoDriver.physicalHeight);
  viewport.x := x;
  viewport.y := y;
end;

{-------------------------------------------------}

begin
end.
