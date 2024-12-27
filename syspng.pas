{PNG loading support}
unit sysPng;

// --------------------------------------------------------------------
//
// Importing this unit will import a lot of system stuff (400k?),
// so I don't really like to use it. However, converting all the
// PNGs to BMP by hand was annoying, so we'll make use of this
// during mastering only.
//
// --------------------------------------------------------------------

interface

uses
  graph32;

function loadPNG(const FileName: string): tPage;

implementation

uses
  utils,
  debug,
  FPImage,
  FPReadPNG;

{reads a PNG file and returns it as a tPage}
function loadPNG(const FileName: string): tPage;
var
  PNGReader: tFPReaderPNG;
  img: tFPMemoryImage;
  x,y: int32;
  col16: tFPColor;
  col: RGBA;
  startTime: double;
begin

  PNGReader := tFPReaderPNG.create();
  img := tFPMemoryImage.create(0,0);

  try

    startTime := getSec;
    img.loadFromFile(filename, PNGReader);
    note(format(' - loaded PNG in %fs', [getSec-startTime]));
    result := tPage.create(img.width, img.height);

    startTime := getSec;
    for y := 0 to img.height-1 do begin
      for x := 0 to img.width-1 do begin
        col16 := img.colors[x,y];
        col := RGBA.create(col16.red shr 8, col16.green shr 8, col16.blue shr 8, col16.alpha shr 8);
        result.setPixel(x, y, col);
      end;
    end;

  finally
    PNGReader.free;
    img.free;
  end;
end;

begin
end.
