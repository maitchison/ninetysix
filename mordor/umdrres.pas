unit uMDRRes;

interface

uses
  uDebug,
  uTest,
  uSprite,
  uSound,
  uColor,
  uUtils,
  uVoxel,
  uGraph32;

var
  gfx: tGFXLibrary;
  sfx: tSFXLibrary;
  mapSprites: tSpriteSheet;
  doorVoxel: tVoxel;
  carVoxel: tVoxel;

procedure loadResources();

{global colors}
const
  MDR_LIGHTGRAY: RGBA = (b:$a5; g:$9C; r:$95; a:$ff);
  MDR_DARKGRAY: RGBA  = (b:$46; g:$43; r:$40; a:$ff);
  MDR_FOURNINES: RGBA = (b:230; g:230; r:230; a:230);
  MDR_BLUE: RGBA      = (b:round(255*0.62);g:round(255*0.42); r:round(255*0.40); a:$ff);
  {still working on these colors}
  MDR_GREEN: RGBA = (b:$39; g:$b7; r:$60; a:$ff);



implementation

procedure loadResources();
begin
  gfx := tGFXLibrary.Create(true);
  gfx.loadFromFolder('res', '*.p96');

  sfx := tSFXLibrary.Create(true);
  sfx.loadFromFolder('res', '*.a96');

  mapSprites := tSpriteSheet.create(gfx['map']);
  mapSprites.grid(16,16);

  doorVoxel := tVoxel.Create(joinPath('res', 'door_32'), 32);
  carVoxel := tVoxel.Create(joinPath('res', 'carRed'), 16);

end;

begin
end.
