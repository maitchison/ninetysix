Unit Patch;

{$MODE DELPHI}

interface

uses
  test,
  debug,
  utils,
  stream,
  graph32;


type

  TPatchColors = packed array[0..3] of RGBA;
  TPatchIndexes = packed array[0..3, 0..3] of byte;

  TPatchColorDepth = (PCD_VLC, PCD_24,PCD_16);

  TPatch = record

    ColorDepth: TPatchColorDepth;

    atX,atY: integer;
    LastSSE: int32;
    color: TPatchColors;
    pixels: packed array[0..3, 0..3] of RGBA;
    idx: TPatchIndexes;
    grad: array[0..3] of RGBA16;
    counts: array[0..3] of integer;
    proposedIdx: TPatchIndexes;

    Constructor Create(img: TPage; atX, aty: integer; AColorDepth: TPatchColorDepth=PCD_24);

    procedure ReadFrom(img: TPage; atX, atY: integer);

    procedure WriteTo(img: TPage; atX,atY: integer); overload;
    procedure WriteErrorTo(img: Tpage; atX, atY: integer); overload;
    procedure WriteTo(img: TPage); overload;
    procedure WriteErrorTo(img: Tpage); overload;

    function  EvaluateSSE(newColors: TPatchColors): int32;
    procedure Map();
    procedure InterpolateColors();
    function  GetError(x,y: integer): integer; inline;

    procedure SolveMinMax();
    procedure SolveIterative(temperature: double=1.0);
    procedure SolveDescent(steps: integer=30;momentium:single=0.9);
    procedure SolveAllPairs();

    procedure writeBytes(dst: tStream);
  end;

implementation

Constructor TPatch.Create(img: TPage; atX, aty: integer; AColorDepth: TPatchColorDepth=PCD_24);
begin
  ColorDepth := AColorDepth;
  ReadFrom(img, atX, atY);
end;

{Outputs patch bytes.}
procedure TPatch.writeBytes(dst: tStream);
var
  i: integer;
  data: array[0..5] of dword;
begin
  {note: patch bytes exclude type, as this it stored elsewhere}

  case ColorDepth of
    PCD_VLC: begin
      data[0] := color[0].r;
      data[1] := color[0].g;
      data[2] := color[0].b;
      data[3] := color[1].r;
      data[4] := color[1].g;
      data[5] := color[1].b;
      dst.writeVLCSegment(data);
    end;
    PCD_24:
      for i := 0 to 1 do begin
        dst.writeByte(color[i].r);
        dst.writeByte(color[i].g);
        dst.writeByte(color[i].b);
      end;
    PCD_16:
      for i := 0 to 1 do
        dst.writeWord(color[i].to16);
  end;

  for i := 0 to 3 do
    dst.writeByte(idx[i,0] or (idx[i,1] shl 2) or (idx[i,2] shl 4) or (idx[i,3] shl 6));

end;

procedure TPatch.InterpolateColors();
var
  r,g,b: integer;
  i: integer;
begin

  {apply quantization here}
  {note: interpolated colors need not be quantized}
  case ColorDepth of
    PCD_24: {pass};
    PCD_16: begin
      for i := 0 to 1 do begin
        color[i].r := color[i].r shr 3 shl 3;
        color[i].g := color[i].g shr 2 shl 2;
        color[i].b := color[i].b shr 3 shl 3;
      end;
    end;
  end;

  {compute 0.33 * a + 0.67 * b, but in integer math}
  color[2].r := (color[0].r * 85 + color[1].r * 171) shr 8;
  color[2].g := (color[0].g * 85 + color[1].g * 171) shr 8;
  color[2].b := (color[0].b * 85 + color[1].b * 171) shr 8;
  color[3].r := (color[0].r * 171 + color[1].r * 85) shr 8;
  color[3].g := (color[0].g * 171 + color[1].g * 85) shr 8;
  color[3].b := (color[0].b * 171 + color[1].b * 85) shr 8;
  color[2].a := 255;
  color[3].a := 255;


end;

function sqr(x: integer): integer; inline;
begin
  result := x*x;
end;

function max(a,b: int32): int32; inline;
begin
  result := a;
  if b > a then result := b;
end;

function min(a,b: int32): int32; inline;
begin
  result := a;
  if b < a then result := b;
end;

{picks two colors to use for this patch}
procedure TPatch.SolveMinMax();
var
  cMin, cMax: RGBA;
  r,g,b: integer;
  x,y: integer;
  l: integer;
  lMin, lMax: integer;
  c: RGBA;
begin
  {simple strategy, sort by brightness and take min/max}
  r := 0; g := 0; b := 0;
  lMin := 999;
  lMax := -1;
  for y := 0 to 3 do
    for x := 0 to 3 do begin
      c := Pixels[y,x];
      l := c.r+c.g+c.b;
      if l > lMax then begin
        lMax := l;
        cMax := c;
      end;
      if l < lMin then begin
        lMin := l;
        cMin := c;
      end;
    end;
  color[0] := cMin;
  color[1] := cMax;

  InterpolateColors();
end;

{returns a random integer from -15 to +15}
function jitter: integer;
begin
  result := rnd and $0f;
  if rnd and $1 = $1 then result := -result;
end;

function bump(c: RGBA): rgba;
begin
  result.init(c.r+jitter, c.g+jitter, c.b+jitter);
end;

{Try all color pairs, and set the best one}
procedure TPatch.SolveAllPairs();
var
  i,j: integer;
  ThisError, BestError: int32;
  bestColors: TPatchColors;
begin
  BestError := 999999;
  for i := 0 to 15 do begin
    color[0] := self.pixels[i and $3, i shr 2];
    for j := i to 15 do begin
      color[1] := self.pixels[j and $3, j shr 2];
      self.InterpolateColors();
      ThisError := EvaluateSSE(self.color);
      if ThisError < BestError then begin
        BestError := ThisError;
        BestColors := self.color;
      end;
    end;
  end;
  self.color := BestColors;
end;

{
performance
Start: 8k / second.
11k: Release mode
11k: Back to debug mode, but calculate SSE during Map()
14k: Faster revert
17k: Inline squared error function
18k: Faster path for reject (but slower for accept)
21k: Also improved path for accept
54k: MMX EvaluateSSE
48k: Also write out proposed indices
}


{Move colors around a little to see if we can improve things}
procedure TPatch.SolveIterative(temperature: double=1.0);
var
  oldColors: TPatchColors;
  oldSSE, newSSE: integer;
  probKeep: double;
  roll: double;
  delta: integer;
  keep: boolean;
begin
  oldColors := color;
  oldSSE := self.LastSSE;
  case rnd mod 6 of
    0: color[0].init(color[0].r+jitter, color[0].g, color[0].b);
    1: color[0].init(color[0].r, color[0].g+jitter, color[0].b);
    2: color[0].init(color[0].r, color[0].g, color[0].b+jitter);
    3: color[1].init(color[1].r+jitter, color[1].g, color[1].b);
    4: color[1].init(color[1].r, color[1].g+jitter, color[1].b);
    5: color[1].init(color[1].r, color[1].g, color[1].b+jitter);
  end;
  self.InterpolateColors();

  newSSE := self.EvaluateSSE(self.color);

  delta := newSSE - oldSSE;

  if delta <= 0 then begin
    keep := True;
  end else begin
    {Error got worse... so consider taking this only if temp is high.}
    probKeep := exp(-(delta / temperature));
    roll := Random(1000000) / 1000000;
    keep := roll < probKeep;
  end;

  if keep then begin
    self.idx := self.proposedIdx;
  end else begin
    {reject move}
    self.color := oldColors;
    self.lastSSE := oldSSE;
  end;
end;

{returns squared error between two colors, with 0 being an exact match.}
function SE(a, b: RGBA): int32; inline;
begin
  result := sqr(a.r-b.r) + sqr(a.g-b.g) + sqr(a.b-b.b);
end;

procedure TPatch.Map();
begin
  {evaluation proposes ids, so just use those}
  self.EvaluateSSE(self.color);
  self.idx := self.ProposedIdx;
end;

function TPatch.GetError(x,y: integer): int32;
var
  s, d: RGBA;
  err: int32;
begin
  s := pixels[y,x];
  d := color[idx[y,x]];
  err := 0;
  err += sqr(int32(s.r) - d.r);
  err += sqr(int32(s.g) - d.g);
  err += sqr(int32(s.b) - d.b);
  result := err;
end;


{Evaluates given colors on this patch, returns SSE}
{does not require idx to already be set, but instead sets proposedIdx to
 what would have been used}
function EvaluateSSE_REF(var patch: TPatch; newColors: TPatchColors): int32;
var
  x,y: integer;
  i: integer;
  col: RGBA;
  Score: int32;
  BestScore: int32;
  BestI: byte;
  TotalError: int32;
begin
  fillchar(patch.grad, sizeof(patch.grad), 0);
  fillchar(patch.counts, sizeof(patch.counts), 0);
  TotalError := 0;
  for y := 0 to 3 do
    for x := 0 to 3 do begin

      col := patch.pixels[y,x];
      BestScore := $FFFFFF;

      BestI := 0;

      for i := 0 to 3 do begin
        Score := SE(patch.color[i], col);
        BestScore := min(BestScore, Score);
        if Score = BestScore then BestI := i;
      end;

      patch.proposedIdx[y,x] := BestI;
      TotalError += BestScore;

      {update grad}
      patch.grad[BestI].r += (patch.color[BestI].r - col.r);
      patch.grad[BestI].g += (patch.color[BestI].g - col.g);
      patch.grad[BestI].b += (patch.color[BestI].b - col.b);
      inc(patch.counts[BestI]);

    end;
  result := TotalError;

end;

{Evaluates given colors on this patch, returns SSE}
function EvaluateSSE_ASM(var self: TPatch; newColors: TPatchColors): int32;
var
  MMXRegister: uint64; {note: would be good to 8byte align this}
  MMXDeltas: uint64;
  PixelsAddr: pointer; {todo: figure out how I can avoid these pointers}
  ColorsAddr: pointer;
  GradAddr: pointer;
  ProIdxAddr: pointer;
  BestError: dword;
  TotalError: int32;
  BestI: dword;
begin

  {todo: test this for overflows, especially when delta is < -127}

  fillchar(self.grad, sizeof(self.grad), 0);

  PixelsAddr := @self.pixels;
  ColorsAddr := @NewColors;
  ProIdxAddr := @self.proposedIdx;
  GradAddr := @self.grad;

  TotalError := 0;

  asm
    pusha

    mov ecx, 16

    mov edi, [PixelsAddr]

    {
      EAX: pixel
      EDX: color
      ECX: Loop

      EDI: Pixels[y,x]

      MM0: Zero register
    }

    pxor mm0, mm0

  @OUTER_LOOP:

    push ecx

    mov eax, $FFFFFF
    mov [BestError], eax

    {read pixel}
    mov eax, edi[ecx*4-4]

    mov ecx, 4

    {set MM2 with packed pixel colors}
    movd       mm2, eax      // MM2 <-  0000|ARGB
    punpcklbw mm2, mm0      // MM2 <-  0A0R|0G0B (d)

  @INNER_LOOP:

    {calculate sum of squared error for this option}
    mov edx, NewColors[ecx*4-4]
    movd       mm1, edx      // MM1 <-  0000|ARGB
    punpcklbw mm1, mm0      // MM1 <-  0A0R|0G0B (s)
    psubw     mm1, mm2      // MM1 <-  s-d
    {absolute difference means we won't run into overflow when we square}
    {an alternative would be to do the full 32bit multiply}
    movq      mm4, mm1      // MM4 <- s-d (save for later)
    movq      mm3, mm1
    psraw      mm3, 15        // get sign bit
    pxor      mm1, mm3
    psubw      mm1, mm3
    pmullw    mm1, mm1      // (s-d)^2
    {horizontal sum}
    movq [MMXRegister], mm1
    movzx eax, word ptr [MMXRegister+0]
    movzx edx, word ptr [MMXRegister+2]
    add eax, edx
    movzx edx, word ptr [MMXRegister+4]
    add eax, edx

    {check if this is best}
    cmp eax, [BestError]

    jae @SKIP_SET

  @DO_SET:
    mov [BestError], eax
    xor ebx, ebx
    mov bl, cl
    dec  bl
    mov [BestI], ebx
    movq mm5, mm4            // MM5 <- (s-d) for best selection

  @SKIP_SET:

    dec ecx
    jnz @INNER_LOOP

    {---- house keeping... ---}

    pop ecx

    push edi

    {write the index out}
    mov edi, [ProIdxAddr]
    mov ebx, [BestI]
    mov byte ptr edi[ecx-1], bl

    {update grad}
    {
      ebx=BestI
      mm5=(s-d) (for best color)
    }
    mov   edi, [GradAddr]
    paddw mm5, [edi+ebx*8]
    movq  [edi+ebx*8], mm5

    pop edi

    {BestError is now set correctly}
    mov eax, [TotalError]
    add eax, [BestError]
    mov [TotalError], eax

    dec ecx
    jnz @OUTER_LOOP

    emms
    popa
  end;

  result := TotalError;
end;

function TPatch.EvaluateSSE(newColors: TPatchColors): int32;
begin
  lastSSE := EvaluateSSE_Asm(self, newColors);
  result := lastSSE;
end;

procedure TPatch.SolveDescent(steps: integer=30; momentium: single=0.9);
var
  n: integer;
  orgPos: array[0..1] of RGBA32;
  currentPos: array[0..1] of RGBA32;
  currentGrad: array[0..1] of RGBA32;
  velocity: array[0..1] of RGBA32;
  i: integer;
  j: integer;
  lr: single;
  cnt: single;
  w: single;
  bestSSE: dword;
  bestColors: TPatchColors;
const weights: array[0..1, 0..3] of single = (
  (1, 0, 1/3, 2/3),
  (0, 1, 2/3, 1/2)
);


begin

  BestSSE := $FFFFFF;

  for i := 0 to 1 do begin
    currentPos[i] := self.color[i];
    orgPos[i] := currentPos[i];
  end;

  fillchar(momentium, sizeof(momentium), 0);

  for n := 0 to steps-1 do begin

    {calculate gradient}
    EvaluateSSE(self.color);

    {memorize the best result}
    if self.LastSSE < BestSSE then begin
      BestSSE := self.LastSSE;
      BestColors := self.Color;
    end;

    lr := 0.2*(1-(n/steps));

    {compile gradients according to weight}
    {this is because we have 4 colors, but we can only move 2 of them}
    fillchar(currentGrad, sizeof(currentGrad), 0);
    for i := 0 to 1 do
      for j := 0 to 3 do
        currentGrad[i] += RGBA32(grad[j]) * weights[i][j];

    {apply gradient}
    if momentium <= 0 then begin
      {standard sgd}
      for i := 0 to 1 do
        currentPos[i] += currentGrad[i] * -lr;
    end else begin
      {momentium}
      for i := 0 to 1 do begin
        if n = 1 then
          velocity[i] := currentGrad[i]
        else
          velocity[i] := (velocity[i] * momentium) + currentGrad[i];
        currentPos[i] += velocity[i] * -lr;
      end;
    end;

    {logging}
    (*
    for i := 0 to 0 do begin
      {Info(Format('[%d] P:%s V:%s L:%d', [n, currentPos[i].ToString, momentium[i].ToString, self.LastSSE]));}
      Info(Format('[%d] %d %d', [n, BestSSE, self.LastSSE]));
    end;
    *)

    {round to nearest color}
    for i := 0 to 1 do
      self.color[i] := currentPos[i];
    self.InterpolateColors();

  end;

  {final evaluation}
  EvaluateSSE(self.color);
  if self.LastSSE >= BestSSE then begin
    {restore best color}
    self.color := BestColors;
    self.lastSSE := BestSSE;
  end;

end;

procedure TPatch.ReadFrom(img: Tpage; atX, atY: integer);
var
  x,y: integer;
begin
  self.atX := atX;
  self.atY := atY;
  for y := 0 to 3 do
    for x := 0 to 3 do
      pixels[y,x] := img.GetPixel(atX+x, atY+y);
end;

procedure TPatch.WriteTo(img: Tpage); overload;
begin
  writeTo(img, self.atX, self.atY);
end;

(*
{just a bit of scratch space to work out how the decoder will look}
procedure WritePatchAbs_ASM(pixelsPtr: pointer; pixelsStride: int32; patch: tPage);
begin

  {note: to get to this point we would need to decode the frame, which
   if using VLC is slow... so maybe don't do that? Or simply it a lot}

  {absolute decoder, this should be very fast}

  {inputs:}
  {BASECOLORS should be array of 2 dwords}
  {ONETHIRD should be 65536/3 = 11855}

  asm
    pushad

    {
      ----------------------------
      Color Interpolation
      ----------------------------

      Input is 2 RGB color values
      output is 4 RGB color values

      ESI
      EDI

      EAX
      EBX
      ECX
      EDX

      MM0   tmp
      MM1   A
      MM2   B
      MM3   A*0.33
      MM4   B*0.33
      MM5   A*0.66
      MM6   B*0.66
      MM7   ONETHIRD


    }

      movd      mm0, BASECOLORS[0]
      pxor      mm1, mm1
      punpcklbw mm0, mm1                  // mm1 = [A] 0a0r0g0b

      movd      mm0, BASECOLORS[4]
      pxor      mm2, mm2
      punpcklbw mm0, mm2                  // mm2 = [B] 0a0r0g0b

      movq      mm7, ONETHIRD

      movq      mm3, mm1
      pmulhw    mm3, mm7                  // mm3 = 0.33 * A
      movq      mm4, mm2
      pmulhw    mm4, mm7                  // mm4 = 0.33 * B

      psllw     mm7

      movq      mm5, mm1
      pmulhw    mm5, mm7                  // mm5 = 0.66 * A
      movq      mm6, mm2
      pmulhw    mm6, mm7                  // mm6 = 0.66 * B

      {write out the values}
      packuswb  mm1, mm1
      movd      COLORS[0], mm1
      paddw     mm5, mm4                  // mm5 = 0.66A+0.33B
      packuswb  mm5, mm5
      movd      COLORS[1], mm5
      paddw     mm6, mm3                  // mm6 = 0.33A+0.66B
      packuswb  mm6, mm6
      movd      COLORS[2], mm6
      packuswb  mm2, mm2
      movd      COLORS[3], mm1

      //mm1 = [A]rgba [B]rgba

    {
      ----------------------------
      Write out values
      ----------------------------

      ESI   Color
      EDI   PixelsPtr

      EAX   tmp (used for pixel color)
      EBX   used for index into color
      ECX   loop
      EDX   indices
    }

    mov esi, IDX
    mov edx, [esi]
    mov esi, COLOR
    mov edi, PIXELS

    mov ecx, 4

    xor ebx, ebx

    {I think I could interleave these to get close to 2x perfomance?
     this would take a few registers though}
  @ROW_LOOP:
    mov bl, dl
    and bl, $03
    mov eax, [esi+ebx*4]
    shr edx, 2
    mov [edi+0], eax
    mov bl, dl
    and bl, $03
    mov eax, [esi+ebx*4]
    shr edx, 2
    mov [edi+4], eax
    mov bl, dl
    and bl, $03
    mov eax, [esi+ebx*4]
    shr edx, 2
    mov [edi+8], eax
    mov bl, dl
    and bl, $03
    mov eax, [esi+ebx*4]
    shr edx, 2
    mov [edi+12], eax

    add edi, PIXELSTRIDE
    dec ecx
    jnz @ROW_LOOP

    popad
  end;
end;
*)

procedure TPatch.WriteTo(img: Tpage; atX, atY: integer); overload;
var
  x,y: integer;
begin
  for y := 0 to 3 do
    for x := 0 to 3 do
      img.PutPixel(atX + x,atY + y, color[idx[y,x]]);
end;

procedure TPatch.WriteErrorTo(img: Tpage); overload;
begin
  WriteErrorTo(img, self.atX, self.atY);
end;

procedure TPatch.WriteErrorTo(img: Tpage; atX, atY: integer); overload;
var
  x,y: integer;
  c: RGBA;
  err: dword;
  sse: integer;
begin
  LastSSE := 0;
  for y := 0 to 3 do
    for x := 0 to 3 do begin
      err := getError(x, y);
      LastSSE += err;
      c.init(err, err shr 4, err shr 8);
      img.PutPixel(atX + x,atY + y, c);
    end;
end;


procedure runTests();
var
  PatchA, PatchB: TPatch;
  x,y,i: integer;
  a,b: integer;
begin

  note('[init] Patch');

  for x := 0 to 3 do
    for y := 0 to 3 do
      PatchA.pixels[x,y] := RGBA.Random();

  for i := 0 to 3 do
    PatchA.color[i] := RGBA.Random();

  PatchB := PatchA;

  a := EvaluateSSE_Ref(PatchA, PatchA.color);
  b := EvaluateSSE_Asm(PatchB, PatchB.color);

  {show grads}
  for i := 0 to 3 do
    Info(Format('%s', [ShortString(RGBA32(PatchA.grad[i]))]));
  Info('');
  for i := 0 to 3 do
    Info(Format('%s', [ShortString(RGBA32(PatchB.grad[i]))]));

  AssertEqual(b, a);

  for x := 0 to 3 do
    for y := 0 to 3 do
      AssertEqual(PatchB.ProposedIdx[y,x], PatchA.ProposedIdx[y,x]);

  {Note: gradient may sometimes not match as I never specified how to break
   ties, and I didn't check if both algorithms apply the same method.}
  for i := 0 to 3 do
    AssertEqual(PatchB.grad[i].r, PatchA.grad[i].r);

end;

begin
  runTests();
end.
