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
  lc96,
	lz4;


var
	imgBMP: tPage;

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

procedure printStats(s: shortstring; nBytes:int32);
begin
	writeln(Format('%s    %f:1', [s,imgBMP.width*imgBMP.height*3/nBytes]));
end;


procedure makeImgRandom(page: tPage);
var
	x,y: int32;
begin
	for y := 0 to page.height-1 do
  	for x := 0 to page.width-1 do
    	page.putPixel(x,y,RGBA.random);
end;

procedure testImages();

var	
	imgBytes24: tBytes;
	imgBytes32: tBytes;
  lz: tBytes;
  s: tStream;


begin

  imgBMP := LoadBMP('video\frames_0001.bmp');
  info(Format('Image is %d x %d', [imgBMP.width, imgBMP.height]));

  {makeImgRandom(imgBMP);}


  imgBytes24 := imgBMP.asRGBBytes;
{
  lz := LZ4Compress(imgBytes24);
  printStats('LZ4', length(lz));

  lz := LZ4Compress(deltaModulate24(imgBytes24));
  printStats('LZ4-DM', length(lz));
 }

 	lz := LZ4Compress(imageToLCBytes(imgBMP));
  printStats('LZ4-LC', length(lz));
  writeln(length(lz));

end;

begin
	testImages();
  printLog;
  readkey;
end.
