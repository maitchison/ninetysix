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
    function  isEmpty(x,y: integer): boolean;
    function  isSolid(x,y: integer): boolean;
    procedure burn(atX,atY: integer;r: integer;power:integer=255);
    procedure generate();
    procedure draw(screen: tScreen);
  end;

var
  terrain: tTerrain;

implementation

const
  TC_DIRT: RGBA =  (b:$44; g:$80; r:$8d; a: $20);
  TC_ROCK: RGBA =  (b:$44; g:$44; r:$44; a: $ff);
  TC_GRASS: RGBA = (b:$5d; g:$80; r:$0d; a: $0f);
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
  if y > 255 then exit(true);
  if (x < 0) or (x > 255) or (y < 0) then exit(false);
  result := terrain.getPixel(x, y).a > $07;
end;

function tTerrain.isEmpty(x,y: integer): boolean;
begin
  if (x < 0) or (x > 255) or (y < 0) or (y > 255) then exit(true);
  result := terrain.getPixel(x, y).a = 0;
end;

{removes terrain in given radius, and burns edges}
procedure tTerrain.burn(atX,atY: integer;r: integer;power:integer=255);
var
  dx, dy: integer;
  x,y: integer;
  v: integer;
  dst2: integer;
  r2: integer;
  emptyC, burntC: RGBA;
  tc: RGBA;
  dimFactor: integer;
begin
  if power <= 0 then exit;
  if r <= 0 then exit;
  r2 := r*r;
  for dy := -r to +r do begin
    for dx := -r to +r do begin
      dst2 := (dx*dx)+(dy*dy);
      x := atX+dx;
      y := atY+dy;
      if (dst2 > r2) then continue;
      if isEmpty(x, y) then continue;
      v := round((1-(dst2/r2)) * power);
      tc := terrain.getPixel(x, y);
      dimFactor := round(50 * v / (tc.a+1));
      tc.a := clamp(tc.a - v, 0, 255);

      tc.r := clamp(tc.r - dimFactor, 0, 255);
      tc.g := clamp(tc.g - dimFactor, 0, 255);
      tc.b := clamp(tc.b - dimFactor, 0, 255);
      terrain.setPixel(x, y, tc);
    end;
  end;
end;

procedure tTerrain.generate();
var
  dirtHeight: array[0..255] of integer;
  rockHeight: array[0..255] of integer;
  x,y: integer;
  c: RGBA;
  v: single;
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
      else if y > dirtHeight[x]-1 then
        c := RGB(TC_DIRT.r-10, TC_DIRT.g-10, TC_DIRT.b-10, TC_DIRT.a-10)
      else
        continue;
      v := 0.9+(0.1*(rnd/255));
      c.r := round(c.r * v);
      c.g := round(c.g * v);
      c.b := round(c.r * v);
      c.a := round(c.a * v);
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
      bswap eax
      test al, al
      jz @SKIP
      bswap eax
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
