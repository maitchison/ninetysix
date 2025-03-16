program drawMap;

uses
  uDebug,
  uTest,
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

procedure runTransferSpeedTests();
var
  page: tPage;
  i: integer;
  vidSeg: word;
  pixels: pointer;
begin

  page := tPage.Create(256,256);

  note('Fillrate');

  startTimer('fillrate_system', tmMBS);
  for i := 1 to 10 do
    page.Clear(RGB(rnd, rnd, rnd));
  stopTimer('fillrate_system', 10*page.width*page.height*4);

  startTimer('fillrate_video', tmMBS);
  for i := 1 to 10 do begin
    vidSeg := videoDriver.LFB_SEG;
    asm
      cld
      pushad
      push es
      mov es, VIDSEG

      mov ecx, 256*256
      mov eax, 0
      mov edi, 0
      rep movsd
      pop es
      popad
    end;
  end;
  stopTimer('fillrate_video', 10*256*256*4);

  startTimer('fillrate_video_mmx', tmMBS);
  for i := 1 to 10 do begin
    vidSeg := videoDriver.LFB_SEG;
    asm
      cld
      pushad
      push es
      mov es, VIDSEG

      mov ecx, 256*256
      mov eax, 0
      mov edi, 0
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
  stopTimer('fillrate_video_mmx', 10*256*256*4);

  startTimer('fillrate_s3', tmMBS);
  for i := 1 to 10 do begin
    S3SetFGColor(RGB(rnd, rnd, rnd));
    s3.fillRect(0,0,256,256);
  end;
  stopTimer('fillrate_s3', 10*256*256*4);

  note('Transfer');

  startTimer('sys_to_sys', tmMBS);
  for i := 1 to 10 do begin
    vidSeg := videoDriver.LFB_SEG;
    pixels := page.pixels;

    asm
      cld
      pushad
      mov esi, PIXELS
      mov edi, PIXELS
      add edi, 128*256*4
      mov ecx, 128*256
      rep movsd
      popad
    end;

  end;
  stopTimer('sys_to_sys', 10*128*256*4);

  startTimer('sys_to_vid', tmMBS);
  for i := 1 to 10 do begin
    vidSeg := videoDriver.LFB_SEG;
    pixels := page.pixels;
    asm
      cld
      pushad
      push es
      mov es,  VIDSEG
      mov edi, 0
      mov esi, PIXELS
      mov ecx, 256*256
      rep movsd
      pop es
      popad
    end;
  end;
  stopTimer('sys_to_vid', 10*256*256*4);

  startTimer('vid_to_vid', tmMBS);
  for i := 1 to 10 do begin
    vidSeg := videoDriver.LFB_SEG;
    pixels := page.pixels;
    asm
      cld
      pushad
      push es
      push ds
      mov es,  VIDSEG
      mov ds,  VIDSEG
      mov esi, 0
      mov edi, (128*256*4)
      mov ecx, 128*256
      rep movsd
      pop ds
      pop es
      popad
    end;
  end;
  stopTimer('vid_to_vid', 10*128*256*4);

  startTimer('vid_to_vid (S3)', tmMBS);
  for i := 1 to 10 do begin
    S3CopyRect(0,0,128,0,256,128);
  end;
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

  {this tests the fast path for a=255 pixels, as well as no tint}
  dc := screen.canvas.getDC(bmBlit);
  dc.textureFilter := tfNearest;
  runStretchTest(dc, 'stretch_nearest');

  dc := screen.canvas.getDC(bmBlit);
  dc.textureFilter := tfLinear;
  runStretchTest(dc, 'stretch_linear');


  S3 := tS3Driver.create();
  runTransferSpeedTests();

  readkey;

  videoDriver.setText();
  logTimers();
  printLog(32);

  readkey;

end.
