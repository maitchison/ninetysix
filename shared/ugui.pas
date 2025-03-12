{A simple retained mode gui}
unit uGui;

interface

uses
  uDebug,
  uTest,
  uUtils,
  uGraph32,
  uFont,
  uMouse,
  uInput,
  uMap,
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

  tGuiComponent = class;
  tGuiContainer = class;

  tHookProc = procedure(sender: tGuiComponent; msg: string; args: array of const);

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
    isVisible: boolean;
    isEnabled: boolean;
    isPressed: boolean;
    fText: string;
    fCol: RGBA;
    fHookKey: tStrings;
    fHookProc: array of tHookProc;
    mouseOverThisFrame, mouseOverLastFrame: boolean;
    {buffering}
    canvas: tPage;
    isDirty: boolean;
  protected
    procedure playSFX(sfxName: string);
    procedure doDraw(dc: tDrawContext); virtual;
    procedure doUpdate(elapsed: single); virtual;
    procedure setText(aText: string); virtual;
    procedure setCol(col: RGBA); virtual;
    procedure setSize(aWidth, aHeight: integer);
    procedure fireMessage(aMsg: string; args: array of const); overload;
    procedure fireMessage(aMsg: string); overload;
    procedure defaultBackgroundDraw(dc: tDrawContext);
    function  bounds: tRect;
    function  innerBounds: tRect;
    procedure sizeToContent(); virtual;
    procedure setBounds(aRect: tRect);
    {style}
    function  getSprite(): tSprite;
    {canvas}
    procedure enableDoubleBuffered();
    procedure disableDoubleBuffered();
    function  isDoubleBuffered: boolean;
  public
    fontStyle: tFontStyle;
  public
    constructor Create();
    procedure draw(dc: tDrawContext); virtual;
    procedure update(elapsed: single); virtual;
    function  state: tGuiState;
    function  screenPos(): tPoint;
    function  screenBounds(): tRect;
    procedure addHook(aMsg: string; aProc: tHookProc);
  public
    procedure onKeyPress(code: word); virtual;
  public
    property text: string read fText write setText;
    property col: RGBA read fCol write setCol;
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
    procedure draw(dc: tDrawContext); override;
    procedure update(elapsed: single); override;
  end;

  tGui = class(tGuiContainer)
  public
    constructor Create();
  end;

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
  if GUI_DOUBLEBUFFER then x.enableDoubleBuffered();
end;

procedure tGuiContainer.draw(dc: tDrawContext);
var
  gc: tGuiComponent;
begin
  {draw ourselves}
  inherited draw(dc);

  {todo: update clip rect aswell I guess}
  dc.offset += innerBounds.pos + fPos;
  for gc in elements do if gc.isVisible then gc.draw(dc);
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
  sfx: tSound;
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

procedure tGuiComponent.enableDoubleBuffered();
begin
  if assigned(canvas) and (canvas.width = fWidth) and (canvas.height = fHeight) then
    {already done}
    exit;
  if assigned(canvas) then canvas.free();
  canvas := tPage.create(fWidth, fHeight);
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
  isVisible := true;
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
procedure tGuiComponent.defaultBackgroundDraw(dc: tDrawContext);
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

procedure tGuiComponent.doDraw(dc: tDrawContext);
var
  drawX, drawY: integer;
  textRect: tRect;
  style: tGuiStyle;
  s: tSprite;
begin

  {draw background}
  s := getSprite();
  if assigned(s) then begin
    s.drawNineSlice(dc, bounds);
  end else begin
    defaultBackgroundDraw(dc);
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

  {note: font does not yet support draw contexts, so update position here...
   we won't get clipping though}
  drawX += dc.offset.x;
  drawY += dc.offset.y;
  if fontStyle.shadow then
    font.textOut(dc.page, drawX+1, drawY+1, text, RGB(0,0,0,fontStyle.col.a*3 div 4));
  font.textOut(dc.page, drawX, drawY, text, fontStyle.col);

end;

procedure tGuiComponent.draw(dc: tDrawContext);
var
  oldTint: RGBA;
  canvasDC: tDrawContext;
begin
  {todo: check clipping bounds}

  if isDoubleBuffered then begin
    {draw component to canvas, then write this to dc}
    if isDirty then begin
      canvas.clear(RGB(0,0,0,0));
      canvasDC := canvas.getDC(bmBlend);
      if GUI_HQ then canvasDC.textureFilter := tfLinear;
      canvasDC.tint := col;
      doDraw(canvasDC);
      isDirty := false;
    end;
    dc.blendMode := bmBlend;
    dc.tint := RGBA.White;
    dc.offset += fPos;
    //dc.drawImage(canvas, bounds.pos);
    dc.inOutDraw(canvas, bounds.pos, 8, bmBlit, bmBlend);
  end else begin
    {draw component directly to dc}
    if GUI_HQ then dc.textureFilter := tfLinear;
    dc.tint := col;
    dc.offset += fPos;
    doDraw(dc);
  end;
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
  if fText = aText then exit;
  fText := aText;
  isDirty := true;
end;

procedure tGuiComponent.setCol(col: RGBA);
begin
  if fCol = col then exit;
  fCol := col;
  isDirty := true;
end;

procedure tGuiComponent.setSize(aWidth, aHeight: integer);
begin
  if (fWidth = aWidth) and (fHeight = aHeight) then exit;
  fWidth := aWidth;
  fHeight := aHeight;
  if isDoubleBuffered then
    enableDoubleBuffered();
  isDirty := true;
end;

{-----------------------}

begin
  {create a default, empty style}
  DEFAULT_GUI_SKIN := tGuiSkin.Create();
  DEFAULT_GUI_SKIN.styles['default'] := tGuiStyle.Create();
end.
