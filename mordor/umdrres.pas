unit uMDRRes;

interface

uses
  netFont,
  uDebug,
  uTest,
  uSprite,
  uSound,
  uColor,
  uUtils,
  uVoxel,
  uFont,
  uGraph32;

type
  {global space}
  tMordor = class
  const
    LIGHTGRAY: RGBA = (b:$a5; g:$9C; r:$95; a:$ff);
    DARKGRAY: RGBA  = (b:$46; g:$43; r:$40; a:$ff);
    FOURNINES: RGBA = (b:230; g:230; r:230; a:230);
    BLUE: RGBA      = (b:round(255*0.62);g:round(255*0.42); r:round(255*0.40); a:$ff);
    {still working on these colors}
    GREEN: RGBA     = (b:$39; g:$b7; r:$60; a:$ff);
  var
    FONT_TINY,
    FONT_SMALL,
    FONT_MEDIUM: tFont;

    gfx: tGFXLibrary;
    sfx: tSFXLibrary;
    mapSprites: tSpriteSheet;
    monsterSprites: tSpriteSheet;

    procedure loadResources();
  end;

var
 mdr: tMordor;

implementation

procedure tMordor.loadResources();
begin
  {additional fonts}
  FONT_TINY := loadNetFont(joinPath('res', 'netfont2.p96'));
  FONT_SMALL := tFont.LOAD(joinPath('res', 'fontin12'));
  FONT_MEDIUM := tFont.LOAD(joinPath('res', 'fontin18'));

  gfx := tGFXLibrary.Create(true);
  gfx.loadFromFolder('res', '*.p96');

  sfx := tSFXLibrary.Create(true);
  sfx.loadFromFolder('res', '*.a96');

  mapSprites := tSpriteSheet.Create(gfx['map']);
  mapSprites.grid(16,16);

  monsterSprites := tSpriteSheet.Create(gfx['monsters']);
  monsterSprites.grid(16,24);
end;

initialization
  mdr := tMordor.Create();
finalization
  mdr.free();
end.
