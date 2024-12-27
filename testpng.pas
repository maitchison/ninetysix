{see if we can load PNG files}
program testpng;

uses
  debug,
  utils,

  sysPng,
  graph32,
  LC96;

var
  startTime: double;

begin
  startTime := getSec;
  loadPNG('png\XMAS_title.png');
  writeln(format('PNG: %f',[getSec-startTime]));

  startTime := getSec;
  loadBMP('png\XMAS_title.bmp');
  writeln(format('BMP: %f',[getSec-startTime]));

  startTime := getSec;
  loadLC96('png\XMAS_title.p96');
  writeln(format('P96: %f',[getSec-startTime]));
end.