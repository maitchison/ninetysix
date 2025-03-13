{store global game state for Mordor}
unit uGame;

interface

uses
  uMap;

type GameState = class
  class var map: tMap;
  class var exploredMap: tMap;
  end;

implementation

begin
end.