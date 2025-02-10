unit resources;

interface

uses
  debug, utils, test,
  sprite,
  graph32;

procedure loadResources();

var
  titleGFX: tPage;
  sprites: tSpriteSheet;

implementation

procedure loadResources();
begin
  info('Loading resources');

  titleGFX := tPage.Load('res\title_320.p96');

  sprites := tSpriteSheet.create(tPage.load('res\sprites.p96'));
  sprites.load('sprites.ini');

end;

begin
end.
