unit uBmp;

interface

uses
  uDebug,
  uTest,
  uUtils,
  uResource,
  uColor,
  uGraph32;

function loadBMP(fileName: string): tPage;

implementation

type
  TBMPHeader = packed record
    FileType: Word;
    FileSize: Cardinal;
    Reserved1: Word;
    Reserved2: Word;
    Offset: Cardinal;
  end;

  TBitmapInfoHeader = packed record
    Size: Cardinal;
    Width: Integer;
    Height: Integer;
    Planes: Word;
    BitsPerPixel: Word;
    Compression: Cardinal;
    SizeImage: Cardinal;
    XPelsPerMeter: Integer;
    YPelsPerMeter: Integer;
    ClrUsed: Cardinal;
    ClrImportant: Cardinal;

    function ByteCount(): Cardinal;
    function PixelCount(): Cardinal;
  end;

{----------------------------------------------}

{SizeImage is often zero, so calculate the number of bytes here.}
function TBitmapInfoHeader.ByteCount(): Cardinal;
begin
  result := PixelCount * BitsPerPixel div 8;
end;

{SizeImage is often zero, so calculate the number of bytes here.}
function TBitmapInfoHeader.PixelCount(): Cardinal;
begin
  result := Width * Height;
end;

{----------------------------------------------}

function LoadBMP(fileName: string): tPage; register;
var
  FileHeader: TBMPHeader;
  InfoHeader: TBitmapInfoHeader;
  f: File;

  lineWidth: integer;
  x, y, i: integer;
  c: RGBA;
  linePadding: integer;
  lineData: Array of byte;

  BytesPerPixel: integer;

  BytesRead: int32;
  IOError: word;
begin

  result := tPage.create();

  FileMode := 0; {read only}
  Assign(F, FileName);
  {$I-}
  Reset(F, 1);
  {$I+}
  IOError := IOResult;
  if IOError <> 0 then
    fatal('Could not open file "'+FileName+'" '+getIOErrorString(IOError));

  BlockRead(F, FileHeader, SizeOf(TBMPHeader), BytesRead);
  if BytesRead <> SizeOf(TBMPHeader) then
    fatal('Error reading BMP Headed.');

  BlockRead(F, InfoHeader, SizeOf(TBitmapInfoHeader), BytesRead);
  if BytesRead <> Sizeof(TBitmapInfoHeader) then
    fatal('Error reading BMP Info Header.');

  if (FileHeader.FileType <> $4D42) then
    fatal(format('Not a valid BMP file, found $%h, expected $%h', [FileHeader.FileType, $4D42]));

  if not (InfoHeader.BitsPerPixel in [8, 24, 32]) then
    fatal(
      'Only 8, 24, and 32-bit BMP images are supported, but "'+FileName+'" is '+
      intToStr(InfoHeader.BitsPerPixel)+'-bit');

  result.Width := InfoHeader.Width;
  result.Height := InfoHeader.Height;

  BytesPerPixel := InfoHeader.BitsPerPixel div 8;
  LineWidth := result.Width * BytesPerPixel;
  while LineWidth mod 4 <> 0 do
    inc(LineWidth);

  Seek(F, FileHeader.Offset);

  SetLength(LineData, LineWidth);

  result.pData := getMem(InfoHeader.PixelCount * 4);
  fillchar(result.pData^, InfoHeader.PixelCount * 4, 255);

  for y := result.Height-1 downto 0 do begin
    BlockRead(F, LineData[0], LineWidth, BytesRead);
    for x := 0 to result.Width-1 do begin
      {ignore alpha for the moment}
      case InfoHeader.BitsPerPixel of
        8:
          {assume 8bit is monochrome}
          c.init(LineData[x], LineData[x], LineData[x], 255);
        24:
          c.init(LineData[x*3+2], LineData[x*3+1], LineData[x*3+0], 255);
        32:
          c.init(LineData[x*4+2], LineData[x*4+1], LineData[x*4+0], LineData[x*4+3]);
        else
          fatal('Invalid Bitmap depth '+IntToStr(InfoHeader.BitsPerPixel));
      end;
      result.PutPixel(x, y, c);
    end;
  end;

  Close(F);

end;

{----------------------------------------------}

begin
  registerResourceLoader('bmp', @loadBMP);
end.
