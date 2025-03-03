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

const
  FLOOR_SPRITE: array[tFloorType] of integer =
    (-1, -1, 15, 16, 26);

  MEDIUM_SPRITE: array[tMediumType] of integer =
    (-1, 20, 19);

  {+1 for rotated varient}
  WALL_SPRITE: array[tWallType] of integer =
    (-1, 0, 2, 4, 32+4);

  WALL_DX: array[0..3] of integer = (0,+8,0,-7);
  WALL_DY: array[0..3] of integer = (-7,0,+8,0);

type
  tWallSpec = packed record
    t: tWallType;
    variation: byte;
    decoration1: byte;
    decoration2: byte;
  end;

  tFloorSpec = packed record
    t: tFloorType;
    variation: byte;
    decoration1: byte;
    decoration2: byte;
  end;

  tMediumSpec = packed record
    t: tMediumType;
    variation: byte;
    decoration1: byte;
    decoration2: byte;
  end;

  tTile = class
    attributes: bitpacked array[0..63] of boolean;
    wall: array[0..3] of tWallSpec;
    floor: tFloorSpec;
    medium: tMediumSpec;
    procedure clear();
  end;

  tMap = class
  protected
    fTile: array of tTile;
    fWidth,fHeight: integer;
    function getTile(x,y: integer): tTile;
    procedure setTile(x,y: integer; aTile: tTile);
  public
    constructor Create(aWidth, aHeight: word);
    destructor destroy(); override;
    procedure clear();
  public
    property width: integer read fWidth;
    property height: integer read fHeight;
    property tile[x,y: integer]: tTile read getTile;
  end;

implementation

{-------------------------------------------------}

procedure tTile.clear();
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
  for i := 0 to length(fTile)-1 do
    fTile[i] := tTile.create();
end;

destructor tMap.destroy();
var
  tile: tTile;
begin
  for tile in fTile do tile.free;
  setLength(fTile, 0);
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

procedure tMap.clear();
var
  tile: tTile;
begin
  for tile in fTile do tile.clear();
end;

end.
