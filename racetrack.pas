{handle airtime tracks}
unit raceTrack;

interface

uses
  debug,
  utils,
  graph32;

type tRaceTrack = class

  background: tPage;
  heightMap: tPage;
  terrainMap: tPage;

  function width(): integer;
  function height(): integer;

  constructor Create(filename: string);
  destructor Destroy();
  end;

implementation


function tRaceTrack.width: integer;
begin
  result := background.width;
end;

function tRaceTrack.height: integer;
begin
  result := background.height;
end;


{load a track file}
constructor tRaceTrack.Create(filename: string);
begin
  inherited create();
  {for the moment this is just a series of files}
  background := tPage.Load(filename+'.p96');
  heightMap := tPage.Load(filename+'_height.p96');
  terrainMap := tPage.Load(filename+'_terrain.p96');
  if (terrainMap.width <> background.width)  or (terrainMap.height <> background.height) then error('TerrainMap dims do not background');
  if (heightMap.width <> background.width)  or (heightMap.height <> background.height) then error('HeightMap dims do not background');
end;

destructor tRaceTrack.Destroy();
begin
  background.free;
  heightMap.free;
  terrainMap.free;
  inherited Destroy();
end;
begin
end.