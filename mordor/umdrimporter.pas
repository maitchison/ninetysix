unit uMDRImporter;

interface

uses
  uDebug,
  uTest,
  uUtils,
  uFileSystem,
  uStream,
  uMap;

type
  {used to read MDR files}
  tMDRDataStream = class(tMemoryStream)
  private
    recordSize: integer;
  public

    constructor Create(aRecordSize: integer=1);

    function  readMDRWord(): word;
    function  readCurrency(): double;
    procedure recordSeek(recordNumber: int32);
    procedure nextRecord();
    function  getRecord: int32;

    property  currentRecord: int32 read getRecord write recordSeek;
  end;

type
  tMDRImporter = class
  private
    numAreas, numChutes, numTeleports: integer;
    ds: tMDRDataStream;
  public
    procedure load(filename: string);
    function  readMap(aLevelID: integer): tMap;
  end;

implementation

type
  tMDRMapHeader = packed record
    width, height, floorNumber: word;
    numAreas, numChutes, numTeleports: word;
  end;

{-------------------------------------------}

constructor tMDRDataStream.Create(aRecordSize: integer=1);
begin
  inherited Create();
  recordSize := aRecordSize;
end;

function tMDRDataStream.readMDRWord(): word;
begin
  result := readWord();
  if recordSize > 2 then nextRecord;
end;

function tMDRDataStream.readCurrency(): double;
begin
  result := readInt64() / 10000;
end;

procedure tMDRDataStream.recordSeek(recordNumber: int32);
begin
  seek((recordNumber-1)*RecordSize);
end;

procedure tMDRDataStream.nextRecord();
begin
  recordSeek(currentRecord+1);
end;

function tMDRDataStream.getRecord: int32;
begin
  result := (pos div recordSize)+1;
end;


{-------------------------------------------}

procedure tMDRImporter.load(filename: string);
begin
  ds := tMDRDataStream.Create(20);
  ds.readFromFile(filename);
end;

function tMDRImporter.readMap(aLevelID: integer): tMap;
var
  map: tMap;
  numLevels: integer;
  levelOffset: word;
  header: tMDRMapHeader;
  xlp, ylp: integer;
  value: dword;
  tile: tTile;
  northWall,eastWall: tWall;
begin
  map := tMap.Create(32,32);

  ds.seek(0);

  // check how many levels we have in dungeon
  numLevels := ds.ReadMDRWord();
  if (aLevelID <= 0) or (aLevelID > numLevels) then
    raise ValueError('Invalid level number ' + intToStr(aLevelID));

  // get the offset
  ds.recordSeek(1 + aLevelID);
  levelOffset := ds.readMDRWord();

  // load the map header
  ds.recordSeek(levelOffset);
  ds.readBlock(header, sizeof(header));
  assertEqual(header.floorNumber, aLevelID);

  // make sure it looks vaguely right
  if (byte(header.width) <> header.width) or (byte(header.height) <> header.height) then
    raise ValueError('Map dims invalid (%d,%d)', [header.width, header.height]);

  // load field records
  for ylp := 1 to header.height do begin
    for xlp := 1 to header.width do begin

      // read in the bit values
      value := round(ds.readCurrency());

      // copy accross the attributes
      // these will need to be changed later
      move(value, tile.attributes, 4);

      tile.clear();
      northWall.clear();
      eastWall.clear();

      // map MDR attributes to our map format.
      if (value and (1 shl 1) <> 0) then eastWall.t := wtWall;
      if (value and (1 shl 2) <> 0) then northWall.t := wtWall;
      if (value and (1 shl 3) <> 0) then eastWall.t := wtDoor;
      if (value and (1 shl 4) <> 0) then northWall.t := wtDoor;
      if (value and (1 shl 5) <> 0) then eastWall.t := wtSecret;
      if (value and (1 shl 6) <> 0) then northWall.t := wtSecret;
      if (value and (1 shl 15) <> 0) then tile.floorType := ftWater;
      if (value and (1 shl 16) <> 0) then tile.floorType := ftDirt;
      if (value and (1 shl 19) <> 0) then tile.mediumType := mtRock;
      if (value and (1 shl 20) <> 0) then tile.mediumType := mtFog;
      if (value and (1 shl 26) <> 0) then tile.floorType := ftGrass;

      map.tile[xlp,ylp] := tile;
      map.wall[xlp,ylp,dNorth] := northWall;
      map.wall[xlp,ylp,dEast] := eastWall;

      // skip unused bytes in this record
      ds.nextRecord();
    end;
  end;



end;

begin
end.
