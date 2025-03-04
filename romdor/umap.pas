{represents a single dungeon floor}
unit uMap;

interface

uses
  test,
  debug,
  utils;

type

  tWallType = (wtNone, wtWall, wtDoor, wtSecret, wtLockedDoor);
  tFloorType = (ftNone, ftStone, ftWater, ftDirt, ftGrass);
  tMediumType = (mtNone, mtMist, mtRock);
  tMapDirection = (mdNorth, mdEast, mdSouth, mdWest);

const
  FLOOR_SPRITE: array[tFloorType] of integer =
    (-1, -1, 15, 16, 26);

  MEDIUM_SPRITE: array[tMediumType] of integer =
    (-1, 20, 19);

  {+1 for rotated varient}
  WALL_SPRITE: array[tWallType] of integer =
    (-1, 0, 2, 4, 32+4);

  MD_X: array[tMapDirection] of integer = (0,+8,0,-7);
  MD_Y: array[tMapDirection] of integer = (-7,0,+8,0);

type

  tWall = packed record
    t: tWallType;
    variation: byte;
    decoration1: byte;
    decoration2: byte;
    procedure clear();
  end;

  tTile = packed record
    attributes: bitpacked array[0..31] of boolean;
    floorType: tFloorType;
    mediumType: tMediumType;
    procedure clear();
  end;

  tMap = class
  protected
    fTile: array of tTile;
    fNorthWall, fWestWall: array of tWall;
    fWidth,fHeight: integer;
    function  getTile(x,y: integer): tTile;
    procedure setTile(x,y: integer; aTile: tTile);
    function  getWall(x,y: integer; d: tMapDirection): tWall;
    procedure setWall(x,y: integer; d: tMapDirection;aWall: tWall);
  public
    constructor Create(aWidth, aHeight: word);
    destructor destroy(); override;
    procedure clear();
  public
    property width: integer read fWidth;
    property height: integer read fHeight;
    property tile[x,y: integer]: tTile read getTile write setTile;
    property wall[x,y: integer;d: tMapDirection]: tWall read getWall;
  end;

implementation

{-------------------------------------------------}

procedure tTile.clear();
begin
  fillchar(self, sizeof(self), 0);
end;

{-------------------------------------------------}

procedure tWall.clear();
begin
  fillchar(self, sizeof(self), 0);
end;

{-------------------------------------------------}

constructor tMap.Create(aWidth, aHeight: word);
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

destructor tMap.destroy();
begin
  setLength(fTile, 0);
  setLength(fNorthWall, 0);
  setLength(fWestWall, 0);
  inherited destroy();
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

function tMap.getWall(x,y: integer;d: tMapDirection): tWall;
begin
  if (word(x) >= width) or (word(y) >= height) then raise ValueError('Out of bounds tile co-ords (%d,%d)', [x, y]);
  case d of
    mdNorth: result := fNorthWall[x+y*(fWidth+1)];
    mdWest: result := fWestWall[x+y*(fWidth+1)];
    mdSouth: result := fNorthWall[x+(y+1)*(fWidth+1)];
    mdEast: result := fWestWall[(x+1)+y*(fWidth+1)];
  end;
end;

procedure tMap.setWall(x,y: integer;d: tMapDirection; aWall: tWall);
begin
  if (word(x) >= width) or (word(y) >= height) then raise ValueError('Out of bounds tile co-ords (%d,%d)', [x, y]);
  case d of
    mdNorth: fNorthWall[x+y*(fWidth+1)] := aWall;
    mdWest: fWestWall[x+y*(fWidth+1)] := aWall;
    mdSouth: fNorthWall[x+(y+1)*(fWidth+1)] := aWall;
    mdEast: fWestWall[(x+1)+y*(fWidth+1)] := aWall;
  end;
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

end.
