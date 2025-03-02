unit uTile;

interface

uses
  Classes, SysUtils; // Needed for TList, Exception, etc.

type
  tTransitObstacle = (
    toNone,
    toWall
  );

  tWallType = (
    wtNone,
    wtWall,
    wtDoor,
    wtSecret,
    wtGate,
    wtArch
  );

  tWallRecord = record
    wall  : Boolean;
    door  : Boolean;
    secret: Boolean;
    gate  : Boolean;
    arch  : Boolean;
  end;

  function emptyWallRecord: tWallRecord;
  
  tTileCopyMode = (
    tcmStandard,
    tcmFull
  );

  tAreaList = class(TObject)
  private
    fList: TList;
    function getCount: Integer;
    function getItem(index: Integer): tMDRArea;
  public
    constructor Create;
    destructor Destroy; override;
    property Count: Integer read getCount;
    property Items[index: Integer]: tMDRArea read getItem; default;
  end;

  // Forward declaration so tMDRMap.getField can return tMapField
  tMapField = class;

  // Now correct the signature of getField:
  tMDRMap = class
  private
    fArea: tAreaList;
  public
    constructor Create;
    destructor Destroy; override;
    function getField(ax, ay: Integer): tMapField;
    property Area: tAreaList read fArea;
  end;

  // -- This is your "FieldRecord"
  tMapField = class
  private
    fBitMask  : array[0..63] of Boolean;  // Replaces "BitArray"
    fX, fY    : Integer;
    fMap      : tMDRMap;
    fAreaNumber: Word;

    // Helpers for direct access to fBitMask
    function getBit(index: Integer): Boolean;
    procedure setBit(index: Integer; aValue: Boolean);

    function toUInt64: QWord;
    procedure fromUInt64(aValue: QWord);

    // The private get/set for property areaNumber
    function getAreaNumber: Word;
    procedure setAreaNumber(aValue: Word);

    // Internal “get” methods for the tWallRecord properties
    function getNorthWall: tWallRecord;
    function getEastWall: tWallRecord;
    function getSouthWall: tWallRecord;
    function getWestWall : tWallRecord;

    // Internal “set” methods for the tWallRecord properties
    procedure setNorthWall(const aValue: tWallRecord);
    procedure setEastWall(const aValue: tWallRecord);
    procedure setSouthWall(const aValue: tWallRecord);
    procedure setWestWall(const aValue: tWallRecord);

  public
    // Constructors
    constructor Create(atX, atY: Integer; parentMap: tMDRMap);

    // Field-like properties
    property x: Integer read fX;
    property y: Integer read fY;

    // Provide direct read/write of the 64 bits
    property value: QWord read toUInt64 write fromUInt64;
    
    // Return the “ground only” bits (value minus wall bits)
    function getGroundValue: QWord;

    // Get or set a specific bit in the array
    function getBitMask(index: Integer): Boolean;
    procedure setBitMask(index: Integer; aValue: Boolean);

    // The area index
    property areaNumber: Word read getAreaNumber write setAreaNumber;

    // Return tMDRArea by using the parent map's list
    function getArea: tMDRArea;

    // Neighbor fields
    function west : tMapField;
    function south: tMapField;
    function east : tMapField;
    function north: tMapField;

    // "TransitObstacle" logic
    function getTransit(const aDir: tDirection): tTransitObstacle;

    // Returns a tWallRecord for the given direction
    function getWallRecord(const aDir: tDirection): tWallRecord; overload;
    function getWallRecord(index: Integer): tWallRecord; overload;

    // Sets a tWallRecord for the given wall index
    procedure setWallRecord(index: Integer; const aValue: tWallRecord);

    // Walls as distinct properties
    property northWall: tWallRecord read getNorthWall write setNorthWall;
    property eastWall : tWallRecord read getEastWall  write setEastWall;
    property southWall: tWallRecord read getSouthWall write setSouthWall;
    property westWall : tWallRecord read getWestWall  write setWestWall;

    // Floor attributes
    function floorHeight: Single;
    function edgeHeight: Single;

    // Various boolean properties mapped to bits
    property faceNorth   : Boolean index  6  read getBit write setBit;
    property faceEast    : Boolean index  7  read getBit write setBit;
    property faceSouth   : Boolean index  8  read getBit write setBit;
    property faceWest    : Boolean index  9  read getBit write setBit;
    property extinguisher: Boolean index 10  read getBit write setBit;
    property pit         : Boolean index 11  read getBit write setBit;
    property stairsUp    : Boolean index 12  read getBit write setBit;
    property stairsDown  : Boolean index 13  read getBit write setBit;
    property teleporter  : Boolean index 14  read getBit write setBit;
    property water       : Boolean index 15  read getBit write setBit;
    property dirt        : Boolean index 16  read getBit write setBit;
    property rotator     : Boolean index 17  read getBit write setBit;
    property antimagic   : Boolean index 18  read getBit write setBit;
    property rock        : Boolean index 19  read getBit write setBit;
    property chute       : Boolean index 21  read getBit write setBit;
    property stud        : Boolean index 22  read getBit write setBit;
    property light       : Boolean index 23  read getBit write setBit;
    // 'alt' is used instead of '_alt'
    property alt         : Boolean index 24  read getBit write setBit;
    property lava        : Boolean index 25  read getBit write setBit;
    property grass       : Boolean index 26  read getBit write setBit;
    property explored    : Boolean index 31  read getBit write setBit;

    // Clears all bits
    procedure clear;

    // True if lower 32 bits are zero
    function isEmpty: Boolean;

    // Copies field bits from another tMapField according to a mode
    procedure copyFrom(source: tMapField; mode: tTileCopyMode = tcmStandard);
  end;

implementation

// -----------------------------------------------------------------------------
// Stub Implementations
// -----------------------------------------------------------------------------

function emptyWallRecord: tWallRecord;
begin
  Result.wall   := False;
  Result.door   := False;
  Result.secret := False;
  Result.gate   := False;
  Result.arch   := False;
end;

// -------------- tAreaList --------------
constructor tAreaList.Create;
begin
  inherited Create;
  fList := TList.Create;
end;

destructor tAreaList.Destroy;
begin
  fList.Free;
  inherited Destroy;
end;

function tAreaList.getCount: Integer;
begin
  Result := fList.Count;
end;

function tAreaList.getItem(index: Integer): tMDRArea;
begin
  if (index < 0) or (index >= fList.Count) then
    Exit(nil);
  Result := tMDRArea(fList[index]);
end;

// -------------- tMDRMap --------------
constructor tMDRMap.Create;
begin
  inherited Create;
  fArea := tAreaList.Create;
end;

destructor tMDRMap.Destroy;
begin
  fArea.Free;
  inherited Destroy;
end;

function tMDRMap.getField(ax, ay: Integer): tMapField;
begin
  // In a real implementation, you'd fetch from a 2D array or something
  Result := nil;
end;

// -------------- tMapField --------------
constructor tMapField.Create(atX, atY: Integer; parentMap: tMDRMap);
begin
  inherited Create;
  fX   := atX;
  fY   := atY;
  fMap := parentMap;
end;

function tMapField.getBit(index: Integer): Boolean;
begin
  if (index < Low(fBitMask)) or (index > High(fBitMask)) then
    raise Exception.CreateFmt('Bit index %d out of range', [index]);
  Result := fBitMask[index];
end;

procedure tMapField.setBit(index: Integer; aValue: Boolean);
begin
  if (index < Low(fBitMask)) or (index > High(fBitMask)) then
    raise Exception.CreateFmt('Bit index %d out of range', [index]);
  fBitMask[index] := aValue;
end;

function tMapField.getBitMask(index: Integer): Boolean;
begin
  Result := getBit(index);
end;

procedure tMapField.setBitMask(index: Integer; aValue: Boolean);
begin
  setBit(index, aValue);
end;

function tMapField.getAreaNumber: Word;
begin
  Result := fAreaNumber;
end;

procedure tMapField.setAreaNumber(aValue: Word);
begin
  fAreaNumber := aValue;
end;

function tMapField.getArea: tMDRArea;
begin
  if fMap = nil then
    raise Exception.Create('Map is null on field.');
  if fMap.Area = nil then
    raise Exception.Create('Map has a null area.');

  // Only check upper bound (Word can't be negative)
  if areaNumber >= fMap.Area.Count then
    Exit(nil);

  Result := fMap.Area[areaNumber];
end;

function tMapField.west: tMapField;
begin
  if Assigned(fMap) then
    Result := fMap.getField(x - 1, y)
  else
    Result := nil;
end;

function tMapField.south: tMapField;
begin
  if Assigned(fMap) then
    Result := fMap.getField(x, y - 1)
  else
    Result := nil;
end;

function tMapField.east: tMapField;
begin
  if Assigned(fMap) then
    Result := fMap.getField(x + 1, y)
  else
    Result := nil;
end;

function tMapField.north: tMapField;
begin
  if Assigned(fMap) then
    Result := fMap.getField(x, y + 1)
  else
    Result := nil;
end;

function tMapField.getNorthWall: tWallRecord;
begin
  if fBitMask[1] then
  begin
    Result.wall := True;
    Exit;
  end;
  if fBitMask[3] then
  begin
    Result.door := True;
    Exit;
  end;
  if fBitMask[5] then
  begin
    Result.secret := True;
    Exit;
  end;
  if fBitMask[37] then
  begin
    Result.gate := True;
    Exit;
  end;
  if fBitMask[39] then
  begin
    Result.arch := True;
    Exit;
  end;
  Result := emptyWallRecord;
end;

procedure tMapField.setNorthWall(const aValue: tWallRecord);
begin
  fBitMask[1]  := aValue.wall;
  fBitMask[3]  := aValue.door;
  fBitMask[5]  := aValue.secret;
  fBitMask[37] := aValue.gate;
  fBitMask[39] := aValue.arch;
end;

function tMapField.getEastWall: tWallRecord;
begin
  if fBitMask[0] then
  begin
    Result.wall := True;
    Exit;
  end;
  if fBitMask[2] then
  begin
    Result.door := True;
    Exit;
  end;
  if fBitMask[4] then
  begin
    Result.secret := True;
    Exit;
  end;
  if fBitMask[36] then
  begin
    Result.gate := True;
    Exit;
  end;
  if fBitMask[38] then
  begin
    Result.arch := True;
    Exit;
  end;
  Result := emptyWallRecord;
end;

procedure tMapField.setEastWall(const aValue: tWallRecord);
begin
  fBitMask[0]  := aValue.wall;
  fBitMask[2]  := aValue.door;
  fBitMask[4]  := aValue.secret;
  fBitMask[36] := aValue.gate;
  fBitMask[38] := aValue.arch;
end;

function tMapField.getSouthWall: tWallRecord;
var
  s: tMapField;
begin
  s := Self.south;
  if s <> nil then
    Result := s.getNorthWall
  else
    Result := emptyWallRecord;
end;

procedure tMapField.setSouthWall(const aValue: tWallRecord);
var
  s: tMapField;
begin
  s := Self.south;
  if s <> nil then
    s.setNorthWall(aValue);
end;

function tMapField.getWestWall: tWallRecord;
var
  w: tMapField;
begin
  w := Self.west;
  if w <> nil then
    Result := w.getEastWall
  else
    Result := emptyWallRecord;
end;

procedure tMapField.setWestWall(const aValue: tWallRecord);
var
  w: tMapField;
begin
  w := Self.west;
  if w <> nil then
    w.setEastWall(aValue);
end;

function tMapField.floorHeight: Single;
begin
  if stairsUp then   Exit(0.15);
  if water    then   Exit(-0.20);
  if pit      then   Exit(-0.10);
  if dirt     then   Exit(-0.01);
  if grass    then   Exit(-0.01);
  // else
  Result := 0.0;
end;

function tMapField.edgeHeight: Single;
begin
  if water then  Exit(-0.20);
  if dirt  then  Exit(-0.01);
  if grass then  Exit(-0.005);
  Result := 0.0;
end;

function tMapField.getTransit(const aDir: tDirection): tTransitObstacle;
var
  w: tWallRecord;
begin
  w := getWallRecord(aDir.sector);
  if w.wall then
    Exit(tTransitObstacle.toWall)
  else
    Exit(tTransitObstacle.toNone);
end;

function tMapField.getWallRecord(const aDir: tDirection): tWallRecord;
begin
  Result := getWallRecord(aDir.sector);
end;

function tMapField.getWallRecord(index: Integer): tWallRecord;
begin
  case index of
    0: Result := northWall;
    1: Result := eastWall;
    2: Result := southWall;
    3: Result := westWall;
  else
    raise Exception.CreateFmt('Invalid wall index: %d', [index]);
  end;
end;

procedure tMapField.setWallRecord(index: Integer; const aValue: tWallRecord);
begin
  case index of
    0: northWall := aValue;
    1: eastWall  := aValue;
    2: southWall := aValue;
    3: westWall  := aValue;
  else
    raise Exception.CreateFmt('Invalid wall index: %d', [index]);
  end;
end;

function tMapField.toUInt64: QWord;
var
  i: Integer;
  temp: QWord;
begin
  temp := 0;
  for i := 0 to 63 do
    if fBitMask[i] then
      temp := temp or (QWord(1) shl i);
  Result := temp;
end;

procedure tMapField.fromUInt64(aValue: QWord);
var
  i: Integer;
begin
  for i := 0 to 63 do
    fBitMask[i] := ((aValue shr i) and QWord(1)) = QWord(1);
end;

function tMapField.getGroundValue: QWord;
var
  i: Integer;
  copyBits: QWord;
begin
  // Start with all bits, then remove the wall bits
  copyBits := toUInt64;
  for i := 0 to 63 do
  begin
    // "wall bits" are at [0,1,2,3,4,5,36,37,38,39]
    if (i in [0,1,2,3,4,5,36,37,38,39]) then
      copyBits := copyBits and not (QWord(1) shl i);
  end;
  Result := copyBits;
end;

procedure tMapField.clear;
begin
  value := 0;
end;

function tMapField.isEmpty: Boolean;
begin
  // Only checks lower 32 bits
  Result := (toUInt64 and $FFFFFFFF) = 0;
end;

procedure tMapField.copyFrom(source: tMapField; mode: tTileCopyMode);
begin
  case mode of
    tcmStandard:
      begin
        fromUInt64(source.toUInt64);
      end;
    tcmFull:
      begin
        fromUInt64(source.toUInt64);
        // Also replicate south and west walls if valid
        if (south <> nil) then
          southWall := source.southWall;
        if (west <> nil) then
          westWall := source.westWall;
      end;
  end;
  // Always copy the "explored" bit
  explored := source.explored;
end;

end.
