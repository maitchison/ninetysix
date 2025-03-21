unit uDungeonViewGui;

interface

uses
  {$i gui.inc}
  uTest,
  uDebug,
  uRect,
  uUtils,
  uMDRRes,
  uVertex,
  uVoxel,
  uColor,
  uFileSystem,
  uP96,
  uMDRMap,
  uStringMap,
  uTileBuilder,
  uVoxelScene,
  uKeyboard,
  uGraph32;

type

  tWalls = array[tDirection] of tWall;

  tDungeonViewGui = class(tGuiPanel)
  protected
    map: tMDRMap;
    function  buildTile(tile: tTile; walls: tWalls): tVoxel;
    function  getTile(tile: tTile; walls: tWalls): tVoxel;
    procedure buildMapTiles(atX, atY: integer; radius: integer);
    function  getTileKey(tile: tTile; walls: tWalls): string;
  public
    procedure doUpdate(elapsed: single); override;
    procedure doDraw(const dc: tDrawContext); override;
  public
    voxelScene: tVoxelScene;
    tileCache: tStringMap<tVoxel>;
    tileBuilder: tTileBuilder;
    constructor Create(aMap: tMDRMap);
    destructor destroy(); override;
  end;

implementation

procedure tDungeonViewGui.doDraw(const dc: tDrawContext);
var
  pos, angle: V3D;
  cell: tVoxel;
begin
  //inherited doDraw(dc);

  {todo: put in update?}
  buildMapTiles(trunc(voxelScene.cameraPos.x), trunc(voxelScene.cameraPos.y), 1);
  voxelScene.render(dc);
  if keyDown(key_z) then begin
    pos := V3(bounds.width/2,bounds.height/2,0);
    angle := V3(0,0,getSec);
    cell := voxelScene.cells[trunc(voxelScene.cameraPos.x), trunc(voxelScene.cameraPos.y)];
    cell.draw(dc, pos, angle, 5.0);
  end;
end;

procedure tDungeonViewGui.doUpdate(elapsed: single);
begin
  isDirty := true;
end;

function tDungeonViewGui.buildTile(tile: tTile; walls: tWalls): tVoxel;
begin
  tileBuilder.composeVoxelCell(tile, walls);
  result := tVoxel.Create(tileBuilder.page, tileBuilder.tileSize);
  result.generateSDF(sdfFull);
end;

function tDungeonViewGui.getTileKey(tile: tTile; walls: tWalls): string;
var
  d: tDirection;
begin
  result := tile.toString;
  for d in tDirection do result := result + '-' + walls[d].toString;
end;

{gets tile, uses tileCache, and disk cache.}
function tDungeonViewGui.getTile(tile: tTile; walls: tWalls): tVoxel;
var
  key: string;
  filename: string;
  rotatedKey: string;
  rotatedWalls: tWalls;
  rotatedFilename: string;
  i,j: integer;
begin

  key := getTileKey(tile, walls);
  if tileCache.contains(key) then
    exit(tileCache[key]);

  result := nil;

  for i := 0 to 3 do begin
    for j := 0 to 3 do rotatedWalls[tDirection(j)] := walls[tDirection((i+j) mod 4)];
    rotatedKey := getTileKey(tile, rotatedWalls);
    rotatedFilename := joinPath('tiles', rotatedKey+'_256.vox');
    if filesystem.exists(rotatedFilename) then begin
      {todo: size from file}
      result := tVoxel.Create(tileBuilder.tileSize, tileBuilder.tileSize, tileBuilder.tileSize);
      result.loadVoxFromFile(removeExtension(rotatedFileName), tileBuilder.tileSize);
      for j := 0 to i-1 do result.rotate();
      break;
    end;
  end;

  if not assigned(result) then begin
    key := getTileKey(tile, walls);
    filename := joinPath('tiles', key+'_256.vox');
    result := buildTile(tile, walls);
    result.lightingSamples := 256;
    result.generateLighting(lmGI);
    saveLC96(fileName, result.vox);
  end;
  tileCache[key] := result;
end;

{builds tiles on map within radius L1 distance of (atX, atY)}
procedure tDungeonViewGui.buildMapTiles(atX, atY: integer; radius: integer);
var
  x,y: integer;
  d: tDirection;
  tile: tTile;
  walls: tWalls;
  vox: tVoxel;
  tag: string;
begin
  for y := 0 to 31 do begin
    for x := 0 to 31 do begin
      if (abs(x-atX) > radius) or (abs(y-atY) > radius) then continue;
      tile := map.tile[x,y];
      if (tile.floor = ftNone) then tile.floor := ftStone;
      for d in tDirection do walls[d] := map.wall[x,y,d];
      voxelScene.cells[x,y] := getTile(tile, walls);
    end;
  end;
end;

constructor tDungeonViewGui.Create(aMap: tMDRMap);
var
  x,y: integer;
  tile: tTile;
  walls: array[1..4] of tWall;
begin
  //stub: larger
  inherited Create(Rect(100, 0, 200, 200), 'View');

  tileCache := tStringMap<tVoxel>.Create();

  map := aMap;
  tileBuilder := tTileBuilder.Create(16);
  voxelScene := tVoxelScene.Create(tileBuilder.tileSize);

  backgroundCol := RGBA.Lerp(MDR_LIGHTGRAY, RGBA.Black, 0.5);

end;

destructor tDungeonViewGui.destroy();
begin
  voxelScene.free;
  tileBuilder.free;
  tileCache.free;
  inherited destroy;
end;

begin
end.
