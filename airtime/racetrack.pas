{handle airtime tracks}
unit raceTrack;

interface

uses {$i units.inc};

type

  tTerrainDef = record
      tag: string;
      friction: single;
      traction: single;
    end;

  tRaceTrack = class

    background: tPage;
    heightMap: tPage;
    terrainMap: tPage;

    function width(): integer;
    function height(): integer;

    function worldToCanvas(p: V3D): tPoint;
    function sampleHeight(pos: V3D): single;
    function sampleTerrain(pos: V3D): tTerrainDef;

    constructor create(filename: string);
    destructor destroy(); override;
  end;

const

  TD_AIR = 0;
  TD_DIRT = 1;
  TD_GRASS = 2;
  TD_BARRIER = 3;

  TERRAIN_DEF: array[0..3] of tTerrainDef = (
    (tag:'air';     friction:0.0; traction:0),
    (tag:'dirt';    friction:0.0; traction:310),
    (tag:'grass';   friction:4.0; traction:210),
    (tag:'barrier'; friction:0.0; traction:1000)
  );

implementation

function tRaceTrack.width: integer;
begin
  result := background.width;
end;

function tRaceTrack.height: integer;
begin
  result := background.height;
end;

{return terrain at world position}
function tRaceTrack.sampleTerrain(pos: V3D): tTerrainDef;
var
  drawPos: tPoint;
  col: RGBA;
begin

  // unlike the canvas, terrain and height are projected onto the xy plane
  pos.z := 0;
  drawPos := worldToCanvas(pos);

  {figure out which terrain we are on}
  {note: this is a bit of a weird way to do it, but oh well}
  col := terrainMap.getPixel(drawPos.x, drawPos.y);

  case col.to32 of
    $FFFF0000: result := TERRAIN_DEF[TD_DIRT];
    $FF00FF00: result := TERRAIN_DEF[TD_GRASS];
    $FFFFFF00: result := TERRAIN_DEF[TD_BARRIER];
    else result := TERRAIN_DEF[TD_DIRT];
  end;

end;

{return height at world position}
function tRaceTrack.sampleHeight(pos: V3D): single;
var
  drawPos: tPoint;
  col: RGBA;
begin

  // unlike the canvas, terrain and height are projected onto the xy plane
  pos.z := 0;
  drawPos := worldToCanvas(pos);
  {figure out why terrain we are on}
  {note: this is a bit of a weird way to do it, but oh well}
  col := heightMap.getPixel(drawPos.x, drawPos.y);
  result := (128-col.r)/3;
end;

{applies our isometric transformation}
function tRaceTrack.worldToCanvas(p: V3D): tPoint;
begin
  result.x := round(p.x);
  result.y := round(p.rotated(-0.615, 0, 0).y);
end;


{load a track file}
constructor tRaceTrack.Create(filename: string);
begin
  inherited create();
  {for the moment this is just a series of files}
  background := tPage.Load(filename+'.p96');
  heightMap := tPage.Load(filename+'h.p96');
  terrainMap := tPage.Load(filename+'t.p96');
  if (terrainMap.width <> background.width)  or (terrainMap.height <> background.height) then fatal('TerrainMap dims do not match background');
  if (heightMap.width <> background.width)  or (heightMap.height <> background.height) then fatal('HeightMap dims do not match background');
end;

destructor tRaceTrack.Destroy();
begin
  background.free();
  heightMap.free();
  terrainMap.free();
  inherited destroy();
end;


begin
end.
