{represents a single dungeon floor}
unit uMap;

interface

uses
  uTest,
  uDebug,
  uFileSystem,
  uStream,
  uUtils;

type

  tWallType = (wtNone, wtWall, wtDoor, wtSecret, wtLockedDoor);
  tFloorType = (ftNone, ftStone, ftWater, ftDirt, ftGrass);
  tMediumType = (mtNone, mtFog, mtRock);
  tDirection = (dNorth, dEast, dSouth, dWest);

  tFloorSpec = record
    tag: string;
    spriteIdx: integer;
  end;

const
  FLOOR_SPEC: array[tFloorType] of tFloorSpec =
   (
    (tag: 'None'; spriteIdx: -1),
    (tag: 'Stone'; spriteIdx: -1),
    (tag: 'Water'; spriteIdx: 15),
    (tag: 'Dirt'; spriteIdx: 16),
    (tag: 'Grass'; spriteIdx: 26)
   );

  MEDIUM_SPRITE: array[tMediumType] of integer =
    (-1, 20, 19);

  {+1 for rotated varient}
  WALL_SPRITE: array[tWallType] of integer =
    (-1, 0, 2, 4, 32+4);

  CURSOR_SPRITE = 19+32;

  MD_X: array[tDirection] of integer = (0,+8,0,-7);
  MD_Y: array[tDirection] of integer = (-7,0,+8,0);

type

  {4 bytes per wall}
  tWall = packed record
    t: tWallType;
    variation: byte;
    padding: word;
    procedure clear();
  end;

  {8 bytes per tile}
  tTile = packed record
    attributes: bitpacked array[0..31] of boolean;  {4 bytes}
    floorType: tFloorType;                          {1 byte}
    mediumType: tMediumType;                        {1 byte}
    padding: word;                                  {2 bytes}
    procedure clear();
    function floorSpec: tFloorSpec;
  end;

  tMap = class
  protected
    fWidth,fHeight: integer;
    fTile: array of tTile;
    fNorthWall, fWestWall: array of tWall;
    function  getTile(x,y: integer): tTile;
    procedure setTile(x,y: integer; aTile: tTile);
    function  getWall(x,y: integer; d: tDirection): tWall;
    procedure setWall(x,y: integer; d: tDirection;aWall: tWall);
    procedure init(aWidth, aHeight: integer);
  public
    constructor Create(aWidth, aHeight: word);
    destructor destroy(); override;
    procedure save(filename: string);
    procedure load(filename: string);
    procedure clear();
  public
    property width: integer read fWidth;
    property height: integer read fHeight;
    property tile[x,y: integer]: tTile read getTile write setTile;
    property wall[x,y: integer;d: tDirection]: tWall read getWall;
  end;

implementation

{-------------------------------------------------}

type
  {32 bytes}
  tMapHeader = packed record
    tag: string[4]; // MDRM     {4 bytes}
    width, height: word;        {4 bytes}
    padding: array[1..24] of byte; {24 bytes}
  end;

{-------------------------------------------------}

procedure tTile.clear();
begin
  fillchar(self, sizeof(self), 0);
end;

function tTile.floorSpec: tFloorSpec;
begin
  result := FLOOR_SPEC[floorType];
end;

{-------------------------------------------------}

procedure tWall.clear();
begin
  fillchar(self, sizeof(self), 0);
end;

{-------------------------------------------------}

constructor tMap.Create(aWidth, aHeight: word);
begin
  inherited Create();
  init(aWidth, aHeight);
end;

destructor tMap.destroy();
begin
  setLength(fTile, 0);
  setLength(fNorthWall, 0);
  setLength(fWestWall, 0);
  inherited destroy();
end;

{initialize a map to given size}
procedure tMap.init(aWidth, aHeight: integer);
var
  i: integer;
begin
  fWidth := aWidth;
  fHeight := aHeight;
  setLength(fTile, aWidth * aHeight);
  setLength(fNorthWall, (aWidth+1) * (aHeight+1));
  setLength(fWestWall, (aWidth+1) * (aHeight+1));
  for i := 0 to length(fTile)-1 do fTile[i].clear();
  for i := 0 to length(fNorthWall)-1 do fNorthWall[i].clear();
  for i := 0 to length(fWestWall)-1 do fWestWall[i].clear();
end;

function tMap.getTile(x,y: integer): tTile;
begin
  if (word(x) >= width) or (word(y) >= height) then raise ValueError('Out of bounds tile co-ords (%d,%d)', [x, y]);
  result := fTile[x+y*fWidth];
end;

procedure tMap.setTile(x,y: integer;aTile: tTile);
begin
  if (word(x) >= width) or (word(y) >= height) then raise ValueError('Out of bounds tile co-ords (%d,%d)', [x, y]);
  fTile[x+y*fWidth] := aTile;
end;

function tMap.getWall(x,y: integer;d: tDirection): tWall;
begin
  if (word(x) >= width) or (word(y) >= height) then raise ValueError('Out of bounds tile co-ords (%d,%d)', [x, y]);
  case d of
    dNorth: result := fNorthWall[x+y*(fWidth+1)];
    dWest: result := fWestWall[x+y*(fWidth+1)];
    dSouth: result := fNorthWall[x+(y+1)*(fWidth+1)];
    dEast: result := fWestWall[(x+1)+y*(fWidth+1)];
  end;
end;

procedure tMap.setWall(x,y: integer;d: tDirection; aWall: tWall);
begin
  if (word(x) >= width) or (word(y) >= height) then raise ValueError('Out of bounds tile co-ords (%d,%d)', [x, y]);
  case d of
    dNorth: fNorthWall[x+y*(fWidth+1)] := aWall;
    dWest: fWestWall[x+y*(fWidth+1)] := aWall;
    dSouth: fNorthWall[x+(y+1)*(fWidth+1)] := aWall;
    dEast: fWestWall[(x+1)+y*(fWidth+1)] := aWall;
  end;
end;

procedure tMap.save(filename: string);
var
  f: tFileStream;
  header: tMapHeader;
begin
  fillchar(header, sizeof(header), 0);
  header.tag := 'MDRM';
  header.width := width;
  header.height := height;
  f := tFileStream.Create(filename, FM_WRITE);
  f.writeBlock(header, sizeof(header));
  f.writeBlock(fTile[0], sizeof(fTile[0])*length(fTile));
  f.writeBlock(fNorthWall[0], sizeof(fNorthWall[0])*length(fNorthWall));
  f.writeBlock(fWestWall[0], sizeof(fWestWall[0])*length(fWestWall));
  f.flush();
  f.free();
end;

procedure tMap.load(filename: string);
var
  f: tFileStream;
  header: tMapHeader;
begin

  header.tag := 'MDRM';
  header.width := width;
  header.height := height;

  f := tFileStream.Create(filename);

  f.readBlock(header, sizeof(header));
  if (header.tag <> 'MDRM') then raise ValueError('Invalid map');
  init(header.width, header.height);

  f.readBlock(fTile[0], sizeof(fTile[0])*length(fTile));
  f.readBlock(fNorthWall[0], sizeof(fNorthWall[0])*length(fNorthWall));
  f.readBlock(fWestWall[0], sizeof(fWestWall[0])*length(fWestWall));
  f.free();
end;

procedure tMap.clear();
var
  tile: tTile;
  wall: tWall;
begin
  for tile in fTile do tile.clear();
  for wall in fNorthWall do wall.clear();
  for wall in fWestWall do wall.clear();
end;

{----------------------------------------------------------}

type
  tMapTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tMapTest.run();
var
  tile: tTile;
  wall: tWall;
begin
  {make sure everything is the right size, as we'll need this for loading/saving}
  assertEqual(sizeof(tile), 8);
  assertEqual(sizeof(wall), 4);
end;

{--------------------------------------------------------}

var
  i: integer;

initialization
  tMapTest.create('Map');
end.
