unit uScreen;

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
    SSM_OFFSET,  // flip by updating the screen offset
    SSM_COPY     // flip copies entire canvas to video
  );

  {bit-depth of the video memory. Screen buffer is always 32bit,
   however do support on-the-fly conversion to any of these depths}
  tVideoDepth = (VD_15, VD_16, VD_24, VD_32);

  tFlipEffect = (
    FX_NONE,
    FX_SCANLINE,    // every other line is dim
    FX_DOTS,        // looks like dots
    FX_NOISE        // adds noise. helpful for debugging when screen is updated.
    );

  tScreen = class

  private
    viewport: tRect;
    // dirty grid
    // support for up to 1024x2048
    // pixel -> grid is divide by 8
    flagGrid: array[0..128-1, 0..256-1] of byte;
    videoDepth: tVideoDepth;

  public
    canvas: tPage;
    background: tPage;
    backgroundColor: RGBA;
    SHOW_DIRTY_RECTS: boolean;
    stats: tScreenStats;
    bounds: tRect;    // logical bounds of canvas
    scrollMode: tScreenScrollMode;
    fx: tFlipEffect;

  protected
    procedure copyLine(x1, x2, y: int32);
    procedure flipLineToScreen(srcX,srcY,dstX,dstY: int32; pixelCnt: int32);
  public

    constructor create();
    destructor destroy(); override;

    function width: word;
    function height: word;

    {basic drawing commands}
    procedure hLine(x1, x2, y: int32;col: RGBA);

    function  getViewPort(): tRect;
    procedure setViewPort(x,y: int32);

    procedure resize(aWidth: word; aHeight: word);
    {copy commands}
    procedure copyRegion(rect: tRect);
    procedure clearRegion(rect: tRect);

    procedure pageFlip();
    procedure pageClear();

    {dirty handling}
    procedure flipAll();
    procedure clearAll();
    procedure markRegion(rect: tRect; flags:word=FG_FLIP+FG_CLEAR); inline;
    procedure markPixel(x,y: integer; flags:word=FG_FLIP+FG_CLEAR); inline;


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

procedure shiftLineToScreen(canvas: tPage; srcX,srcY,dstX,dstY: int32; pixelCnt: int32; shift1,shift2: byte);
var
  lfb_seg: word;
  srcOffset,dstOffset: dword;
  sourceShift: byte;
  mask1,mask2: dword;
begin
  {only 32bit supported right now}
  lfb_seg := videoDriver.LFB_SEG;
  dstOffset := (dstX+(dstY * videoDriver.logicalWidth))*4;
  srcOffset := dword(canvas.pixels) + ((srcX + srcY * canvas.width) * 4);
  mask1 := $ff shr shift1;
  mask1 := mask1 + (mask1 shl 8) + (mask1 shl 16) + (mask1 shl 24);
  mask2 := $ff shr shift2;
  mask2 := mask2 + (mask2 shl 8) + (mask2 shl 16) + (mask2 shl 24);
  asm
    cli
    pushad
    push es

    mov ax,  LFB_SEG
    mov es,  ax
    mov edi, DSTOFFSET
    mov esi, SRCOFFSET

    mov ebx, MASK1
    mov cl,  SHIFT1
    mov ch,  SHIFT2
    mov edx, PIXELCNT
    shr edx, 1

  @X32:

    mov eax, dword ptr ds:[esi]
    shr eax, cl
    and eax, ebx
    mov dword ptr es:[edi], eax

    add esi, 4
    add edi, 4

    mov eax, dword ptr ds:[esi]
    ror ecx, 8
    shr eax, cl
    rol ecx, 8
    and eax, MASK2
    mov dword ptr es:[edi], eax

    add esi, 4
    add edi, 4
    dec edx
    jnz @X32

    pop es
    popad
    sti
  end;
end;

procedure noiseLineToScreen(canvas: tPage; srcX,srcY,dstX,dstY: int32; pixelCnt: int32);
var
  lfb_seg: word;
  srcOffset,dstOffset,noisePtr: dword;
  noiseOffset: dword;
begin
  {only 32bit supported right now}
  lfb_seg := videoDriver.LFB_SEG;
  dstOffset := (dstX+(dstY * videoDriver.logicalWidth))*4;
  srcOffset := dword(canvas.pixels) + ((srcX + srcY * canvas.width) * 4);
  noisePtr := dword(@NOISE_BUFFER);
  noiseOffset := rnd;
  asm
    cli
    pushad
    push es

    mov ax,  LFB_SEG
    mov es,  ax

    mov ebx, NOISEOFFSET
    mov ecx, PIXELCNT
    mov edx, NOISEPTR

    mov edi, DSTOFFSET
    mov esi, SRCOFFSET

    {
      eax: temp
      ebx: noise index
      ecx: loop
      edx: noise base pointer

      edi: dst
      esi: source

      MM0 source pixel
      MM1 noise
    }

  @X32:

    movd      MM0, dword ptr ds:[esi]
    mov       al, [edx+ebx]
    shr       al, 2
    mov       ah, al
    movd      MM1, eax
    punpcklwd MM1, MM1
    psubusb   MM0, MM1
    movd      dword ptr es:[edi], MM0

    add esi, 4
    add edi, 4
    inc ebx
    and ebx, $ff
    dec ecx
    jnz @X32

    pop es
    popad
    emms
    sti
  end;
end;


procedure transferLineToScreen(canvas: tPage; srcX,srcY,dstX,dstY: int32; pixelCnt: int32);
var
  lfb_seg: word;
  srcOffset,dstOffset: dword;
  bytesPerPixel: byte;
  bitsPerPixel: byte;
  sourceShift: byte;
begin
  lfb_seg := videoDriver.LFB_SEG;
  bitsPerPixel := videoDriver.bitsPerPixel;
  bytesPerPixel := (videoDriver.bitsPerPixel+7) div 8;
  dstOffset := (dstX+(dstY * videoDriver.logicalWidth))*bytesPerPixel;
  srcOffset := dword(canvas.pixels) + ((srcX + srcY * canvas.width) * 4);
  asm
    cli
    pushad
    push es

    mov ax, lfb_seg
    mov es,  ax
    mov edi, dstOffset
    mov esi, srcOffset

    mov ecx, pixelCnt

    mov al, bitsPerPixel
    cmp al, 24
    je  @X24
    jg  @X32
    cmp al, 16

    je  @X16
    //fall through to @X15

  @X15:

    {todo: mmx 2pixels at a time (is it any faster on real hardware?}
    {also, we could pair this by processing two colors at a time and using ebx}

    mov eax, dword ptr ds:[esi]       // aaaaaaaarrrrrrrrggggggggbbbbbbbb

    shr ah, 3                         // aaaaaaaarrrrrrrr000gggggbbbbbbbb
    shr ax, 3                         // aaaaaaaarrrrrrrr000000gggggbbbbb
    ror eax, 10                       //           aaaaaaaarrrrrrrr000000gggggbbbbb
    shr ax, 9                         //                    aaaaaaaarrrrrgggggbbbbb
    rol eax, 10                       //         aaaaaaaarrrrrggggggbbbbb

    mov word ptr es:[edi], ax

    add esi, 4
    add edi, 2
    dec ecx
    jnz @X15

    jmp @Done


  @X16:

    {todo: mmx 2pixels at a time (is it any faster on real hardware?}

    mov eax, dword ptr ds:[esi]       // aaaaaaaarrrrrrrrggggggggbbbbbbbb

    shr ah, 2                         // aaaaaaaarrrrrrrr00ggggggbbbbbbbb
    shr ax, 3                         // aaaaaaaarrrrrrrr00000ggggggbbbbb
    ror eax, 11                       //            aaaaaaaarrrrrrrr00000ggggggbbbbb
    shr ax, 8                         //                    aaaaaaaarrrrrggggggbbbbb
    rol eax, 11                       //         aaaaaaaarrrrrggggggbbbbb

    mov word ptr es:[edi], ax

    add esi, 4
    add edi, 2
    dec ecx
    jnz @X16

    jmp @Done

  @X24:

    {mmx is
      movq        ARGBARGB
      shl lowd    ARGBRGB0   (if we can, maybe do this on read?)
      shrq 8      0ARGBRGB

      then repeat for another 0ARGBRGB

      then somehow combine into RGBR GBRG BRGB
      then write out the 3 dwords.}


    {probably wrong...}
    {also can be done faster if we just write out 4 pixels at a time (aligned)}
    mov eax, dword ptr ds:[esi]
    mov word ptr [edi], ax
    ror eax, 8
    mov byte ptr es:[edi+2], al

    add esi, 4
    add edi, 3
    loop @X24

    jmp @Done

  @X32:

    cld
    rep movsd
    jmp @Done

  @Done:

    pop es
    popad
    sti
  end;

end;

{-------------------------------------------------}


constructor tScreen.create();
begin
  inherited create();
  backgroundColor.init(0,0,0,255);
  background := nil;
  canvas := nil;
  SHOW_DIRTY_RECTS := false;
  scrollMode := SSM_OFFSET;
  fx := FX_NONE;
  viewport := Rect(0,0);
  resize(videoDriver.width, videoDriver.height);
end;

destructor tScreen.destroy();
begin
  if assigned(canvas) then canvas.free;
  canvas := nil;
  inherited destroy();
end;

procedure tScreen.flipLineToScreen(srcX,srcY,dstX,dstY: int32; pixelCnt: int32);
begin

  case fx of
    FX_NONE: transferLineToScreen(canvas,srcX,srcY,dstX,dstY,pixelCnt);
    FX_SCANLINE: if (dstY and $1) = 0 then
      transferLineToScreen(canvas,srcX,srcY,dstX,dstY,pixelCnt)
    else
      shiftLineToScreen(canvas,srcX,srcY,dstX,dstY,pixelCnt,1,1);
    FX_DOTS: case (dstY and $3) of
      0: shiftLineToScreen(canvas,srcX,srcY,dstX,dstY,pixelCnt,0,1);
      1: shiftLineToScreen(canvas,srcX,srcY,dstX,dstY,pixelCnt,2,1);
      2: shiftLineToScreen(canvas,srcX,srcY,dstX,dstY,pixelCnt,1,0);
      3: shiftLineToScreen(canvas,srcX,srcY,dstX,dstY,pixelCnt,1,2);
    end;
    FX_NOISE:
      noiseLineToScreen(canvas,srcX,srcY,dstX,dstY,pixelCnt);
  end;
end;


{must be called whenever a resolution change occurs after creation.}
procedure tScreen.resize(aWidth: word; aHeight: word);
begin
  if assigned(canvas) then freeAndNil(canvas);
  canvas := tPage.create(aWidth, aHeight);
  case videoDriver.bitsPerPixel of
    15: videoDepth := VD_15;
    16: videoDepth := VD_16;
    24: videoDepth := VD_24;
    32: videoDepth := VD_32;
    else debug.fatal(format('Bit depth %d not supported',[videoDriver.bitsPerPixel]));
  end;

  fillchar(flagGrid, sizeof(flagGrid), 0);

  viewport := Rect(videoDriver.physicalWidth, videoDriver.physicalHeight);
  bounds := Rect(aWidth, aHeight);

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
  i: int32;
  srcX, srcY, dstX, dstY, cnt: integer;
begin
  {todo: support S3 upload (but maybe make sure regions are small enough
   to not cause stutter - S3 is about twice as fast.}
  rect.clipTo(bounds);

  case scrollmode of
    SSM_COPY: begin
      {no need to copy anything offscreen}
      rect.clipTo(viewport);
      srcX := rect.x; srcY := rect.y;
      dstX := rect.x-viewport.x; dstY := rect.y-viewport.y;
    end;
    SSM_OFFSET: begin
      {copy everything}
      srcX := rect.x; srcY := rect.y;
      dstX := rect.x; dstY := rect.y;
    end;
    else fatal('Invalid scroll mode');
  end;

  if (rect.width <= 0) or (rect.height <= 0) then exit;

  cnt := rect.width;
  for i := 0 to rect.height-1 do
    flipLineToScreen(srcX, srcY+i, dstX, dstY+i, cnt);
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
    fatal('background not assigned');
  if background.width <> canvas.width then
    fatal(format('background width must match canvas, %d != %d ', [background.width, canvas.width]));

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
procedure tScreen.markRegion(rect: tRect; flags:word=FG_FLIP+FG_CLEAR); inline;
var
  x,y, x1,x2,y1,y2: integer;
begin
  rect.clipTo(bounds);

  if (rect.width <= 0) or (rect.height <= 0) then exit;

  x1 := rect.x div 8;
  y1 := rect.y div 8;
  x2 := (rect.right-1) div 8;
  y2 := (rect.bottom -1) div 8;

  for y := y1 to y2 do
    for x := x1 to x2 do
      flagGrid[y, x] := flags;
end;

{indicates that a pixel should fliped this frame, and cleared next frame}
procedure tScreen.markPixel(x,y: integer; flags:word=FG_FLIP+FG_CLEAR); inline;
begin
  if (dword(y) >= width) or (dword(x) >= width) then exit;
  flagGrid[y div 8,x div 8] := flags;
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
  for y := 0 to (height div 8)-1 do begin
    rle := 0;
    {todo: fast read in ASM, until we hit first and last non-zero cell}
    for x := 0 to (width div 8)-1 do begin
      if (flagGrid[y, x] and FG_CLEAR) = FG_CLEAR then begin
        if rle = 0 then xStart := x;
        inc(stats.clearCells);
        inc(rle);
        flagGrid[y,x] := (flagGrid[y,x] xor FG_CLEAR) or FG_FLIP;
      end else begin
        if rle > 0 then begin
          clearRegion(Rect(xStart*8, y*8, 8*rle, 8));
          stats.clearRegions += 1;
          rle := 0;
        end;
      end;
    end;
    if rle > 0 then begin
      clearRegion(Rect(xStart*8, y*8, 8*rle, 8));
      stats.clearRegions += 1;
    end;
  end;
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
      {todo: if viewport did not move then copy only changed regions (e.g. from below)}
      for y := 0 to videoDriver.physicalHeight-1 do
        flipLineToScreen(viewport.x, viewport.y+y, 0, y, videoDriver.physicalWidth);
      end;
    SSM_OFFSET: begin
      videoDriver.setDisplayStart(viewport.x, viewport.y);
      for y := 0 to (height div 8)-1 do begin
        rle := 0;
        for x := 0 to (width div 8)-1 do begin
          if (flagGrid[y,x] and FG_FLIP) = FG_FLIP then begin
            if rle = 0 then xStart := x;
            inc(stats.copyCells);
            inc(rle);
            flagGrid[y,x] := (flagGrid[y,x] xor FG_FLIP)
          end else begin
            if rle > 0 then begin
              copyRegion(Rect(xStart*8, y*8, 8*rle, 8));
              stats.copyRegions += 1;
              rle := 0;
            end;
          end;
        end;
        if rle > 0 then begin
          copyRegion(Rect(xStart*8, y*8, 8*rle, 8));
          stats.copyRegions += 1;
        end;
      end;
    end;
    else fatal('Invalid copy mode');
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
  copyRegion(Rect(canvas.width, canvas.height));
end;

{clears the entire page}
procedure tScreen.pageClear();
begin
  clearRegion(Rect(canvas.width, canvas.height));
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
