unit uMDRImporter;

uses
  uDebug,
  uTools,
  uFileSystem,
  uStream,
  uMap;

interface

type
  {used to read MDR files}
  tMDRDataStream = class(tMemoryStream)
  private
    recordSize: integer;
  public

    constructor Create(recordSize: integer=1);

    function  readMDRWord(): word;
    function  readCurrency(): double;
{
    function  readPrefixString(): string;
    function  readFixedString(): string;
}
    procedure recordSeek(recordNumber: int32);
    procedure nextRecord();
    function  getRecord: int32;

    property  currentRecord: int32 read getRecord write recordSeek;
  end;

type
  tMDRImporter = class()
  private
    numAreas, numChutes, numTeleports: integer;
    ds: tMDRStream;
  public
    function load(fs: tFileStream);
    function readMap(aLevelID: integer): tMap;
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

function getRecord: int32;
begin
  result := (pos div RecordSize)+1;
end;


{-------------------------------------------}

function tMDRImporter.load(filename: string);
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
  value: int64;
  tile: pTile;
  northWall,eastWall: pWall;
begin
  map := tMap.Create();

  ds.seek(0);

  // check how many levels we have in dungeon
  numLevels := ds.ReadMDRWord();
  if (aLevelID <= 0) || (aLevelID > numberOfLevels) then begin
    ds.close();
    raise ValueError('Invalid level number ' + intToStr(aLevelID));
  end;

  // get the offset
  ds.recordSeek(1 + aLevelID);
  levelOffset = ds.readMDRWord();

  // load the map header
  ds.recordSeek(levelOffset);
  ds.readBlock(header, length(header);
  assertEqual(header.floorNumber, aLevelID);

  // make sure it looks vaguely right
  if (byte(header.width) <> header.width) or (byte(header.height) <> header.height) then begin
    ds.close();
    raise ValueError('Map dims invalid (%d,%d)', [header.width, header.height]);
  end;

  // load field records
  for ylp := 1 to header.height do beign
    for xlp := 1 to header.width do begin

      tile := @map.tile[xlp, ylp];
      northWall := @map.wall[xlp, ylp, dNorth];
      eastWall := @map.wall[xlp, ylp, dEast];

      // read in the bit values
      value := round(ds.readCurrency());

      // copy accross the attributes
      // these will need to be changed later
      tile^.attributes := value;

      tile^.clear();
      northWall^.clear();
      eastWall^.clear();

      // map MDR attributes to our map format.
      if (value and (1 shl 1) <> 0) then eastWall^.t := wtWall;
      if (value and (1 shl 2) <> 0) then northWall^.t := wtWall;
      if (value and (1 shl 3) <> 0) then eastWall^.t := wtDoor;
      if (value and (1 shl 4) <> 0) then northWall^.t := wtDoor;
      if (value and (1 shl 5) <> 0) then eastWall^.t := wtSecret;
      if (value and (1 shl 6) <> 0) then northWall^.t := wtSecret;
      if (value and (1 shl 15) <> 0) then tile^.floorType := ftWater;
      if (value and (1 shl 16) <> 0) then tile^.floorType := ftDirt;
      if (value and (1 shl 19) <> 0) then tile^.mediumType := mtRock;
      if (value and (1 shl 20) <> 0) then tile^.mediumType := mtFog;
      if (value and (1 shl 26) <> 0) then tile^.floorType := ftGrass;

      // skip unused bytes in this record
      ds.nextRecord();
    end;
  end;



end;

begin
end.