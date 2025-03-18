unit uDungeonViewGui;

interface

uses
  {$i gui.inc}
  uTest,
  uDebug,
  uRect,
  uUtils,
  uMDRRes,
  uVertex,
  uVoxel,
  uColor,
  uMDRMap,
  uGraph32;

type
  tDungeonViewGui = class(tGuiPanel)
  protected
    noisePage: tPage;
    voxelPage: tPage;
  public
    procedure composeVoxelCell(tile: tTile; walls: array of tWall);
    procedure doUpdate(elapsed: single); override;
    procedure doDraw(const dc: tDrawContext); override;
  public
    voxelCell: tVoxel;
    constructor Create();
    destructor destroy(); override;
  end;

implementation

procedure tDungeonViewGui.composeVoxelCell(tile: tTile; walls: array of tWall);
var
  page: tPage;
  pixelsPtr: pointer;
  dc: tDrawContext;
  layer: integer;
  d: tDirection;
  x,y,z: integer;
  i,j,k: integer;
  corner: integer;
  c: integer;

  procedure noise(power: single=0.5);
  begin
    dc.asBlendMode(bmBlend).asTint(RGB(255,255,255,round(power*255))).drawImage(noisePage, Point(0,layer*32));
  end;

  procedure decimate(p: single);
  var
    x,y: integer;
    c: RGBA;
  begin
    for x := 0 to 31 do begin
      for y := 0 to 31 do begin
        if (random() > p) then continue;
        page.setPixel(x,y+layer*32,RGBA.Clear);
      end;
    end;
  end;

  procedure speckle(col: RGBA; p: single=0.1; border: integer=0);
  var
    x,y: integer;
    c: RGBA;
  begin
    for x := border to 31-border do begin
      for y := border to 31-border do begin
        if (random() > p) then continue;
        page.setPixel(x,y+layer*32,col);
      end;
    end;
  end;

  procedure fill(col: RGBA; border: integer=0);
  begin
    dc.fillRect(Rect(border,layer*32,32-(border*2),32-(border*2)), col);
  end;

  procedure pillar(x,y: integer;size: integer=3; height: integer=31);
  var
    i,j,k: integer;
  begin
    for k := 0 to height-1 do
      for i := 0 to size-1 do
        for j := 0 to size-1 do begin
          c := (rnd-128) div 4-20;
          page.setPixel(i+x,(j+y)+k*32,RGB($6f+c, $5c+c, $42+c));
        end;
  end;

  procedure wall(d: tDirection; height: integer=16);
  var
    i,j: integer;
  begin
    for i := -15 to 15 do begin
      for j := 0 to height-1 do begin
        x := round(15.5 + DX[d]*15.5) + DY[d]*i;
        y := round(15.5 + DY[d]*15.5) + DX[d]*i;
        z := 31-j;
        c := (rnd-128) div 8;
        if rnd >= 200 then begin
          {brick outlines}
          if j and $3 = 0 then
            c -= 32
          else begin
            if (i+15) and $7 = 3 then c -= 16;
            if (i+15) and $7 = 4 then c += 16;
          end;
        end;
        page.setPixel(x,y+z*32,RGB($6f+c, $5c+c, $42+c));
      end;
    end;
  end;

begin
  page := voxelPage;
  assertEqual(page.width, 32);
  assertEqual(page.height, 32*32);
  page.clear(RGBA.Clear());
  dc := page.getDC(bmBlit);
  {ceiling}
  //dc.fillRect(Rect(0,0*32,32,32), MDR_DARKGRAY);
  //dc.fillRect(Rect(0,1*32,32,32), MDR_LIGHTGRAY);
  {floor}
  case tile.floor of
    ftStone: begin
      //bedrock
      layer := 31;
      fill(MDR_DARKGRAY);
      noise(0.25);
      //stone
      layer := 30;
      fill(MDR_LIGHTGRAY);
      noise(0.5);
      decimate(0.1);
    end;
    ftDirt: begin
      //bedrock
      layer := 31;
      fill(MDR_DARKGRAY);
      noise(0.25);
      //dirt
      layer := 30;
      fill(RGB($FF160616));
      noise(0.5);
      decimate(0.1);
      //dry grass
      speckle(MDR_GREEN*RGB(128,128,128), 0.05);
      //stones
      layer := 29;
      speckle(MDR_LIGHTGRAY, 0.5);
    end;
    ftGrass: begin
      //bedrock
      layer := 31;
      fill(MDR_DARKGRAY);
      noise(0.25);
      //grass
      layer := 30;
      fill(MDR_GREEN*MDR_LIGHTGRAY);
      noise(0.6);
      //dry patch
      speckle(RGBA.Lerp(RGB($FF160616), MDR_GREEN, 0.5), 0.15);
      //stones
      //layer := 29;
      //speckle(MDR_LIGHTGRAY, 0.5);
    end;
    ftWater: begin
      layer := 31;
      fill(MDR_BLUE);
      noise(0.3);
      layer := 30;
      fill(MDR_BLUE);
      noise(0.1);
    end;
  end;

  {walls}
  for d in tDirection do begin
    if not walls[ord(d)].isSolid then continue;
    wall(d);
  end;

  {pillars}
  if walls[ord(dNorth)].isSolid or walls[ord(dWest)].isSolid then
    pillar(0,0);
  if walls[ord(dNorth)].isSolid or walls[ord(dEast)].isSolid then
    pillar(32-3,0);
  if walls[ord(dSouth)].isSolid or walls[ord(dWest)].isSolid then
    pillar(0,32-3);
  if walls[ord(dSouth)].isSolid or walls[ord(dEast)].isSolid then
    pillar(32-3,32-3);

  {trim}
  {todo: get trim from neighbours... ah... we do want map then...
   either that or build it into wall? yes.. wall is probably better}
  if (tile.floor in [ftStone]) then begin
    dc.fillRect(Rect(0,0+29*32,32,32), MDR_LIGHTGRAY);
    dc.fillRect(Rect(1,1+29*32,30,30), RGBA.Clear);
  end;

  {uniform CDF for now... can optimize later}
  pixelsPtr := page.pixels;
  asm
    pushad
    mov edi, PIXELSPTR
    mov ecx, 32*32*32
  @PIXELLOOP:
    mov eax, [edi]
    and eax, $00ffffff
    jz @EMPTY
  @SOLID:
    or  eax, $ff000000  //256 = solid
    jmp @APPLY
  @EMPTY:
    or  eax, $fa000000  //255-4 = 1 unit (for empty cells)
  @APPLY:
    mov [edi], eax
    add edi, 4
    dec ecx
    jnz @PIXELLOOP
    popad
  end;
end;

procedure tDungeonViewGui.doDraw(const dc: tDrawContext);
var
  pos, angle: V3D;
begin
  inherited doDraw(dc);
  pos := V3(bounds.width/2,bounds.height/2,0);
  angle := V3(0,0,getSec);
  voxelCell.draw(dc, pos, angle, 2.0);
end;

procedure tDungeonViewGui.doUpdate(elapsed: single);
begin
  isDirty := true;
end;

constructor tDungeonViewGui.Create();
var
  x,y: integer;
  c: byte;
  tile: tTile;
  walls: array[1..4] of tWall;
begin
  inherited Create(Rect(20, 10, 96, 124), 'View');
  voxelCell := tVoxel.Create(32,32,32);
  voxelPage := voxelCell.vox.clone();
  noisePage := tPage.Create(32,32);
  for y := 0 to 31 do
    for x := 0 to 31 do begin
      c := rnd div 2 + 64;
      noisePage.setPixel(x,y, RGB(c,c,c));
    end;

  tile.floor := ftStone;
  walls[1].t := wtWall;
  walls[2].t := wtNone;
  walls[3].t := wtNone;
  walls[4].t := wtNone;

  composeVoxelCell(tile, walls);
  voxelCell.generateLighting(lmGradient, voxelPage);

  backgroundCol := RGBA.Lerp(MDR_LIGHTGRAY, RGBA.Black, 0.5);
end;

destructor tDungeonViewGui.destroy();
begin
  voxelCell.free;
  noisePage.free;
  inherited destroy;
end;

begin
end.
