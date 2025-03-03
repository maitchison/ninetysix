{represents a single dungeon floor}
unit uMap;

interface

uses
  test,
  debug,
  utils;

type

  tWallType = (wtNone, wtSecret, wtWall, twDoor);
  tFloorType = (ftStone, ftWater);

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

  tTile = record
    attributes: bitpacked array[0..63] of boolean;
    wall: array[0..3] of tWallSpec;
    floor: tFloorSpec;
  end;

  tMap = class
  protected
    fTile: array of tTile;
    fWidth,fHeight: integer;
    function getTile(x,y: integer): tTile;
    procedure setTile(x,y: integer;aTile: tTile);

  public
    constructor Create(aWidth, aHeight: word);
  public
    property width: integer read fWidth;
    property height: integer read fHeight;
    property tile[x,y: integer]: tTile read getTile write setTile;
  end;

implementation

constructor tMap.Create(aWidth, aHeight: word);
begin
  fWidth := aWidth;
  fHeight := aHeight;
  setLength(fTile, aWidth * aHeight);
  fillchar(fTile, sizeof(fTile), 0);
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

end.
