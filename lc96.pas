{lossless image compression}
unit LC96;

{
 	Super fast lossless image compression

  Usage:

}

interface

uses
	test,
  utils,
	stream,
	graph32;

procedure compressLC96(s: tStream; page: tPage);
function  uncompressLC96(s: tStream): tPage;

procedure saveLC96(filename: string; page: tPage);
function loadLC96(filename: string): tPage;

{stub: remove}
function imageToLCBytes(page: tPage): tBytes;


implementation

{-------------------------------------------------------}
{ Private }
{-------------------------------------------------------}

function sqr(x: integer): int32; inline;
begin
	result := x*x;
end;

function rms(a,b: RGBA): int32;
begin
	result := sqr(a.r-b.r) + sqr(a.g-b.g) + sqr(a.b-b.b);
end;

{interleave pos and negative numbers into a whole number}
function funkyNeg(x: int32): int32;
begin
	result := abs(x)*2;
  if x < 0 then dec(result);
end;

{generates code representing delta between two bytes}
function encodeByteDelta(a,b: byte): byte;
var
	delta: integer;
begin
	{take advantage of 256 wrap around on bytes}
  {note, the values we can represent in 8 bits are...
  [-128...127], which is different from 2s complement
  }
	delta := integer(a)-b;
	if delta > 127 then
		exit(funkyNeg(delta-256))
  else if delta < -128 then
	  exit(funkyNeg(delta+256))
  else
  	exit(funkyNeg(delta));
end;

{Encode a 4x4 patch at given location.}
procedure encodePatch(s: tStream; page: tPage; atX,atY: integer);
var
	c: RGBA;
  x,y: integer;
  o1,o2: RGBA;
  cost1,cost2: int32;
  choiceCode: dword;
  deltas: array[0..4*4*3-1] of dword;
  dPos: word;
begin
  {output deltas}
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
      	deltas[dPos] := encodeByteDelta(c.r,o1.r); inc(dPos);
        deltas[dPos] := encodeByteDelta(c.g,o1.g); inc(dPos);
        deltas[dPos] := encodeByteDelta(c.b,o1.b); inc(dPos);
      end else begin
      	deltas[dPos] := encodeByteDelta(c.r,o2.r); inc(dPos);
        deltas[dPos] := encodeByteDelta(c.g,o2.g); inc(dPos);
        deltas[dPos] := encodeByteDelta(c.b,o2.b); inc(dPos);
        inc(choiceCode);
      end;
      choiceCode := choiceCode shl 1;
    end;
  end;
  AssertEqual(dPos, 4*4*3);
  {write choice word}
  s.writeWord(choiceCode shr 1);
  s.writeVLCSegment(deltas);
  s.byteAlign();
end;

{convert an image into 'lossless compression' format.}
function imageToLCBytes(page: tPage): tBytes;
var
	c, prevc: rgba;
	s: tStream;
  px,py: integer;
  x,y: integer;
  o1,o2: RGBA;
  choiceCode: dword;
  cnt: integer;

begin
	s := tStream.Create();

  {potential improvement, use control codes to activate packed
   segments where they can be done. Perhaps on a patch level?}

  {write header}
  s.writeChars('LC96');
  s.writeWord(page.Width);
  s.writeWord(page.Height);
  s.writeWord(page.BPP);

  for py := 0 to page.height div 4-1 do
  	for px := 0 to page.width div 4-1 do
    	encodePatch(s, page, px*4, py*4);

  result := s.asBytes;
  s.free;
end;


{-------------------------------------------------------}
{ Public }

{-------------------------------------------------------}

procedure compressLC96(s: tStream; page: tPage);
var
	bytes: tBytes;
begin
  bytes := imageToLCBytes(page);
  s.writeBytes(bytes);   	
end;

function uncompressLC96(s: tStream): tPage;
begin
end;

procedure saveLC96(filename: string; page: tPage);
var
	stream: tStream;
begin
	stream := tStream.create();
  compressLC96(stream, page);
  stream.writeToDisk(filename);
  stream.free;	
end;

function loadLC96(filename: string): tPage;
var
	stream: tStream;
begin
	stream := tStream.create();
  stream.readFromDisk(filename);
  result := uncompressLC96(stream);
  stream.free;
end;

{-------------------------------------------------------}

procedure runTests();
var	
	img: tPage;
  bytes: tBytes;
begin
	img := tPage.create(4,4);
  img.clear(RGBA.create(255,0,255));
	bytes := imageToLCBytes(img);
	writeln(bytesToStr(bytes));
end;

begin
	runTests();
end.
