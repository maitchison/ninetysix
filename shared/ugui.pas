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

  tFontStyle = record
    font: tFont;
    col: RGBA;
    shadow: boolean;
    centered: boolean;
    procedure setDefault();
  end;

  tGuiStyle = class
    padding: tBorder;       // how far to inset objects
    {maps from state to value}
    sprites: tStringMap<tSprite>;
    sounds: tStringMap<tSoundEffect>;
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

  tGuiState = (gsNormal, gsDisabled, gsHighlighted, gsPressed, gsSelected);

  tGuiComponent = class;

  tHookProc = procedure(sender: tGuiComponent; msg: string; args: array of const);

  tGuiComponent = class
  protected
    style: tGuiStyle;
    bounds: tRect;
    isInteractive: boolean;
    isVisible: boolean;
    isEnabled: boolean;
    isPressed: boolean;
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
    procedure defaultBackgroundDraw(screen: tScreen);
    function  innerBounds: tRect;
    procedure sizeToContent(); virtual;
    {style}
    function  getSprite(): tSprite;
  public
    fontStyle: tFontStyle;
  public
    constructor Create();
    procedure draw(screen: tScreen); virtual;
    procedure update(elapsed: single); virtual;
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
    property font: tFont read fontStyle.font write fontStyle.font;
    property textColor: RGBA read fontStyle.col write fontStyle.col;
  end;

  tGuiContainer = class(tGuiComponent)
  protected
    elements: array of tGuiComponent;
  public
    constructor Create();
    destructor destroy; override;
    procedure append(x: tGuiComponent); virtual;
    procedure draw(screen: tScreen); override;
    procedure update(elapsed: single); override;
  end;

const
  DEFAULT_GUI_SKIN: tGuiSkin = nil;
  GUI_STATE_NAME: array[tGuiState] of string = (
    'normal',
    'disabled',
    'highlighted',
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
  padding := Border(2,2,2,2);
  sprites := tStringMap<tSprite>.Create();
  sounds := tStringMap<tSoundEffect>.Create();
end;

destructor tGuiStyle.destroy();
begin
  sprites.free;
  sounds.free;
  inherited destroy();
end;

function tGuiStyle.clone(): tGuiStyle;
begin
  result := tGuiStyle.Create();
  result.padding := padding;
  result.sprites := sprites.clone();
  result.sounds := sounds.clone();
end;

{--------------------------------------------------------}

procedure tFontStyle.setDefault();
begin
  col := RGB(255,255,255);
  font := DEFAULT_FONT;
  shadow := false;
  centered := false;
end;

{--------------------------------------------------------}

constructor tGuiContainer.Create();
begin
  inherited Create();
  {todo: think of some reasonable bounds}
  bounds := Rect(0,0,1024,1024);
  setLength(elements, 0);
  {make sure we don't draw background}
  fCol.a := 0;
end;

destructor tGuiContainer.destroy;
var
  gc: tGuiComponent;
begin
  for gc in elements do gc.free;
  setLength(elements, 0);
  inherited destroy;
end;

procedure tGuiContainer.append(x: tGuiComponent);
begin
  setLength(elements, length(elements)+1);
  elements[length(elements)-1] := x;
end;

procedure tGuiContainer.draw(screen: tScreen);
var
  gc: tGuiComponent;
begin
  doDraw(screen);
  for gc in elements do if gc.isVisible then gc.draw(screen);
end;

procedure tGuiContainer.update(elapsed: single);
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

  for gc in elements do if gc.isEnabled then gc.update(elapsed);

  doUpdate(elapsed)
end;

{--------------------------------------------------------}

procedure tGuiComponent.playSFX(sfxName: string);
var
  sfx: tSoundEffect;
begin
  if not style.sounds.contains(sfxName) then exit;
  mixer.play(style.sounds[sfxName]);
end;

function tGuiComponent.getSprite(): tSprite;
var
  defaultSprite: tSprite;
begin
  defaultSprite := style.sprites.getWithDefault('default', nil);
  result := style.sprites.getWithDefault(GUI_STATE_NAME[state], defaultSprite);
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
  if not isEnabled then exit(gsDisabled);
  if not isInteractive then exit(gsNormal);
  if isPressed then exit(gsPressed);
  if mouseOverThisFrame then exit(gsHighlighted);
  exit(gsNormal);
end;

{--------------------------------------------------------}
{ UI Components }

constructor tGuiComponent.create();
begin
  inherited Create();
  isVisible := true;
  isEnabled := true;
  isInteractive := false;
  bounds.init(0,0,0,0);
  text := '';
  col := RGB(128,128,128);
  fontStyle.setDefault();
  style := DEFAULT_GUI_SKIN.styles['default'];
end;

procedure tGuiComponent.doUpdate(elapsed: single);
begin
  // pass
end;

{the fallback default background draw}
procedure tGuiComponent.defaultBackgroundDraw(screen: tScreen);
var
  backCol, frameCol: RGBA;
  dc: tDrawContext;
begin

  if col.a = 0 then exit;

  backCol := col;
  frameCol := RGB(0,0,0,backCol.a div 2);

  case state of
    gsNormal: ;
    gsDisabled: backCol := RGBA.Lerp(backCol, RGBA.Black, 0.5);
    gsHighlighted: backCol := RGBA.Lerp(backCol, RGB(255,255,0), 0.33);
    gsPressed: backCol := RGBA.Lerp(backCol, RGB(128,128,255), 0.33);
  end;

  dc := screen.canvas.dc();
  dc.fillRect(bounds, backCol);
  dc.drawRect(bounds, frameCol);
end;

function tGuiComponent.innerBounds: tRect;
begin
  result := style.padding.inset(bounds);
end;

procedure tGuiComponent.sizeToContent();
begin
  bounds := font.textExtents(text, bounds.topLeft);
  bounds.width += style.padding.horizontal;
  bounds.height += style.padding.vertical;
end;

procedure tGuiComponent.doDraw(screen: tScreen);
var
  drawX, drawY: integer;
  textRect: tRect;
  style: tGuiStyle;
  s: tSprite;
begin

  {draw background}
  s := getSprite();
  if assigned(s) then begin
    s.nineSlice(screen.canvas, bounds);
  end else begin
    defaultBackgroundDraw(screen);
  end;

  if fontStyle.centered then begin
    textRect := font.textExtents(text);
    drawX := innerBounds.x+((innerBounds.width - textRect.width) div 2);
    drawY := innerBounds.y+((innerBounds.height - textRect.height) div 2)-1;
  end else begin
    {-2 due to font height being a bit weird}
    drawX := innerBounds.x;
    drawY := innerBounds.y-2;
  end;

  if isPressed then begin
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
  if not isVisible then exit;
  doDraw(screen);
end;

procedure tGuiComponent.update(elapsed: single);
begin
  mouseOverLastFrame := mouseOverThisFrame;
  mouseOverThisFrame := false;
  if not isEnabled then exit;
  mouseOverThisFrame := bounds.isInside(input.mouseX, input.mouseY);

  if isInteractive then begin
    {handle pressed logic}
    if mouseOverThisFrame then begin
      if input.mousePressed then begin
        fireMessage(ON_MOUSE_DOWN);
        playSFX('clickdown');
        isPressed := true;
      end;
    end else
      isPressed := false;

    if isPressed and not input.mouseLB then begin
      playSFX('clickup');
      fireMessage(ON_MOUSE_CLICK);
      isPressed := false;
    end;
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

begin
  {create a default, empty style}
  DEFAULT_GUI_SKIN := tGuiSkin.Create();
  DEFAULT_GUI_SKIN.styles['default'] := tGuiStyle.Create();
end.
