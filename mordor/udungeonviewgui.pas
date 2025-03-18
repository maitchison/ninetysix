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
    noise: tPage;
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

  procedure decimateLayer(depth: integer;p: single);
  var
    x,y: integer;
    c: RGBA;
  begin
    for x := 0 to 31 do begin
      for y := 0 to 31 do begin
        if (random > p) then continue;
        page.setPixel(x,y+depth*32,RGBA.Clear);
      end;
    end;
  end;

begin
  page := voxelCell.vox;
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
      dc.fillRect(Rect(0,31*32,32,32), MDR_DARKGRAY);
      //stone layer
      dc.fillRect(Rect(0,30*32,32,32), MDR_LIGHTGRAY);
      dc.asBlendMode(bmBlend).asTint(RGB(255,255,255,128)).drawImage(noise, Point(0,30*32));
      decimateLayer(30, 0.1);
    end;
    ftDirt: begin
      dc.fillRect(Rect(0,30*32,32,32), MDR_LIGHTGRAY);
      dc.asBlendMode(bmBlend).asTint(RGB(255,255,255,128)).drawImage(noise, Point(0,30*32));
    end;
  end;
  {trim}
  dc.fillRect(Rect(0,0+29*32,32,32), MDR_LIGHTGRAY);
  dc.fillRect(Rect(1,1+29*32,30,30), RGBA.Clear);

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
    or  eax, $fc000000  //255-2 = 2 units (for empty cells)
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
  noise := tPage.Create(32,32);
  for y := 0 to 31 do
    for x := 0 to 31 do begin
      c := rnd div 2 + 64;
      noise.setPixel(x,y, RGB(c,c,c));
    end;

  tile.floor := ftDirt;

  composeVoxelCell(tile, walls);
  backgroundCol := RGBA.Lerp(MDR_LIGHTGRAY, RGBA.Black, 0.5);
end;

destructor tDungeonViewGui.destroy();
begin
  voxelCell.free;
  noise.free;
  inherited destroy;
end;

begin
end.
