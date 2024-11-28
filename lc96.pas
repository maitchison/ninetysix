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

{writes a variable code length delta between two bytes}
procedure writeDelta(s: tStream; a,b: byte); overload;
begin
  s.writeVLC(funkyNeg(integer(a)-b));
end;

{writes RGB delta (without alpha)}
procedure writeDelta(s: tStream; c1, c2: RGBA); overload;
begin
	writeDelta(s, c1.r, c2.r);
	writeDelta(s, c1.g, c2.g);
  writeDelta(s, c1.b, c2.b);
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
      	deltas[dPos] := funkyNeg(integer(c.r)-o1.r); inc(dPos);
        deltas[dPos] := funkyNeg(integer(c.g)-o1.g); inc(dPos);
        deltas[dPos] := funkyNeg(integer(c.b)-o1.b); inc(dPos);
      end else begin
      	deltas[dPos] := funkyNeg(integer(c.r)-o2.r); inc(dPos);
        deltas[dPos] := funkyNeg(integer(c.g)-o2.g); inc(dPos);
        deltas[dPos] := funkyNeg(integer(c.b)-o2.b); inc(dPos);
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

  exit(s.asBytes);
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
