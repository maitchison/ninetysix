{represents a single dungeon floor}
unit uMDRMap;

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

  tWallSpec = record
    tag: string;
    canTransit: boolean;
  end;

const

  WALL_SPEC: array[tWallType] of tWallSpec =
  (
    (tag: 'None';       canTransit: true),
    (tag: 'Wall';       canTransit: false),
    (tag: 'Door';       canTransit: true),
    (tag: 'Secret';     canTransit: true),
    (tag: 'LockedDoor'; canTransit: false)
  );

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
  PARTY_SPRITE = 6;

  WALL_DX: array[tDirection] of integer = (0,+8,0,-7);
  WALL_DY: array[tDirection] of integer = (-7,0,+8,0);

  DX: array[tDirection] of integer = (0,+1,0,-1);
  DY: array[tDirection] of integer = (-1,0,+1,0);

type

  tExplorationStatus = (eNone, ePartial, eFull);

  tVisionStatus = bitpacked record
    explored: tExplorationStatus;
    recent: boolean;
  end;

  {8 bytes per wall}
  tWall = packed record
    t: tWallType;
    variation: byte;
    status: tVisionStatus;
    padding: array[1..5] of byte;
    procedure clear();
    function asExplored(): tWall;
    function isSolid: boolean;
    function toString(): string;
  end;

  {16 bytes per tile}
  tTile = packed record
    attributes: bitpacked array[0..31] of boolean;  {4 bytes}
    floor: tFloorType;                              {1 byte}
    medium: tMediumType;                            {1 byte}
    status: tVisionStatus;                          {1 byte}
    padding: array[1..9] of byte;                   {9 bytes}
    procedure clear();
    function floorSpec: tFloorSpec;
    function asExplored(): tTile;
    function toString(): string;
  end;

  pTile = ^tTile;
  pWall = ^tWall;

  tMDRMap = class
  protected
    fWidth,fHeight: integer;
    fTile: array of tTile;
    fWall: array of tWall; {ordered north, west, north, west etc...}
    function  getTile(x,y: integer): tTile;
    function  getWall(x,y: integer; d: tDirection): tWall;
    procedure setTile(x,y: integer; aTile: tTile);
    procedure setWall(x,y: integer; d: tDirection;aWall: tWall);
    function  getWallIdx(x,y: integer;d: tDirection): integer;
    function  getTileIdx(x,y: integer): integer;
    procedure init(aWidth, aHeight: integer);
  public
    constructor Create(aWidth, aHeight: word);
    destructor destroy(); override;
    procedure  save(filename: string);
    procedure  load(filename: string);
    procedure  clear();
    procedure  setExplored(aExplored: tExplorationStatus);
  public
    property width: integer read fWidth;
    property height: integer read fHeight;
    property tile[x,y: integer]: tTile read getTile write setTile;
    property wall[x,y: integer;d: tDirection]: tWall read getWall write setWall;
  end;

implementation

{-------------------------------------------------}

type
  {32 bytes}
  tMDRMapHeader = packed record
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
  result := FLOOR_SPEC[floor];
end;

{returns copy of tile with exploration limited applied}
function tTile.asExplored(): tTile;
begin
  result := self;
  case status.explored of
    eNone: begin
      result.floor := ftNone;
      result.medium := mtNone;
    end;
    ePartial:;
    eFull: ;
  end;
end;

function tTile.toString(): string;
begin
  // medium set to none for the moment.
  result := FLOOR_SPEC[floor].tag+'-None'
end;

{-------------------------------------------------}

procedure tWall.clear();
begin
  fillchar(self, sizeof(self), 0);
end;

function tWall.isSolid: boolean;
begin
  result := t in [wtWall, wtLockedDoor];
end;

function tWall.toString(): string;
begin
  result := WALL_SPEC[t].tag;
end;

{returns copy of tile with exploration limited applied}
function tWall.asExplored(): tWall;
begin
  result := self;
  case status.explored of
    eNone: result.t := wtNone;
    ePartial: begin
      if result.t = wtSecret then result.t := wtWall;
    end;
    eFull: ;
  end;
end;

{-------------------------------------------------}

constructor tMDRMap.Create(aWidth, aHeight: word);
begin
  inherited Create();
  init(aWidth, aHeight);
end;

destructor tMDRMap.destroy();
begin
  setLength(fTile, 0);
  setLength(fWall, 0);
  inherited destroy();
end;

{initialize a map to given size}
procedure tMDRMap.init(aWidth, aHeight: integer);
var
  i: integer;
begin
  fWidth := aWidth;
  fHeight := aHeight;
  setLength(fTile, aWidth * aHeight);
  setLength(fWall, 2 * (aWidth+1) * (aHeight+1));
  for i := 0 to length(fTile)-1 do fTile[i].clear();
  for i := 0 to length(fWall)-1 do fWall[i].clear();
end;

function tMDRMap.getTile(x,y: integer): tTile;
begin
  result := fTile[getTileIdx(x,y)];
end;

procedure tMDRMap.setTile(x,y: integer;aTile: tTile);
begin
  fTile[getTileIdx(x,y)] := aTile;
end;

function tMDRMap.getTileIdx(x,y: integer): integer;
begin
  if (word(x) >= width) or (word(y) >= height) then raise ValueError('Out of bounds tile co-ords (%d,%d)', [x, y]);
  result := x+y*fWidth;
end;

function tMDRMap.getWallIdx(x,y: integer;d: tDirection): integer;
begin
  if (word(x) >= width) or (word(y) >= height) then raise ValueError('Out of bounds tile co-ords (%d,%d)', [x, y]);
  case d of
    dNorth: result := 2*(x+y*(fWidth+1));
    dWest:  result := 2*(x+y*(fWidth+1))+1;
    dSouth: result := 2*(x+(y+1)*(fWidth+1));
    dEast:  result := 2*((x+1)+y*(fWidth+1))+1;
    else fatal('Invalid direction');
  end;
end;

function tMDRMap.getWall(x,y: integer;d: tDirection): tWall;
begin
  result := fWall[getWallIdx(x,y,d)];
end;

procedure tMDRMap.setWall(x,y: integer;d: tDirection; aWall: tWall);
begin
  fWall[getWallIdx(x,y,d)] := aWall;
end;

procedure tMDRMap.save(filename: string);
var
  f: tFileStream;
  header: tMDRMapHeader;
begin
  fillchar(header, sizeof(header), 0);
  header.tag := 'MDRM';
  header.width := width;
  header.height := height;
  f := tFileStream.Create(filename, FM_WRITE);
  f.writeBlock(header, sizeof(header));
  f.writeBlock(fTile[0], sizeof(fTile[0])*length(fTile));
  f.writeBlock(fWall[0], sizeof(fWall[0])*length(fWall));
  f.flush();
  f.free();
end;

procedure tMDRMap.load(filename: string);
var
  f: tFileStream;
  header: tMDRMapHeader;
begin

  header.tag := 'MDRM';
  header.width := width;
  header.height := height;

  f := tFileStream.Create(filename);

  f.readBlock(header, sizeof(header));
  if (header.tag <> 'MDRM') then raise ValueError('Invalid map');
  init(header.width, header.height);

  f.readBlock(fTile[0], sizeof(fTile[0])*length(fTile));
  f.readBlock(fWall[0], sizeof(fWall[0])*length(fWall));
  f.free();
end;

{set explored flag for every tile / wall}
procedure tMDRMap.setExplored(aExplored: tExplorationStatus);
var
  i: integer;
begin
  for i := 0 to length(fTile)-1 do fTile[i].status.explored := aExplored;
  for i := 0 to length(fWall)-1 do fWall[i].status.explored := aExplored;
end;

procedure tMDRMap.clear();
var
  tile: tTile;
  wall: tWall;
begin
  for tile in fTile do tile.clear();
  for wall in fWall do wall.clear();
end;

{----------------------------------------------------------}

type
  tMDRMapTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tMDRMapTest.run();
var
  tile: tTile;
  wall: tWall;
begin
  {make sure everything is the right size, as we'll need this for loading/saving}
  assertEqual(sizeof(tile), 16);
  assertEqual(sizeof(wall), 8);
end;

{--------------------------------------------------------}

var
  i: integer;

initialization
  tMDRMapTest.create('MDRMap');
end.
