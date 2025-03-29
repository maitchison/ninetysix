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
  uJob,
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
    renderJob: tJobProc;
    function  buildTile(tile: tTile; walls: tWalls): tVoxel;
    function  getTile(tile: tTile; walls: tWalls): tVoxel;
    procedure buildMapTiles(atX, atY: integer; radius: integer);
    function  getTileKey(tile: tTile; walls: tWalls): string;
  public
    voxelScene: tVoxelScene;
    tileCache: tStringMap<tVoxel>;
    tileBuilder: tTileBuilder;
    function  updateRender(): boolean;
    procedure doUpdate(elapsed: single); override;
    procedure doDraw(const dc: tDrawContext); override;
    constructor Create(aMap: tMDRMap);
    destructor destroy(); override;
  end;

implementation

type
  tVoxelRenderJob = class(tJob)
    target: tVoxel;
    outputFilename: string;
    procedure update(timeSlice: single); override;
    constructor Create(aTarget: tVoxel;aOutputFilename: string='');
  end;

{-------------------------------------------------}

constructor tVoxelRenderJob.Create(aTarget: tVoxel;aOutputFilename: string='');
begin
  inherited Create();
  target := aTarget;
  outputFilename := aOutputFilename;
  mdr.addMessage('Starting job '+aOutputFilename);
end;

procedure tVoxelRenderJob.update(timeSlice: single);
var
  startTime: single;
begin
  startTime := getSec;
  while getSec < startTime + timeSlice do
    if target.updateLighting() then begin
      {pitty we can't also to a job for this..}
      if (outputFilename <> '') then
        saveLC96(outputFileName, target.vox);
      mdr.addMessage('Completed job '+outputFilename);
      state := jsDone;
      break;
    end;
end;

{-------------------------------------------------}

procedure tDungeonViewGui.doDraw(const dc: tDrawContext);
var
  pos, angle: V3D;
  cell: tVoxel;
begin

  self.backgroundCol := RGB(50,50,50);

  if voxelScene.didCameraMove() then begin
    inherited doDraw(dc);
    {initial preview render}
    voxelScene.render(dc);
  end;

  {debug key: show current tile}
  if keyDown(key_x) then begin
    pos := V3(bounds.width/2,bounds.height/2,0);
    angle := V3(0,0,getSec);
    cell := voxelScene.cells[trunc(voxelScene.cameraPos.x), trunc(voxelScene.cameraPos.y)];
    cell.draw(dc, pos, angle, 5.0);
  end;
end;

procedure tDungeonViewGui.doUpdate(elapsed: single);
begin
  inherited doUpdate(elapsed);
  buildMapTiles(trunc(voxelScene.cameraPos.x), trunc(voxelScene.cameraPos.y), 5);
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
  job: tVoxelRenderJob;
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
    result.generateLighting(lmGI, true);
    job := tVoxelRenderJob.Create(result, filename);
    job.start();
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

function tDungeonViewGui.updateRender(): boolean;
begin
  voxelScene.render(canvas.getDC, 0.001);
  {turn off once we are done}
  result := voxelScene.isDone;
end;

constructor tDungeonViewGui.Create(aMap: tMDRMap);
var
  x,y: integer;
  tile: tTile;
  walls: array[1..4] of tWall;
begin
  inherited Create(Rect(20, 16, 96, 112), 'View');

  tileCache := tStringMap<tVoxel>.Create();

  map := aMap;
  tileBuilder := tTileBuilder.Create(16);
  voxelScene := tVoxelScene.Create(tileBuilder.tileSize);

  backgroundCol := RGBA.Lerp(mdr.LIGHTGRAY, RGBA.Black, 0.5);

  renderJob := tJobProc.Create(self.updateRender);
  renderJob.start();
end;

destructor tDungeonViewGui.destroy();
begin
  renderJob.stop();
  renderJob.free;
  voxelScene.free;
  tileBuilder.free;
  tileCache.free;
  inherited destroy;
end;

begin
end.
