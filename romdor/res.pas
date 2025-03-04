unit res;

interface

uses
  debug,
  test,
  sprite,
  graph32;

var
  gfx: tGFXLibrary;
  mapSprites: tSpriteSheet;

procedure loadResources();

implementation

procedure loadResources();
begin
  gfx := tGFXLibrary.Create();
  gfx.loadFromFolder('res', '*.p96');

  mapSprites := tSpriteSheet.create(gfx['map']);
  mapSprites.grid(16,16);
end;

begin
end.
