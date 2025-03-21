{builds voxel tiles}
unit uTileBuilder;

interface

uses
  uDebug,
  uTest,
  uVoxel,
  uVertex,
  uUtils,
  uColor,
  uRect,
  uGraph32,
  uMDRMap,
  uMDRRes;

type
  tTileBuilder = class
  protected
    layer: integer;
    dc: tDrawContext;
    procedure noise(power: single=0.5;border: integer=0);
    procedure decimate(p: single);
    procedure speckle(col: RGBA; p: single=0.1; border: integer=0);
    procedure fill(col: RGBA; border: integer=0);
    procedure pillar(x,y: integer;size: integer; height: integer);
    procedure wall(d: tDirection; height: integer);
  public
    tileSize: integer;
    page: tPage;
    procedure composeVoxelCell(tile: tTile; walls: array of tWall);
    constructor Create(aTileSize: integer=16);
    destructor destroy; override;
  end;

implementation

constructor tTileBuilder.Create(aTileSize: integer=16);
var
  x,y: integer;
  c: integer;
begin
  inherited Create();
  tileSize := aTileSize;
  page := tPage.Create(tileSize,tileSize*tileSize);
end;

destructor tTileBuilder.destroy;
begin
  page.free;
  inherited destroy();
end;

procedure tTileBuilder.noise(power: single=0.5; border: integer=0);
var
  x,y: integer;
  c: RGBA;
  v: single;
begin
  for x := border to (tileSize-1)-border do begin
    for y := border to (tileSize-1)-border do begin
      c := page.getPixel(x,y+layer*tileSize);
      v := 1-((rnd/255)*power);
      c.init(round(c.r*v), round(c.g*v), round(c.b*v), c.a);
      page.setPixel(x,y+layer*tileSize,c);
    end;
  end;
end;

procedure tTileBuilder.decimate(p: single);
var
  x,y: integer;
  c: RGBA;
begin
  for x := 0 to tileSize-1 do begin
    for y := 0 to tileSize-1 do begin
      if (random() > p) then continue;
      page.setPixel(x,y+layer*tileSize,RGBA.Clear);
    end;
  end;
end;

procedure tTileBuilder.speckle(col: RGBA; p: single=0.1; border: integer=0);
var
  x,y: integer;
  c: RGBA;
begin
  for x := border to (tileSize-1)-border do begin
    for y := border to (tileSize-1)-border do begin
      if (random() > p) then continue;
      page.setPixel(x,y+layer*tileSize,col);
    end;
  end;
end;

procedure tTileBuilder.fill(col: RGBA; border: integer=0);
begin
  dc.fillRect(Rect(border,layer*tileSize,tileSize-(border*2),tileSize-(border*2)), col);
end;

procedure tTileBuilder.pillar(x,y: integer;size: integer; height: integer);
var
  i,j,k: integer;
  c: integer;
begin
  for k := 0 to height-1 do
    for i := 0 to size-1 do
      for j := 0 to size-1 do begin
        c := (rnd-128) div 4-20;
        page.setPixel(i+x,(j+y)+k*tileSize,RGB($6f+c, $5c+c, $42+c));
      end;
end;

procedure tTileBuilder.wall(d: tDirection; height: integer);
var
  i,j: integer;
  x,y,z: integer;
  c: integer;
begin
  for i := -(tileSize div 2) to (tileSize div 2) do begin
    for j := 0 to height-1 do begin
      x := round(15.5 + DX[d]*15.5) + DY[d]*i;
      y := round(15.5 + DY[d]*15.5) + DX[d]*i;
      z := tileSize-1-j;
      c := (rnd-128) div 8;
      if rnd >= 200 then begin
        {brick outlines}
        if j and $3 = 0 then
          c -= tileSize
        else begin
          if (i+15) and $7 = 3 then c -= 16;
          if (i+15) and $7 = 4 then c += 16;
        end;
      end;
      page.setPixel(x,y+z*tileSize,RGB($6f+c, $5c+c, $42+c));
    end;
  end;
end;

procedure tTileBuilder.composeVoxelCell(tile: tTile; walls: array of tWall);
var
  pixelsPtr: pointer;
  d: tDirection;
  x,y,z: integer;
  i,j,k: integer;
  corner: integer;
  c: integer;
begin
  dc := page.getDC(bmBlit);
  assertEqual(page.width, tileSize);
  assertEqual(page.height, tileSize*tileSize);
  page.clear(RGBA.Clear());
  {ceiling (temp)}
  {
  dc.fillRect(Rect(0,20*32,32,32), MDR_DARKGRAY);
  dc.fillRect(Rect(0,21*32,32,32), MDR_LIGHTGRAY);
  }
  {floor}
  case tile.floor of
    ftStone: begin
      //bedrock
      layer := (tileSize-1);
      fill(MDR_DARKGRAY, 1);
      noise(0.25);
      //stone
      layer := (tileSize-2);
      fill(MDR_LIGHTGRAY, 1);
      noise(0.5);
    end;
    ftDirt: begin
      //bedrock
      layer := (tileSize-1);
      fill(MDR_DARKGRAY);
      noise(0.25);
      //dirt
      layer := (tileSize-2);
      fill(RGB($FF442C14));
      noise(0.5);
      decimate(0.1);
      //dry grass
      //speckle(MDR_GREEN*RGB(128,128,128), 0.05);
      //stones
      {layer := 29;
      speckle(MDR_LIGHTGRAY, 0.05);}
    end;
    ftGrass: begin
      //bedrock
      layer := (tileSize-1);
      fill(MDR_DARKGRAY);
      noise(0.25);
      //grass
      layer := (tileSize-2);
      fill(MDR_GREEN*MDR_LIGHTGRAY);
      noise(0.6);
      //dry patch
      speckle(RGBA.Lerp(RGB($FF160616), MDR_GREEN, 0.5), 0.15);
      //stones
      //layer := 29;
      //speckle(MDR_LIGHTGRAY, 0.5);
    end;
    ftWater: begin
      layer := (tileSize-1);
      fill(MDR_BLUE);
      noise(0.3);
      layer := (tileSize-2);
      fill(MDR_BLUE);
      noise(0.1);
    end;
  end;

  {walls}
  for d in tDirection do begin
    if not walls[ord(d)].isSolid then continue;
    wall(d, tileSize-2);
  end;

  {pillars}
  if walls[ord(dNorth)].isSolid or walls[ord(dWest)].isSolid then
    pillar(0,0,2, tileSize);
  if walls[ord(dNorth)].isSolid or walls[ord(dEast)].isSolid then
    pillar(tileSize-3,0,2, tileSize);
  if walls[ord(dSouth)].isSolid or walls[ord(dWest)].isSolid then
    pillar(0,tileSize-3,2, tileSize);
  if walls[ord(dSouth)].isSolid or walls[ord(dEast)].isSolid then
    pillar(tileSize-3,tileSize-3,2,tileSize);

  {trim}
  {todo: get trim from neighbours... ah... we do want map then...
   either that or build it into wall? yes.. wall is probably better}
  if (tile.floor in [ftStone]) then begin
    dc.drawRect(Rect(0,0+(tileSize-3)*tileSize,tileSize,tileSize), MDR_LIGHTGRAY);
  end;

end;

begin
end.
