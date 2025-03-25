{3d texture support}
unit uTexture3D;

{
3d textures are limited to power of twos
}


interface

uses
  uColor,
  uGraph32;

type
  tTexture3DBase = class
  protected
    fWidth,fHeight,fDepth: int32;
    maskH, maskW, maskD: dword;
    fRadius: single;
    fVolume: int32;
    fLog2Width,fLog2Height: byte;
  protected
    procedure setDims(aWidth, aHeight, aDepth: integer);
  public
    function inBounds(x,y,z: integer): boolean; inline;
    function getAddr(x,y,z: integer): dword; inline;
    function getPixel(x,y,z: integer): RGBA; virtual;
    function getValue(x,y,z: integer): byte; virtual;
    constructor Create(aWidth, aHeight, aDepth: integer);
    property width: integer read fWidth;
    property height: integer read fHeight;
    property depth: integer read fDepth;
  end;

  tTexture3D = class(tTexture3DBase)
  protected
    page: tPage32;
  public
    function getPixel(x,y,z: integer): RGBA; override;
    function getValue(x,y,z: integer): byte; override;
    constructor Create(aWidth, aHeight, aDepth: integer);
  end;

  tTexture3D8 = class(tTexture3DBase)
  protected
    page: tPage8;
  public
    function getAddr(x,y,z: integer): dword; inline;
    function getPixel(x,y,z: integer): RGBA; override;
    function getValue(x,y,z: integer): byte; override;
    constructor Create(aWidth, aHeight, aDepth: integer);
  end;

  tSparseTexture3D = class(tTexture3DBase)
  protected
    rowOfs: array of word;
    colOfs: array of byte;
    pData: array of RGBA;
  public
    function getPixel(x,y,z: integer): RGBA; override;
    function getValue(x,y,z: integer): byte; override;
    constructor Create(aPage: tPage; aDepth: integer); overload;
  end;

implementation

{-------------------------------------------------------}

constructor tTexture3DBase.Create(aWidth, aHeight, aDepth: integer);
begin
  inherited Create();
  setDims(aWidth, aHeight, aDepth);
end;

procedure tTexture3DBase.setDims(aWidth, aHeight, aDepth: integer);
begin
  assert(isPowerOfTwo(aWidth));
  assert(isPowerOfTwo(aDepth));
  assert(isPowerOfTwo(aHeight));
  fWidth := aWidth;
  fHeight := aHeight;
  fDepth := aDepth;
  fLog2Width := round(log2(aWidth));
  fLog2Height := round(log2(aDepth));
  fRadius := sqrt(sqr(fWidth)+sqr(fHeight)+sqr(fDepth));
  fVolume := fWidth * fHeight * fDepth;
  maskW := not (aWidth-1);
  maskH := not (aHeight-1);
  maskD := not (aDepth-1);
end;

function tTexture3DBase.inBounds(x,y,z: integer): boolean;
begin
  result := ((x and maskW) or (y and maskH) or (z and maskD)) = 0;
end;

function tTexture3DBase.getAddr(x,y,z: integer): dword; inline;
begin
  result := (x + (y + (z shl flog2Height)) shl fLog2Width);
end;

{-------------------------------------------------------}

constructor tTexture3D.Create(aWidth, aHeight, aDepth: integer);
begin
  inherited Create(aWidth, aHeight, aDepth);
  page := tPage32.Create(aWidth, aDepth*aHeight);
end;

function tTexture3D.getPixel(x,y,z: integer): RGBA;
begin
  result := (page.pixels + getAddr(x,y,z))^;
end;

function tTexture3D.getValue(x,y,z: integer): byte;
begin
  result := (page.pixels + getAddr(x,y,z))^.a;
end;

{-------------------------------------------------------}

constructor tTexture3D8.Create(aWidth, aHeight, aDepth: integer);
begin
  inherited Create(aWidth, aHeight, aDepth);
  page := tPage8.Create(aWidth, aDepth*aHeight);
end;

function tTexture3D8.getPixel(x,y,z: integer): RGBA;
var
  v: byte;
begin
  v := (page.pixels + getAddr(x,y,z))^;
  result.r := v; result.g := v; result.b := v; result.a := 255;
end;

function tTexture3D8.getValue(x,y,z: integer): byte;
begin
  result := (page.pixels + getAddr(x,y,z))^.a;
end;

{-------------------------------------------------------}

function tSparseTexture3D.getPixel(x,y,z: integer): RGBA;
var
  p: pointer;
begin

end;

function tSparseTexture3D.getValue(x,y,z: integer): byte;
begin
  result := getPixel(x,y,z).a;
end;

constructor tSparseTexture3D.Create(aPage: tPage; aDepth: integer);
begin
  inherited Create(aPage.width, aPage.height*aDepth);
  fromPage(aPage, aDepth);
end;

function tSparseTexture3D.fromPage(aPage: tPage; aDepth: integer);
var
  row: integer;
  col: integer;
  numRows: integer;
  usedRows: integer;
  pixels: pRGBA;
  allEmpty: boolean;

begin
  assert(aPage.width = 16);
  setDims(aPage.width, aPage.height div aDepth, aDepth);

  {add zero column}
  numRows := height * depth

  setLength(rowOfs, numRows);
  setLength(colOfs, (8 * numRows)+1);
  setLength(pData, numRows+8);

  {create an empty row}
  fillchar(rowOfs[0], length(rowOfs)*2, 0);
  fillchar(colOfs[0], length(colOfs)*1, 0);
  fillchar(pData[0], length(pData)*4, 0);

  pixels := @aPage.pixels^[0];

  for row := 0 to numRows-1 do begin
    {check if all zeros}
    allEmpty := true;
    for col := 0 to 15 do
      if pixels^.a <> 0 then begin
        allEmpty := false;
        break;
      end;
  end;

  rowOfs: pWord;
  colOfs: pByte;
  pData: pointer;
end;

begin
end.
