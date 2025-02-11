unit res;

interface

uses
  debug, utils, test,
  sound,
  sprite,
  graph32;

procedure loadResources();

var
  titleGFX: tPage;
  shootSFX, explodeSFX: tSoundEffect;
  sprites: tSpriteSheet;

implementation

procedure loadResources();
begin
  info('Loading resources');

  titleGFX := tPage.Load('res\title_320.p96');

  shootSFX := tSoundEffect.Load('res\shoot.a96');
  explodeSFX := tSoundEffect.Load('res\explode.a96');

  sprites := tSpriteSheet.create(tPage.load('res\sprites.p96'));
  sprites.load('sprites.ini');

end;

begin
end.
