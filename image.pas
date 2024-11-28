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

procedure printStats(imgBMP: tPage; s: shortstring; nBytes:int32);
begin
	writeln(Format('%s    %f:1', [s,imgBMP.width*imgBMP.height*3/nBytes]));
end;


procedure testImages();

var	
	imgBytes24: tBytes;
	imgBytes32: tBytes;
  lcBytes: tBytes;
  s: tStream;
  imgBMP, imgDecoded: tPage;


begin

  imgBMP := LoadBMP('video\frames_0001.bmp');
  info(Format('Image is %d x %d', [imgBMP.width, imgBMP.height]));

  {makeImgRandom(imgBMP);}


  imgBytes24 := imgBMP.asRGBBytes;

  s := encodeLCBytes(imgBMP);
  lcBytes := s.asBytes;
  printStats(imgBMP, 'LZ4-LC', length(lcBytes));
  writeln(length(lcBytes));
  s.seek(0);

  {decode}
  imgDecoded := decodeLCBytes(s);

  assertEqual(imgBMP, imgDecoded);

end;

begin
	testImages();
  printLog;
  readkey;
end.
