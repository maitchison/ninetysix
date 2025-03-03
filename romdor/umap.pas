{represents a single dungeon floor}
unit uMap;

interface

type

  tWallType = (wtNone, wtSecret, wtWall, twDoor);
  tFloorType = (ftStone, ftWater);

  tWallSpec: packed record
    t: tWallType;
    variation: byte;
    decoration1: byte;
    decoration2: byte;
  end;

  tFloorSpec: packed record
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
  public
    constructor Create(aWidth, aHeight: word);
    width, height: integer;
    tile[x,y: integer]: tTile read getTile write setTile default;
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
