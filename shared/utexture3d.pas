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
  tTexture3D = class
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
    procedure clear(); virtual; abstract;
    constructor Create(aWidth, aHeight, aDepth: integer);
    property  width: integer read fWidth;
    property  height: integer read fHeight;
    property  depth: integer read fDepth;
    function  toString: string; override;
  end;

  tDenseTexture3D = class(tTexture3D)
  protected
    page: tPage32;
  public
    function getPixel(x,y,z: integer): RGBA; override;
    procedure setPixel(x,y,z: integer; c: RGBA); override;
    procedure clear(); override;
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

  tSparseTexture3D = class(tTexture3D)
  protected
    data: array of dword;
    procedure addCellChildren(var cell: tSVOCell);
    procedure addPixels(var cell: tSVOCell);
  public
    function  byteCount: int32;
    function  getPixel(x,y,z: integer): RGBA; override;
    procedure setPixel(x,y,z: integer; c: RGBA); override;
    function  toString: string; override;
    procedure clear(); override;
    constructor Create(aWidth, aHeight, aDepth: integer);
  end;

implementation

{-------------------------------------------------------}

{todo: do this with a lookup table}
function countBits(b: byte): byte; inline;
var
  i: integer;
begin
  result := 0;
  for i := 0 to 7 do result += ((b shr i) and 1);
end;

{-------------------------------------------------------}

constructor tTexture3D.Create(aWidth, aHeight, aDepth: integer);
begin
  inherited Create();
  setDims(aWidth, aHeight, aDepth);
end;

procedure tTexture3D.setDims(aWidth, aHeight, aDepth: integer);
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

function tTexture3D.inBounds(x,y,z: integer): boolean;
begin
  result := ((x and maskW) or (y and maskH) or (z and maskD)) = 0;
end;

function tTexture3D.getAddr(x,y,z: integer): dword; inline;
begin
  result := (x + (y + (z shl flog2Height)) shl fLog2Width);
end;

function tTexture3D.getValue(x,y,z: integer): byte;
begin
  result := getPixel(x,y,z).a;
end;

function tTexture3D.toString: string;
begin
  result := format('T3D(%d,%d,%d)',[width, height, depth]);
end;

{-------------------------------------------------------}

constructor tDenseTexture3D.Create(aWidth, aHeight, aDepth: integer);
begin
  inherited Create(aWidth, aHeight, aDepth);
  page := tPage32.Create(aWidth, aDepth*aHeight);
  clear();
end;

procedure tDenseTexture3D.clear();
begin
  page.clear(RGBA.Clear);
end;

function tDenseTexture3D.getPixel(x,y,z: integer): RGBA;
begin
  result := page.pixel^[getAddr(x,y,z)];
end;

procedure tDenseTexture3D.setPixel(x,y,z: integer; c: RGBA);
begin
  page.pixel^[getAddr(x,y,z)] := c;
end;

{-------------------------------------------------------}

{dead cells are reserved spaced. This allows for editing}
function tSVOCell.isReserved: boolean; inline;
begin
  result := data = 0;
end;

function tSVOCell.baseOffset: dword; inline;
begin
  result := data and $ffffff;
end;

function tSVOCell.mask: byte; inline;
begin
  result := data shr 24;
end;

procedure tSVOCell.setBaseOffset(aBaseOffset: dword); inline;
begin
  data := aBaseOffset + (mask shl 24);
end;

procedure tSVOCell.setMask(aMask: dword); inline;
begin
  data := baseOffset + (aMask shl 24);
end;

{-------------------------------------------------------}

constructor tSparseTexture3D.Create(aWidth, aHeight, aDepth: integer);
begin
  inherited Create(aWidth, aHeight, aDepth);
end;

function tSparseTexture3D.toString: string;
var
  cell: tSVOCell;
  pixel: RGBA;
  i: integer;
begin
  result := 'T3D:';
  for i := 0 to length(data)-1 do
    result += format(' %d:%d', [i, data[i]]);
end;

procedure tSparseTexture3D.clear();
begin
  {todo: support for non-cubes}
  setLength(data,1);
  addCellChildren(tSVOCell(data[0]));
end;

{number of bytes required to store this 3d texture}
function tSparseTexture3D.byteCount: int32;
begin
  result := length(data)*4;
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

  cell := @data[0];

  result := RGBA.Clear;

  while true do begin

    size := size shr 1;
    maskPosition := 0;
    if x >= px+size then begin
      px += size;
      maskPosition += 1;
    end;
    if y >= py+size then begin
      py += size;
      maskPosition += 2;
    end;
    if z >= pz+size then begin
      pz += size;
      maskPosition += 4;
    end;

    if (cell^.data = 0) then exit;

    if size = 1 then
      {fetch the payload}
      exit(RGBA(data[cell.baseOffset+maskPosition]));

    {otherwise expand the next cell}
    cell := @data[cell.baseOffset+maskPosition];
  end;
end;

{add a new empty cell, as well as reserve space for 8 children.
 returns based address for cell added}
procedure tSparseTexture3D.addCellChildren(var cell: tSVOCell);
var
  i: integer;
begin
  assert(cell.data = 0);
  cell.setBaseOffset(length(data));
  {reserve space for children - this allows for editing}
  setLength(data, length(data)+8);
  for i := 0 to 7 do
    data[cell.baseOffset+i] := 0;
end;

{adds 8 new pixels and returns offset}
procedure tSparseTexture3D.addPixels(var cell: tSVOCell);
var
  i: integer;
begin
  assert(cell.data = 0);
  cell.setBaseOffset(length(data));
  setLength(data, length(data)+8);
  filldword(data[cell.baseOffset], 8, 0);
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

  cell := @data[0];

  while true do begin
    maskPosition := 0;
    size := size shr 1;
    if x >= px+size then begin
      px += size;
      maskPosition += 1;
    end;
    if y >= py+size then begin
      py += size;
      maskPosition += 2;
    end;
    if z >= pz+size then begin
      pz += size;
      maskPosition += 4;
    end;

    if size = 1 then begin
      {set the payload}
      data[cell.baseOffset+maskPosition] := dword(c);
      exit;
    end;

    cell := @data[cell.baseOffset+maskPosition];

    if (cell^.data = 0) then begin
      {cell is empty, create a new cell}
      if size = 2 then begin
        {create pixel data}
        addPixels(cell^);
      end else begin
        {create a cell}
        addCellChildren(cell^);
      end;
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
  t: tTexture3D;

  procedure runRandomVoxelTest(t3d: tTexture3D);
  var
    i,j: integer;
    p1,p2,p3: V3D16;
    p: V3D16;
    x,y,z: integer;

  begin
    for i := 1 to 1 do begin
      t3d.clear();
      p1 := V3D16.make(rnd mod 8, rnd mod 8, rnd mod 8);
      p2 := V3D16.make(rnd mod 8, rnd mod 8, rnd mod 8);
      p3 := V3D16.make(rnd mod 8, rnd mod 8, rnd mod 8);
      t3d.setPixel(p1.x, p1.y, p1.z, RGB(255,0,0));
      assertEqual(T3D.getPixel(p1.x, p1.y, p1.z), RGB(255,0,0));
      t3d.setPixel(p2.x, p2.y, p2.z, RGB(0,255,0));
      assertEqual(T3D.getPixel(p2.x, p2.y, p2.z), RGB(0,255,0));
      t3d.setPixel(p3.x, p3.y, p3.z, RGB(0,0,255));
      assertEqual(T3D.getPixel(p3.x, p3.y, p3.z), RGB(0,0,255));

      for j := 0 to 15 do begin
        p := V3D16.make(rnd mod 8, rnd mod 8, rnd mod 8);
        if (p=p1) or (p=p2) or (p=p3) then continue;
        assertEqual(t3d.getPixel(p.x, p.y, p.z), RGBA.Clear, p1.toString);
      end;
    end;
  end;

begin
  t := tDenseTexture3D.Create(8,8,8);
  runRandomVoxelTest(t);
  t.free;
  t := tSparseTexture3D.Create(8,8,8);
  runRandomVoxelTest(t);
  t.free;
end;

{--------------------------------------------------------}

initialization
  tTexture3DTest.create('Texture3D');

finalization

end.
