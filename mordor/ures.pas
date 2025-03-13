unit uRes;

interface

uses
  uDebug,
  uTest,
  uSprite,
  uSound,
  uGraph32;

var
  gfx: tGFXLibrary;
  sfx: tSFXLibrary;
  mapSprites: tSpriteSheet;

procedure loadResources();

implementation

procedure loadResources();
begin
  gfx := tGFXLibrary.Create(true);
  gfx.loadFromFolder('res', '*.p96');

  sfx := tSFXLibrary.Create(true);
  sfx.loadFromFolder('res', '*.a96');

  mapSprites := tSpriteSheet.create(gfx['map']);
  mapSprites.grid(16,16);
end;

begin
end.
