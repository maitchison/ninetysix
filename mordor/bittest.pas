program bittest;

uses
  sysUtils,classes;

type
  tTileDef = bitpacked record
    northWall: boolean;
    southWall: boolean;
  end;

var
  tile: tTileDef;

begin
  writeln(sizeof(tile));
  tile.northWall := True;
  writeln(tile.northWall);
  writeln(tile.southWall);
end.
