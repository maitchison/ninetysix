{lossless image compression}
unit LC96;

{$MODE Delphi}

{
   Super fast lossless image compression

  Usage:


  Verion history

  v0.1 - first version
  v0.2 - support for larger images (numPatchs now dword)
  v0.3 - Switch to VLC2 (faster loading, and slightly (~1%) more efficent).
  v0.4 - Uses RICE
  v0.5 - switch from negEncode to zigZag
}

interface

uses
  debug,
  test,
  utils,
  sysTypes,
  stream,
  resource,
  graph2d,
  graph32;

procedure saveLC96(filename: string; page: tPage;forceAlpha: boolean=False);
function loadLC96(filename: string): tPage;

function decodeLC96(s: tStream): tPage;
function encodeLC96(page: tPage;s: tStream=nil;withAlpha: boolean=False): tStream;

implementation

uses
  lz4;

const
  VER_BIG = 0;
  VER_SMALL = 5;

var
  {stores byte(zagZig(x))}
  BYTE_DELTA_LOOKUP: array[0..255] of byte;

{-------------------------------------------------------}
{ Private }
{-------------------------------------------------------}

function sqr(x: integer): int32; inline;
begin
  result := x*x;
end;

function rms(a,b: RGBA): int32; inline;
begin
  result := sqr(a.r-b.r) + sqr(a.g-b.g) + sqr(a.b-b.b) + sqr(a.a-b.a);
end;

function applyByteDelta(a, code: byte): byte; inline;
var
  delta: integer;
begin
  {$R-}
  result := byte(a)+byte(zagZig(code));
  {$R+}
end;

{Encode a 4x4 patch at given location.}
procedure encodePatch24(s: tStream; page: tPage; atX,atY: integer);
var
  i: integer;
  c: RGBA;
  x,y: integer;
  o1,o2,o: RGBA;
  cost1,cost2: int32;
  choiceCode: dword;
  deltas: array[0..16*3-1] of dword;
  dPos: word;
  BPP: byte;
begin
  {todo: make this one function}
  page.defaultColor.init(0,0,0);
  choiceCode := 0;
  dPos := 0;
  for y := 0 to 3 do begin
    for x := 0 to 3 do begin
      c := page.getPixel(atX+x, atY+y);
      o1 := page.getPixel(atX+x-1, atY+y);
      o2 := page.getPixel(atX+x, atY+y-1);
      o1.a := 255; o2.a := 255; c.a := 255; {make sure to ignore alpha}
      cost1 := rms(c, o1);
      cost2 := rms(c, o2);
      if cost1 <= cost2 then
        o := o1
      else begin
        o := o2;
        inc(choiceCode);
      end;

      deltas[dPos] := encodeByteDelta(o.r, c.r); inc(dPos);
      deltas[dPos] := encodeByteDelta(o.g, c.g); inc(dPos);
      deltas[dPos] := encodeByteDelta(o.b, c.b); inc(dPos);

      choiceCode := choiceCode shl 1;
    end;
  end;
  {write choice word}
  s.writeWord(choiceCode shr 1);

  s.writeSegment(deltas);

end;

{Encode a 4x4 patch at given location.}
procedure encodePatch32(s: tStream; page: tPage; atX,atY: integer);
var
  i: integer;
  c: RGBA;
  x,y: integer;
  o1,o2: RGBA;
  cost1,cost2: int32;
  choiceCode: dword;
  deltas: array[0..16*4-1] of dword;
  dPos: word;
  BPP: byte;
begin
  page.defaultColor.init(0,0,0);
  choiceCode := 0;
  dPos := 0;
  for y := 0 to 3 do begin
    for x := 0 to 3 do begin
      c := page.getPixel(atX+x, atY+y);
      o1 := page.getPixel(atX+x-1, atY+y);
      o2 := page.getPixel(atX+x, atY+y-1);
      cost1 := rms(c, o1);
      cost2 := rms(c, o2);
      if cost1 <= cost2 then begin
        deltas[dPos] := encodeByteDelta(o1.r, c.r); inc(dPos);
        deltas[dPos] := encodeByteDelta(o1.g, c.g); inc(dPos);
        deltas[dPos] := encodeByteDelta(o1.b, c.b); inc(dPos);
        deltas[dPos] := encodeByteDelta(o1.a, c.a); inc(dPos);
      end else begin
        deltas[dPos] := encodeByteDelta(o2.r, c.r); inc(dPos);
        deltas[dPos] := encodeByteDelta(o2.g, c.g); inc(dPos);
        deltas[dPos] := encodeByteDelta(o2.b, c.b); inc(dPos);
        deltas[dPos] := encodeByteDelta(o2.a, c.a); inc(dPos);
        inc(choiceCode);
      end;
      choiceCode := choiceCode shl 1;
    end;
  end;
  {write choice word}
  s.writeWord(choiceCode shr 1);
  s.writeSegment(deltas);
end;

var
  {todo: move all this into a class}
  gDeltaCodes: tDwords;   // delta codes
  gDeltas: array[0..64-1] of byte;   // actual bytes needed to add to get new pixel color

{Decode a 4x4 patch at given location.}
{reference implementation}
procedure decodePatch_REF(s: tStream; page: tPage; atX,atY: integer;withAlpha: boolean);
var
  i,j: int32;
  c: RGBA;
  x,y: int32;
  o1,o2,src: RGBA;
  dr,dg,db,da: byte;
  choiceCode: dword;
  dPos: word;

begin
  {output deltas}
  page.defaultColor.init(0,0,0);
  choiceCode := s.readWord;
  if withAlpha then
    s.readSegment(16*4, gDeltaCodes)
  else
    s.readSegment(16*3, gDeltaCodes);

  dPos := 0;
  for y := 0 to 3 do begin
    for x := 0 to 3 do begin
      dr := gDeltaCodes[dpos]; inc(dpos);
      dg := gDeltaCodes[dpos]; inc(dpos);
      db := gDeltaCodes[dpos]; inc(dpos);
      if withAlpha then begin
        da := gDeltaCodes[dpos]; inc(dpos);
      end;
      if choiceCode and $8000 = $8000 then
        src := page.getPixel(atX+x, atY+y-1)
      else
        src := page.getPixel(atX+x-1, atY+y);

      c.r := applyByteDelta(src.r, dr);
      c.g := applyByteDelta(src.g, dg);
      c.b := applyByteDelta(src.b, db);

      if withAlpha then
        c.a := applyByteDelta(src.a, da)
      else
        c.a := 255;

      page.setPixel(atX+x, atY+y, c);
      choiceCode := choiceCode shl 1;

    end;
  end;
end;

{Decode a 4x4 patch at given location.}
procedure decodePatch_ASM(s: tStream; page: tPage; atX,atY: int32;withAlpha: boolean);
var
  i,j: int32;
  c: RGBA;
  x,y: int32;
  o1,o2,src: RGBA;
  choiceCode: dword;

  db,dg,dr,da: byte;
  dPos: word;
  ofs: dword;

  pixelsPtr,ppLeft,ppAbove: pointer;
  deltasPtr, deltaCodesPtr: pointer;

  DELTA_INC: dword;
  deltaBytes: dword;
  lineBytes: dword;

  tmp1,tmp2: dword;
  xPos: dword;

begin
  {output deltas}
  page.defaultColor.init(0,0,0);
  choiceCode := s.readWord;

  if withAlpha then
    DELTA_INC := 4
  else
    DELTA_INC := 3;

  deltaBytes := 16 * DELTA_INC;
  lineBytes := 4 * page.width;

  s.readSegment(deltaBytes, gDeltaCodes);

  pixelsPtr := page.pixels;
  ppLeft := pixelsPtr - 4;
  ppAbove := pixelsPtr - lineBytes;
  ofs := (atX + (dword(atY)*page.width)) * 4;
  deltasPtr := @gDeltas[0];
  deltaCodesPtr := @gDeltaCodes[0];

  // convert our codes into actual byte deltas
  // note:
  //  input is either 4 or 3 dwords, but output is always 4 bytes
  //  in the case we don't have alpha, all the deltas for alpha will be 0.
  asm
    pushad

    // -----------------------
    // Convert deltas

    mov esi, deltaCodesPtr
    mov edi, deltasPtr
    mov cx, 16
  @LOOP:
    // red
    mov eax, dword ptr [esi]
    mov al, byte ptr [BYTE_DELTA_LOOKUP+eax]
    mov byte ptr [edi+2], al
    add esi, 4
    // green
    mov eax, dword ptr [esi]
    mov al, byte ptr [BYTE_DELTA_LOOKUP+eax]
    mov byte ptr [edi+1], al
    add esi, 4
    // blue
    mov eax, dword ptr [esi]
    mov al, byte ptr [BYTE_DELTA_LOOKUP+eax]
    mov byte ptr [edi+0], al
    add esi, 4

    // alpha
    mov al,0
    cmp DELTA_INC, 3
    je @NO_ALPHA

  @WITH_ALPHA:
    mov eax, dword ptr [esi]
    mov al, byte ptr [BYTE_DELTA_LOOKUP+eax]
    add esi, 4

  @NO_ALPHA:
    mov byte ptr [edi+3], al

    add edi, 4

    dec cx
    jnz @LOOP

    // -----------------------
    // Apply deltas

    mov esi, deltasPtr
    mov edi, ofs
    mov ebx, choiceCode
    xor ecx, ecx
    mov ch,  4

    // EAX = pixel color
    // EBX =  - | - | choiceCode
    // ECX =  - | - | xlp | ylp
    // EDX = pixel deltas
    // ESI = global_deltas
    // EDI = pixelOffset

  @YLOOP:

    mov cl, 4
    mov eax,  atX
    mov xPos, eax

  @XLOOP:

    // check high bit of choice code
    mov eax, $ff000000          // this is the default color for out of bounds
    shl bx, 1

    jc @COPY_ABOVE

  @COPY_LEFT:
    cmp xPos, 0
    jz @APPLY
    add edi, ppLeft
    mov eax, dword ptr [edi]
    sub edi, ppLeft
    jmp @APPLY

  @COPY_ABOVE:
    cmp edi, lineBytes
    jl @APPLY
    add edi, ppAbove
    mov eax,  dword ptr [edi]
    sub edi, ppAbove

  @APPLY:
    // apply the byte delta
    // note: MMX would be great here...
    mov edx, dword ptr [esi]
    add al, dl
    add ah, dh
    ror eax, 16
    ror edx, 16
    add al, dl
    add ah, dh
    ror eax, 16

    add edi, pixelsPtr
    mov dword ptr [edi], eax
    sub edi, pixelsPtr

    add edi, 4
    add esi, 4

    inc xPos

    dec cl
    jnz @XLOOP

    add edi, lineBytes
    sub edi, 16

    dec ch
    jnz @YLOOP

    popad
  end;
end;

function decodeLC96(s: tStream): tPage;
var
  width, height, BPP: word;
  i,j: int32;
  px,py: int32;
  bytes: tBytes;
  data: tStream;
  decompressedBytes: tBytes;
  numPatches: dword;
  compressedSize,uncompressedSize: dword;
  hasAlpha: boolean;
  verBig,verSmall: byte;
  startPos: int32;
const
  CODE_4CC = 'LC96';

begin

  startPos := s.pos;

  for i := 1 to 4 do
    if s.readByte <> ord(CODE_4CC[i]) then
      fatal('Not an LC96 file.');

  {todo: make this a record}
  width := s.readWord;
  height := s.readWord;
  bpp := s.readWord;
  verSmall := s.readByte;
  verBig := s.readByte;
  numPatches := s.readDWord;
  uncompressedSize := s.readDWord;
  compressedSize := s.readDWord;

  {read reserved bytes}
  while s.pos < startPos+32 do
    s.readByte();

  if (verBig <> VER_BIG) and (verSmall <> VER_SMALL) then
    fatal(format('Invalid version, expecting %d.%d, but found %d.%d',[VER_BIG, VER_SMALL, verBig, verSmall]));

  result := tPage.Create(width, height);

  if not (bpp in [24,32]) then
    fatal('Invalid BitPerPixel '+intToStr(bpp));

  hasAlpha := bpp = 32;

  {make sure limits are sort of ok}
  {typically this occurs with a corrupt file}
  if width > 16384 then
    fatal(format('Image width too large (%d > 16k)', [width]));
  if height > 16384 then
    fatal(format('Image height too large (%d > 16k)', [height]));
  if numPatches > 256*1024 then
    fatal(format('Image patches too large (%d > 256k)', [numPatches]));

  if uncompressedSize > 16*1024*1024 then
    fatal(format('Image size too large (%d > 16MB)', [uncompressedSize]));

  {This is not great, it would be nice to be able decompress from
   part way in a stream.
   Note: having LZ4 work on streams rather than bytes would solve this.
   }
  decompressedBytes := nil;
  setLength(decompressedBytes, uncompressedSize);
  data := tMemoryStream.create();
  bytes := s.readBytes(compressedSize);
  LZ4Decompress(bytes, decompressedBytes);
  data.writeBytes(decompressedBytes);

  data.seek(0);

  for py := 0 to result.height div 4-1 do
    for px := 0 to result.width div 4-1 do
      decodePatch_ASM(data, result, px*4, py*4, hasAlpha);

  data.free;
end;

{convert an image into 'lossless compression' format.}
{todo: would be better as a state machine, where I can set
 various settings, rather than pass everything in. I.e. we want
 a compressor class}
function encodeLC96(page: tPage;s: tStream=nil;withAlpha: boolean=False): tStream;
var
  i: integer;
  c, prevc: rgba;
  px,py: integer;
  x,y: integer;
  o1,o2: RGBA;
  choiceCode: dword;
  cnt: integer;
  data: tStream;
  bpp: byte;
  numPatches: dword;
  uncompressedSize: dword;
  compressedSize: dword;
  startPos: int32;
  compressedData: tBytes;

begin

  if (page.width <= 0) or (page.height <= 0) then
    fatal('Invalid page dims');

  if not assigned(s) then
    s := tMemoryStream.Create();

  startPos := s.pos;

  if withAlpha then bpp := 32 else bpp := 24;

  {check everything is ok}
  if ((page.width and $3) <> 0) or ((page.height and $3) <> 0) then
    warning(format(
        'Page (%d, %d) has invalid dims, cropping to multiple of 4.',
        [page.width, page.height]
    ));

  numPatches := (page.width div 4) * (page.height div 4);

  {compress first so we know length}
  data := tMemoryStream.create();
  for py := 0 to page.height div 4-1 do
    for px := 0 to page.width div 4-1 do
      case bpp of
        32: encodePatch32(data, page, px*4, py*4);
        24: encodePatch24(data, page, px*4, py*4);
      end;
  compressedData := LZ4Compress(data.asBytes);
  compressedSize := length(compressedData);
  unCompressedSize := length(data.asBytes);
  data.free;

  {write header}
  s.writeChars('LC96');
  s.writeWord(page.Width);
  s.writeWord(page.Height);
  s.writeWord(bpp);
  s.writebyte(VER_SMALL);
  s.writebyte(VER_BIG);
  s.writeDWord(numPatches);
  s.writeDWord(uncompressedSize);
  s.writeDWord(compressedSize);

  {write reserved space}
  while s.pos < startPos+32 do
    s.writeByte(0);

  s.writeBytes(compressedData);

  result := s;
end;


{-------------------------------------------------------}
{ Public }

{-------------------------------------------------------}

{Saves LC96 file.
  forceAlpha: if true an alpha channel will always be saved. Otherwise only
  saves alpha channel if there is atleast one non-solid pixel}
procedure saveLC96(filename: string; page: tPage;forceAlpha: boolean=False);
var
  s: tMemoryStream;
  withAlpha: boolean;
begin
  withAlpha := forceAlpha or page.checkForAlpha;
  s := tMemoryStream.create();
  encodeLC96(page, s, withAlpha);
  s.writeToFile(filename);
  s.free;
end;

function loadLC96(filename: string): tPage;
var
  s: tMemoryStream;
begin
  s := tMemoryStream.create();
  s.readFromFile(filename);
  result := decodeLC96(s);
  s.free;
end;

{-------------------------------------------------------}

type
  tLC96Test = class(tTestSuite)
    procedure run; override;
  end;

procedure tLC96Test.run();
var
  img1,img2: tPage;
  s: tStream;
  a, b, delta: int32;
  x,y: int32;
  i,j,k: integer;
begin
  {byte deltas}
  delta := encodeByteDelta(5,3);
  assertEqual(applyByteDelta(5, delta), 3);
  delta := encodeByteDelta(3,5);
  assertEqual(applyByteDelta(3, delta), 5);
  delta := encodeByteDelta(0,128);
  assertEqual(applyByteDelta(0, delta), 128);
  delta := encodeByteDelta(0,255);
  assertEqual(applyByteDelta(0, delta), 255);

  {randomized testing}
  for k := 0 to 255 do begin
    i := rnd;
    j := rnd;
    delta := encodeByteDelta(i,j);
    assertEqual(applyByteDelta(i, delta), j);
  end;

  {make sure we can encode and decode a simple page}
  img1 := tPage.Create(4,4);
  img1.clear(RGBA.create(255,0,128));
  s := encodeLC96(img1);
  s.seek(0);
  img2 := decodeLC96(s);
  assertEqual(img1, img2);
  s.free;
  img1.free();
  img2.free();

  {test on random bytes for larger page}
  img1 := tPage.Create(4,4);
  makePageRandom(img1);
  s := encodeLC96(img1);
  s.seek(0);
  img2 := decodeLC96(s);
  assertEqual(img1, img2);
  s.free;
  img1.free();
  img2.free();

  {test on random bytes for larger page}
  img1 := tPage.Create(16,16);
  for i := 1 to 1 do begin
    {stub: really try to catch this have an error}
    makePageRandom(img1);
    s := encodeLC96(img1);
    s.seek(0);
    img2 := decodeLC96(s);
    assertEqual(img1, img2);
    img2.free();
    s.free();
  end;
  img1.free();

end;

var
  i: integer;

initialization

  {todo: move this out of global}
  setLength(gDeltaCodes, 64);
  fillDWord(gDeltaCodes[0], 16, 0);
  fillChar(gDeltas, 16, 0);

  for i := 0 to 255 do
    BYTE_DELTA_LOOKUP[i] := byte(zagZig(i));

  tLC96Test.create('LC96');

  registerResourceLoader('p96', @loadLC96);

finalization

end.
