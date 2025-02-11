unit terrain;

interface

uses
  test, debug,
  graph32, screen;

var
  terrain: array[0..255, 0..255] of byte;

procedure generateTerrain();
procedure drawTerrain(screen: tScreen);

implementation

procedure generateTerrain();
var
  mapHeight: array[0..255] of integer;
  x,y: integer;
begin
  fillchar(terrain, sizeof(terrain), 0);
  for x := 0 to 255 do
    mapHeight[x] := 128 + round(30*sin(3+x*0.0197) - 67*cos(2+x*0.003) + 15*sin(1+x*0.023));
  for y := 0 to 255 do
    for x := 0 to 255 do begin
      if y > mapHeight[x] then terrain[y,x] := 1;
    end;
end;

procedure drawTerrain(screen: tScreen);
var
  c: RGBA;
  x,y: integer;
  srcPtr, dstPtr: pointer;
begin
  c.from32($8d7044);
  for y := 0 to 240-1 do begin
    {
    for x := 0 to 255 do
      if terrain[y,x] <> 0 then screen.canvas.setPixel(32+x,y,c);
    }
    srcPtr := @terrain[y, 0];
    dstPtr := screen.canvas.pixels + ((32 + (y*screen.canvas.width)) * 4);
    asm
      pushad
      mov esi, srcPtr
      mov edi, dstPtr
      mov ecx, 255
      mov ebx, c
    @XLOOP:
      mov al, byte ptr [esi]
      test al, al
      jz @SKIP
      mov dword ptr [edi], ebx
    @SKIP:
      inc esi
      add edi, 4
      loop @XLOOP
      popad
    end;
  end;

end;



begin
end.
