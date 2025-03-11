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
  uMap,
  sound,
  mixLib,
  sysTypes,
  uColor,
  graph2d,
  graph32,
  keyboard,
  uStringMap,
  sprite,
  uScreen;

const
  ON_MOUSE_CLICK = 'mouseclick';
  ON_MOUSE_DOWN = 'mousedown';
  ON_KEYPRESS = 'keypress';

type

  tFontStyle = class
    font: tFont;
    col: RGBA;
    shadow: boolean;
    centered: boolean;
    constructor Create();
    function clone(): tFontStyle;
  end;

  tGuiStyle = class
    fontStyle: tFontStyle;
    {maps from state to value}
    sprites: tStringMap<tSprite>;
    {these are not implemented yet}
    //sounds: tStringMap<tSoundEffect>;
    constructor Create();
    destructor destroy; override;
    function clone(): tGuiStyle;
  end;

  tGuiSkin = class
    gfx: tGFXLibrary;
    sfx: tSFXLibrary;
    styles: tStringMap<tGuiStyle>;
    constructor Create();
    destructor destroy; override;
  end;

  tGuiState = (gsNormal, gsDisabled, gsHover, gsPressed, gsSelected);

  tGuiComponent = class;

  tHookProc = procedure(sender: tGuiComponent; msg: string; args: array of const);

  tGuiComponent = class
  protected
    style: tGuiStyle;
    bounds: tRect;
    visible: boolean;
    enabled: boolean;
    pressed: boolean;
    autoStyle: boolean; {if true will autostyle the component based on state}
    {standard label like draw}
    fText: string;
    fCol: RGBA;
    fHookKey: tStrings;
    fHookProc: array of tHookProc;
    mouseOverThisFrame, mouseOverLastFrame: boolean;
  protected
    procedure playSFX(sfxName: string);
    procedure doDraw(screen: tScreen); virtual;
    procedure doUpdate(elapsed: single); virtual;
    procedure setText(aText: string); virtual;
    procedure fireMessage(aMsg: string; args: array of const); overload;
    procedure fireMessage(aMsg: string); overload;
    {style}
    function  getSprite(): tSprite;
    function  getTextColor(): RGBA;
    function  getFontStyle(): tFontStyle;
    function  getFont(): tFont;
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
    property text: string read fText write setText;
    property col: RGBA read fCol write fCol;
    {style helpers}
    property fontStyle: tFontStyle read getFontStyle;
    property font: tFont read getFont;
    property textColor: RGBA read getTextColor;
    property sprite: tSprite read getSprite;
  end;

  tGuiComponents = class
    elements: array of tGuiComponent;
    procedure append(x: tGuiComponent); virtual;
    procedure draw(screen: tScreen); virtual;
    procedure update(elapsed: single); virtual;
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
  DEFAULT_GUI_SKIN: tGuiSkin = nil;
  GUI_STATE_NAME: array[tGuiState] of string = (
    'normal',
    'disabled',
    'hover',
    'pressed',
    'selected'
  );

implementation

{--------------------------------------------------------}

constructor tGuiSkin.Create();
begin
  inherited Create();
  styles := tStringMap<tGuiStyle>.Create();
  gfx := tGFXLibrary.Create(True);
  sfx := tSFXLibrary.Create(True);
end;

destructor tGuiSkin.destroy();
begin
  inherited destroy();
  styles.free();
  gfx.free();
  sfx.free();
end;

{--------------------------------------------------------}

constructor tGuiStyle.Create();
begin
  inherited Create();
  fontStyle := tFontStyle.Create();
  sprites := tStringMap<tSprite>.Create();
end;

destructor tGuiStyle.destroy();
begin
  fontStyle.free;
  sprites.free;
  inherited destroy();
end;

function tGuiStyle.clone(): tGuiStyle;
begin
  result := tGuiStyle.Create();
  result.fontStyle := fontStyle.clone.clone();
  result.sprites := sprites.clone();
end;

{--------------------------------------------------------}

constructor tFontStyle.Create();
begin
  inherited Create();
  col := RGB(255,255,255);
  font := DEFAULT_FONT;
  shadow := false;
  centered := false;
end;

function tFontStyle.clone(): tFontStyle;
begin
  result.col := col;
  result.font := font;
  result.shadow := shadow;
  result.centered := centered;
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

procedure tGuiComponent.playSFX(sfxName: string);
var
  sfx: tSoundEffect;
begin
  {todo: add sounds back in}
  {
  if not assigned(skin) then exit;
  if not skin.sfx.hasResource(sfxName) then exit;
  sfx := skin.sfx[sfxName];
  mixer.play(sfx);
  }
end;

function tGuiComponent.getSprite(): tSprite;
begin
  result := style.sprites.getWithDefault(GUI_STATE_NAME[state], nil);
end;

function tGuiComponent.getTextColor(): RGBA;
begin
  {todo: make this state dependant}
  result := fontStyle.col;
end;

function tGuiComponent.getFontStyle(): tFontStyle;
begin
  result := style.fontStyle;
end;

function tGuiComponent.getFont(): tFont;
begin
  result := fontStyle.font;
end;

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
  inherited Create();
  visible := true;
  enabled := true;
  bounds.init(0,0,0,0);
  text := '';
  col := RGB(128,128,128);
  style := DEFAULT_GUI_SKIN.styles['default'];
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
  style: tGuiStyle;
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

  {draw background}
  screen.canvas.dc.fillRect(bounds, backCol);
  screen.canvas.dc.drawRect(bounds, frameCol);

  if fontStyle.centered then begin
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

  if fontStyle.shadow then
    font.textOut(screen.canvas, drawX+1, drawY+1, text, RGB(0,0,0,fontStyle.col.a*3 div 4));
  font.textOut(screen.canvas, drawX, drawY, text, fontStyle.col);

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
      playSFX('clickdown');
      pressed := true;
    end;
  end else
    pressed := false;

  if pressed and not input.mouseLB then begin
    playSFX('clickup');
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
  inherited Create();
  bounds.x := aPos.x;
  bounds.y := aPos.y;
  {todo: remove (well clone the 'label' style and update.}
  {
  fontStyle.centered := false;
  fontStyle.shadow := false;
  fontStyle.col := RGB(250, 250, 250);
  }
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
  inherited Create();

  style := DEFAULT_GUI_SKIN.styles['button'];

  bounds.x := aPos.x;
  bounds.y := aPos.y;

  fText := aText;
  width := 100;
  height := 19;
  autoStyle := true;
end;

procedure tGuiButton.doDraw(screen: tScreen);
begin
  inherited doDraw(screen);
end;

begin
  {create a default, empty style}
  DEFAULT_GUI_SKIN := tGuiSkin.Create();
  DEFAULT_GUI_SKIN.styles['default'] := tGuiStyle.Create();
end.
