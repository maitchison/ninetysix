unit uMDRMap;

interface

uses
  Classes, SysUtils, Generics.Collections; // For TList<T>

// --- Stubs/Placeholders ------------------------------------------------------
type
  // Stub attribute to match [DataObjectAttribute("Something", true)]
  DataObjectAttribute = class(TCustomAttribute)
  private
    fName   : string;
    fFlag   : Boolean;
  public
    constructor Create(const aName: string; aFlag: Boolean);
    property Name: string read fName;
    property Flag: Boolean read fFlag;
  end;

  // Stub for your base data object system
  tDataObject = class
    // Insert shared logic if needed
  end;

  // Stub for your "NamedDataObject" class
  tNamedDataObject = class(tDataObject)
  private
    fName: string;
  public
    property objName: string read fName write fName;
    // Possibly other members ...
  end;

  // Stub for your "Trace" or logging system
  tTrace = class
    class procedure logError(const msg: string); static;
  end;

  // Stub for the CoM / SpawnManager references
  tMdrMonsterInstance = class
  public
    x, y: Integer;
  end;

  tSpawnManager = class
  public
    monsters: TList<tMdrMonsterInstance>;
    constructor Create;
    destructor Destroy; override;
  end;

  // "CoM" global or state reference
  tCoMState = class
    spawnManager: tSpawnManager;
  end;

  tCoM = class
    class var state: tCoMState;
  end;

  // Stub for reading/writing XML
  tXElement = class
    // ...
  end;

  // You might implement actual logic for these read/write calls.
  // Here, they're simple stubs:
  function readInt(node: tXElement; const tag: string): Integer;
  function readArrayUInt64(node: tXElement; const tag: string): TArray<UInt64>;
  function readDataObjectList<T: class, constructor>(node: tXElement; const tag: string): TObjectList<T>;
  procedure writeValue(node: tXElement; const tag: string; value: Variant); overload;
  procedure writeValue(node: tXElement; const tag: string; list: TList<tDataObject>); overload;
  procedure writeValue(node: tXElement; const tag: string; arr: TArray<UInt64>); overload;

// -----------------------------------------------------------------------------
// Enums, Records, and Classes
// -----------------------------------------------------------------------------

type
  // ---------------------------------------------------------------------------
  // tTileCopyMode
  // ---------------------------------------------------------------------------
  tTileCopyMode = (
    tcmStandard, // STANDARD
    tcmFull      // FULL
  );

  // ---------------------------------------------------------------------------
  // tWallType
  // ---------------------------------------------------------------------------
  tWallType = (
    wtNone,
    wtWall,
    wtDoor,
    wtSecret,
    wtArch,
    wtGate
  );

  // ---------------------------------------------------------------------------
  // tWallRecord
  // ---------------------------------------------------------------------------
  // Equivalent to C# struct WallRecord
  tWallRecord = record
  private
    fWallType: tWallType;
  public
    // Constructors & "static" equivalents
    constructor Create(aType: tWallType);
    class function empty: tWallRecord; static;

    // Accessors
    function wall: Boolean;
    function door: Boolean;
    function secret: Boolean;
    function arch: Boolean;
    function gate: Boolean;
    function isEmpty: Boolean;
    function canSeeThrough: Boolean;

    // property-like
    property wallType: tWallType read fWallType write fWallType;
  end;

  // ---------------------------------------------------------------------------
  // tTransitObstacal
  // ---------------------------------------------------------------------------
  tTransitObstacal = (
    toNone,
    toMonster,
    toDoor,
    toWall
  );

  // ---------------------------------------------------------------------------
  // tTrapInfo
  // ---------------------------------------------------------------------------
  // class TrapInfo : DataObject
  tTrapInfo = class(tDataObject)
  private
    fx: Integer;
    fy: Integer;
    function getIsValid: Boolean;
  public
    property x: Integer read fx write fx;
    property y: Integer read fy write fy;

    property isValid: Boolean read getIsValid;
  end;

  // ---------------------------------------------------------------------------
  // tTeleportTrapInfo
  // ---------------------------------------------------------------------------
  // [DataObjectAttribute("Teleport", true)]
  tTeleportTrapInfo = class(tTrapInfo)
  private
    fDestX     : Integer;
    fDestY     : Integer;
    fDestFloor : Integer;
  public
    property destX: Integer read fDestX write fDestX;
    property destY: Integer read fDestY write fDestY;
    property destFloor: Integer read fDestFloor write fDestFloor;

    function isRandom: Boolean;
  end;

  // ---------------------------------------------------------------------------
  // tChuteTrapInfo
  // ---------------------------------------------------------------------------
  // [DataObjectAttribute("Chute", true)]
  tChuteTrapInfo = class(tTrapInfo)
  private
    fDropDepth: Integer;
  public
    property dropDepth: Integer read fDropDepth write fDropDepth;
  end;

  // ---------------------------------------------------------------------------
  // Forward declaration of tMdrArea, tFieldRecord (like in your example stubs)
  // ---------------------------------------------------------------------------
  tMdrArea = class;
  tFieldRecord = class;
  
  // ---------------------------------------------------------------------------
  // tMdrMap
  // ---------------------------------------------------------------------------
  // [DataObjectAttribute("Map")]
  tMdrMap = class(tNamedDataObject)
  private
    // Constants
    const
      maxAreas     = 201;
      maxTeleports = 200;
      maxChutes    = 200;
      maxWidth     = 256;
      maxHeight    = 256;

    // The 2D array of fields
    fField: array of array of tFieldRecord;

    // The areas, teleports, and chutes
    fArea     : TObjectList<tMdrArea>;
    fTeleport : TObjectList<tTeleportTrapInfo>;
    fChute    : TObjectList<tChuteTrapInfo>;

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
    // Constructors / destructors
    constructor Create; override;
    destructor Destroy; override;

    // Access properties
    property width: Integer read fWidth;
    property height: Integer read fHeight;
    property floorNumber: Integer read fFloorNumber write fFloorNumber;

    // Lists
    property area: TObjectList<tMdrArea> read fArea;
    property teleport: TObjectList<tTeleportTrapInfo> read fTeleport;
    property chute: TObjectList<tChuteTrapInfo> read fChute;

    // Indexer 
