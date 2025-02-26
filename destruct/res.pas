unit res;

interface

uses
  {$i units},
  template,
  fileSystem;

procedure loadResources();
procedure freeResources();

var
  titleGFX: tPage;
  sfx: tSFXLibrary;
  sprites: tSpriteSheet;
  particleTemplate: tTemplate;
  tankGuiSprite: tSprite;

implementation

function sfxFilter(path: string): boolean;
begin
  {only load 'short' audio'}
  if fs.getFileSize(path) > 128*1024 then exit(false);
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
  tankGuiSprite := tSprite.create(sprites.page, Rect(0, 16*13, 155, 16));

  particleTemplate := tTemplate.Load('res\template.p96');
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
