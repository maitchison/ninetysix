{lossless image compression}
unit LC96;

{$MODE Delphi}

{
 	Super fast lossless image compression

  Usage:

}

interface

uses
	debug,
	test,
  utils,
	stream,
	graph32;

procedure saveLC96(filename: string; page: tPage;forceAlpha: boolean=False);
function loadLC96(filename: string): tPage;

function decodeLC96(s: tStream): tPage;
function encodeLC96(page: tPage;s: tStream=nil;withAlpha: boolean=False): tStream;

implementation

uses lz4;

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

{interleave pos and negative numbers into a whole number}
function invFunkyNeg(x: int32): int32; inline;
begin
	result := ((x+1) shr 1);
  if x and $1 = 0 then result := -result;
end;

{interleave pos and negative numbers into a whole number}
function funkyNeg(x: int32): int32; inline;
begin
	result := abs(x)*2;
  if x > 0 then dec(result);
end;

{generates code representing delta to go from a to b}
function encodeByteDelta(a,b: byte): byte; inline;
var
	delta: integer;
begin
	{take advantage of 256 wrap around on bytes}
	delta := integer(b)-a;
	if delta > 128 then
		exit(funkyNeg(delta-256))
  else if delta < -127 then
	  exit(funkyNeg(delta+256))
  else
  	exit(funkyNeg(delta));
end;

function applyByteDelta(a, code: byte): byte; inline;
var
	delta: integer;
begin
	{$R-}
  result := byte(a)+byte(invFunkyNeg(code));
  {$R+}	
end;

{Encode a 4x4 patch at given location.}
procedure encodePatch24(s: tStream; page: tPage; atX,atY: integer);
var
	i: integer;
	c: RGBA;
  x,y: integer;
  o1,o2: RGBA;
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
      if cost1 <= cost2 then begin
      	deltas[dPos] := encodeByteDelta(o1.r, c.r); inc(dPos);
        deltas[dPos] := encodeByteDelta(o1.g, c.g); inc(dPos);
        deltas[dPos] := encodeByteDelta(o1.b, c.b); inc(dPos);
      end else begin
      	deltas[dPos] := encodeByteDelta(o2.r, c.r); inc(dPos);
        deltas[dPos] := encodeByteDelta(o2.g, c.g); inc(dPos);
        deltas[dPos] := encodeByteDelta(o2.b, c.b); inc(dPos);
        inc(choiceCode);
      end;
      choiceCode := choiceCode shl 1;
    end;
  end;
  {write choice word}
  s.writeWord(choiceCode shr 1);
  s.writeVLCSegment(deltas);
  s.byteAlign();
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
  s.writeVLCSegment(deltas);
  s.byteAlign();
end;

{Encode a 4x4 patch at given location.}
procedure decodePatch(s: tStream; page: tPage; atX,atY: integer;withAlpha: boolean);
var
	i: integer;
	c: RGBA;
  x,y: integer;
  o1,o2,src: RGBA;
  dr,dg,db,da: byte;
  choiceCode: dword;
	deltas: array of dword;
  dPos: word;
begin
  {output deltas}
  page.defaultColor.init(0,0,0);
  choiceCode := s.readWord;
  if withAlpha then
	  deltas := s.readVLCSegment(16*4)
  else
  	deltas := s.readVLCSegment(16*3);
  s.byteAlign();

  dPos := 0;
  for y := 0 to 3 do begin
  	for x := 0 to 3 do begin
      o1 := page.getPixel(atX+x-1, atY+y);
      o2 := page.getPixel(atX+x, atY+y-1);
      dr := deltas[dpos]; inc(dpos);
      dg := deltas[dpos]; inc(dpos);
      db := deltas[dpos]; inc(dpos);
      if withAlpha then begin
	      da := deltas[dpos]; inc(dpos);
      end;
      if choiceCode and $8000 = $8000 then
      	src := o2
      else
      	src := o1;
      c.r := applyByteDelta(src.r, dr);
      c.g := applyByteDelta(src.g, dg);
      c.b := applyByteDelta(src.b, db);
      if withAlpha then
	      c.a := applyByteDelta(src.a, da)
      else
      	c.a := 255;
			page.putPixel(atX+x, atY+y, c);
			choiceCode := choiceCode shl 1;
    end;
  end;
end;

function decodeLC96(s: tStream): tPage;
var
  width, height, BPP: word;
  i, px,py: int32;
  bytes: tBytes;
  data: tStream;
  decompressedBytes: tBytes;
  numPatches: int32;
  hasAlpha: boolean;
const
	CODE_4CC = 'LC96';

begin

	for i := 1 to 4 do
  	if s.readByte <> ord(CODE_4CC[i]) then
    	Error('Not a LC96 file.');	

  width := s.readWord;
  height := s.readWord;

	result := tPage.create(width, height);
  BPP := s.readWord;

  {read reserved bytes}
  s.readBytes(32-10);

  if not (BPP in [24,32]) then
  	Error('Invalid BitPerPixel '+intToStr(BPP));

  hasAlpha := BPP = 32;

  numPatches := (width div 4) * (height div 4);

  {This is not great, it would be nice to be able decompress from
   part way in a stream.
   Note: having LZ4 work on streams rather than bytes would solve this.
   }
  decompressedBytes := nil;
	setLength(decompressedBytes, numPatches * (16*(BPP div 8)+2));
  data := tStream.create();
  bytes := s.readBytes(s.len-s.getPos);
  decompressedBytes := LZ4Decompress(bytes);
  data.writeBytes(decompressedBytes);
  data.seek(0);

	for py := 0 to result.height div 4-1 do
  	for px := 0 to result.width div 4-1 do
	  	decodePatch(data, result, px*4, py*4, hasAlpha);

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

begin

	if not assigned(s) then	
		s := tStream.Create();

  if withAlpha then bpp := 32 else bpp := 24;

  {write header}
  s.writeChars('LC96');
  s.writeWord(page.Width);
  s.writeWord(page.Height);
  s.writeWord(bpp);

  {write reserved space}
  for i := 1 to (32-10) do
  	s.writeByte(0);

	data := tStream.create();
  for py := 0 to page.height div 4-1 do
  	for px := 0 to page.width div 4-1 do
    	case bpp of
      	32: encodePatch32(data, page, px*4, py*4);
      	24: encodePatch24(data, page, px*4, py*4);
      end;

  s.writeBytes(LZ4Compress(data.asBytes));

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
	s: tStream;
  withAlpha: boolean;
begin
	withAlpha := forceAlpha or page.checkForAlpha;
  s := encodeLC96(page, nil, withAlpha);

  s.writeToDisk(filename);
  s.free;
end;

function loadLC96(filename: string): tPage;
var
	s: tStream;
begin
	s := tStream.create();
  s.readFromDisk(filename);
  result := decodeLC96(s);
  s.free;
end;

{-------------------------------------------------------}

procedure runTests();
var	
	img1,img2: tPage;
  s: tStream;
  a, b, delta: int32;
  x,y: int32;
  i: integer;
begin

  {test funky neg}
  for i := -256 to +256 do
	  AssertEqual(invFunkyNeg(funkyNeg(i)), i);

  {byte deltas}
	delta := encodeByteDelta(5,3);
	assertEqual(applyByteDelta(5, delta), 3);
  delta := encodeByteDelta(3,5);
	assertEqual(applyByteDelta(3, delta), 5);
  delta := encodeByteDelta(0,128);
	assertEqual(applyByteDelta(0, delta), 128);
  delta := encodeByteDelta(0,255);
	assertEqual(applyByteDelta(0, delta), 255);

	{make sure we can encode and decode a simple page}
	img1 := tPage.create(4,4);
  img1.clear(RGBA.create(255,0,128));
	s := encodeLC96(img1);
  s.seek(0);
  img2 := decodeLC96(s);
  assertEqual(img1, img2);
  s.free;

  {test on random bytes for larger page}
	img1 := tPage.create(4,4);
  makePageRandom(img1);
	s := encodeLC96(img1);
  s.seek(0);
  img2 := decodeLC96(s);
  assertEqual(img1, img2);
  s.free;

  {test on random bytes for larger page}
	img1 := tPage.create(16,16);
  makePageRandom(img1);
	s := encodeLC96(img1);
  s.seek(0);
  img2 := decodeLC96(s);
  assertEqual(img1, img2);
  s.free;

end;

begin
	runTests();
end.
