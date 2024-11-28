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

procedure compressLC96(s: tStream; page: tPage);
function  uncompressLC96(s: tStream): tPage;

procedure saveLC96(filename: string; page: tPage);
function loadLC96(filename: string): tPage;

{stub: remove}
function readLCBytes(s: tStream): tPage;
function encodeLCBytes(page: tPage;s: tStream=nil): tStream;

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
  if x > 0 then dec(result);
end;

{interleave pos and negative numbers into a whole number}
function invFunkyNeg(x: int32): int32;
begin
	result := ((x+1) shr 1);
  if x and $1 = 0 then result := -result;
end;

{generates code representing delta between two bytes}
function encodeByteDelta(a,b: byte): byte;
var
	delta: integer;
begin
	{take advantage of 256 wrap around on bytes}
	delta := integer(a)-b;
	if delta > 128 then
		exit(funkyNeg(delta-256))
  else if delta < -127 then
	  exit(funkyNeg(delta+256))
  else
  	exit(funkyNeg(delta));
end;

function applyByteDelta(a, code: byte): byte;
var
	delta: integer;
begin
	{$R-}
  result := byte(a)+byte(invFunkyNeg(code));
  {$R+}	
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

{Encode a 4x4 patch at given location.}
procedure decodePatch(s: tStream; page: tPage; atX,atY: integer);
var
	c: RGBA;
  x,y: integer;
  o1,o2,src: RGBA;
  dr,dg,db: byte;
  choiceCode: dword;
	deltas: array of dword;
  dPos: word;
begin
  {output deltas}
  choiceCode := s.readWord;
  deltas := s.readVLCSegment(4*4*3);
  dPos := 0;
  for y := 0 to 3 do begin
  	for x := 0 to 3 do begin
      o1 := page.getPixel(atX+x-1, atY+y);
      o2 := page.getPixel(atX+x, atY+y-1);
      dr := deltas[dpos]; inc(dpos);
      dg := deltas[dpos]; inc(dpos);
      db := deltas[dpos]; inc(dpos);
      if choiceCode >= $8000 then
      	src := o1
      else
      	src := o2;
      c.init(applyByteDelta(src.r, dr), applyByteDelta(src.g, dg), applyByteDelta(src.b, db));
			choiceCode := choiceCode shr 1;
    end;
  end;
  s.byteAlign();
end;


function readLCBytes(s: tStream): tPage;
var
  BPP: word;
  i, px,py: int32;
const
	CODE_4CC = 'LC96';

begin

	for i := 1 to 4 do
  	if s.readByte <> ord(CODE_4CC[i]) then
    	Error('Not a LC96 file.');	

	result := tPage.create(s.readWord, s.readWord);
  BPP := s.readWord;

  if BPP <> 24 then
  	Error('Only 24bit supported.');

	for py := 0 to result.height div 4-1 do
  	for px := 0 to result.width div 4-1 do
    	decodePatch(s, result, px*4, py*4);
	
end;

{convert an image into 'lossless compression' format.}
function writeLCBytes(page: tPage;s: tStream=nil): tStream;
var
	c, prevc: rgba;
  px,py: integer;
  x,y: integer;
  o1,o2: RGBA;
  choiceCode: dword;
  cnt: integer;

begin

	if not assigned(s) then	
		s := tStream.Create();

  {potential improvement, use control codes to activate packed
   segments where they can be done. Perhaps on a patch level?}

  {write header}
  s.writeChars('LC96');
  s.writeWord(page.Width);
  s.writeWord(page.Height);
  s.writeWord(24); {only 24bit supported right now}

  for py := 0 to page.height div 4-1 do
  	for px := 0 to page.width div 4-1 do
    	encodePatch(s, page, px*4, py*4);

  result := s;
end;


{-------------------------------------------------------}
{ Public }

{-------------------------------------------------------}

procedure compressLC96(s: tStream; page: tPage);
var
	bytes: tBytes;
begin
  bytes := writeLCBytes(page).asBytes;
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
	img1,img2: tPage;
  s: tStream;
  a, b, delta: int32;
  testDeltas: array of integer = [-10, -1, 0, 1, 10];
  x,y: int32;
begin

	{make sure we can encode and decode a simple page}
	img1 := tPage.create(4,4);
  img1.clear(RGBA.create(255,0,255));
	s := writeLCBytes(img1);
	writeln(bytesToStr(s.asBytes));
  s.seek(0);
  img2 := readLCBytes(s);
  assertEqual(img1, img2);

  {test funky neg}
  for delta in testDeltas do
	  AssertEqual(invFunkyNeg(funkyNeg(delta)), delta);

end;

begin
	runTests();
end.
