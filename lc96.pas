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
  graph2d,
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
function invFunkyNeg(x: word): int32; inline;
begin
	result := ((x+1) shr 1);
  if x and $1 = $0 then result := -result;
end;

{interleave pos and negative numbers into a whole number}
function funkyNeg(x: int32): word; inline;
begin
	result := abs(x)*2;
  if x > 0 then dec(result);
end;

{generates code representing delta to go from a to b}
function encodeByteDelta(a,b: byte): byte; inline;
var
	delta: int32;
begin
	{take advantage of 256 wrap around on bytes}
	delta := int32(b)-a;
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

  s.writeVLCSegment(deltas);

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

var
	{todo: move all this into a clas}
	global_deltas: tDwords;

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
	  s.readVLCSegment(16*4, global_deltas)
  else
  	s.readVLCSegment(16*3, global_deltas);
  s.byteAlign();

  dPos := 0;
  for y := 0 to 3 do begin
  	for x := 0 to 3 do begin
      dr := global_deltas[dpos]; inc(dpos);
      dg := global_deltas[dpos]; inc(dpos);
      db := global_deltas[dpos]; inc(dpos);
      if withAlpha then begin
	      da := global_deltas[dpos]; inc(dpos);
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
procedure decodePatch(s: tStream; page: tPage; atX,atY: integer;withAlpha: boolean);
var
	i,j: int32;
	c: RGBA;
  x,y: int32;
  o1,o2,src: RGBA;
  choiceCode: dword;

	db,dg,dr,da: byte;
  dPos: word;
  ofs: dword;

begin
  {output deltas}
  page.defaultColor.init(0,0,0);
  choiceCode := s.readWord;

  if withAlpha then
	  s.readVLCSegment(16*4, global_deltas)
  else
  	s.readVLCSegment(16*3, global_deltas);

  s.byteAlign();

  ofs := (atX + (atY*page.width)) * 4;

  {stub:}
  for i := 0 to 16*3-1 do if global_deltas[i] > 255 then begin
  	warn('invalid delta');
    exit;
  end;

  {eventually this will all be asm...}
  dPos := 0;
  da := 0;
  for y := 0 to 3 do begin
  	for x := 0 to 3 do begin

      dr := global_deltas[dpos]; inc(dpos);
      dg := global_deltas[dpos]; inc(dpos);
      db := global_deltas[dpos]; inc(dpos);
      if withAlpha then begin
	      da := global_deltas[dpos]; inc(dpos);
      end;

      if choiceCode and $8000 = $8000 then begin
      	if (atY = 0) and (y = 0) then
        	src.init(0,0,0)
        else
	      	pDword(@src)^ := pDword(page.pixels+ofs-(4*page.width))^
      end else begin
      	if (atX = 0) and (x = 0) then
        	src.init(0,0,0)
        else
	      	pDword(@src)^ := pDword(page.pixels+ofs-4)^;
      end;

	    c.r := applyByteDelta(src.r, dr);
  	  c.g := applyByteDelta(src.g, dg);
    	c.b := applyByteDelta(src.b, db);

      if withAlpha then
      	{check this is right}
				c.a := applyByteDelta(src.a, da)
      else
      	c.a := 255;

      pDword(page.pixels+ofs)^ := pDword(@c)^;

			choiceCode := choiceCode shl 1;

      ofs += 4;

    end;

    ofs += ((page.width-4) * 4);

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
  numPatches: word;
  compressedSize,uncompressedSize: dword;
  hasAlpha: boolean;
  verBig,verSmall: byte;
  startPos: int32;
const
	CODE_4CC = 'LC96';

begin

	startPos := s.getPos;

	for i := 1 to 4 do
  	if s.readByte <> ord(CODE_4CC[i]) then
    	Error('Not an LC96 file.');	

  {todo: make this a record}
  width := s.readWord;
  height := s.readWord;
  bpp := s.readWord;
  verSmall := s.readByte;
  verBig := s.readByte;
  numPatches := s.readWord;
  uncompressedSize := s.readDWord;
  compressedSize := s.readDWord;

  {read reserved bytes}
  while s.getPos < startPos+32 do
  	s.readByte();

  if (verBig <> 0) and (verSmall <> 1) then
  	error(format('Invalid version, expecting 0.1, but found %d.%d',[verBig, verSmall]));

	result.Init(width, height);

  if not (bpp in [24,32]) then
  	Error('Invalid BitPerPixel '+intToStr(bpp));

  hasAlpha := bpp = 32;

  {This is not great, it would be nice to be able decompress from
   part way in a stream.
   Note: having LZ4 work on streams rather than bytes would solve this.
   }
  decompressedBytes := nil;
	setLength(decompressedBytes, uncompressedSize);
  data := tStream.create();
  bytes := s.readBytes(compressedSize);
  LZ4Decompress(bytes, decompressedBytes);
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
  numPatches: word;
  uncompressedSize: dword;
  compressedSize: dword;
  startPos: int32;
  compressedData: tBytes;

begin

	if not assigned(s) then	
		s := tStream.Create();

  startPos := s.getPos;

  if withAlpha then bpp := 32 else bpp := 24;

  {check everything is ok}
  if ((page.width and $3) <> 0) or ((page.height and $3) <> 0) then
  	warn(format(
      	'Page (%d, %d) has invalid dimensions, cropping to multiple of 4.',
        [page.width, page.height]
    ));

  numPatches := (page.width div 4) * (page.height div 4);

  {compress first so we know length}
	data := tStream.create();
  for py := 0 to page.height div 4-1 do
  	for px := 0 to page.width div 4-1 do
    	case bpp of
      	32: encodePatch32(data, page, px*4, py*4);
      	24: encodePatch24(data, page, px*4, py*4);
      end;
	compressedData := LZ4Compress(data.asBytes);
  compressedSize := length(compressedData);
  unCompressedSize := length(data.asBytes);

  {write header}
  s.writeChars('LC96');
  s.writeWord(page.Width);
  s.writeWord(page.Height);
  s.writeWord(bpp);
  s.writeWord($0001);
  s.writeWord(numPatches);
  s.writeDWord(uncompressedSize);
  s.writeDWord(compressedSize);

  {write reserved space}
  while s.getPos < startPos+32 do
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
  i,j,k: integer;
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

  {randomized testing}
  for k := 0 to 255 do begin
  	i := rnd;
    j := rnd;  	
    delta := encodeByteDelta(i,j);
		assertEqual(applyByteDelta(i, delta), j);
  end;

	{make sure we can encode and decode a simple page}
	img1.init(4,4);
  img1.clear(RGBA.create(255,0,128));
	s := encodeLC96(img1);
  s.seek(0);
  img2 := decodeLC96(s);
  assertEqual(img1, img2);
  s.free;
  img1.done;
  img2.done;

  {test on random bytes for larger page}
	img1.init(4,4);
  makePageRandom(img1);
	s := encodeLC96(img1);
  s.seek(0);
  img2 := decodeLC96(s);
  assertEqual(img1, img2);
  s.free;
  img1.done;
  img2.done;

  {test on random bytes for larger page}
  img1.init(16,16);
  for i := 1 to 10 do begin
  	{stub: really try to catch this have an error}
	  makePageRandom(img1);
		s := encodeLC96(img1);
	  s.seek(0);
	  img2 := decodeLC96(s);
	  assertEqual(img1, img2);
    img2.done;
	  s.free;
  end;
  img1.done;

end;

begin
	{todo: move this out of global}
  global_deltas := nil;
  setLength(global_deltas, 16*4);
  filldword(global_deltas[0], length(global_deltas), 0);

	runTests();
end.
