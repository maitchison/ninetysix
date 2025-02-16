unit sprite;

{$MODE delphi}
{$Interfaces corba}

interface

uses
  test,
  debug,
  utils,
  sysTypes,
  vga,
  iniFile,
  graph2d,
  graph32,
  vertex;

type

  tBorder = record
    top, left, bottom, right: Integer;
    constructor init(aLeft, aTop, aRight, aBottom: Integer);
    procedure setDefault();
    function  isDefault: boolean;
    function toString(): string;
    procedure writeToIni(ini: tIniWriter; tag: string='Border');
    procedure readFromIni(ini: tIniReader; tag: string='Border');
  end;

  tSprite = class(tObject, iIniSerializable)

    tag: string;
    page: tPage;
    rect: tRect;
    border: tBorder;

    constructor create(aPage: tPage);
    destructor destroy(); override;

    function  width: int32;
    function  height: int32;

    function  clone(): tSprite;

    function  getPixel(atX, atY: integer): RGBA;
    procedure blit(dstPage: tPage; atX, atY: int32);
    procedure draw(dstPage: tPage; atX, atY: int32);
    procedure drawFlipped(dstPage: tPage; atX, atY: int32);
    procedure drawStretched(DstPage: TPage; dest: tRect);
    procedure drawTransformed(dstPage: tPage; pos: V3D;transform: tMatrix4x4);
    procedure nineSlice(DstPage: TPage; atX, atY: Integer; DrawWidth, DrawHeight: Integer);

    {iIniSerializable}
    procedure writeToIni(ini: tIniWriter);
    procedure readFromIni(ini: tIniReader);

  end;

  tSpriteSheet = class
  protected
    function getByTag(tag: string): tSprite;
    function getByIndex(idx: integer): tSprite;
  public
    page: tPage;
    sprites: array of tSprite;
  public
    constructor create(aPage: tPage);
    procedure append(sprite: tSprite);
    procedure load(filename: string);
    procedure grid(cellWidth, cellHeight: word);
    property items[tag: string]: tSprite read getByTag; default;
  end;

implementation

uses
  poly,
  keyboard, //stub
  filesystem;

{$i sprite_ref.inc}
{$i sprite_asm.inc}

{---------------------------------------------------------------------}

constructor tBorder.init(aLeft, aTop, aRight, aBottom: Integer);
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

constructor tSprite.Create(aPage: TPage);
begin
  inherited create();
  self.tag := 'sprite';
  self.page := aPage;
  self.rect := graph2d.Rect(aPage.width, aPage.height);
  self.border.init(0, 0, 0, 0);
end;

function TSprite.Width: int32;
begin
  result := self.rect.Width;
end;

function tSprite.Height: int32;
begin
  result := Self.rect.Height;
end;


{Draw sprite to screen at given location, with alpha etc}
procedure tSprite.draw(dstPage: tPage; atX, atY: integer);
begin
  draw_REF(dstPage, self.page, self.rect, atX, atY)
end;

{Draws sprite flipped on x-axis}
procedure tSprite.drawFlipped(dstPage: tPage; atX, atY: integer);
begin
  {a bit inefficent, but ok for the moment}
  polyDraw_REF(dstPage, page, rect,
    Point(atX + rect.width - 1, atY),
    Point(atX, atY),
    Point(atX, atY + rect.height - 1),
    Point(atX + rect.width - 1, atY + rect.height - 1)
  );
end;

function tSprite.getPixel(atX, atY: integer): RGBA;
begin
  fillchar(result, sizeof(result), 0);
  if (atX < 0) or (atY < 0) or (atX >= rect.width) or (atY >= rect.height) then exit;
  result := page.getPixel(atX+rect.x, atY+rect.y);
end;

{Copy sprite to screen at given location, no alpha blending}
procedure tSprite.blit(dstPage: tPage; atX, atY: Integer);
begin
  blit_ASM(dstPage, self.page, self.rect, atX, atY);
end;

{Draws sprite stetched to cover destination rect}
procedure tSprite.drawStretched(dstPage: tPage; dest: tRect);
begin
  stretchDraw_ASM(dstPage, Self.page, Self.rect, dest);
end;

{identity transform will the centered on sprite center...
 todo: implement a default anchor}
procedure tSprite.drawTransformed(dstPage: tPage; pos: V3D;transform: tMatrix4x4);
var
  p1,p2,p3,p4: tPoint;

  function xform(delta: tPoint): tPoint;
  var
    v: V3D;
  begin
    v := V3(delta.x, delta.y, 0) - V3(rect.width / 2, rect.height / 2, 0);
    v := transform.apply(v) + pos;
    // no perspective for the moment}
    result.x := round(v.x);
    result.y := round(v.y);
  end;

begin
  polyDraw_ASM(dstPage, page, rect,
    xform(Point(0,0)),
    xform(Point(rect.width-1, 0)),
    xform(Point(rect.width, rect.height-1)),
    xform(Point(0, rect.height-1))
  );
end;

{Draw sprite using nine-slice method}
procedure tSprite.NineSlice(DstPage: TPage; atX, atY: Integer; DrawWidth, DrawHeight: Integer);
var
  oldRect: tRect;
  drawRect: tRect;
begin

  if not assigned(self) then
    fatal('Tried drawing unassigned sprite');

  oldRect := self.rect;

  drawRect := graph2d.Rect(atX, atY, DrawWidth, DrawHeight);

  {top part}
  rect := tRect.Inset(oldRect, 0, 0, Border.Left, Border.Top);
  self.draw(DstPage, atX, atY);

  self.rect := tRect.Inset(oldRect,Border.Left, 0, -Border.Right, Border.Top);
  self.drawStretched(DstPage, TRect.Inset(DrawRect, Border.Left, 0, -Border.Right, Border.Top));

  self.rect := tRect.Inset(oldRect,-Border.Right, 0, 0, Border.Top);
  self.draw(DstPage, atX+DrawWidth-Border.Right, atY);

  {middle part}
  self.rect := tRect.Inset(oldRect, 0, Border.Top, Border.Left, -Border.Bottom);
  self.drawStretched(DstPage, TRect.Inset(DrawRect, 0, Border.Top, Border.Left, -Border.Bottom));

  self.rect := tRect.Inset(oldRect, Border.Left, Border.Top, -Border.Right, -Border.Bottom);
  self.drawStretched(DstPage, TRect.Inset(DrawRect, Border.Left, Border.Top, -Border.Right, -Border.Bottom));

  self.rect := tRect.Inset(oldRect,-Border.Right, Border.Top, 0, -Border.Bottom);
  self.drawStretched(DstPage, TRect.Inset(DrawRect,-Border.Right, Border.Top, 0, -Border.Bottom));

  {bottom part}

  self.rect := tRect.Inset(oldRect,0, -Border.Bottom, Border.Left, 0);
  self.draw(DstPage, atX, atY+DrawHeight-Border.Bottom);

  self.rect := tRect.Inset(oldRect,Border.Left, -Border.Bottom, -Border.Right, 0);
  self.drawStretched(DstPage, TRect.Inset(DrawRect,Border.Left, -Border.Bottom, -Border.Right, 0));

  rect := tRect.Inset(oldRect,-Border.Right, -Border.Bottom, 0, 0);
  draw(DstPage, atX+DrawWidth-Border.Right, atY+DrawHeight-Border.Bottom);

  self.rect := oldRect;

end;

{create a shallow copy of the sprite}
function tSprite.clone(): tSprite;
begin
  result := tSprite.create(self.page);
  result.tag := self.tag;
  result.rect := self.rect;
  result.border := self.border;
end;

destructor tSprite.destroy();
begin
  self.tag := '';
  self.page := nil;
  inherited destroy();
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

constructor tSpriteSheet.create(aPage: tPage);
begin
  setLength(sprites, 0);
  page := aPage;
end;

procedure tSpriteSheet.append(sprite: tSprite);
begin
  sprite.page := self.page;
  setLength(sprites, length(sprites)+1);
  sprites[length(sprites)-1] := sprite;
end;

procedure tSpriteSheet.load(filename: string);
var
  reader: tIniReader;
  sprite: tSprite;
begin
  reader := tIniReader.create(filename);
  while not reader.eof do begin
    sprite := tSprite.create(page);
    sprite.readFromIni(reader);
    append(sprite);
  end;
  reader.free();
  note(' - loaded sprite sheet "%s" with %d sprites.', [filename, length(sprites)]);
end;

{create sprites using a grid}
procedure tSpriteSheet.grid(cellWidth,cellHeight: word);
var
  sprite: tSprite;
  x, y: integer;
begin
  for y := 0 to (page.height div cellHeight)-1 do begin
    for x := 0 to (page.width div cellWidth)-1 do begin
      sprite := tSprite.create(page);
      sprite.rect := Rect(x*cellWidth, y*cellHeight, cellWidth, cellHeight);
      append(sprite);
    end;
  end;
end;

{---------------}

function tSpriteSheet.getByTag(tag: string): tSprite;
var
  sprite: tSprite;
begin
  {linear scan for moment}
  for sprite in sprites do
    if assigned(sprite) and (sprite.tag = tag) then exit(sprite);
  fatal('Sprite sheet contains no sprite named "'+tag+'"');
end;

function tSpriteSheet.getByIndex(idx: integer): tSprite;
begin
  result := sprites[idx];
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
  sprite1.border.init(2,3,4,1);

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

  {todo: tests for draw/blit/stretch}

end;

initialization
  tSpriteTest.create('Sprite');
end.
