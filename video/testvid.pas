{(the old) Test Video (and image) compression.}
program testvid;

{scores:
Start: 88.97 (0.25s to compress, 28.74 db)

146: Single interpolation color!
86.92: Higher precision interpolation colors (used to be rounded one bit)
317: Corner colors...
1815: Uniform block
54.3: Color optimization (100 rounds)! Wow did this make a big difference
  Took 50 seconds to encode though, also PSNR is now at 30.7 DB
53.3: Change one dim at a time, and tuning to SA... gains from here are hard come by.
77.2: 10 optimization steps (4 seconds to compress)
50.8: 400 steps (170s), this is just far too slow.
59.5: 50 steps (21s)
56.5: AllPairs (approx 128 evaluations) (32s).

57.8: Iterative, new optimizations, (7.7 s.) Slightly worse though...
50.3: 30 steps using descent (8.5s)
50.8: 10 steps using descent (3s)
50.7: 10 steps with MMX EvaluateSSE (1.6s)
51.7: 10 steps with MMX EvaluateSSE (0.9s) << goal reached :)
60.7: 16bit mode... not too bad I guess
}

{todo:
Optimize so we can do 100 steps (which seems like a good tradeoff),
over image in less than a second,}



{$mode DELPHI}

uses
  debug,
  utils,
  mouse,
  keyboard,
  graph32,
  graph2d,
  patch,
  font,
  gui,
  stream,
  screen,
  vga,
  vesa
  ;

TYPE
  TColorSelectionMode = (MinMax, Iterative, Descent, AllPairs);


CONST
  MAX_OPTIMIZATION_STEPS = 5;
  ALPHA = 0.95;
  T0 = 100;

  COLOR_SELECTION_MODE: TColorSelectionMode = Descent;

var
  startTime: double;
  elapsed: double;

  imgOrg, imgCmp, imgErr: TPage;

  canvas: TPage;
  totalSSE: int64 = 0;
  totalPixels: int64 = 0;
  totalBytes: int32 = 0;
  totalCompressTime: double = 0;
  totalDecompressTime: double = 0;
  outStream: tStream;

  currentPatch: integer = 0;

type
  DynamicArray = Array of Integer;

type
  TByteDeltaMapping = record
    BitWidth: byte;
    {encode a byte delta into a code}
    encode: array[-255..255] of byte;
    {decode the delta}
    decode: array of integer;
    procedure init(ADecodeTable: DynamicArray);
    procedure print();
  end;

var
  MAP5BIT: TByteDeltaMapping;
  MAP6BIT: TByteDeltaMapping;
  MAP7BIT: TByteDeltaMapping;
  MAP8BIT: TByteDeltaMapping;


{---------------------------------------------------------------}
{ Mappings }
{---------------------------------------------------------------}

{Creates a table going from 1 to 255 using a power curve}
function GenerateEncodeTable(n: integer;k: double=2.0): DynamicArray;
var
  x: double;
  y: integer;
  arr: Array of Integer;
  i: integer;
begin
  SetLength(arr, n);
  for i := 1 to n do begin
    x := Power(i / (n), k) * 255;
    y := trunc(x);
    if frac(x) > 0 then inc(y);
    {Make sure we never output y < i, otherwise non-monotonic}
    if y < i then y := i;
    arr[i-1] := y
  end;
  result := arr;
end;

procedure TByteDeltaMapping.print();
var
  i: integer;
begin
  for i := 0 to Length(Decode)-1 do begin
    WriteLn(Format('%d -> %d', [i, Decode[i]]));
  end;
  {
  for i := -7 to 7 do begin
    WriteLn(Format('%d -> %d = %d', [i, Encode[i], Decode[Encode[i]]]));
  end;}
end;

function sign(x: integer): integer;
begin
  if x < 0 then exit(-1);
  if x > 1 then exit(1);
  exit(0);
end;


procedure TByteDeltaMapping.init(ADecodeTable: DynamicArray);
var
  i, j: integer;
  elements: integer;
  bestMatch: byte;
  bestMatchError: integer;
  ThisError: integer;
const
  {
  If true, forces match to have property that |x| <= |F'F(x))|
  }
  ROUND_TOWARDS_ZERO = False;
begin
  Elements := Length(ADecodeTable);
  SetLength(Decode, Elements*2);

  {we interleave positive and negative deltas so that the encodings are
   roughtly in probability order.}

  for i := 0 to Elements-1 do begin
    Decode[i*2+1] := ADecodeTable[i];
    if i < Elements-1 then
      Decode[i*2+2] := -ADecodeTable[i];
  end;

  {find inverse
   we could do this more efficently, but for small tables it'll be fine.
   (i.e. we could build it while creating the decode table but this
   would require montonic input.
   }
  for i := -255 to +255 do begin
    bestMatchError := abs(i);
    bestMatch := 0;
    for j := 0 to (Elements*2)-1 do begin
      thisError := (i - integer(Decode[j]));
      if ROUND_TOWARDS_ZERO and (thisError*sign(i) < 0) then continue;
      thisError := abs(thisError);
      if thisError < bestMatchError then begin
        bestMatchError := thisError;
        bestMatch := j;
      end;
    end;
    Encode[i] := bestMatch;
  end;

end;

{todo: remove this, and use screen}
procedure draw(page: tPage; atX, atY: int32);
var
  y: integer;
  ScreenOffset: dword;
  ImageOffset: dword;
  lfbSeg: word;
  pageWidth: word;
begin
  {note: not very safe if clipping occurs}
  ScreenOffset := (atX + (atY * videoDriver.width)) * 4;
  ImageOffset := dword(page.Pixels);
  lfbSeg := videoDriver.LFB_SEG;
  pageWidth := page.width;
  for y := 0 to page.Height-1 do begin
    asm
      pushad
      push es

      mov es,  LFBSEG
      mov edi, ScreenOffset
      mov esi, ImageOffset
      xor ecx, ecx
      mov cx,  PAGEWIDTH

      rep movsd

      pop es
      popad

    end;
    screenOffset += videoDriver.width*4;
    imageOffset += page.width*4;
  end;
end;

procedure DrawX(src, dst: TPage; atX, atY: int32; scale: integer);
var
  x,y: integer;
  i,j: integer;
  c: RGBA;
begin
  for y := 0 to src.height-1 do
    for x := 0 to src.width-1 do begin
      c := src.GetPixel(x,y);
      for i := 0 to scale-1 do
        for j := 0 to scale-1 do
          dst.putPixel(atX+(x*scale)+j, atY+(y*scale)+i, c);
    end;
end;

procedure Draw2X(src, dst: TPage; atX, atY: int32);
var
  y: integer;
  srcOffset, dstOffset: dword;
  srcWidth, dstWidth: word;
begin
  {note: not very safe if clipping occurs}
  dstOffset := dword(dst.Pixels) + (atX + (atY * dst.width)) * 4;
  srcOffset := dword(src.Pixels);
  srcWidth := src.width;
  dstWidth := dst.width;
  for y := 0 to src.height-1 do begin
    asm
      pushad

      mov esi, srcOffset
      mov edi, dstOffset

      mov cx,  SRCWIDTH

      xor ebx, ebx
      mov bx,  DSTWIDTH
      shl ebx, 2

    @LOOP:

      mov eax, [esi]
      mov [edi], eax
      mov [edi+ebx], eax
      add edi, 4
      mov [edi], eax
      mov [edi+ebx], eax
      add edi, 4
      add esi, 4

      dec cx
      jnz @LOOP

      popad

    end;
    srcOffset += src.width*4;
    dstOffset += dst.width*4*2;
  end;
end;


(*
procedure process(x,y: integer);
var
  patch: TPatch;
begin
  x := x shr 1; y := y shr 1;
  if (x < 0) or (y < 0) then exit;
  if (x > 320) or (y > 180) then exit;
  x := x div 4 * 4;
  y := y div 4 * 4;
  patch.ReadFrom(img, x, y);
  patch.SelectColors();
  patch.Map();
  lastSSE := patch.Apply();
end;

procedure restore(x,y: integer);
var
  patch: TPatch;
begin
  x := x shr 1; y := y shr 1;
  if (x < 0) or (y < 0) then exit;
  if (x > 320) or (y > 180) then exit;
  x := x div 4 * 4;
  y := y div 4 * 4;
  patch.ReadFrom(img, x, y);
  patch.WriteTo(canvas, x, y);
end; *)

var
  xofs,yofs: integer;
  table: DynamicArray;

{Returns true if there is more work to be done.}
function ProcessNextPatch(): boolean;
var
  patch: TPatch;
  px,py: integer;
  i: integer;
  startTime: double;
begin

  {todo: check this is really the correct last patch.}
  if CurrentPatch >= 45*80 then
    exit(False);

  px := CurrentPatch mod 80;
  py := CurrentPatch div 80;
  patch := TPatch.Create(imgOrg, px*4, py*4, PCD_24);

  startTime := getSec;
  patch.Map();

  case COLOR_SELECTION_MODE of
    MinMax:
      patch.SolveMinMax();
    Iterative: begin
      {an ok starting point}
      patch.SolveMinMax();
      for i := 1 to MAX_OPTIMIZATION_STEPS do
        patch.SolveIterative(T0*Power(ALPHA,i));
      end;
    Descent: begin
      patch.SolveMinMax();
      patch.SolveDescent(MAX_OPTIMIZATION_STEPS);
    end;
    AllPairs:
      patch.SolveAllPairs();
  end;

  patch.Map();
  totalCompressTime += (getSec-startTime);

  startTime := getSec;
  patch.WriteTo(imgCmp);
  totalDecompressTime += (getSec-startTime);

  {apply error}
  patch.WriteErrorTo(imgErr);

  {accounting}
  totalSSE += patch.LastSSE;
  totalPixels += 16;

  patch.writeBytes(outStream);

  inc(CurrentPatch);
end;

function CurrentMSE(): double;
begin
  if totalPixels = 0 then exit(-1);
  result := totalSSE/TotalPixels;
end;

function CurrentPSNR(): double;
begin
  result := 10 * Log10((Power(255, 2)) / CurrentMSE);
end;

function CurrentCompression(): double;
var
  UncompressedSize: integer;
begin
  if outStream.len = 0 then exit(-1);
  UncompressedSize := TotalPixels*3;
  result := UncompressedSize / outStream.len;
end;

var
  VIEW_MODE: byte = 2;
  selectedPatch: TPatch;
  selectedMSE: double;
  zoomPanel: TPage;
  SelectedTemperature: double;
  SelectedRounds: int32;

procedure ProcessOptimization();
begin
  SelectedPatch.SolveIterative(SelectedTemperature);
  SelectedTemperature *= ALPHA;
  inc(SelectedRounds);
end;

procedure SelectPatchAt(atX,atY: integer);
var
  x,y: integer;
begin
  atX := atX div 4 * 4;
  atY := atY div 4 * 4;
  Info(Format('Selected patch at %d,%d', [atX, atY]));
  SelectedPatch.ReadFrom(imgOrg, atX, atY);
  SelectedPatch.SolveDescent();
  SelectedPatch.Map();
  for y := 0 to 3 do
    for x := 0 to 3 do
      zoomPanel.PutPixel(x+1, y+1, SelectedPatch.Pixels[y,x]);
  SelectedPatch.WriteTo(zoomPanel, 1+5, 1);
  SelectedPatch.WriteErrorTo(zoomPanel, 1+10, 1);
  selectedMSE := SelectedPatch.LastSSE / 16;
end;

procedure RunBenchmark();
var
  startTime: double;
  i: integer;
  a,b: int32;
const
  NUM_UPDATES = 100;
begin

  videoDriver.setText();

  SelectPatchAt(100, 52);
  SelectedPatch.SolveMinMax();
  SelectedPatch.Map();
  a := SelectedPatch.LastSSE;
  b := SelectedPatch.EvaluateSSE(SelectedPatch.color);

  Info(Format('Errors are %d %d', [a,b]));


  StartTime := getSec;
  for i := 1 to NUM_UPDATES do
    SelectedPatch.SolveIterative();

  Info(Format('%fk updates per second.', [NUM_UPDATES / (getSec-StartTime) / 1000]));

  PrintLog();

end;

{Just to have a closer look at the descent algorithm}
procedure RunDescent();
var
  startTime: double;
  i: integer;
  a,b: int32;
begin

  {Set high-res text mode}
  asm
{    mov ax,$4F02
    mov bx,$0100
    int $10}
    mov ax, $10C
    int $10
  end;


  SelectPatchAt(100, 52);
  SelectedPatch.SolveMinMax();
  SelectedPatch.Map();

  SelectedPatch.SolveDescent(100);

  PrintLog(30);

  repeat
    until keyDown(key_q);


end;

procedure Init();
begin
  Randomize;

  MAP5BIT.init(GenerateEncodeTable(16));
  MAP6BIT.init(GenerateEncodeTable(32));
  MAP7BIT.init(GenerateEncodeTable(64));
  {8 bit mapping is a bit better if we do piecewise linear with
   slope +1 at x=15, and x=110}
  MAP8BIT.init(GenerateEncodeTable(128));

  startTime := now;
  imgOrg := LoadBMP('..\masters\video\frames_0001.bmp');

  imgCmp := TPage.Create(imgOrg.Width, imgOrg.Height);
  imgErr := TPage.Create(imgOrg.Width, imgOrg.Height);

  canvas := TPage.Create(640, 480);

  zoomPanel := TPage.Create(16, 6);

  elapsed := frac(now - startTime) * (24*60*60);

  Info(Format('Read file in %f seconds', [elapsed]));
  Info(Format('Source image is %dx%d', [imgOrg.width, imgOrg.height]));

end;

procedure RunMainLoop();
var
  LFBSEG: word;
  canvasPixels: pointer;
begin

  canvasPixels := canvas.pixels;

  enableVideoDriver(tVesaDriver.create());
  videoDriver.setMode(640,480,32);
  LFBSEG := videoDriver.LFB_SEG;

  InitMouse();

  asm
    push es
    pusha
    mov edi, canvas.pixels
    mov ecx, 640*480
    mov eax, $0007F00;
    rep stosd
    popa
    pop es
    end;

  {set current selected patch}
  SelectPatchAt(100, 52);

  {setup output stream}
  outStream := tStream.create();

  {show uncompressed image}
  xofs := (640-(320*2)) div 2;
  yofs := (480-(180*2)) div 2;
  Draw2X(imgOrg, canvas, xofs, yofs);

  repeat

    startTime := getSec;
    while getSec < (startTime + 0.050) do
      if not ProcessNextPatch() then break;

    {draw gui}
    GUILabel(canvas, 10, 10, Format('MSE %f PSNR %f @%f:1', [currentMSE, currentPSNR, currentCompression]));
    GUILabel(canvas, 10, 40, Format('Selected MSE %f (%d steps)', [SelectedMSE, SelectedRounds]));

    if keyDown(key_1) then
      VIEW_MODE := 1;
    if keyDown(key_2) then
      VIEW_MODE := 2;
    if keyDown(key_3) then
      VIEW_MODE := 3;

    case VIEW_MODE of
      1: Draw2X(imgOrg, canvas, xofs, yofs);
      2: Draw2X(imgCmp, canvas, xofs, yofs);
      3: Draw2X(imgErr, canvas, xofs, yofs);
    end;

    {select patch under cursor when mouse down}
    if Mouse_B = 1 then begin
      SelectPatchAt((Mouse_X - xofs) div 2, (Mouse_Y - yofs) div 2);
      {hilight selected patch}
      canvas.fillRect(
        TRect.Create(SelectedPatch.atX*2+xofs, SelectedPatch.atY*2+yofs, 8, 8),
        RGBA.Create(255,0,255,127)
      );
    end;


    {show zoom pannel}
    DrawX(zoomPanel, canvas, 400, 8, 8);

    {flip page}
    asm
      pushad
      push es
      mov es,  LFBSEG
      mov edi,  0
      mov esi, CANVASPIXELS
      mov ecx, 640*480
      rep movsd
      pop es
      popad
      end;

    until keyDown(Key_Q) or keyDown(Key_ESC);

  Info(Format('PSNR was %fdb', [currentPSNR]));
  Info(Format('MSE was %f', [currentMSE]));
  Info(Format('Compression took %fs', [totalCompressTime]));
  Info(Format('Decompression took %fs', [totalDecompressTime]));

  outStream.writeToFile('out.dat');

  videoDriver.setText();

  PrintLog();

end;

begin
  InitKeyboard();
  Init();
  {RunBenchmark();}
  RunMainLoop();
  {RunDescent();}
end.
