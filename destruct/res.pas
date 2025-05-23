unit res;

interface

uses
  {$i units},
  uFont,
  netFont,
  template;

procedure loadResources();
procedure freeResources();

var
  titleGFX: tPage;
  sfx: tSFXLibrary;
  sprites: tSpriteSheet;
  particleTemplate: tTemplate;
  tankGuiSprite: tSprite;
  smallFont: tFont;

implementation

function sfxFilter(path: string): boolean;
begin
  {only load 'short' audio'}
  if fileSystem.getFileSize(path) > 128*1024 then exit(false);
  exit(true);
end;

procedure loadResources();
var
  i: integer;
  tag: string;
begin
  info('Loading resources');

  titleGFX := tPage.Load('res\title.p96');

  sfx := tSFXLibrary.create();
  sfx.loadFromFolder('res', '*.a96', sfxFilter);

  sprites := tSpriteSheet.create(tPage.Load('res\sprites.p96'));
  sprites.grid(16, 16, true);
  tankGuiSprite := tSprite.create(sprites.page, Rect(0, 16*13, 128, 16));

  particleTemplate := tTemplate.Load('res\template.p96');

  smallFont := loadNetFont('res\netfont2.p96');
  DEFAULT_FONT := smallFont;
end;

procedure freeResources();
begin
  freeAndNil(titleGFX);
  freeAndNil(sfx);
  freeAndNil(sprites);
  freeAndNil(particleTemplate);
  freeAndNil(tankGuiSprite);
end;

begin
end.
