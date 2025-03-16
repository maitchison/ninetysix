program drawMap;

uses
  uDebug,
  uTest,
  go32,
  uVGADriver,
  uVESADriver,
  uS3Driver,
  uUtils,
  crt,
  uScreen,
  uColor,
  uRect,
  uGraph32,
  uTimer;

var
  testPage: tPage;
  screen: tScreen;
  i: integer;
  dc: tDrawContext;
  S3: tS3Driver;

const
  ITERATIONS = 16;

procedure runFillTest(dc: tDrawContext; tag: string);
var
  i: integer;
  col: RGBA;
  backend: tDrawBackend;
begin
  for backend in [dbREF, dbMMX] do begin
    dc.backend := backend;
    for i := 0 to ITERATIONS-1 do begin
      col.init(rnd, rnd, rnd, rnd);
      startTimer(tag+'_'+BACKEND_NAME[backend]);
      dc.fillRect(Rect(rnd, rnd, 256, 256), col);
      stopTimer(tag+'_'+BACKEND_NAME[backend]);
      if (i mod 4 = 0) then begin
        screen.markRegion(screen.bounds);
        screen.flipAll();
      end;
    end;
  end;
end;

procedure runDrawTest(dc: tDrawContext; tag: string);
var
  i: integer;
  backend: tDrawBackend;
begin
  for backend in [dbREF, dbMMX] do begin
    dc.backend := backend;
    for i := 0 to ITERATIONS-1 do begin
      startTimer(tag+'_'+BACKEND_NAME[backend]);
      dc.drawImage(testPage, Point(rnd, rnd));
      stopTimer(tag+'_'+BACKEND_NAME[backend]);
      if (i mod 4 = 0) then begin
        screen.markRegion(screen.bounds);
        screen.flipAll();
      end;
    end;
  end;
end;

procedure runStretchTest(dc: tDrawContext; tag: string);
var
  i: integer;
  backend: tDrawBackend;
begin
  for backend in [dbREF, dbMMX] do begin
    dc.backend := backend;
    for i := 0 to ITERATIONS-1 do begin
      startTimer(tag+'_'+BACKEND_NAME[backend]);
      dc.stretchSubImage(testPage, Rect(rnd, rnd, 256, 256), Rect(0,0,32,32));
      stopTimer(tag+'_'+BACKEND_NAME[backend]);
      if (i mod 4 = 0) then begin
        screen.markRegion(screen.bounds);
        screen.flipAll();
      end;
    end;
  end;
end;

type
  tBackend = (bSYS, bASM, bMMX);

const
  BACKEND_NAME: array[tBackend] of string = ('sys', 'asm', 'mmx');

procedure fillMemory(backend: tBackend;srcseg:word;srcofs: dword;cnt:dword);
begin
  case backend of
    bSYS: if srcSeg = DSeg then
      fillDword(pointer(srcofs)^, cnt, 0)
    else
      seg_fillword(srcseg, srcofs, cnt*2, 0);
    bASM: asm
      cld
      pushad
      push es
      mov es,  SRCSEG
      mov edi, SRCOFS
      mov ecx, CNT
      mov eax, 0
      rep stosd
      pop es
      popad
    end;
    bMMX: asm
      cld
      pushad
      push es
      mov ax,  SRCSEG
      mov es,  ax
      mov edi, SRCOFS
      mov ecx, CNT
      shr ecx, 2
      por mm0, mm0
    @PIXELLOOP:
      movq es:[edi], mm0
      movq es:[edi+8], mm0
      add edi,16
      dec ecx
      jnz @PIXELLOOP
      pop es
      popad
      emms
    end;
  end;
end;

procedure copyMemory(backend: tBackend;srcSeg:word;srcOfs: dword;dstSeg:word;dstOfs: dword;cnt: dword);
begin
  case backend of
    bSYS: seg_move(srcSeg, srcOfs, dstSeg, dstOfs, cnt*4);
    bASM: asm
      cld
      pushad
      push es
      push ds
      mov ax,  DSTSEG
      mov es,  ax
      mov edi, DSTOFS
      mov ax,  SRCSEG
      mov ds,  ax
      mov esi, SRCOFS
      mov ecx, CNT
      mov eax, 0
      rep movsd
      pop ds
      pop es
      popad
    end;
    bMMX: asm
      cld
      pushad
      push es
      push ds
      mov ax,  DSTSEG
      mov es,  ax
      mov edi, DSTOFS
      mov ax,  SRCSEG
      mov ds,  ax
      mov esi, SRCOFS
      mov ecx, CNT
      shr ecx, 2
      mov eax, 0
    @PIXELLOOP:
      movq mm0, ds:[esi]
      movq mm1, ds:[esi+8]
      movq es:[edi], mm0
      movq es:[edi+8], mm1
      add edi,16
      add esi,16
      dec ecx
      jnz @PIXELLOOP
      pop ds
      pop es
      popad
      emms
    end;
  end;
end;

function getDS(): word; assembler; register;
asm
  mov ax, ds
end;

procedure runTransferSpeedTests();
var
  page: tPage;
  i: integer;
  pixels: dword;
  ds, vidSeg: word;
  backend: tBackend;
begin

  page := tPage.Create(256,256);

  note('Fillrate');

  ds := getDS;
  vidSeg := videoDriver.LFB_SEG;
  pixels := dword(page.pixels);

  for backend in tBackend do begin
    note(BACKEND_NAME[backend]);
    startTimer('fillrate_ram_'+BACKEND_NAME[backend], tmMBS);
    for i := 1 to 10 do fillMemory(backend, ds, pixels, 64*1024);
    stopTimer('fillrate_ram_'+BACKEND_NAME[backend], 10*64*1024*4);

    startTimer('fillrate_vid_'+BACKEND_NAME[backend], tmMBS);
    for i := 1 to 10 do fillMemory(backend, vidSeg, 0, 64*1024);
    stopTimer('fillrate_vid_'+BACKEND_NAME[backend], 10*64*1024*4);
  end;

  startTimer('fillrate (S3)', tmMBS);
  for i := 1 to 10 do begin
    S3SetFGColor(RGB(rnd, rnd, rnd));
    s3.fillRect(0,0,256,256);
  end;
  stopTimer('fillrate (S3)', 10*256*256*4);

  note('Transfer');

  for backend in tBackend do begin
    startTimer('ram_to_ram_'+BACKEND_NAME[backend], tmMBS);
    for i := 1 to 10 do copyMemory(backend, ds, pixels, ds, pixels+32*1024, 32*1024);
    stopTimer('ram_to_ram_'+BACKEND_NAME[backend], 10*32*1024*4);

    startTimer('ram_to_vid_'+BACKEND_NAME[backend], tmMBS);
    for i := 1 to 10 do copyMemory(backend, ds, pixels, vidSeg, 0, 32*1024);
    stopTimer('ram_to_vid_'+BACKEND_NAME[backend], 10*32*1024*4);

    startTimer('vid_to_vid_'+BACKEND_NAME[backend], tmMBS);
    for i := 1 to 10 do copyMemory(backend, vidSeg, 0, vidSeg, 32*1024, 32*1024);
    stopTimer('vid_to_vid_'+BACKEND_NAME[backend], 10*32*1024*4);
  end;

  startTimer('vid_to_vid (S3)', tmMBS);
  for i := 1 to 10 do S3CopyRect(0,0,128,0,256,128);
  stopTimer('vid_to_vid (S3)', 10*128*256*4);
end;

begin

  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    fatal('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    fatal('Requires 1MB video card.');

  videoDriver.setText();
  runTestSuites();

  videoDriver.setTrueColor(800, 600);
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;

  testPage := tPage.Create(256, 256);
  makePageRandom(testPage);

  startTimer('flip'); stopTimer('flip');
(*
  dc := screen.canvas.getDC(bmBlit);
  runFillTest(dc, 'fill_blit');

  dc := screen.canvas.getDC(bmBlend);
  runFillTest(dc, 'fill_blend');

  dc := screen.canvas.getDC(bmBlit);
  runDrawTest(dc, 'draw_blit');

  dc := screen.canvas.getDC(bmBlit);
  dc.tint := RGB(255,128,64);
  runDrawTest(dc, 'draw_tint');

  dc := screen.canvas.getDC(bmBlend);
  dc.tint := RGB(255,128,64,128);
  runDrawTest(dc, 'blend');

  {this tests the fast path for a=255 pixels, as well as no tint}
  dc := screen.canvas.getDC(bmBlend);
  runDrawTest(dc, 'blend_fast');
  *)

  (*
  {this tests the fast path for a=255 pixels, as well as no tint}
  dc := screen.canvas.getDC(bmBlit);
  dc.textureFilter := tfNearest;
  runStretchTest(dc, 'stretch_nearest');

  dc := screen.canvas.getDC(bmBlit);
  dc.textureFilter := tfLinear;
  runStretchTest(dc, 'stretch_linear');
  *)

  S3 := tS3Driver.create();
  runTransferSpeedTests();

  readkey;

  videoDriver.setText();
  logTimers();
  printLog(32);

  readkey;

end.
