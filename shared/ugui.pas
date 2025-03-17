{A simple retained mode gui}
unit uGui;

interface

uses
  uDebug,
  uTest,
  uUtils,
  uGraph32,
  uVgaDriver,
  uFont,
  uFileSystem,
  uMouse,
  uInput,
  uSound,
  uMixer,
  uTypes,
  uColor,
  uRect,
  uKeyboard,
  uStringMap,
  uSprite;

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
    sounds: tStringMap<tSound>;
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

  tDoubleBufferMode = (
    // buffer is blended during composition (but only outed edge)
    dbmBlend,
    // buffer is blitted
    dbmBlit,
    // force double buffering off
    dbmOff
  );

  tGuiComponent = class;
  tGuiContainer = class;

  tHookProc = procedure(sender: tGuiComponent; msg: string; args: array of const) of object;

  tGuiComponent = class
  private
    prevState: tGuiState;
  protected
    {position relative to parent}
    fPos: tPoint;
    fWidth, fHeight: integer;
    parent: tGuiContainer;
    style: tGuiStyle;
    isInteractive: boolean;
    fVisible: boolean;
    isEnabled: boolean;
    isPressed: boolean;
    fText: string;
    fCol: RGBA;
    fHookKey: tStrings;
    fHookProc: array of tHookProc;
    mouseOverThisFrame, mouseOverLastFrame: boolean;
    {buffering}
    canvas: tPage;
    fIsDirty: boolean;
    doubleBufferMode: tDoubleBufferMode;
    doubleBufferEdge: integer; {only this many pixels are blended when using double buffering}
    {background}
    fBackground: tPage;
    fBackgroundCol: RGBA;
  public
    property isVisible: boolean read fVisible write fVisible;
  protected
    procedure playSFX(sfxName: string);
    procedure doDraw(const dc: tDrawContext); virtual;
    procedure doUpdate(elapsed: single); virtual;
    procedure setText(aText: string); virtual;
    procedure setCol(col: RGBA); virtual;
    procedure fireMessage(aMsg: string; args: array of const); virtual; overload;
    procedure fireMessage(aMsg: string); overload;
    procedure defaultBackgroundDraw(const dc: tDrawContext);
    function  bounds: tRect;
    function  innerBounds: tRect;
    procedure sizeToContent(); virtual;
    procedure setBounds(aRect: tRect);
    procedure setIsDirty(value: boolean);
    {style}
    function  getSprite(): tSprite;
  public
    {canvas}
    procedure enableDoubleBuffered();
    procedure disableDoubleBuffered();
    function  isDoubleBuffered: boolean;
  public
    fontStyle: tFontStyle;
  public
    constructor Create();
    procedure draw(const dc: tDrawContext); virtual;
    procedure update(elapsed: single); virtual;
    function  state: tGuiState;
    function  screenPos(): tPoint;
    function  screenBounds(): tRect;
    procedure addHook(aMsg: string; aProc: tHookProc);
    procedure invalidate(); virtual;
    procedure setSize(aWidth, aHeight: integer);
  public
    procedure onKeyPress(code: word); virtual;
  public
    property text: string read fText write setText;
    property col: RGBA read fCol write setCol;
    property pos: tPoint read fPos write fPos;
    {style helpers}
    property font: tFont read fontStyle.font write fontStyle.font;
    property textColor: RGBA read fontStyle.col write fontStyle.col;
    property background: tPage read fBackground write fBackground;
    property backgroundColor: RGBA read fBackgroundCol write fBackgroundCol;
    property isDirty: boolean read fIsDirty write setIsDirty;
  end;

  tGuiContainer = class(tGuiComponent)
  protected
    elements: array of tGuiComponent;
    procedure fireMessage(aMsg: string; args: array of const); override;
  public
    constructor Create();
    destructor destroy; override;
    procedure append(x: tGuiComponent); virtual;
    procedure draw(const dc: tDrawContext); override;
    procedure update(elapsed: single); override;
  end;

  tGui = class(tGuiContainer)
  public
    { If true checks for and handles keyboard input.
      Unfortunately this conflicts a bit with my other keyboard unit}
    handlesInput: boolean;
    constructor Create();
    procedure update(elapsed: single); override;
  end;

type
  tGuiDrawMode = (
    // every component will be draw (composited) every frame
    gdmFull,
    // only components that have updated will be drawn.
    gdmDirty
  );

const
  {global GUI stuff}
  DEFAULT_GUI_SKIN: tGuiSkin = nil;
  GUI_STATE_NAME: array[tGuiState] of string = (
    'normal',
    'disabled',
    'highlighted',
    'pressed',
    'selected'
  );

  GUI_HQ: boolean = true;
  GUI_DOUBLEBUFFER: boolean = true;
  GUI_DRAWMODE: tGuiDrawMode = gdmFull;

procedure initGuiSkinSimple();
procedure initGuiSkinEpic();

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
  padding := Border(0,0,0,0);
  sprites := tStringMap<tSprite>.Create();
  sounds := tStringMap<tSound>.Create();
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

constructor tGui.Create();
begin
  inherited Create();
  handlesInput := true;
  setBounds(Rect(0,0,videoDriver.physicalWidth,videoDriver.physicalHeight));
  fCol.a := 0;
end;

{--------------------------------------------------------}

constructor tGuiContainer.Create();
begin
  inherited Create();
  fWidth := 100;
  fHeight := 100;
  setLength(elements, 0);
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
  x.parent := self;
  if GUI_DOUBLEBUFFER and (x.doubleBufferMode <> dbmOff) then
    x.enableDoubleBuffered();
end;

procedure tGuiContainer.draw(const dc: tDrawContext);
var
  gc: tGuiComponent;
  childDC: tDrawContext;
begin
  {draw ourselves}
  inherited draw(dc);

  childDC := dc;
  childDC.offset += innerBounds.pos + fPos;
  childDC.clip := self.innerBounds;
  childDC.clip.pos += screenPos;

  for gc in elements do if gc.fVisible then gc.draw(childDC);
end;

procedure tGuiContainer.update(elapsed: single);
var
  gc: tGuiComponent;
begin
  for gc in elements do if gc.isEnabled then gc.update(elapsed);
  doUpdate(elapsed)
end;

procedure tGuiContainer.fireMessage(aMsg: string; args: array of const);
var
  gc: tGuiComponent;
begin
  inherited fireMessage(aMsg, args);
  for gc in elements do if gc.isEnabled then gc.fireMessage(aMsg, args);
end;


{--------------------------------------------------------}

procedure tGui.update(elapsed: single);
var
  code: word;
  gc: tGuiComponent;
begin

  {process keys, if any}
  {note: this fights with my keyboard handler...}
  if handlesInput then while true do begin
    code := dosGetKey.code;
    if code = 0 then break;
    self.fireMessage(ON_KEYPRESS, [code]);
    for gc in elements do begin
      gc.fireMessage(ON_KEYPRESS, [code]);
      gc.onKeyPress(code);
    end;
  end;

  inherited update(elapsed);
end;

{--------------------------------------------------------}

procedure tGuiComponent.playSFX(sfxName: string);
var
  sfx: tSound;
begin
  if not style.sounds.contains(sfxName) then exit;
  mixer.play(style.sounds[sfxName]);
end;

procedure tGuiComponent.setIsDirty(value: boolean);
begin
  fIsDirty := value;
end;

function tGuiComponent.getSprite(): tSprite;
var
  defaultSprite: tSprite;
begin
  defaultSprite := style.sprites.getWithDefault('default', nil);
  result := style.sprites.getWithDefault(GUI_STATE_NAME[state], defaultSprite);
end;

procedure tGuiComponent.enableDoubleBuffered();
begin
  if assigned(canvas) and (canvas.width = fWidth) and (canvas.height = fHeight) then
    {already done}
    exit;
  if assigned(canvas) then canvas.free();
  canvas := tPage.create(fWidth, fHeight);
  canvas.Clear(RGBA.Clear);
  isDirty := true;
end;

procedure tGuiComponent.disableDoubleBuffered;
begin
  if assigned(canvas) then canvas.free;
  canvas := nil;
end;

function tGuiComponent.isDoubleBuffered: boolean;
begin
  result := assigned(canvas);
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

{notifies component that it should redraw on next draw call}
procedure tGuiComponent.invalidate();
begin
  isDirty := true;
end;

function tGuiComponent.state: tGuiState;
begin
  if not isEnabled then exit(gsDisabled);
  if not isInteractive then exit(gsNormal);
  if isPressed then exit(gsPressed);
  if mouseOverThisFrame then exit(gsHighlighted);
  exit(gsNormal);
end;

constructor tGuiComponent.Create();
begin
  inherited Create();
  fVisible := true;
  isEnabled := true;
  isInteractive := false;
  fPos := Point(0, 0);
  fWidth := 16;
  fHeight := 16;
  text := '';
  col := RGB(255,255,255);
  fontStyle.setDefault();
  style := DEFAULT_GUI_SKIN.styles['default'];
  isDirty := true;
  doubleBufferMode := dbmBlend;
  doubleBufferEdge := 8;
  fBackground := nil;
  fBackgroundCol := RGBA.White;
end;

{get absolute bounds by parent query}
function tGuiComponent.screenPos(): tPoint;
begin
  result := fPos;
  if not assigned(parent) then exit;
  result += parent.fPos + Point(parent.style.padding.left, parent.style.padding.top);
end;

function tGuiComponent.screenBounds(): tRect;
begin
  result.pos := screenPos;
  result.width := fWidth;
  result.height := fHeight;
end;

procedure tGuiComponent.doUpdate(elapsed: single);
begin
  // pass
end;

{the fallback default background draw}
procedure tGuiComponent.defaultBackgroundDraw(const dc: tDrawContext);
var
  backCol, frameCol: RGBA;
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

  dc.fillRect(bounds, backCol);
  dc.drawRect(bounds, frameCol);
end;

function tGuiComponent.innerBounds: tRect;
begin
  result := style.padding.inset(bounds);
end;

function tGuiComponent.bounds: tRect;
begin
  result := Rect(0,0,fWidth,fHeight);
end;

{set both position and size}
procedure tGuiComponent.setBounds(aRect: tRect);
begin
  fPos := aRect.pos;
  setSize(aRect.width, aRect.height);
  isDirty := true;
end;

procedure tGuiComponent.sizeToContent();
var
  newBounds: tRect;
begin
  newBounds := font.textExtents(text);
  newBounds.width += style.padding.horizontal;
  newBounds.height += style.padding.vertical;
  setSize(newBounds.width, newBounds.height);
end;

procedure tGuiComponent.doDraw(const dc: tDrawContext);
var
  drawX, drawY: integer;
  textRect: tRect;
  style: tGuiStyle;
  s: tSprite;
  backgroundDC: tDrawContext;
begin

  {draw background}
  backgroundDC := dc;
  if (dc.page = canvas) then
    // force blit if we are redrawing our own canvas
    backgroundDC.blendMode := bmBlit;
  s := getSprite();
  if assigned(s) then begin
    s.drawNineSlice(backgroundDC, bounds);
  end else begin
    defaultBackgroundDraw(backgroundDC);
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

  {stretched background}
  if assigned(fBackground) then
    dc.asTint(fBackgroundCol).stretchImage(fBackground, innerBounds);

  if text <> '' then begin
    if fontStyle.shadow then
      font.textOut(dc, drawX+1, drawY+1, text, RGB(0,0,0,fontStyle.col.a*3 div 4));
    font.textOut(dc, drawX, drawY, text, fontStyle.col);
  end;

end;

procedure tGuiComponent.draw(const dc: tDrawContext);
var
  oldTint: RGBA;
  canvasDC: tDrawContext;
  drawDC: tDrawContext;
begin
  {todo: check clipping bounds}
  drawDC := dc;

  {draw component directly to dc}
  if (GUI_DRAWMODE = gdmDirty) and (not fIsDirty) then exit;

  if isDoubleBuffered then begin
    {draw component to canvas, then write this to dc}
    if isDirty then begin
      canvasDC := canvas.getDC();
      if GUI_HQ then canvasDC.textureFilter := tfLinear;
      //canvasDC.tint := col;
      doDraw(canvasDC);
      isDirty := false;
    end;
    drawDC.tint := RGBA.White;
    drawDC.offset += fPos;
    case doubleBufferMode of
      dbmBlend:
        drawDC.asBlendMode(bmBlend).inOutDraw(canvas, bounds.pos, doubleBufferEdge, bmBlit, bmBlend);
      dbmBlit:
        drawDC.asBlendMode(bmBlit).drawImage(canvas, bounds.pos);
    end;
    exit;
  end;

  if GUI_HQ then drawDC.textureFilter := tfLinear;
  //drawDC.tint := col;
  drawDC.offset += fPos;
  doDraw(drawDC);
  fIsDirty := false;
end;

procedure tGuiComponent.update(elapsed: single);
begin
  mouseOverLastFrame := mouseOverThisFrame;
  mouseOverThisFrame := false;
  if not isEnabled then exit;
  mouseOverThisFrame := screenBounds.isInside(input.mouseX, input.mouseY);

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

  {check if our state changed}
  if prevState <> state then
    isDirty := true;
  prevState := state;
end;

procedure tGuiComponent.onKeyPress(code: word);
begin
  // nothing
end;

procedure tGuiComponent.setText(aText: string);
begin
  if (fText = aText) then exit;
  fText := aText;
  isDirty := true;
end;

procedure tGuiComponent.setCol(col: RGBA);
begin
  if (fCol = col) then exit;
  fCol := col;
  isDirty := true;
end;

procedure tGuiComponent.setSize(aWidth, aHeight: integer);
begin
  if (fWidth = aWidth) and (fHeight = aHeight) then exit;
  fWidth := aWidth;
  fHeight := aHeight;
  if isDoubleBuffered then
    {this just renables it with correct size}
    enableDoubleBuffered();
  isDirty := true;
end;

{-----------------------}

{todo: make this an ini file}
procedure initGuiSkinEpic();
var
  style: tGuiStyle;
  guiSkin: tGuiSkin;

  function makeSprite(tag: string; aBorder: tBorder;innerBlendMode: tBlendMode=bmBlit): tSprite; overload;
  begin
    result := tSprite.Create(guiSkin.gfx[tag]);
    result.border := aBorder;
    result.innerBlendMode := ord(innerBlendMode);
  end;

  procedure makeStateSprites(style: tGuiStyle; tag: string; aBorder: tBorder);
  var
    state: string;
    gfxName: string;
  begin
    for state in GUI_STATE_NAME do begin
      gfxName := tag+'_'+state;
      if guiSkin.gfx.hasResource(gfxName) then
        style.sprites[state] := makeSprite(gfxName, aBorder)
      else
        warning('Missing gui gfx: "'+gfxName+'"');
    end;
  end;

begin
  guiSkin := tGuiSkin.Create();
  guiSkin.gfx.loadFromFolder('gui', '*.p96');
  guiSkin.sfx.loadFromFolder('sfx', '*.a96');

  style := tGuiStyle.Create();
  guiSkin.styles['default'] := style;

  style := tGuiStyle.Create();
  style.padding.init(8,11,8,11);
  style.sprites['default'] := makeSprite('ec_box', Border(20,20,20,20), bmNone);
  guiSkin.styles['box'] := style;

  style := tGuiStyle.Create();
  style.padding.init(8,5,8,9);
  makeStateSprites(style, 'ec_button', Border(8,8,6,11));
  style.sounds['clickup'] := guiSkin.sfx['clickup'];
  style.sounds['clickdown'] := guiSkin.sfx['clickdown'];
  guiSkin.styles['button'] := style;

  style := tGuiStyle.Create();
  style.sprites['default'] := makeSprite('ec_toggle_off', Border(4,4,6,6));
  style.sprites['selected'] := makeSprite('ec_toggle_on', Border(4,4,6,6));
  guiSkin.styles['toggle'] := style;

  style := tGuiStyle.Create();
  style.padding.init(4,4,4,4);
  style.sprites['default'] := makeSprite('ec_panel', Border(4,4,4,4));
  guiSkin.styles['panel'] := style;

  DEFAULT_GUI_SKIN := guiSkin;
end;

{very simple default gui. No sprites required}
procedure initGuiSkinSimple();
var
  guiSkin: tGuiSkin;
  style: tGuiStyle;
begin
  guiSkin := tGuiSkin.Create();
  style := tGuiStyle.Create();
  guiSkin.styles['default'] := style.clone();
  guiSkin.styles['box'] := style.clone();
  guiSkin.styles['button'] := style.clone();
  guiSkin.styles['toggle'] := style.clone();
  guiSkin.styles['panel'] := style.clone();

  DEFAULT_GUI_SKIN := guiSkin;
end;

begin
  initGuiSkinSimple();
end.
