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

  titleGFX := tPage.Load('res\title.p96');

  shootSFX := tSoundEffect.Load('res\shoot.a96');
  explodeSFX := tSoundEffect.Load('res\explode.a96');

  sprites := tSpriteSheet.create(tPage.load('res\sprites.p96'));
  sprites.page.setTransparent(RGB(255,0,255));
  sprites.grid(12,14);

end;

begin
end.
