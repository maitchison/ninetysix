{store global game state for Mordor}
unit uGameState;

interface

uses
  uMDRParty,
  uMDRMap;

type tGameState = class
  class var map: tMDRMap;
  class var exploredMap: tMDRMap;
  class var party: tMDRParty;
  end;

var
  gs: tGameState;

implementation

begin
  gs := tGameState.Create();
end.
