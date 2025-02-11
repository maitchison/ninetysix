unit bmp;

interface

uses
  debug,
  test,
  utils,
  resource,
  graph32;

function loadBMP(const fileName: string): tPage;

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

function LoadBMP(const fileName: string): tPage;
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
    Error('Could not open file "'+FileName+'" '+getIOErrorString(IOError));

  BlockRead(F, FileHeader, SizeOf(TBMPHeader), BytesRead);
  if BytesRead <> SizeOf(TBMPHeader) then
    Error('Error reading BMP Headed.');

  BlockRead(F, InfoHeader, SizeOf(TBitmapInfoHeader), BytesRead);
  if BytesRead <> Sizeof(TBitmapInfoHeader) then
    Error('Error reading BMP Info Header.');

  if (FileHeader.FileType <> $4D42) then
    Error(format('Not a valid BMP file, found $%h, expected $%h', [FileHeader.FileType, $4D42]));

  if not (InfoHeader.BitsPerPixel in [8, 24, 32]) then
    Error(
      'Only 8, 24, and 32-bit BMP images are supported, but "'+FileName+'" is '+
      intToStr(InfoHeader.BitsPerPixel)+'-bit');

  result.Width := InfoHeader.Width;
  result.Height := InfoHeader.Height;
  result.BPP := InfoHeader.BitsPerPixel;

  BytesPerPixel := result.BPP div 8;
  LineWidth := result.Width * BytesPerPixel;
  while LineWidth mod 4 <> 0 do
    inc(LineWidth);

  Seek(F, FileHeader.Offset);

  SetLength(LineData, LineWidth);

  result.Pixels := getMem(InfoHeader.PixelCount * 4);
  fillchar(result.pixels^, InfoHeader.PixelCount * 4, 255);

  for y := result.Height-1 downto 0 do begin
    BlockRead(F, LineData[0], LineWidth, BytesRead);
    for x := 0 to result.Width-1 do begin
      {ignore alpha for the moment}
      case Result.BPP of
        8:
          {assume 8bit is monochrome}
          c.init(LineData[x], LineData[x], LineData[x], 255);
        24:
          c.init(LineData[x*3+2], LineData[x*3+1], LineData[x*3+0], 255);
        32:
          c.init(LineData[x*4+2], LineData[x*4+1], LineData[x*4+0], LineData[x*4+3]);
        else
          Error('Invalid Bitmap depth '+IntToStr(Result.BPP));
      end;
      result.PutPixel(x, y, c);
    end;
  end;

  Close(F);

  {todo: don't store bitmap depth in result.bpp}
  result.BPP := 32;
end;

{----------------------------------------------}

begin
  registerResourceLoader('bmp', @loadBMP);
end.
