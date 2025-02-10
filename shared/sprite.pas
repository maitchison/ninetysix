unit sprite;

{$MODE delphi}

interface

uses
  test,
  debug,
  utils,
  sysTypes,
  vga,
  iniFile,
  graph2d,
  graph32;

type

  tBorder = record
    top, left, bottom, right: Integer;
    constructor create(aLeft, aTop, aRight, aBottom: Integer);
    procedure setDefault();
    function  isDefault: boolean;
    function toString(): string;
    procedure writeToIni(ini: tIniWriter; tag: string='Border');
    procedure readFromIni(ini: tIniReader; tag: string='Border');
  end;

  tSprite = class(iIniSerializable)

    tag: string;
    page: tPage;
    rect: tRect;
    border: tBorder;

    constructor create(aPage: tPage);

    function width: int32;
    function height: int32;

    function clone(): tSprite;

    procedure blit(dstPage: tPage; atX, atY: int32);
    procedure draw(dstPage: tPage; atX, atY: int32);
    procedure drawStretched(DstPage: TPage; dest: TRect);
    procedure nineSlice(DstPage: TPage; atX, atY: Integer; DrawWidth, DrawHeight: Integer);

    {iIniSerializable}
    procedure writeToIni(ini: tIniWriter);
    procedure readFromIni(ini: tIniReader);

  end;

implementation

{-------------------------------------------------------------}

{draw an image segment, stretched}
procedure stretchBlit_REF(DstPage, SrcPage: TPage; Src,Dst: TRect);
var
  x, y: integer;
  u, v: single;
  c: RGBA;
begin
  {todo: switch to having a source rect}
  for y := Dst.Top to Dst.Bottom-1 do begin
    for x := Dst.Left to Dst.Right-1 do begin
      u := (x - Dst.Left) / Dst.Width;
      v := (y - Dst.Top) / Dst.Height;
      c := SrcPage.GetPixel(Src.x+u*Src.Width, Src.y+v*Src.Height);
      DstPage.PutPixel(x, y, c);
    end;
  end;
end;

{draw an image segment to screen}
procedure blit_REF(dstPage, srcPage: TPage; srcRect: tRect; atX,atY: int16);
var
  x,y: int32;
  xMin,xMax,yMin,yMax: int32;
begin
  xMin := max(0, -atX);
  yMin := max(0, -atY);
  xMax := min(videoDriver.width-atX, srcRect.width);
  yMax := min(videoDriver.height-atY, srcRect.height);

  for y := yMin to yMax-1 do
    for x := xMin to xMax-1 do
      dstPage.putPixel(atX+x, atY+y, srcPage.getPixel(x+srcRect.x, y+srcRect.y));
end;

{draw an image segment to screen, no alpha}
procedure blit_ASM(dstPage, srcPage: TPage; srcRect: tRect; atX,atY: int16);
var
  srcOfs: dword;
  dstOfs: dword;
  y, y1, y2: int32;
  x1,x2: int32;
  bytesToCopy: word;
  topCrop,leftCrop: int32;
begin

  y1 := max(atY, 0);
  y2 := min(atY+srcRect.height, dstPage.height-1);
  topCrop := y1-atY;

  x1 := max(atX, 0);
  x2 := min(atX+srcRect.width, dstPage.width-1);
  leftCrop := x1-atX;

  {might be off by one here}
  if y2 < y1 then exit;
  if x2 < x1 then exit;

  {todo adjust when cropping y on top}
  srcOfs := 4 * ((srcRect.x + leftCrop) + (srcRect.y+topCrop)*srcPage.width);
  dstOfs := 4 * (x1 + y1*dstPage.width);

  bytesToCopy := 4 * (x2-x1);

  for y := y1 to y2 do begin
    move((srcPage.pixels+srcOfs)^, (dstPage.pixels+dstOfs)^, bytesToCopy);
    srcOfs += srcPage.width * 4;
    dstOfs += dstPage.width * 4;
  end;
end;


{draw an image segment, stretched}
procedure stretchBlit_ASM(dstPage, srcPage: TPage; Src, Dst: TRect);
var
  deltaX, deltaY: uint32;
  x,y: uint32;
  v: single;
  sx, sy: uint32;
  screenOfs: uint32;
  imageOfs: uint32;
  cnt: uint16;
  dstPixels: pointer;

  sx1,sx2,dx1,dx2,sy1,sy2,dy1,dy2: integer;

begin
  {todo: implement proper clipping}
  if (src.height <= 0) or (src.width <= 0) then
    error('Tried drawing sprite with invalid bounds: '+ShortString(src));

  if (dst.height <= 0) or (dst.width <= 0) then exit;

  {Mapping from new parameters to the legacy ones,
   avoids having to rewrite the code}
  sx1 := Src.left;
  sy1 := Src.top;
  sx2 := Src.right;
  sy2 := Src.bottom;

  dx1 := Dst.left;
  dy1 := Dst.top;
  dx2 := Dst.right;
  dy2 := Dst.bottom;

  {for debugging...}
  {Info(ShortString(src)+' '+ShortString(dst));}

  {todo: maybe only support power of 2 images...}
  {todo: linear interpolation with MMX, if we can...}
  {todo: support transpariency}
  deltaX := trunc(65536.0 * (sx2-sx1) / (dx2-dx1));
  deltaY := round(65536.0 * (sy2-sy1) / (dy2-dy1));
  sx := sx1 * 65536;
  sy := sy1 * 65536;

  cnt := (dx2 - dx1);
  if cnt <= 0 then exit;

  dstPixels := dstPage.Pixels;

  for y := dy1 to dy2-1 do begin
    if y > videoDriver.height then exit;
    v := (y - dy1) / (dy2 - dy1);
    screenOfs := y * videoDriver.width + dx1;
    imageOfs := sy1 + round((sy2-sy1) * v);
    imageOfs *= srcPage.width * 4;
    imageOfs += dword(srcPage.Pixels);
    asm
      pusha

      mov edi, screenOfs
      shl edi, 2
      add edi, dstPixels

      movzx ecx, cnt

      mov edx, sx

    @LOOP:

      mov esi, edx
      shr esi, 16
      shl esi, 2
      add esi, imageOfs

      mov eax, ds:[esi]
      mov bl, ds:[esi+3]

      cmp bl, 0
      je @Skip
      cmp bl, 255
      je @Blit

    @Blend:

      push edx

      xor edx, edx
      mov bh, 255
      sub bh, bl

      {note: switch to MMX later}
      mov al, byte ptr ds:[esi+2]
      mul bl
      mov dl, ah
      mov al, byte ptr [edi+2]
      mul bh
      add dl, ah
      shl edx, 8

      mov al, byte ptr ds:[esi+1]
      mul bl
      mov dl, ah
      mov al, byte ptr [edi+1]
      mul bh
      add dl, ah
      shl edx, 8

      mov al, byte ptr ds:[esi+0]
      mul bl
      mov dl, ah
      mov al, byte ptr [edi+0]
      mul bh
      add dl, ah

      mov eax, edx

      pop edx


    @Blit:

      mov dword ptr [edi], eax

    @Skip:

      add edi, 4

      add edx, deltaX

      dec ecx
      jnz @LOOP

      popa
    end;
  end;

end;


{---------------------------------------------------------------------}

constructor tBorder.create(aLeft, aTop, aRight, aBottom: Integer);
begin
  self.left := aLeft;
  self.top := aTop;
  self.right := aRight;
  self.bottom := aBottom;
end;

function tBorder.isDefault: boolean;
begin
  result := (left=0) and (right=0) and (top=0) and (bottom=0);
end;

procedure tBorder.setDefault();
begin
  left := 0; right := 0; top := 0; bottom := 0;
end;

function tBorder.toString(): string;
begin
  result := format('(%d %d %d %d)', [left, top, right, bottom]);
end;

procedure tBorder.writeToIni(ini: tIniWriter; tag: string='Border');
begin
  ini.writeArray(tag, [left, top, right, bottom]);
end;

procedure tBorder.readFromIni(ini: tIniReader; tag: string='Border');
var
  data: tInt32Array;
begin
  data := ini.readIntArray(tag);
  left := data[0];
  top := data[1];
  right := data[2];
  bottom := data[3];
end;

{---------------------------------------------------------------------}

constructor tSprite.Create(APage: TPage);
begin
  self.Tag := 'sprite';
  self.Page := APage;
  self.Rect.Create(0, 0, APage.Width, APage.Height);
  self.Border.Create(0, 0, 0, 0);
end;

function TSprite.Width: int32;
begin
  result := self.Rect.Width;
end;

function tSprite.Height: int32;
begin
  result := Self.Rect.Height;
end;


{Draw sprite to screen at given location, with alpha etc}
procedure tSprite.draw(dstPage: tPage; atX, atY: Integer);
begin
  blit_REF(dstPage, self.page, self.rect, atX, atY);
end;

{Copy sprite to screen at given location, no alpha blending}
procedure tSprite.blit(dstPage: tPage; atX, atY: Integer);
begin
  blit_ASM(dstPage, self.page, self.rect, atX, atY);
end;

{Draws sprite stetched to cover destination rect}
procedure tSprite.DrawStretched(DstPage: TPage; dest: TRect);
begin
  stretchBlit_ASM(DstPage, Self.Page, Self.Rect, dest);
end;

{Draw sprite using nine-slice method}
procedure tSprite.NineSlice(DstPage: TPage; atX, atY: Integer; DrawWidth, DrawHeight: Integer);
var
  Sprite: TSprite;
  DrawRect: TRect;
begin

  if not assigned(self) then
    error('Tried drawing unassigned sprite');

  sprite := self.clone();

  DrawRect := TRect.Create(atX, atY, DrawWidth, DrawHeight);

  {top part}

  Sprite.Rect := TRect.Inset(Self.Rect,
    0, 0, Border.Left, Border.Top
  );
  Sprite.Draw(DstPage, atX, atY);


  Sprite.Rect := TRect.Inset(Self.Rect,
    Border.Left, 0, -Border.Right, Border.Top
  );
  Sprite.DrawStretched(DstPage, TRect.Inset(DrawRect,
    Border.Left, 0, -Border.Right, Border.Top
  ));


  Sprite.Rect := TRect.Inset(Self.Rect,
    -Border.Right, 0, 0, Border.Top
  );
  Sprite.Draw(DstPage, atX+DrawWidth-Border.Right, atY);

  {middle part}

  Sprite.Rect := TRect.Inset(Self.Rect,
    0, Border.Top, Border.Left, -Border.Bottom
  );
  Sprite.DrawStretched(DstPage, TRect.Inset(DrawRect,
    0, Border.Top, Border.Left, -Border.Bottom
  ));

  Sprite.Rect := TRect.Inset(Self.Rect,
    Border.Left, Border.Top, -Border.Right, -Border.Bottom
  );
  Sprite.DrawStretched(DstPage, TRect.Inset(DrawRect,
    Border.Left, Border.Top, -Border.Right, -Border.Bottom
  ));


  Sprite.Rect := TRect.Inset(Self.Rect,
    -Border.Right, Border.Top, 0, -Border.Bottom
  );
  Sprite.DrawStretched(DstPage, TRect.Inset(DrawRect,
    -Border.Right, Border.Top, 0, -Border.Bottom
  ));

  {bottom part}

  Sprite.Rect := TRect.Inset(Self.Rect,
    0, -Border.Bottom, Border.Left, 0
  );
  Sprite.Draw(DstPage, atX, atY+DrawHeight-Border.Bottom);


  Sprite.Rect := TRect.Inset(Self.Rect,
    Border.Left, -Border.Bottom, -Border.Right, 0
  );
  Sprite.DrawStretched(DstPage, TRect.Inset(DrawRect,
    Border.Left, -Border.Bottom, -Border.Right, 0
  ));


  Sprite.Rect := TRect.Inset(Self.Rect,
    -Border.Right, -Border.Bottom, 0, 0
  );
  Sprite.Draw(DstPage, atX+DrawWidth-Border.Right, atY+DrawHeight-Border.Bottom);


end;

{create a shallow copy of the sprite}
function tSprite.clone(): tSprite;
begin
  result := tSprite.create(self.page);
  result.rect := self.rect;
  result.border := self.border;
end;

{---------------------}

procedure tSprite.writeToIni(ini: tIniWriter);
begin
  ini.writeString('Tag', tag);
  ini.writeRect('Rect', rect);
  // todo: support skipping default values
  //if not border.isDefault then
  border.writeToIni(ini);
end;

procedure tSprite.readFromIni(ini: tIniReader);
begin
  tag := ini.readString('Tag');
  rect := ini.readRect('Rect');
  if ini.peekKey.toLower = 'border' then
    border.readFromIni(ini)
  else
    border.setDefault();
end;


{-----------------------------------------------------}

type
  tSpriteTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tSpriteTest.run();
var
  sprite1, sprite2: tSprite;
  iniWriter: tIniWriter;
  iniReader: tIniReader;
  page: tPage;
begin
  page := tPage.create(64,64);
  sprite1 := tSprite.create(page);
  sprite1.tag := 'Fish';
  sprite1.rect := Rect(8,12,30,34);
  sprite1.border := tBorder.create(2,3,4,1);

  iniWriter := tIniWriter.create('test.ini');
  iniWriter.writeObject('Sprite', sprite1);
  iniWriter.free();

  sprite2 := tSprite.create(page);
  iniReader := tIniReader.create('test.ini');
  sprite2.readFromINI(iniReader);
  iniReader.free();

  assertEqual(sprite2.tag, sprite1.tag);
  assertEqual(sprite2.rect.toString, sprite1.rect.toString);
  assertEqual(sprite2.border.toString, sprite1.border.toString);

  fs.delFile('test.ini');

  sprite1.free;
  sprite2.free;
  page.free;

end;

initialization
  tSpriteTest.create('Sprite');
end.
