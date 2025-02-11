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
    function  isSolid(x,y: integer): boolean;
    procedure burn(atX,atY: integer;r: integer);
    procedure generate();
    procedure draw(screen: tScreen);
  end;

var
  terrain: tTerrain;

implementation

const
  TC_DIRT: RGBA =  (b:$44; g:$80; r:$8d; a: $ff);
  TC_ROCK: RGBA =  (b:$44; g:$44; r:$44; a: $ff);
  TC_GRASS: RGBA = (b:$5d; g:$80; r:$0d; a: $ff);
  TC_SKY: RGBA =   (b:$00; g:$00; r:$00; a: $00);

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
  if y > 240 then exit(true);
  if (x < 0) or (x > 255) or (y < 0) then exit(false);
  result := terrain.getPixel(x, y).a > 0;
end;

{removes terrain in given radius, and burns edges}
procedure tTerrain.burn(atX,atY: integer;r: integer);
var
  dx, dy: integer;
  x,y: integer;
  dst2: integer;
  r2: integer;
  rExtended: integer;
  rEdge2: integer;
  emptyC, burntC: RGBA;
begin
  emptyC := RGB(0,0,0,0);
  burntC := RGB(50,0,0,128);

  r2 := r*r;
  rExtended := r+1;
  rEdge2 := rExtended*rExtended;
  for dy := -rExtended to +rExtended do begin
    for dx := -rExtended to +rExtended do begin
      dst2 := (dx*dx)+(dy*dy);
      x := atX+dx;
      y := atY+dy;
      if (dst2 <= r2) then
        terrain.setPixel(x, y, emptyC)
      else if (dst2 <= rEdge2) then
        if isSolid(x, y) then terrain.putPixel(x, y, burntC);
    end;
  end;
end;

procedure tTerrain.generate();
var
  dirtHeight: array[0..255] of integer;
  rockHeight: array[0..255] of integer;
  x,y: integer;
  c: RGBA;
begin
  terrain.clear(RGB(0, 0, 0, 0));

  for x := 0 to 255 do begin
    dirtHeight[x] := 128 + round(30*sin(3+x*0.0197) - 67*cos(2+x*0.003) + 15*sin(1+x*0.023));
    rockHeight[x] := 200 + round(30*sin(30+x*0.0197) - 67*cos(20+x*0.003) + 15*sin(10+x*0.023)) div 4;
  end;

  for y := 0 to 255 do
    for x := 0 to 255 do begin

      if y > rockHeight[x] then
        c := TC_ROCK
      else if y > dirtHeight[x] then
        c := TC_DIRT
      else
        continue;

      c *= 0.9+(0.1*(rnd/255));
      terrain.setPixel(x, y, c);

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
