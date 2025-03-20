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
  uTileBuilder,
  uVoxelScene,
  uGraph32;

type
  tDungeonViewGui = class(tGuiPanel)
  protected
    procedure buildTiles();
  public
    procedure doUpdate(elapsed: single); override;
    procedure doDraw(const dc: tDrawContext); override;
  public
    voxelScene: tVoxelScene;
    tiles: array[tFloorType] of tVoxel;
    constructor Create(map: tMDRMap);
    destructor destroy(); override;
  end;

implementation

procedure tDungeonViewGui.doDraw(const dc: tDrawContext);
var
  pos, angle: V3D;
begin
  inherited doDraw(dc);

  voxelScene.render(dc);
  {
  pos := V3(bounds.width/2,bounds.height/2,0);
  angle := V3(0,0,getSec);
  tiles[ftWater].draw(dc, pos, angle, 3.0);
  }
end;

procedure tDungeonViewGui.doUpdate(elapsed: single);
begin
  isDirty := true;
end;

procedure tDungeonViewGui.buildTiles();
var
  ft: tFloorType;
  tileBuilder: tTileBuilder;
  tile: tTile;
  walls: array[1..4] of tWall;
  voxelCell: tVoxel;
  tag, fileName: string;
begin

  tileBuilder := tTileBuilder.Create();
  for ft in tFloorType do begin

    tag := FLOOR_SPEC[ft].tag;
    fileName := joinPath('tiles', tag+'_16.vox');

    if fileSystem.exists(filename) then begin
      tiles[ft] := tVoxel.Create(32,32,32);
      tiles[ft].loadVoxFromFile(removeExtension(fileName), 32);
      continue;
    end;

    tile.floor := ft;
    walls[1].t := wtNone;
    walls[2].t := wtNone;
    walls[3].t := wtNone;
    walls[4].t := wtNone;
    tileBuilder.composeVoxelCell(tile, walls);
    voxelCell := tVoxel.Create(tileBuilder.page, 32);
    voxelCell.generateSDF(sdfFull);
    //voxelCell.lightingSamples := 16;
    //voxelCell.generateLighting(lmGI);
    tiles[ft] := voxelCell;
    saveLC96(fileName, voxelCell.vox);
  end;
  tileBuilder.free;
end;

constructor tDungeonViewGui.Create(map: tMDRMap);
var
  x,y: integer;
begin
  inherited Create(Rect(20, 30, 96, 124), 'View');

  voxelScene := tVoxelScene.Create();
  buildTiles();

  for x := 0 to 31 do
    for y := 0 to 31 do
      case map.tile[x,y].floor of
        ftNone: voxelScene.cells[x,y] := tiles[ftStone]
        else voxelScene.cells[x,y] := tiles[map.tile[x,y].floor]
      end;

  backgroundCol := RGBA.Lerp(MDR_LIGHTGRAY, RGBA.Black, 0.5);

end;

destructor tDungeonViewGui.destroy();
begin
  voxelScene.free;
  inherited destroy;
end;

begin
end.
