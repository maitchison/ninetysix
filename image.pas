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
	writeln(Format('%s %fx', [s,imgBMP.width*imgBMP.height*3/nBytes]));
end;


procedure testImages();

var	
	imgBytes24: tBytes;
	imgBytes32: tBytes;
  lcBytes: tBytes;
  s: tStream;
  imgBMP, imgDecoded: tPage;
  startTime, elapsed: double;
begin

	writeln('Loading BMP');

  startTime := getSec;
  imgBMP := LoadBMP('video\frames_0001.bmp');
  elapsed := getSec-startTime;
  writeln(Format('Load took          %f',[elapsed]));

  info(Format('Image is %d x %d', [imgBMP.width, imgBMP.height]));

  {makeImgRandom(imgBMP);}

  imgBytes24 := imgBMP.asRGBBytes;

  {just see how good we can compress it}
  s := encodeLC96(imgBMP);
  lcBytes := s.asBytes;
  printStats(imgBMP, 'Compression ratio ',length(lcBytes));
  s.free;

  {make sure it decodes}
  {imgDecoded := decodeLCBytes(s);
    assertEqual(imgBMP, imgDecoded);
  }

  {save to disk}
  startTime := getSec;
  saveLC96('test.I96', imgBMP);
  elapsed := getSec-startTime;
  writeln(Format('Compress took      %f',[elapsed]));

  {load from disk}
  startTime := getSec;
  imgDecoded := loadLC96('test.I96');
  elapsed := getSec-startTime;
  writeln(Format('Decompress took    %f',[elapsed]));

  assertEqual(imgDecoded, imgBMP);
  writeln('Image verification [OK].');

end;

begin
	textAttr := 15;
  writeln();
	testImages();
  writeln();
  writeln('Logs');
  writeln('------------');
  printLog;
end.
