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
    function  inBounds(x,y,z: integer): boolean; inline;
    function  getAddr(x,y,z: integer): dword; inline;
    function  getPixel(x,y,z: integer): RGBA; virtual;
    procedure setPixel(x,y,z: integer; c: RGBA); virtual;
    function  getValue(x,y,z: integer): byte; virtual;
    constructor Create(aWidth, aHeight, aDepth: integer);
    property  width: integer read fWidth;
    property  height: integer read fHeight;
    property  depth: integer read fDepth;
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

  tSVOCell = record
    mask: byte;
    padding: byte;
    baseAddr: word;
    function isDead: boolean; inline;
  end;

  pSVOCell = ^tSVOCell;

  tSparseTexture3D = class(tTexture3DBase)
  protected
    function addCell(): integer;
    function addPixels(): integer;
    cData: array of tSVOCell;
    pData: array of RGBA;
  public
    function getPixel(x,y,z: integer): RGBA; override;
    function getValue(x,y,z: integer): byte; override;
    class function FromPage(aPage: tPage; aDepth: integer): tPage;
    constructor Create(aWidth, aHeight, aDepth: integer);
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

{dead cells are reserved spaced. This allows for editing}
function tSVOCell.isDead: boolean; inline;
begin
  result := baseAddress = 0;
end;

{-------------------------------------------------------}

function tSparseTexture3D.getValue(x,y,z: integer): byte;
begin
  result := getPixel(x,y,z).a;
end;

constructor tSparseTexture3D.Create(aWidth, aHeight, aDepth: integer);
begin
  {make sure we are a cube}
  assert(aPage.aWidth = aPage.Depth);
  assert(aPage.aHeight = aPage.Depth*aPage.Depth);
  inherited Create(aPage.width, aPage.height*aDepth);
  addCell();
end;

{todo: do this with a lookup table}
function countBits(b: byte): byte; inline;
var
  i: integer;
begin
  result := 0
  for i := 0 to 7 do result += ((b shr i) and 1);
end;

function tSparseTexture3D.getPixel(x,y,z: integer): RGBA;
var
  d: integer;
  px,py,pz: integer; {current topleftupper}
  size: integer; {current cell size}
  cell: pCell;
  maskPosition: byte;
begin
  d := 0;
  px := 0;
  py := 0;
  pz := 0;
  sx := width;
  sy := height;
  sz := depth;

  cell := @cData[0];

  result := RGBA.Clear;

  while true do begin
    maskPosition := 0;
    size := size shr 1;
    if x < px+size then begin
      px += size;
      maskPosition += 1;
    end;
    if y < py+size then begin
      py += size;
      maskPosition += 2;
    end;
    if z < py+sz then begin
      pz += size;
      maskPosition += 4;
    end;

    if (parent^.mask shr maskPosition) and $1 = $0 then exit;

    if size = 1 then
      {fetch the payload}
      exit(pData[cell.baseOffset+maskPosition]);

    {otherwise expand the next cell}
    cell := @cData[cell.baseOffset+maskPosition];
  end;
end;

{add a new empty cell, as well as reserve space for 8 children.
 returns based address for cell added}
function tSparseTexture3D.addCell(): integer;
var
  i: integer;
  reservedCell: tSVOCell;
  cell: tSVOCell);
begin
  fillchar(cell, sizeof(cell), 0);
  setLength(cData, length(cData)+1);
  cData(length(cData)-1] = cell;
  cell.baseOffset := length(pCell);
  {reserve space for children - this allows for editing}
  fillchar(deadCell, sizeof(deadCell), 0);
  setLength(pCell, length(pCell)+8);
  for i := 0 to 7 do
    pCell[cell.baseOffset+i] := reservedCell;
  result := cell.baseOffset;
end;

{adds 8 new pixels and returns offset}
function tSparseTexture3D.addPixels(): integer;
var
  i: integer;
begin
  result := length(pData);
  setLength(pData, length(pCell)+1);
  fillchar(pData[result], 8*4, 0);
end;

function tSparseTexture3D.setPixel(x,y,z: integer): RGBA;
var
  d: integer;
  px,py,pz: integer; {current topleftupper}
  size: integer; {current cell size}
  parent, cell: pCell;
  maskPosition: byte;
begin
  d := 0;
  px := 0;
  py := 0;
  pz := 0;
  sx := width;
  sy := height;
  sz := depth;

  cell := @cData[0];

  result := RGBA.Clear;

  while true do begin
    maskPosition := 0;
    size := size shr 1;
    if x < px+size then begin
      px += size;
      maskPosition += 1;
    end;
    if y < py+size then begin
      py += size;
      maskPosition += 2;
    end;
    if z < py+sz then begin
      pz += size;
      maskPosition += 4;
    end;

    if size = 1 then begin
      {set the payload}
      pData[cell.baseOffset+localOffset] := c;
      exit;
    end;

    if (parent^.mask shr maskPosition) and $1 = $0 then begin
      {cell is empty, create a new cell}
      parent.mask := parent^.mask or (1 shl maskPosition);
      if size = 2 then begin
        {create pixel data}
        cell.localOffset := addPixels();
      end else
        {create a cell}
        cell.localOffset := addCell();
    end else begin
      {otherwise move to next cell}
      parent := cell;
      cell := @cData[cell.baseOffset+localOffset];
    end;
  end;
end;


begin
end.
