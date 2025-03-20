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
  public
    procedure doUpdate(elapsed: single); override;
    procedure doDraw(const dc: tDrawContext); override;
  public
    voxelScene: tVoxelScene;
    voxelCell: tVoxel;
    constructor Create();
    destructor destroy(); override;
  end;

implementation

procedure tDungeonViewGui.doDraw(const dc: tDrawContext);
var
  pos, angle: V3D;
begin
  inherited doDraw(dc);
  {
  pos := V3(bounds.width/2,bounds.height/2,0);
  angle := V3(0,0,getSec);
  voxelCell.draw(dc, pos, angle, 1.0);
  }
  {bug stub... camera movement}
  voxelScene.render(dc);

end;

procedure tDungeonViewGui.doUpdate(elapsed: single);
begin
  isDirty := true;
end;

constructor tDungeonViewGui.Create();
var
  x,y: integer;
  c: byte;
  tile: tTile;
  walls: array[1..4] of tWall;
  tileBuilder: tTileBuilder;
  cached: string;
begin
  inherited Create(Rect(20, 30, 96, 124), 'View');
  voxelCell := tVoxel.Create(32,32,32);

  voxelScene := tVoxelScene.Create();

  cached := joinPath('res', 'tile1');
  if fileSystem.exists(cached+'.vox') then begin
    voxelCell.loadVoxFromFile(cached, 32);
  end else begin
    tileBuilder := tTileBuilder.Create();
    tile.floor := ftStone;
    walls[1].t := wtWall;
    walls[2].t := wtWall;
    walls[3].t := wtNone;
    walls[4].t := wtNone;
    tileBuilder.composeVoxelCell(tile, walls);
    voxelCell := tVoxel.Create(tileBuilder.page, 32);
    voxelCell.generateSDF(sdfFull);
    voxelCell.generateLighting(lmGI);
    saveLC96(cached+'.vox', voxelCell.vox);
    tileBuilder.free;
  end;

  backgroundCol := RGBA.Lerp(MDR_LIGHTGRAY, RGBA.Black, 0.5);

end;

destructor tDungeonViewGui.destroy();
begin
  voxelScene.free;
  voxelCell.free;
  inherited destroy;
end;

begin
end.
