unit terra;

interface

uses
  test, debug,
  utils,
  graph32, screen;

type
  tTerrain = class
    {todo: implement cell system, 0=empty, 1=mixed, 2=full}
  public
    terrain: tPage;
  public
    constructor create();
    destructor destroy(); override;
    function isSolid(x,y: integer): boolean;
    procedure generate();
    procedure draw(screen: tScreen);
  end;

var
  terrain: tTerrain;

implementation

const
  TC_DIRT: RGBA = (b:$44; g:$80; r:$8d; a: $ff);

{-----------------------------------------------------------}

constructor tTerrain.create();
begin
  inherited create();
  terrain := tPage.create(256, 256);
end;

destructor tTerrain.destroy();
begin
  terrain.free();
  inherited destroy();
end;

function tTerrain.isSolid(x,y: integer): boolean;
begin
  x -= 32;
  if y > 240 then exit(true);
  if (x < 0) or (x > 255) or (y < 0) then exit(false);
  result := terrain.getPixel(x, y).a > 0;
end;

procedure tTerrain.generate();
var
  mapHeight: array[0..255] of integer;
  x,y: integer;
  c: RGBA;
begin
  terrain.clear(RGB(0, 0, 0, 0));
  for x := 0 to 255 do
    mapHeight[x] := 128 + round(30*sin(3+x*0.0197) - 67*cos(2+x*0.003) + 15*sin(1+x*0.023));
  for y := 0 to 255 do
    for x := 0 to 255 do begin
      c.init(TC_DIRT.r + (rnd-128) div 8, TC_DIRT.g, TC_DIRT.b);
      if y > mapHeight[x] then terrain.setPixel(x,y, c);
    end;
end;

procedure tTerrain.draw(screen: tScreen);
var
  c: RGBA;
  x,y: integer;
  srcPtr, dstPtr: pointer;
begin
  for y := 0 to 240-1 do begin
    srcPtr := terrain.pixels + (y * 256 * 4);
    dstPtr := screen.canvas.pixels + ((32 + (y*screen.canvas.width)) * 4);
    asm
      pushad
      mov esi, srcPtr
      mov edi, dstPtr
      mov ecx, 255
    @XLOOP:
      mov eax, dword ptr [esi]
      test al, al
      jz @SKIP
      mov dword ptr [edi], eax
    @SKIP:
      add esi, 4
      add edi, 4
      loop @XLOOP
      popad
    end;
  end;

end;

{-----------------------------------------------------------}

begin
end.
