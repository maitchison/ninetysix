{store global game state for Mordor}
unit uGameState;

interface

uses
  uMDRParty,
  uMDRMap;

type tGameState = class
  class var map: tMap;
  class var exploredMap: tMap;
  end;

var
  gs: tGameState;

implementation

begin
  gs := tGameState.Create();
end.
