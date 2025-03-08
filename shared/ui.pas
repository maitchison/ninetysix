{A simple retained mode gui}
unit ui;

interface

uses
  debug,
  test,
  font,
  utils,
  graph2d,
  graph32,
  keyboard,
  uScreen;

type

  tTextStyle = record
    font: tFont;
    col: RGBA;
    shadow: boolean;
    centered: boolean;
    procedure setDefault();
  end;

  tGuiComponent = class
  protected
    bounds: tRect;
    visible: boolean;
    enabled: boolean;
    {standard label like draw}
    fText: string;
    fTextStyle: tTextStyle;
    fCol: RGBA;
  protected
    procedure doDraw(screen: tScreen); virtual;
    procedure doUpdate(elapsed: single); virtual;
    procedure setText(aText: string); virtual;
  public
    procedure onKeyPress(code: word); virtual;
    procedure draw(screen: tScreen);
    procedure update(elapsed: single);
    constructor create();
  public
    property x: integer read bounds.x write bounds.x;
    property y: integer read bounds.y write bounds.y;
    property width: integer read bounds.width write bounds.width;
    property height: integer read bounds.height write bounds.height;
    property font: tFont read fTextStyle.font write fTextStyle.font;
    property text: string read fText write setText;
    property textStyle: tTextStyle read fTextStyle write fTextStyle;
    property col: RGBA read fCol write fCol;
  end;

  tGuiComponents = class
    elements: array of tGuiComponent;
    procedure append(x: tGuiComponent);
    procedure draw(screen: tScreen);
    procedure update(elapsed: single);
  end;

  tGuiLabel = class(tGuiComponent)
  protected
    procedure setText(aText: string); override;
  public
    autoSize: boolean;
  public
    constructor Create(aPos: tPoint; aText: string='');
  end;

  tGuiButton = class(tGuiComponent)
  protected
    procedure doDraw(screen: tScreen); override;
  public
    constructor Create(aPos: tPoint; aText: string='');
  end;

implementation

{--------------------------------------------------------}

procedure tTextStyle.setDefault();
begin
  col := RGB(255,255,255);
  font := DEFAULT_FONT;
  shadow := false;
  centered := false;
end;

{--------------------------------------------------------}
{ tGuiComponents }

procedure tGuiComponents.append(x: tGuiComponent);
begin
  setLength(elements, length(elements)+1);
  elements[length(elements)-1] := x;
end;

procedure tGuiComponents.draw(screen: tScreen);
var
  gc: tGuiComponent;
begin
  for gc in elements do gc.draw(screen);
end;

procedure tGuiComponents.update(elapsed: single);
var
  gc: tGuiComponent;
  code: word;
begin

  {process keys, if any}
  while true do begin
    code := dosGetKey.code;
    if code = 0 then break;
    for gc in elements do gc.onKeyPress(code);
  end;

  for gc in elements do gc.update(elapsed);
end;

{--------------------------------------------------------}
{ UI Components }

constructor tGuiComponent.create();
begin
  inherited create();
  self.visible := true;
  self.enabled := true;
  self.bounds.init(0,0,0,0);
  text := '';
  textStyle.setDefault();
  col := RGB(128,128,128);
end;

procedure tGuiComponent.doUpdate(elapsed: single);
begin
  // pass
end;

procedure tGuiComponent.doDraw(screen: tScreen);
var
  drawX, drawY: integer;
  textRect: tRect;
begin
  if col.a > 0 then begin
    screen.canvas.fillRect(bounds, col);
    screen.canvas.drawRect(bounds, RGB(0,0,0,128));
  end;

  if textStyle.col.a > 0 then begin
    if textStyle.centered then begin
      textRect := font.textExtents(text);
      drawX := x+((width - textRect.width) div 2);
      drawY := y+((height - textRect.height) div 2)-1;
    end else begin
      drawX := x+2;
      drawY := y;
    end;
    if textStyle.shadow then
      font.textOut(screen.canvas, drawX+1, drawY+1, text, RGB(0,0,0,textStyle.col.a*3 div 4));
    font.textOut(screen.canvas, drawX, drawY, text, textStyle.col);
  end;

  screen.markRegion(bounds);
end;

procedure tGuiComponent.draw(screen: tScreen);
begin
  if not visible then exit;
  doDraw(screen);
end;

procedure tGuiComponent.update(elapsed: single);
begin
  if not enabled then exit;
  doUpdate(elapsed);
end;

procedure tGuiComponent.onKeyPress(code: word);
begin
  // do nothing;
end;

procedure tGuiComponent.setText(aText: string);
begin
  // todo: set dirty
  fText := aText;
end;

{-----------------------}

constructor tGuiLabel.create(aPos: tPoint; aText: string='');
begin
  inherited create();
  bounds.x := aPos.x;
  bounds.y := aPos.y;
  fTextStyle.centered := false;
  fTextStyle.shadow := false;
  fTextStyle.col := RGB(250, 250, 250);
  text := aText;
  autoSize := true;
end;

procedure tGuiLabel.setText(aText: string);
begin
  {todo: set dirty}
  inherited setText(aText);
  if autoSize then
    bounds := font.textExtents(text, bounds.topLeft);
end;

{-----------------------}

constructor tGuiButton.create(aPos: tPoint; aText: string='');
begin
  inherited create();
  self.bounds.x := aPos.x;
  self.bounds.y := aPos.y;
  self.fTextStyle.centered := true;
  self.fTextStyle.shadow := true;
  self.fTextStyle.col := RGB(250, 250, 250);
  self.fText := aText;
  self.width := 100;
  self.height := 18;
end;

procedure tGuiButton.doDraw(screen: tScreen);
begin
  {todo: use a proper nine-slice background with clicking graphics}
  inherited doDraw(screen);
end;

begin
end.
