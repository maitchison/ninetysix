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

procedure loadResources();

{global colors}
const
  MDR_LIGHTGRAY: RGBA = (b:$a5; g:$9C; r:$95; a:$ff);
  MDR_DARKGRAY: RGBA  = (b:$46; g:$43; r:$40; a:$ff);
  MDR_FOURNINES: RGBA = (b:230; g:230; r:230; a:230);

implementation

procedure loadResources();
begin
  gfx := tGFXLibrary.Create(true);
  gfx.loadFromFolder('res', '*.p96');

  sfx := tSFXLibrary.Create(true);
  sfx.loadFromFolder('res', '*.a96');

  mapSprites := tSpriteSheet.create(gfx['map']);
  mapSprites.grid(16,16);

  doorVoxel := tVoxel.Create(joinPath('res', 'door_64'), 64);

end;

begin
end.
