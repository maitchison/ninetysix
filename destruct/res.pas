unit res;

interface

uses
  {$i units}
  ;

procedure loadResources();

var
  titleGFX: tPage;
  shootSFX, explodeSFX: tSoundEffect;
  sprites: tSpriteSheet;
  tankGuiSprite: tSprite;

implementation

procedure loadResources();
begin
  info('Loading resources');

  titleGFX := tPage.Load('res\title.p96');

  shootSFX := tSoundEffect.Load('res\shoot.a96');
  explodeSFX := tSoundEffect.Load('res\explode.a96');

  sprites := tSpriteSheet.create(tPage.load('res\sprites.p96'));
  sprites.grid(16,16);
  tankGuiSprite := tSprite.create(sprites.page, Rect(0, 16*13, 160, 16));

end;

begin
end.
