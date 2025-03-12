unit uTileEditorGui;

interface

uses
  uDebug,
  uTest,
  uUtils,
  uMap,
  uGraph32,
  uColor,
  uKeyboard,
  uFont,
  uGui,
  res;

type

  tEditMode = (emFloor);

  tTileEditorGUI = class(tGuiComponent)
  protected
    fFloorType: tFloorType;
    fEditMode: tEditMode;
  public
    constructor Create(x,y: integer);
    procedure changeSelection(delta: integer);
    procedure applyToMapTile(map: tMap; atX, atY: integer);
    procedure onKeyPress(code: word); override;
    procedure doDraw(dc: tDrawContext); override;
    property floorType: tFloorType read fFloorType;
    property editMode: tEditMode read fEditMode;
  end;

implementation

constructor tTileEditorGUI.Create(x,y: integer);
begin
  inherited Create();
  bounds.init(x, y, 200, 200);
  fEditMode := emFloor;
  fFloorType := ftStone;
end;

procedure tTileEditorGUI.applyToMapTile(map: tMap; atX, atY: integer);
var
  tile: tTile;
begin
  case editMode of
    emFloor: begin
      tile := map.tile[atX, atY];
      tile.floorType := fFloorType;
      map.tile[atX, atY] := tile;
    end;
  end;
end;

procedure tTileEditorGUI.changeSelection(delta: integer);
begin
  fFloorType := tFloorType(clamp(ord(fFloorType) + delta, 0, length(FLOOR_SPEC)-1));
end;

procedure tTileEditorGUI.onKeyPress(code: word);
begin
  case code of
    Key_OpenSquareBracket: changeSelection(-1);
    Key_CloseSquareBracket: changeSelection(+1);
  end;
end;

procedure tTileEditorGUI.doDraw(dc: tDrawContext);
var
  ft: tFloorType;
  fs: tFloorSpec;
  i: integer;
begin

  dc.fillRect(bounds, RGB(0,0,0));
  dc.drawRect(bounds, RGB(255,255,255));
  for ft in tFloorType do begin
    i := ord(ft);
    fs := FLOOR_SPEC[ft];
    if fs.spriteIdx >= 0 then
      mapSprites.sprites[fs.spriteIdx].draw(dc, bounds.x+i*16, bounds.y);
    if ft = floorType then begin
      mapSprites.sprites[CURSOR_SPRITE].draw(dc, bounds.x+i*16, bounds.y);
      DEFAULT_FONT.textOut(dc.page, bounds.x+1, bounds.y+15, fs.tag, RGB(255,255,255));
    end;
  end;
end;


begin
end.