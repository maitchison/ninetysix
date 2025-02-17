unit res;

interface

uses
  {$i units}
  ;

procedure loadResources();
procedure freeResources();

var
  titleGFX: tPage;
  sfx: tSFXLibrary;
  sprites: tSpriteSheet;
  tankGuiSprite: tSprite;

implementation

const
  sfxFiles: array of string = [
    'shoot', 'explode', 'plasma', 'rocket'
  ];

procedure loadResources();
var
  i: integer;
  tag: string;
begin
  info('Loading resources');

  titleGFX := tPage.Load('res\title.p96');

  sfx := tSFXLibrary.create();
  for tag in sfxFiles do
    sfx.addResource('res\'+tag+'.a96');

  sprites := tSpriteSheet.create(tPage.load('res\sprites.p96'));
  sprites.grid(16, 16);
  tankGuiSprite := tSprite.create(sprites.page, Rect(0, 16*13, 160, 16));

  {center the projectile sprites}
  for i := 11*16+0 to 11*16+15 do begin
    sprites.sprites[i].pivot.x += 8;
    sprites.sprites[i].pivot.y += 8;
  end;
end;

procedure freeResources();
begin
  freeAndNil(titleGFX);
  freeAndNil(sfx);
  freeAndNil(sprites);
  freeAndNil(tankGuiSprite);
end;

begin
end.
