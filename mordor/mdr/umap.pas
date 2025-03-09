unit uMDRMap;

interface

uses
  Classes, SysUtils, Generics.Collections; // For TList<T>

type

  tMap = class(tNamedDataObject)
  private

    const
      MAX_AREAS     = 256;
      maxTeleports  = 200;
      maxChutes    = 200;
      maxWidth     = 256;
      maxHeight    = 256;
  
    fTile: array of array of tTile;

    // The areas, teleports, and chutes
    area     : array[0..MAX_AREAS] of tArea;
    //teleport : array[0..MAX_TELEPORTS] of tTeleportTrapInfo;
    //chute    : array[0..MAX_TELEPORTS] of tChuteInfo;

    // Basic map parameters
    fWidth  : Integer;
    fHeight : Integer;
    fFloorNumber: Integer;

    // For partial updating
    fCurrentAreaUpdateIndex: Integer;

    function getField(x, y: Integer): tFieldRecord;
    procedure setField(x, y: Integer; aValue: tFieldRecord);
    function inBounds(x, y: Integer): Boolean;
  public
    constructor Create; override;
    destructor Destroy; override;

    property width: Integer read fWidth;
    property height: Integer read fHeight;
    property floorNumber: Integer read fFloorNumber write fFloorNumber;

    property area: TObjectList<tMdrArea> read fArea;
    property teleport: TObjectList<tTeleportTrapInfo> read fTeleport;
    property chute: TObjectList<tChuteTrapInfo> read fChute;

    property tile[x, y: Integer]: tFieldRecord read getTile write setTile; default;
    
    procedure clear;
    procedure initialize(aWidth, aHeight: Integer);

    //function getMonsterAtLocation(x, y: Integer): tMdrMonsterInstance;
    //function getChutAt(atX, atY: Integer): tChuteTrapInfo;
    //function getTeleportAt(atX, atY: Integer): tTeleportTrapInfo;

  end;

implementation

constructor tMap.Create;
begin
  inherited Create;
  fArea := TObjectList<tMdrArea>.Create;
  fTeleport := TObjectList<tTeleportTrapInfo>.Create;
  fChute := TObjectList<tChuteTrapInfo>.Create;
  fWidth := 0;
  fHeight := 0;
  fFloorNumber := 0;
end;

destructor tMap.Destroy;
var
  i: Integer;
begin
  // free the 2D field array
  for i := Low(fField) to High(fField) do
    SetLength(fField[i], 0);
  SetLength(fField, 0);

  fArea.Free;
  fTeleport.Free;
  fChute.Free;
  inherited Destroy;
end;

// Indexer get/set
function tMap.getField(x, y: Integer): tFieldRecord;
begin
  if inBounds(x, y) then
    Result := fField[x, y]
  else
    // Return an "empty" field record if out of bounds, like the C# code
    Result := tFieldRecord.Create(x, y, Self);
end;

procedure tMap.setField(x, y: Integer; aValue: tFieldRecord);
begin
  if inBounds(x, y) then
    fField[x, y] := aValue;
end;

function tMap.inBounds(x, y: Integer): Boolean;
begin
  Result := (x >= 0) and (y >= 0) and (x < fWidth) and (y < fHeight);
end;

procedure tMap.clear;
var
  xlp, ylp: Integer;
begin
  for xlp := 0 to fWidth - 1 do
    for ylp := 0 to fHeight - 1 do
      fField[xlp, ylp].clear;
end;

procedure tMap.initialize(aWidth, aHeight: Integer);
var
  xlp, ylp: Integer;
begin
  fWidth := aWidth;
  fHeight := aHeight;

  // Set up the 2D array
  SetLength(fField, fWidth);
  for xlp := 0 to fWidth - 1 do
    SetLength(fField[xlp], fHeight);

  // Clear existing lists
  fArea.Clear;
  fTeleport.Clear;
  fChute.Clear;

  // Create the field records
  for ylp := 0 to fHeight - 1 do
    for xlp := 0 to fWidth - 1 do
    begin
      fField[xlp, ylp] := tFieldRecord.Create(xlp, ylp, Self);
      fField[xlp, ylp].explored := False;
    end;
end;

function tMap.getMonsterAtLocation(x, y: Integer): tMdrMonsterInstance;
var
  i: Integer;
  monster: tMdrMonsterInstance;
begin
  // Compare to: 
  // for (int lp = 0; lp < CoM.State.SpawnManager.Monsters.Count; lp++)
  //   if (monster.X == x && monster.Y == y) return monster;

  Result := nil;
  if (tCoM.state = nil) or (tCoM.state.spawnManager = nil) then
    Exit;

  for i := 0 to tCoM.state.spawnManager.monsters.Count - 1 do
  begin
    monster := tCoM.state.spawnManager.monsters[i];
    if (monster.x = x) and (monster.y = y) then
      Exit(monster);
  end;
end;

function tMap.getChutAt(atX, atY: Integer): tChuteTrapInfo;
var
  i: Integer;
begin
  // "not the most efficient" in C#, likewise in Delphi
  Result := nil;
  for i := 0 to fChute.Count - 1 do
    if (fChute[i].x = atX) and (fChute[i].y = atY) then
      Exit(fChute[i]);
end;

function tMap.getTeleportAt(atX, atY: Integer): tTeleportTrapInfo;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to fTeleport.Count - 1 do
    if (fTeleport[i].x = atX) and (fTeleport[i].y = atY) then
      Exit(fTeleport[i]);
end;

// Reading from XML
procedure tMap.readNode(node: tXElement);
var
  fieldData: TArray<UInt64>;
  xlp, ylp: Integer;
begin
  inherited;
  fWidth       := readInt(node, 'Width');
  fHeight      := readInt(node, 'Height');
  fFloorNumber := readInt(node, 'FloorNumber');

  if (fWidth = 0) or (fHeight = 0) then
  begin
    tTrace.logError(Format('Error reading map, invalid dimensions (%dx%d)', [fWidth, fHeight]));
    Exit;
  end;

  initialize(fWidth, fHeight);

  // Read the "FieldMap"
  fieldData := readArrayUInt64(node, 'FieldMap');
  if fieldData <> nil then
    for ylp := 0 to fWidth - 1 do
      for xlp := 0 to fHeight - 1 do
        fField[xlp, ylp].value := fieldData[xlp + (ylp * fWidth)];

  // Read the "AreaMap"
  fieldData := readArrayUInt64(node, 'AreaMap');
  if fieldData <> nil then
    for ylp := 0 to fWidth - 1 do
      for xlp := 0 to fHeight - 1 do
        fField[xlp, ylp].areaNumber := Word(fieldData[xlp + (ylp * fWidth)]);

  // Lists
  fTeleport := readDataObjectList<tTeleportTrapInfo>(node, 'Teleports');
  fChute    := readDataObjectList<tChuteTrapInfo>(node, 'Chutes');
  fArea     := readDataObjectList<tMdrArea>(node, 'Areas');

  // Link each area back to this map
  if fArea <> nil then
    for xlp := 0 to fArea.Count - 1 do
    begin
      fArea[xlp].map := Self;
      fArea[xlp].id  := xlp;
    end;

  if fTeleport = nil then
    raise Exception.Create('No teleports record found in map');
  if fChute = nil then
    raise Exception.Create('No chutes record found in map');
  if fArea = nil then
    raise Exception.Create('No area record found in map');
end;

// Writing to XML
procedure tMap.writeNode(node: tXElement);
var
  mapData: TArray<UInt64>;
  xlp, ylp: Integer;
begin
  inherited;

  writeValue(node, 'Width', fWidth);
  writeValue(node, 'Height', fHeight);
  writeValue(node, 'FloorNumber', fFloorNumber);

  // Write out Teleports / Chutes / Areas
  writeValue(node, 'Teleports', fTeleport);
  writeValue(node, 'Chutes',    fChute);
  writeValue(node, 'Areas',     fArea);

  SetLength(mapData, fWidth * fHeight);

  // FieldMap
  for ylp := 0 to fWidth - 1 do
    for xlp := 0 to fHeight - 1 do
      mapData[xlp + (ylp * fWidth)] := fField[xlp, ylp].value;
  writeValue(node, 'FieldMap', mapData);

  // AreaMap
  for ylp := 0 to fWidth - 1 do
    for xlp := 0 to fHeight - 1 do
      mapData[xlp + (ylp * fWidth)] := fField[xlp, ylp].areaNumber;
  writeValue(node, 'AreaMap', mapData);
end;

{ tFieldRecord }
constructor tFieldRecord.Create(ax, ay: Integer; parentMap: tMap);
begin
  inherited Create;
  fx   := ax;
  fy   := ay;
  fMap := parentMap;
  fValue := 0;
  fAreaNumber := 0;
  fExplored := False;
end;

procedure tFieldRecord.clear;
begin
  fValue := 0;
end;
