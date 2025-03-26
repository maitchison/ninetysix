{3d texture support}
unit uTexture3D;

{
3d textures are limited to power of twos
}


interface

uses
  uTest,
  uDebug,
  uVertex,
  uUtils,
  uColor,
  uGraph8,
  uGraph32;

type
  tTexture3DBase = class
  protected
    fWidth,fHeight,fDepth: int32;
    maskH, maskW, maskD: dword;
    fRadius: single;
    fVolume: int32;
    fLog2Width,fLog2Height,fLog2Depth: byte;
  protected
    procedure setDims(aWidth, aHeight, aDepth: integer);
  public
    function  inBounds(x,y,z: integer): boolean; inline;
    function  getAddr(x,y,z: integer): dword; inline;
    function  getPixel(x,y,z: integer): RGBA; virtual; abstract;
    procedure setPixel(x,y,z: integer; c: RGBA); virtual; abstract;
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
    procedure setPixel(x,y,z: integer; c: RGBA); override;
    constructor Create(aWidth, aHeight, aDepth: integer);
  end;

  tSVOCell = record
    data: dword;
    function  isReserved: boolean; inline;
    function  baseOffset: dword; inline; {24bit}
    function  mask: byte; inline;
    procedure setBaseOffset(aBaseOffset: dword); inline;
    procedure setMask(aMask: dword); inline;
  end;

  pSVOCell = ^tSVOCell;

  tSparseTexture3D = class(tTexture3DBase)
  protected
    cells: array of tSVOCell;
    pixels: array of RGBA;
    function  addCell(): integer;
    function  addPixels(): integer;
  public
    function  getPixel(x,y,z: integer): RGBA; override;
    procedure setPixel(x,y,z: integer; c: RGBA); override;
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
  fLog2Height := round(log2(aHeight));
  fLog2Depth := round(log2(aDepth));
  fRadius := sqrt(sqr(fWidth)+sqr(fHeight)+sqr(fDepth));
  fVolume := fWidth * fHeight * fDepth;
  maskW := dword(-1) xor (aWidth-1);
  maskH := dword(-1) xor (aHeight-1);
  maskD := dword(-1) xor (aDepth-1);
end;

function tTexture3DBase.inBounds(x,y,z: integer): boolean;
begin
  result := ((x and maskW) or (y and maskH) or (z and maskD)) = 0;
end;

function tTexture3DBase.getAddr(x,y,z: integer): dword; inline;
begin
  result := (x + (y + (z shl flog2Height)) shl fLog2Width);
end;

function tTexture3DBase.getValue(x,y,z: integer): byte;
begin
  result := getPixel(x,y,z).a;
end;

{-------------------------------------------------------}

constructor tTexture3D.Create(aWidth, aHeight, aDepth: integer);
begin
  inherited Create(aWidth, aHeight, aDepth);
  page := tPage32.Create(aWidth, aDepth*aHeight);
  page.clear(RGBA.Clear);
end;

function tTexture3D.getPixel(x,y,z: integer): RGBA;
begin
  result := page.pixel^[getAddr(x,y,z)];
end;

procedure tTexture3D.setPixel(x,y,z: integer; c: RGBA);
begin
  page.pixel^[getAddr(x,y,z)] := c;
end;

{-------------------------------------------------------}

{dead cells are reserved spaced. This allows for editing}
function tSVOCell.isReserved: boolean; inline;
begin
  result := baseOffset = 0;
end;

function tSVOCell.baseOffset: dword; inline;
begin
  result := data shr 8;
end;

function tSVOCell.mask: byte; inline;
begin
  result := data and $ff;
end;

procedure tSVOCell.setBaseOffset(aBaseOffset: dword); inline;
begin
  data := (aBaseOffset shl 8) + mask;
end;

procedure tSVOCell.setMask(aMask: dword); inline;
begin
  data := (baseOffset shr 8) + aMask;
end;

{-------------------------------------------------------}

constructor tSparseTexture3D.Create(aWidth, aHeight, aDepth: integer);
begin
  {make sure we are a cube}
  inherited Create(aWidth, aHeight, aDepth);
  addCell();
end;

{todo: do this with a lookup table}
function countBits(b: byte): byte; inline;
var
  i: integer;
begin
  result := 0;
  for i := 0 to 7 do result += ((b shr i) and 1);
end;

function tSparseTexture3D.getPixel(x,y,z: integer): RGBA;
var
  d: integer;
  px,py,pz: integer; {current topleftupper}
  size: integer; {current cell size}
  cell: pSVOCell;
  maskPosition: byte;
begin
  d := 0;
  px := 0;
  py := 0;
  pz := 0;

  // todo: set this to root size
  size := width;

  cell := @cells[0];

  result := RGBA.Clear;

  while true do begin

    size := size shr 1;
    maskPosition := 0;
    if x < px+size then begin
      px += size;
      maskPosition += 1;
    end;
    if y < py+size then begin
      py += size;
      maskPosition += 2;
    end;
    if z < py+size then begin
      pz += size;
      maskPosition += 4;
    end;

    if (cell^.mask shr maskPosition) and $1 = $0 then exit;

    if size = 1 then
      {fetch the payload}
      exit(pixels[cell.baseOffset+maskPosition]);

    {otherwise expand the next cell}
    cell := @cells[cell.baseOffset+maskPosition];
  end;
end;

{add a new empty cell, as well as reserve space for 8 children.
 returns based address for cell added}
function tSparseTexture3D.addCell(): integer;
var
  i: integer;
  reservedCell: tSVOCell;
  cell: tSVOCell;
begin
  fillchar(cell, sizeof(cell), 0);
  setLength(cells, length(cells)+1);
  cells[length(cells)-1] := cell;
  cell.setBaseOffset(length(cells));
  {reserve space for children - this allows for editing}
  fillchar(reservedCell, sizeof(reservedCell), 0);
  setLength(cells, length(cells)+8);
  for i := 0 to 7 do
    cells[cell.baseOffset+i] := reservedCell;
  result := cell.baseOffset;
end;

{adds 8 new pixels and returns offset}
function tSparseTexture3D.addPixels(): integer;
var
  i: integer;
begin
  result := length(pixels);
  setLength(pixels, length(pixels)+8);
  fillchar(pixels[result], 8*4, 0);
end;

procedure tSparseTexture3D.setPixel(x,y,z: integer;c: RGBA);
var
  d: integer;
  px,py,pz: integer; {current topleftupper}
  size: integer; {current cell size}
  cell: pSVOCell;
  maskPosition: byte;
begin
  d := 0;
  px := 0;
  py := 0;
  pz := 0;

  // todo: set this correctly to initial size
  size := width;

  cell := @cells[0];

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
    if z < py+size then begin
      pz += size;
      maskPosition += 4;
    end;

    if size = 1 then begin
      {set the payload}
      pixels[cell.baseOffset+maskPosition] := c;
      exit;
    end;

    if (cell^.mask shr maskPosition) and $1 = $0 then begin
      {cell is empty, create a new cell}
      cell.setMask(cell^.mask or (1 shl maskPosition));
      if size = 2 then begin
        {create pixel data}
        cell.setBaseOffset(addPixels());
      end else
        {create a cell}
        cell.setBaseOffset(addCell());
    end else begin
      {otherwise move to next cell}
      cell := @cells[cell.baseOffset+maskPosition];
    end;
  end;
end;


{--------------------------------------------------------}

type
  tTexture3DTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tTexture3DTest.run();
var
  T3D: tTexture3D;
  i,j: integer;
  p1,p2,p3: V3D16;
  p: V3D16;
  x,y,z: integer;
begin

  for i := 1 to 10 do begin
    T3D := tTexture3D.Create(8,8,8);
    p1 := V3D16.make(rnd mod 8, rnd mod 8, rnd mod 8);
    p2 := V3D16.make(rnd mod 8, rnd mod 8, rnd mod 8);
    p3 := V3D16.make(rnd mod 8, rnd mod 8, rnd mod 8);
    T3D.setPixel(p1.x, p1.y, p1.z, RGB(255,0,0));
    T3D.setPixel(p2.x, p2.y, p2.z, RGB(0,255,0));
    T3D.setPixel(p3.x, p3.y, p3.z, RGB(0,0,255));
    assertEqual(T3D.getPixel(p1.x, p1.y, p1.z), RGB(255,0,0));
    assertEqual(T3D.getPixel(p2.x, p2.y, p2.z), RGB(0,255,0));
    assertEqual(T3D.getPixel(p3.x, p3.y, p3.z), RGB(0,0,255));
    for j := 0 to 15 do begin
      p := V3D16.make(rnd mod 8, rnd mod 8, rnd mod 8);
      if (p = p1) or (p=p2) or (p=p3) then continue;
      assertEqual(T3D.getPixel(p.x, p.y, p.z), RGBA.Clear);
    end;
    T3D.free();
  end;

end;

{--------------------------------------------------------}

var
  i: integer;

initialization
  tTexture3DTest.create('Texture3D');

finalization

end.
