{prototype image compression}
program image;

{$MODE delphi}

uses	
	crt, {remove}
  stream,
  utils,
	debug,
  test,
  screen,
  graph32,
	lz4;


var
	canvas: tPage;
	imgBMP: tPage;

procedure drawBytes24(bytes: tBytes; atX, atY: integer; width:int32; height: int32);
var
	x,y: int32;
  c: RGBA;
begin
  for y := 0 to height-1 do
  	for x := 0 to width-1 do begin
    	c.init(
    		bytes[(x+y*width)*3+0],
    		bytes[(x+y*width)*3+1],
    		bytes[(x+y*width)*3+2]
      );
      canvas.putPixel(atX+x, atY+y, c);
  end;
end;

procedure drawBytes32(bytes: tBytes; atX, atY: integer; width:int32; height: int32);
var
	x,y: int32;
  c: RGBA;
begin
  for y := 0 to height-1 do
  	for x := 0 to width-1 do begin
    	c := pRGBA(@bytes[0]+dword(x+y*width)*4)^;
      canvas.putPixel(atX+x, atY+y, c);
  end;
end;

procedure drawBytes32Alpha(bytes: tBytes; atX, atY: integer; width:int32; height: int32);
var
	x,y: int32;
  c: RGBA;
begin
  for y := 0 to height-1 do
  	for x := 0 to width-1 do begin
    	c := pRGBA(@bytes[0]+dword(x+y*width)*4)^;
      c.r := c.a;
      c.g := c.a;
      c.b := c.a;
      c.a := 255;
      canvas.putPixel(atX+x, atY+y, c);
  end;
end;

(*
function compress(bytes: tBytes): tBytes;
var
	blockLength: int32;
  remainingBytes: int32;
  pos: int32;

begin

	result := nil;


	remainingBytes := length(bytes);
  pos := 0;
	while remainingBytes > 0 do begin
		blockLength := min(65536, remainingBytes);
		LZ4Compress(slice(bytes, pos, pos+blockLength);
    	
  end;
end;*)

function byteShuffle(bytes: tBytes;planes: byte=3): tBytes;
var
	i: int32;
  planeSize: int32;
  p: int32;
  planeOffset: int32;
begin

	result := nil;
  setLength(result, length(bytes));

  if length(bytes) mod planes <> 0 then
  	Error('Invalid number of bytes for this many planes');
  planeSize := length(bytes) div planes;

	for i := 0 to length(bytes)-1 do begin
  	p := i mod planes;
    planeOffset := i div planes;
  	result[p*planeSize+planeOffset] := bytes[i];
  end;
end;

function deltaModulate24(bytes: tBytes): tBytes;
var
	i: integer;
begin
	result := nil;
  setLength(result, length(bytes));

  result[0] := bytes[0];
  result[1] := bytes[1];
  result[2] := bytes[2];

  {$R-}
  for i := 3 to length(bytes) do begin
  	result[i] := byte(bytes[i]-bytes[i-3])
  end;
  {$R+}

end;

function deltaModulate32(bytes: tBytes): tBytes;
var
	i: integer;
begin
	result := nil;
  setLength(result, length(bytes));

  result[0] := bytes[0];
  result[1] := bytes[1];
  result[2] := bytes[2];
  result[3] := bytes[3];

  {$R-}
  for i := 4 to length(bytes) do begin
  	result[i] := byte(bytes[i]-bytes[i-4])
  end;
  {$R+}

end;

procedure printStats(s: shortstring; nBytes:int32);
begin
	writeln(Format('%s    %f:1', [s,imgBMP.width*imgBMP.height*3/nBytes]));
end;

function sqr(x: int32): int32; inline;
begin
	result := x*x;
end;

function wrappedSqr(x: integer): int32; inline;
begin
	result := min(min(sqr(x), sqr(x+256)), sqr(x-256));
end;

function rms(a,b: RGBA): int32;
begin
	{rapped RMS}
	result :=
  	wrappedSqr(a.r-b.r) +
    wrappedSqr(a.g-b.g) +
    wrappedSqr(a.b-b.b);
end;

function funkyNeg(x: int32): int32;
begin
	result := abs(x)*2;
  if x < 0 then dec(result);
end;

{find the shortest way to encode the delta, assuming we can wrap around}
function smartWriteDelta(s: tStream; a,b: byte;skipWrite: boolean=False): byte;
var
	c1,c2,c3: byte;
  delta: integer;
begin
	{encode naturally}
  delta := integer(a)-b;
  c1 := s.VLCBits(funkyNeg(delta));
  c2 := s.VLCBits(funkyNeg(delta+256));
  c3 := s.VLCBits(funkyNeg(delta-256));
  {wrap over}
  if c2 < c1 then begin
  	{these just never happen...}
  	if not skipWrite then
	  	s.writeVLC(funkyNeg(delta+256));
    exit(c2);
  end;
  if c3 < c1 then begin
  	{these just never happen...}
  	if not skipWrite then
	  	s.writeVLC(funkyNeg(delta-256));
		exit(c3);
  end;
  if not skipWrite then
	  s.writeVLC(funkyNeg(delta));
  exit(c1);
end;

{find the shortest way to encode the delta, assuming we can wrap around}
function dumbWriteDelta(s: tStream; a,b: byte): byte;
var
	c1,c2,c3: byte;
  delta: integer;
begin
	{encode naturally}
  delta := integer(a)-b;
  c1 := s.VLCBits(funkyNeg(delta));
	s.writeVLC(funkyNeg(delta));
  exit(c1);
end;


procedure writeDelta(s: tStream; c1, c2: RGBA);
begin
	smartWriteDelta(s, c1.r, c2.r);
	smartWriteDelta(s, c1.g, c2.g);
  smartWriteDelta(s, c1.b, c2.b);
end;

function bitsToEncodeColorDelta(s: tStream; c1, c2: RGBA): integer;
begin
	result :=
  	smartWriteDelta(s, c1.r, c2.r, True)+
    smartWriteDelta(s, c1.g, c2.g, True)+
    smartWriteDelta(s, c1.b, c2.b, True);
end;

procedure encodePatch(s, s2: tStream; page: tPage; atX,atY: integer;refC: RGBA);
var
	c, prevC: RGBA;
  x,y: integer;
  dx,dy: integer;
  i: integer;
  o1,o2: RGBA;
  cost1,cost2,r1,r2: integer;
  choiceCode: dword;
const
  scanOrder: array[0..15] of byte = (0,1,2,3,7,6,5,4,8,9,10,14,15,14,13,12);

begin
	{output first color}
  prevC := refC;
  {output deltas}
  choiceCode := 0;
  for y := 0 to 3 do begin
  	for x := 0 to 3 do begin
      i := x + y*4;
			{fancy scan order}
      dx := scanOrder[i] and $3;
      dy := scanOrder[i] shr 2;
      {standard scan order}
    	dx := x;
      dy := y;
    	c := page.getPixel(atX+dx, atY+dy);

      {stub:}
      o1 := page.getPixel(atX+dx-1, atY+dy);
      o2 := page.getPixel(atX+dx, atY+dy-1);
      cost1 := rms(c, o1);
      cost2 := rms(c, o2);
      if cost1 <= cost2 then
	    	writeDelta(s, c, o1)
      else begin
				writeDelta(s, c, o2);
        inc(choiceCode);
      end;
      prevC := c;
      choiceCode := choiceCode shl 1;
    end;
  end;
  s2.writeWord(choiceCode shr 1);
end;


{convert an image into 'lossless compression' format.}
function imageToLCBytes(page: tPage): tBytes;
var
	c, prevc: rgba;
	s,s2: tStream;
  px,py: integer;
  refC: RGBA;
	thumbnail: array[0..180 div 8, 0..320 div 8] of RGBA;

  x,y: integer;
  o1,o2: RGBA;
  choiceCode: dword;
  cnt: integer;

begin
	s := tStream.Create();
	s2 := tStream.Create();

  (*
  prevC.init(0,0,0);
	{first we encode the thumbnail}
  for py := 0 to (page.height+7) div 8-1 do
  	for px := 0 to (page.width+7) div 8-1 do begin
    	c := page.getPixelScaled(px, py, 8);
    	{c := page.getPixel(px*8, py*8);}
      thumbnail[py, px] := c;
      writeDelta(s, c, prevC);
      prevC := c;
	  end;
     *)

  {then we encode the patches}
  {try just encoding entire frame? Might be better? and simpler...

  }
  {
  	advantage of patch: 1 word for choices
    details stay a bit more local?
  }

  {full frame is 2.23
   patches are 2.28... interesting}

         (*
  choiceCode := 0;
  cnt := 0;
  for y := 0 to page.height-1 do begin
  	for x := 0 to page.width-1 do begin
    	c := page.getPixel(x, y);
      o1 := page.getPixel(x-1, y);
      o2 := page.getPixel(x, y-1);
      if rms(c, o1) <= rms(c, o2) then
	    	writeDelta(s, c, o1)
      else begin
				writeDelta(s, c, o2);
        inc(choiceCode);
      end;
      {choice codes might be wrong}
      if cnt = 15 then begin
      	s.writeWord(choiceCode);
        cnt := 0;
        choiceCode := 0;
      end else
	      choiceCode := choiceCode shl 1;
      inc(cnt);	
    end;
  end;

  s.writeBytes(s2.asBytes);
           *)

  for py := 0 to page.height div 4-1 do
  	for px := 0 to page.width div 4-1 do begin
    	{refC := thumbnail[py div 2, px div 2];}
      refC := page.getPixel(px*4-1,py*4);
    	encodePatch(s, s2, page, px*4, py*4, refC);
    end;

  s.writeBytes(s2.asBytes);


  exit(s.asBytes);


end;

procedure testImages();

var	
	imgBytes24: tBytes;

	imgBytes32: tBytes;

  lz: tBytes;

begin

  imgBMP := LoadBMP('video\frames_0001.bmp');
  info(Format('Image is %d x %d', [imgBMP.width, imgBMP.height]));


  imgBytes24 := imgBMP.asRGBBytes;

{  lz := LZ4Compress(imgBytes24);
  printStats('LZ4', length(lz));}

{  lz := LZ4Compress(deltaModulate24(imgBytes24));
  printStats('LZ4-DM', length(lz));}

  lz := LZ4Compress(imageToLCBytes(imgBMP));
  printStats('LZ4-LC', length(lz));

end;

begin
	testImages();
  printLog;
  readkey;
end.
