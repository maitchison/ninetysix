{A simple retained mode gui}
unit uGui;

interface

uses
  debug,
  test,
  font,
  utils,
  uMouse,
  uInput,
  sound,
  mixLib,
  sysTypes,
  uColor,
  graph2d,
  graph32,
  keyboard,
  uScreen;

const
  ON_MOUSE_CLICK = 'mouseclick';
  ON_MOUSE_DOWN = 'mousedown';
  ON_KEYPRESS = 'keypress';

type

  tTextStyle = record
    font: tFont;
    col: RGBA;
    shadow: boolean;
    centered: boolean;
    procedure setDefault();
  end;

  tGuiState = (gsNormal, gsDisabled, gsHover, gsPressed, gsSelected);

  tGuiComponent = class;
  tGui = class;

  tHookProc = procedure(sender: tGuiComponent; msg: string; args: array of const);

  tGuiComponent = class
  protected
    gui: tGui;
    bounds: tRect;
    visible: boolean;
    enabled: boolean;
    pressed: boolean;
    autoStyle: boolean; {if true will autostyle the component based on state}
    {standard label like draw}
    fText: string;
    fTextStyle: tTextStyle;
    fCol: RGBA;
    fHookKey: tStrings;
    fHookProc: array of tHookProc;
    mouseOverThisFrame, mouseOverLastFrame: boolean;
  protected
    procedure doDraw(screen: tScreen); virtual;
    procedure doUpdate(elapsed: single); virtual;
    procedure setText(aText: string); virtual;
    procedure fireMessage(aMsg: string; args: array of const); overload;
    procedure fireMessage(aMsg: string); overload;
  public
    constructor Create();
    procedure draw(screen: tScreen);
    procedure update(elapsed: single);
    function  state: tGuiState;
    procedure addHook(aMsg: string; aProc: tHookProc);
  public
    procedure onKeyPress(code: word); virtual;
  public
    property x: integer read bounds.pos.x write bounds.pos.x;
    property y: integer read bounds.pos.y write bounds.pos.y;
    property width: integer read bounds.width write bounds.width;
    property height: integer read bounds.height write bounds.height;
    property font: tFont read fTextStyle.font write fTextStyle.font;
    property text: string read fText write setText;
    property textStyle: tTextStyle read fTextStyle write fTextStyle;
    property col: RGBA read fCol write fCol;
  end;

  tGuiComponents = class
    elements: array of tGuiComponent;
    procedure append(x: tGuiComponent); virtual;
    procedure draw(screen: tScreen); virtual;
    procedure update(elapsed: single); virtual;
  end;

  tGui = class(tGuiComponents)
    procedure append(x: tGuiComponent); override;
    procedure update(elapsed: single); override;
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

const
  DEFAULT_MOUSEDOWN_SFX: tSoundEffect = nil;
  DEFAULT_MOUSECLICK_SFX: tSoundEffect = nil;

implementation

procedure playSFX(sfx: tSoundEffect);
begin
  if assigned(sfx) then mixer.play(sfx);
end;

{--------------------------------------------------------}

procedure tTextStyle.setDefault();
begin
  col := RGB(255,255,255);
  font := DEFAULT_FONT;
  shadow := false;
  centered := false;
end;

{--------------------------------------------------------}

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
    for gc in elements do begin
      gc.fireMessage(ON_KEYPRESS, [code]);
      gc.onKeyPress(code);
    end;
  end;

  for gc in elements do gc.update(elapsed);
end;

{--------------------------------------------------------}

procedure tGui.append(x: tGuiComponent);
begin
  inherited append(x);
  x.gui := self;
end;

procedure tGui.update(elapsed: single);
begin
  inherited update(elapsed);
end;

{--------------------------------------------------------}

procedure tGuiComponent.fireMessage(aMsg: string; args: array of const);
var
  i: integer;
begin
  aMsg := aMsg.toLower();
  for i := 0 to length(fHookKey)-1 do begin
    if fHookKey[i] = aMsg then fHookProc[i](self, aMsg, args);
  end;
end;

procedure tGuiComponent.fireMessage(aMsg: string);
begin
  fireMessage(aMsg, []);
end;

procedure tGuiComponent.addHook(aMsg: string; aProc: tHookProc);
begin
  fHookKey.append(aMsg);
  setLength(fHookProc, length(fHookProc)+1);
  fHookProc[length(fHookProc)-1] := aProc;
end;

function tGuiComponent.state: tGuiState;
begin
  if not enabled then exit(gsDisabled);
  if pressed then exit(gsPressed);
  if mouseOverThisFrame then exit(gsHover);
  exit(gsNormal);
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
  backCol, frameCol: RGBA;
begin
  backCol := col;
  frameCol := RGB(0,0,0,backCol.a div 2);
  if autoStyle then begin
    case state of
      gsNormal: ;
      gsDisabled: backCol := RGBA.Lerp(backCol, RGBA.Black, 0.5);
      gsHover: backCol := RGBA.Lerp(backCol, RGB(255,255,0), 0.33);
      gsPressed: backCol := RGBA.Lerp(backCol, RGB(128,128,255), 0.33);
    end;
  end;

  screen.canvas.dc.fillRect(bounds, backCol);
  screen.canvas.dc.drawRect(bounds, frameCol);

  if textStyle.centered then begin
    textRect := font.textExtents(text);
    drawX := x+((width - textRect.width) div 2);
    drawY := y+((height - textRect.height) div 2)-1;
  end else begin
    drawX := x+2;
    drawY := y;
  end;

  if pressed then begin
    inc(drawX);
    inc(drawY);
  end;

  if textStyle.shadow then
    font.textOut(screen.canvas, drawX+1, drawY+1, text, RGB(0,0,0,textStyle.col.a*3 div 4));
  font.textOut(screen.canvas, drawX, drawY, text, textStyle.col);

  screen.markRegion(bounds);
end;

procedure tGuiComponent.draw(screen: tScreen);
begin
  if not visible then exit;
  doDraw(screen);
end;

procedure tGuiComponent.update(elapsed: single);
begin
  mouseOverLastFrame := mouseOverThisFrame;
  mouseOverThisFrame := false;
  if not enabled then exit;
  mouseOverThisFrame := bounds.isInside(input.mouseX, input.mouseY);

  {handle pressed logic}
  if mouseOverThisFrame then begin
    if input.mousePressed then begin
      fireMessage(ON_MOUSE_DOWN);
      playSFX(DEFAULT_MOUSEDOWN_SFX);
      pressed := true;
    end;
  end else
    pressed := false;

  if pressed and not input.mouseLB then begin
    playSFX(DEFAULT_MOUSECLICK_SFX);
    fireMessage(ON_MOUSE_CLICK);
    pressed := false;
  end;

  doUpdate(elapsed);
end;

procedure tGuiComponent.onKeyPress(code: word);
begin
  // nothing
end;

procedure tGuiComponent.setText(aText: string);
begin
  // todo: set dirty
  fText := aText;
end;

{-----------------------}

constructor tGuiLabel.Create(aPos: tPoint; aText: string='');
begin
  inherited create();
  bounds.x := aPos.x;
  bounds.y := aPos.y;
  fTextStyle.centered := false;
  fTextStyle.shadow := false;
  fTextStyle.col := RGB(250, 250, 250);
  col := RGBA.Clear;
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
  bounds.x := aPos.x;
  bounds.y := aPos.y;
  fTextStyle.centered := true;
  fTextStyle.shadow := true;
  fTextStyle.col := RGB(250, 250, 250);
  fText := aText;
  width := 100;
  height := 19;
  autoStyle := true;
end;

procedure tGuiButton.doDraw(screen: tScreen);
begin
  {todo: use a proper nine-slice background with clicking graphics}
  inherited doDraw(screen);
end;

begin
end.
