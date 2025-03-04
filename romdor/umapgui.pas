unit uMapGUI;

interface

uses
  test,
  debug,
  utils,
  ui,
  graph32,
  sprite,
  uScreen,
  {game stuff}
  res,
  uMap
  ;

type
  tMapGUI = class(tGuiComponent)
  protected
    background: tSprite;
    canvas: tPage;
    cSprite: tSprite; // todo: remove this and enabled pages to draw
  const
    TILE_SIZE = 15;
  public
    map: tMap;
    constructor Create();
    destructor destroy(); override;
    procedure renderTile(x,y: integer);
    procedure doDraw(screen: tScreen); override;
    procedure refresh();
  end;

implementation

{-------------------------------------------------------}

constructor tMapGUI.Create();
begin
  inherited Create();
  map := nil;
  background := tSprite.create(gfx['darkmap']);
  bounds.width := 512;
  bounds.height := 512;
  canvas := tPage.create(bounds.width, bounds.height);
  cSprite := tSprite.create(canvas);
end;

destructor tMapGUI.destroy();
begin
  canvas.free;
  cSprite.free;
  inherited destroy;
end;

{renders a single map tile}
procedure tMapGUI.renderTile(x,y: integer);
var
  tile: tTile;
  atX, atY: integer;
  dx,dy: integer;
  id: integer;
  i: integer;
  padding : integer;
begin
  padding:= (512 - ((TILE_SIZE * 32)+1)) div 2;
  atX := x*TILE_SIZE+padding;
  atY := y*TILE_SIZE+padding;
  tile := map.tile[x,y];

  {floor}
  id := FLOOR_SPRITE[tile.floorType];
  if id >= 0 then mapSprites.sprites[id].draw(canvas, atX, atY);

  {medium}
  id := MEDIUM_SPRITE[tile.mediumType];
  if id >= 0 then mapSprites.sprites[id].draw(canvas, atX, atY);

  {walls}
  {
  for i := 0 to 3 do begin
    id := WALL_SPRITE[tile.wall[i].t];
    if id < 0 then continue;
    dx := WALL_DX[i];
    dy := WALL_DY[i];
    if dy <> 0 then inc(id); // rotated varient
    mapSprites.sprites[id].draw(screen.canvas, atX+dx, atY+dy);
  end;
  }
end;

procedure tMapGUI.doDraw(screen: tScreen);
begin
  cSprite.blit(screen.canvas, bounds.x, bounds.y);
  screen.markRegion(bounds);
end;

procedure tMapGui.refresh();
var
  x,y: integer;
begin
  background.draw(canvas, 0, 0);
  if not assigned(map) then exit();
  for y := 0 to map.height-1 do
    for x := 0 to map.width-1 do
      renderTile(x, y);
end;

end.