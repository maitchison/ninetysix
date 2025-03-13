unit uMDRImporter;

interface

uses
  uDebug,
  uTest,
  uUtils,
  uFileSystem,
  uStream,
  uMDRMap;

type
  {used to read MDR files}
  tMDRDataStream = class(tMemoryStream)
  private
    recordSize: integer;
  public

    constructor Create(aRecordSize: integer=1);

    function  readMDRWord(): word;
    function  readCurrency(): extended;
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

function tMDRDataStream.readCurrency(): extended;
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
  value: int64;
  tile: tTile;
  northWall, eastWall, edgeWall: tWall;
  edgeTile: tTile;
  bits: bitpacked array[0..63] of boolean;
begin

  map := tMap.Create(32,32);
  result := map;

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

  note('Importing Mordor map %dx%d', [header.width, header.height]);

  // load field records
  for ylp := 0 to header.height-1 do begin
    for xlp := 0 to header.width-1 do begin

      // area number
      ds.readWord();

      // read in the bit values
      value := round(ds.readCurrency());

      // copy across the attributes
      // these will need to be changed later
      move(value, tile.attributes, 4);
      move(value, bits, 8);

      tile.clear();
      northWall.clear();
      eastWall.clear();

      // map MDR attributes to our map format.
      if bits[0] then eastWall.t := wtWall;
      if bits[1] then northWall.t := wtWall;
      if bits[2] then eastWall.t := wtDoor;
      if bits[3] then northWall.t := wtDoor;
      if bits[4] then eastWall.t := wtSecret;
      if bits[5] then northWall.t := wtSecret;

      if bits[15] then tile.floor := ftWater;
      if bits[16] then tile.floor := ftDirt;
      // custom adjustment for grass
      if bits[15] and bits[16] then tile.floor := ftWater;

      if bits[19] then tile.medium := mtRock;
      if bits[20] then tile.medium := mtFog;

      {our map is 32x32, but the mordor map is 30, so add a border}
      map.tile[xlp+1,ylp+1] := tile;
      map.wall[xlp+1,ylp+2,dNorth] := northWall;
      map.wall[xlp+1,ylp+1,dEast] := eastWall;

      // skip unused bytes in this record
      ds.nextRecord();
    end;
  end;

  {set outer bounds}
  edgeWall.clear();
  edgeWall.t := wtWall;
  edgeTile.clear();
  edgeTile.medium := mtNone;

  for xlp := 1 to header.width do begin
    map.wall[xlp,1,dNorth] := edgeWall;
    map.wall[xlp,header.height,dSouth] := edgeWall;
  end;
  for ylp := 1 to header.height do begin
    map.wall[1, ylp, dWest] := edgeWall;
    map.wall[header.width, ylp, dEast] := edgeWall;
  end;
  {
  for xlp := 0 to 31 do begin
    map.wall[xlp,0,dNorth] := edgeWall;
    map.wall[xlp,31,dSouth] := edgeWall;
    map.tile[xlp,0] := edgeTile;
    map.tile[xlp,31] := edgeTile;
  end;
  for ylp := 0 to 31 do begin
    map.wall[0, ylp, dWest] := edgeWall;
    map.wall[31, ylp, dEast] := edgeWall;
    map.tile[0, ylp] := edgeTile;
    map.tile[31, ylp] := edgeTile;
  end;
  }

end;

begin
end.
