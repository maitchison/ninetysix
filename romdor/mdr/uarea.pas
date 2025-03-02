unit uMDRArea;

interface

uses
  Classes, SysUtils, Generics.Collections; // For TList<T>


type
  tMdrArea = class(tDataObject)
  private
    // Fields corresponding to the public fields from C#
    [FieldAttr(True)]
    fid: Integer;                // "ID" => "id"
    flairedMonster: tMdrMonster; // "LairedMonster" => "lairedMonster"
    fspawnMask: tMdrSpawnMask;   // "SpawnMask" => "spawnMask"
    forigion: tMdrLocation;      // "Origion" => "origion"
    fmap: tMdrMap;               // "Map" => "map"

    // Helpers to get/set respawn times & spawned monster list from spawn manager
    function getRespawnTime: Int64;
    procedure setRespawnTime(aValue: Int64);
    function getSpawnedMonsters: TList<tMdrMonsterInstance>;
    function getIsLair: Boolean;
    function getStudArea: Boolean;
  public
    // Public property versions
    property id: Integer read fid write fid;
    property lairedMonster: tMdrMonster read flairedMonster write flairedMonster;
    property spawnMask: tMdrSpawnMask read fspawnMask write fspawnMask;
    property origion: tMdrLocation read forigion write forigion;
    property &map: tMdrMap read fmap write fmap; // "map" is a reserved word, so prefix with "&"
    
    // Additional "C# property" conversions
    property respawnTime: Int64 read getRespawnTime write setRespawnTime;
    property spawnedMonsters: TList<tMdrMonsterInstance> read getSpawnedMonsters;
    property studArea: Boolean read getStudArea;
    property isLair: Boolean read getIsLair;

    // Constructor
    constructor Create; reintroduce;

    // For debugging or identification
    function toString: string; override;

    // Spawning logic
    function getSpawnTable: tSpawnTable;
    procedure update;
    procedure spawnMonsters;

    // Overridden read/write methods
    procedure writeNode(node: TObject); override;
    procedure readNode(node: TObject); override;
  private
    // Private helper methods
    function placeMonster(monster: tMdrMonster): tMdrMonsterInstance;
    function getNextEmptyTile: tMdrLocation;
    function spawnMonster(selectedMonster: tMdrMonster): tMdrMonsterInstance;
  end;

implementation

constructor tMdrLocation.Create(ax, ay, aFloor: Integer);
begin
  x := ax;
  y := ay;
  floor := aFloor;
end;

function tMdrLocation.toString: string;
begin
  Result := Format('(%d,%d,%d)', [x, y, floor]);
end;

class function tMdrMonsterInstance.create(monster: tMdrMonster): tMdrMonsterInstance;
begin
  // Real code should store a reference to monster, etc.
  Result := tMdrMonsterInstance(inherited Create);
end;


constructor tMdrSpawnMask.Create(aMask: Integer);
begin
  inherited Create;
  fMask := aMask;
end;

{ tSpawnTable }
procedure tSpawnTable.buildList(area: TObject; minLevel, maxLevel: Integer);
begin
  // Stub for logic building a monster list, etc.
end;

function tSpawnTable.selectRandomItem: tMdrMonster;
begin
  // Stub for returning a random monster from the table
  Result := nil;
end;

{ tCoM }
class var
  tCoM.state: tCoMState;
  tCoM.monsters: TObject;

{ tSpawnManager }
function tSpawnManager.getRespawnTime(aArea: TObject): Int64;
begin
  // Stub
  Result := 0;
end;

procedure tSpawnManager.setRespawnTime(aArea: TObject; ticks: Int64);
begin
  // Stub
end;

function tSpawnManager.getSpawnedMonsters(aArea: TObject): TList<tMdrMonsterInstance>;
begin
  // Stub: return an existing list or nil if none
  Result := nil;
end;

{ tTrace }
class procedure tTrace.logDebug(const msg: string; args: array of const);
begin
  Writeln('[DEBUG] ' + Format(msg, args));
end;

{ tMdrMap }
function tMdrMap.getField(ax, ay: Integer): TObject;
begin
  // Real code returns tFieldRecord, etc.
  Result := nil;
end;

function tMdrMap.getMonsterAtLocation(ax, ay: Integer): tMdrMonsterInstance;
begin
  // Stub
  Result := nil;
end;

{ tMdrArea }
constructor tMdrArea.Create;
begin
  inherited Create;
  fspawnMask := tMdrSpawnMask.Create(0);
end;

function tMdrArea.toString: string;
begin
  // "return Origion.ToString();" in C#
  Result := origion.toString;
end;

// -----------------------------------------------------------------------------
// "Properties" from the C# side
// -----------------------------------------------------------------------------
function tMdrArea.getRespawnTime: Int64;
begin
  if (tCoM.state <> nil) and (tCoM.state.spawnManager <> nil) then
    Result := tCoM.state.spawnManager.getRespawnTime(Self)
  else
    Result := 0;
end;

procedure tMdrArea.setRespawnTime(aValue: Int64);
begin
  if (tCoM.state <> nil) and (tCoM.state.spawnManager <> nil) then
    tCoM.state.spawnManager.setRespawnTime(Self, aValue);
end;

function tMdrArea.getSpawnedMonsters: TList<tMdrMonsterInstance>;
begin
  if (tCoM.state <> nil) and (tCoM.state.spawnManager <> nil) then
    Result := tCoM.state.spawnManager.getSpawnedMonsters(Self)
  else
    Result := nil;
end;

function tMdrArea.getIsLair: Boolean;
begin
  Result := (lairedMonster <> nil);
end;

function tMdrArea.getStudArea: Boolean;
var
  fieldObj: TObject;
begin
  // "return Map.GetField(Origion.X, Origion.Y).Stud" in C#
  // In Pascal, we might do something like:
  //   (map[origion.x, origion.y] as tFieldRecord).stud
  // We'll just stub it out for demonstration:
  if (map = nil) then
    Exit(False);
  fieldObj := map.getField(origion.x, origion.y);
  // Suppose there's a "stud" property?
  // We'll just pretend:
  // Result := (fieldObj <> nil) and (fieldObj is tFieldRecord) and tFieldRecord(fieldObj).stud;
  Result := False; // Stub
end;

// -----------------------------------------------------------------------------
// "getSpawnTable" logic
// -----------------------------------------------------------------------------
function tMdrArea.getSpawnTable: tSpawnTable;
var
  minLevel, maxLevel: Integer;
begin
  if map = nil then
    raise Exception.Create('Area has no map assigned.');

  // in C#:
  //   int minLevel = StudArea ? Map.FloorNumber + 1 : Map.FloorNumber - 2;
  //   int maxLevel = StudArea ? Map.FloorNumber + 1 : Map.FloorNumber;
  if studArea then
  begin
    minLevel := map.floorNumber + 1;
    maxLevel := map.floorNumber + 1;
  end
  else
  begin
    minLevel := map.floorNumber - 2;
    maxLevel := map.floorNumber;
  end;
  if minLevel < 0 then
    minLevel := 0;

  Result := tSpawnTable.Create;
  Result.buildList(Self, minLevel, maxLevel);
end;

// -----------------------------------------------------------------------------
// "update" logic
// -----------------------------------------------------------------------------
procedure tMdrArea.update;
const
  // .NET uses 10,000,000 ticks per second
  // We'll approximate that constant here
  TicksPerSecond = 10000000;
var
  hasMonster: Boolean;
  interval: Int64;
  nowTicks: Int64;
begin
  if (map = nil) then
    raise Exception.Create('Area has no map assigned.');

  // If spawnedMonsters is not nil => we have a monster
  hasMonster := (spawnedMonsters <> nil) and (spawnedMonsters.Count > 0);

  if (not hasMonster) and (respawnTime = 0) then
  begin
    // e.g. var interval = 5 * TimeSpan.TicksPerSecond;
    interval := 5 * TicksPerSecond;
    // We'll emulate DateTime.Now.Ticks in a stub function:
    nowTicks := Trunc(Now * 24 * 3600 * 1000) * 10000; // very rough approximation
    respawnTime := nowTicks + interval;
  end;

  nowTicks := Trunc(Now * 24 * 3600 * 1000) * 10000; // again, rough

  if (not hasMonster) and (nowTicks >= respawnTime) then
  begin
    tTrace.logDebug('Auto spawning monsters in area %s', [Self.toString]);
    respawnTime := 0;
    spawnMonsters;
  end;
end;

// -----------------------------------------------------------------------------
// "spawnMonsters" logic
// -----------------------------------------------------------------------------
procedure tMdrArea.spawnMonsters;
var
  selectedMonster: tMdrMonster;
  table: tSpawnTable;
begin
  table := getSpawnTable;
  try
    selectedMonster := table.selectRandomItem;
    spawnMonster(selectedMonster);
  finally
    table.Free;
  end;
end;

// -----------------------------------------------------------------------------
// Private Helpers
// -----------------------------------------------------------------------------
function tMdrArea.placeMonster(monster: tMdrMonster): tMdrMonsterInstance;
var
  loc: tMdrLocation;
  instance: tMdrMonsterInstance;
begin
  Result := nil;
  if monster = nil then
    Exit;

  loc := getNextEmptyTile;
  if (loc.floor = -1) then
    Exit;

  instance := tMdrMonsterInstance.create(monster);
  // "CoM.State.AddMonster(instance, this, location)" is presumably:
  //   CoM.State.SpawnManager.AddMonster(instance, self, loc) 
  // We'll stub that out:
  // e.g. tCoM.state.spawnManager.addMonster(instance, Self, loc);

  Result := instance;
end;

function tMdrArea.getNextEmptyTile: tMdrLocation;
var
  xlp, ylp: Integer;
begin
  // "for (int xlp=0; xlp < Map.Width; xlp++)..."
  if map = nil then
  begin
    Result := tMdrLocation.Create(0, 0, -1);
    Exit;
  end;

  for xlp := 0 to map.width - 1 do
    for ylp := 0 to map.height - 1 do
    begin
      // if (Map[xlp, ylp].Area == this && Map.GetMonsterAtLocation(xlp, ylp) == null)
      // We'll just stub "field's area" check with Self
      // if (map.getMonsterAtLocation(xlp, ylp) = nil) ...
      if map.getMonsterAtLocation(xlp, ylp) = nil then
        Exit(tMdrLocation.Create(xlp, ylp, map.floorNumber));
    end;
  // If none found
  Result := tMdrLocation.Create(0, 0, -1);
end;

function tMdrArea.spawnMonster(selectedMonster: tMdrMonster): tMdrMonsterInstance;
var
  mainInstance: tMdrMonsterInstance;
  lp: Integer;
begin
  Result := nil;
  if (selectedMonster = nil) or (selectedMonster.spawnCount = 0) then
    Exit;

  // Place the main instance
  mainInstance := placeMonster(selectedMonster);

  // Add additional monster instances
  for lp := 2 to selectedMonster.spawnCount do
    placeMonster(selectedMonster);

  // Add companions
  if (selectedMonster.companion <> nil) then
    for lp := 1 to selectedMonster.companion.spawnCount do
      placeMonster(selectedMonster.companion);

  Result := mainInstance;
end;

// -----------------------------------------------------------------------------
// Overridden read/write
// -----------------------------------------------------------------------------
procedure tMdrArea.writeNode(node: TObject);
begin
  inherited writeNode(node);
  // In the original C#:
  //   if (LairedMonster != null)
  //     WriteValue(node, "LairedMonster", LairedMonster.ID);
  //   WriteValue(node, "SpawnMask", SpawnMask.Mask);
  //   WriteAttribute(node, "LocationX", Origion.X);
  //   WriteAttribute(node, "LocationY", Origion.Y);
  //   WriteAttribute(node, "Floor", Origion.Floor);

  // We'll just stub these with some pseudo-calls:
  // e.g. writeValue(node, 'LairedMonster', flairedMonster.id);
  // ...
end;

procedure tMdrArea.readNode(node: TObject);
var
  lairedMonsterId: Integer;
begin
  inherited readNode(node);

  // C# code:
  //   int lairedMonsterId = ReadInt(node, "LairedMonster", 0);
  //   if (lairedMonsterId > 0)
  //     LairedMonster = CoM.Monsters.ByID(lairedMonsterId);
  //   SpawnMask.Mask = ReadBitArray(node, "SpawnMask");
  //   Origion = new MDRLocation(...);

  // We'll stub:
  lairedMonsterId := 0;
  // if lairedMonsterId > 0 then flairedMonster := ...
end;

end.
