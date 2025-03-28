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

  tWallType = (wtNone, wtWall, wtDoor, wtSecret, wtArch, ftWindow);
  tFloorType = (ftNone, ftStone, ftWater, ftDirt, ftGrass);
  tMediumType = (mtNone, mtFog, mtRock, mtLight);
  tCeilingType = (ctNone, ctRock, ctGrate);
  tDirection = (dNorth, dEast, dSouth, dWest);
  tIntercardinalDirection = (dNorthEast, dNorthWest, dSouthWest, dSouthEast);

  tFloorSpec = record
    tag: string;
    spriteIdx: integer;
  end;

  tMediumSpec = record
    tag: string;
    spriteIdx: integer;
  end;

  tCeilingSpec = record
    tag: string;
    spriteIdx: integer;
  end;

  tWallSpec = record
    tag: string;
    spriteIdx: integer;
    canTransit: boolean;
  end;

const

  WALL_SPEC: array[tWallType] of tWallSpec =
  (
    (tag: 'None';       spriteIdx:-1; canTransit: true),
    (tag: 'Wall';       spriteIdx: 0; canTransit: false),
    (tag: 'Door';       spriteIdx: 1; canTransit: true),
    (tag: 'Secret';     spriteIdx: 2; canTransit: true),
    (tag: 'Arch';       spriteIdx: 3; canTransit: true),
    (tag: 'Window';     spriteIdx: 4; canTransit: true)
  );

  FLOOR_SPEC: array[tFloorType] of tFloorSpec =
   (
    (tag: 'None';       spriteIdx: -1),
    (tag: 'Stone';      spriteIdx: -1),
    (tag: 'Water';      spriteIdx: -1),
    (tag: 'Dirt';       spriteIdx: -1),
    (tag: 'Grass';      spriteIdx: -1)
   );

  MEDIUM_SPEC: array[tMediumType] of tMediumSpec =
   (
    (tag: 'None';       spriteIdx: -1),
    (tag: 'Fog';        spriteIdx: -1),
    (tag: 'Rock';       spriteIdx: -1),
    (tag: 'Light';      spriteIdx: -1)
   );

  CEILING_SPEC: array[tCeilingType] of tCeilingSpec =
   (
    (tag: 'None';       spriteIdx: -1),
    (tag: 'Rock';        spriteIdx: -1),
    (tag: 'Grate';       spriteIdx: -1)
   );

  CURSOR_SPRITE = 19+(32*3);
  PARTY_SPRITE = 0+(32*3);

  WALL_DX: array[tDirection] of integer = (0,+8,0,-7);
  WALL_DY: array[tDirection] of integer = (-7,0,+8,0);

  DX: array[tDirection] of integer = (0,+1,0,-1);
  DY: array[tDirection] of integer = (-1,0,+1,0);

  IDX: array[tIntercardinalDirection] of integer = (+1,-1,-1,+1);
  IDY: array[tIntercardinalDirection] of integer = (-1,-1,+1,+1);

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
    function spec: tWallSpec;
    function asExplored(): tWall;
    function isSolid: boolean;
    function toString(): string;
  end;

  {16 bytes per tile}
  tTile = packed record
    attributes: bitpacked array[0..31] of boolean;  {4 bytes}
    status: tVisionStatus;                          {1 byte}
    floor: tFloorType;                              {1 byte}
    medium: tMediumType;                            {1 byte}
    ceiling: tCeilingType;                          {1 byte}
    padding: array[1..8] of byte;                   {8 bytes}
    procedure clear();
    function floorSpec: tFloorSpec;
    function mediumSpec: tMediumSpec;
    function ceilingSpec: tCeilingSpec;
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
    function  inBounds(x,y: int32): boolean;
    procedure setWall(x,y: integer; d: tDirection;aWall: tWall);
    function  getWallIdx(x,y: integer;d: tDirection): integer;
    function  getTileIdx(x,y: integer): integer;
    procedure init(aWidth, aHeight: integer);
  public
    constructor Create(aWidth, aHeight: word);
    destructor destroy(); override;
    procedure save(filename: string);
    procedure load(filename: string);
    procedure clear();
    procedure setExplored(aExplored: tExplorationStatus);
    function  hasCorner(x,y: integer;d: tIntercardinalDirection): boolean;
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

function tTile.mediumSpec: tMediumSpec;
begin
  result := MEDIUM_SPEC[medium];
end;

function tTile.ceilingSpec: tCeilingSpec;
begin
  result := CEILING_SPEC[ceiling];
end;

{returns copy of tile with exploration limited applied}
function tTile.asExplored(): tTile;
begin
  result := self;
  case status.explored of
    eNone: begin
      result.floor := ftNone;
      result.medium := mtNone;
      result.ceiling := ctNone;
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

function tWall.spec: tWallSpec;
begin
  result := WALL_SPEC[t];
end;

function tWall.isSolid: boolean;
begin
  result := not spec.canTransit;
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

function tMDRMap.inBounds(x,y: int32): boolean;
begin
  result := (dword(x) < width) and (dword(y) < height);
end;

function tMDRMap.getTileIdx(x,y: integer): integer;
begin
  if not inBounds(x,y) then raise ValueError('Out of bounds tile co-ords (%d,%d)', [x, y]);
  result := x+y*fWidth;
end;

function tMDRMap.getWallIdx(x,y: integer;d: tDirection): integer;
begin
  if not inBounds(x,y) then raise ValueError('Out of bounds tile co-ords (%d,%d)', [x, y]);
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

{returns true if corner pixel should be set, directions are to the left}
function tMDRMap.hasCorner(x,y: integer;d: tIntercardinalDirection): boolean;
var
  tx,ty: integer;
begin
  tx := x + IDX[d];
  ty := y + IDY[d];
  if not inBounds(tx,ty) then exit(false);
  case d of
    dNorthEast: result := (wall[tx, ty, dWest].isSolid or wall[tx, ty, dSouth].isSolid);
    dNorthWest: result := (wall[tx, ty, dEast].isSolid or wall[tx, ty, dSouth].isSolid);
    dSouthEast: result := (wall[tx, ty, dWest].isSolid or wall[tx, ty, dNorth].isSolid);
    dSouthWest: result := (wall[tx, ty, dEast].isSolid or wall[tx, ty, dNorth].isSolid);
  end;
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
