unit res;

interface

uses
  {$i units},
  fileSystem;

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
