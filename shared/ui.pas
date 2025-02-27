{A simple retained mode gui}
unit ui;

interface

uses
  debug, test,
  font,
  graph2d,
  graph32,
  uScreen;

type
  tGuiComponent = class
    bounds: tRect;
    alpha: single;
    targetAlpha: single;
    showForSeconds: single;
    visible: boolean;
    autoFade: boolean;
    font: tFont;
  protected
    procedure doDraw(screen: tScreen); virtual;
  public
    procedure draw(screen: tScreen);
    procedure update(elapsed: single); virtual;
    constructor create();
  end;

  tGuiComponents = class
    elements: array of tGuiComponent;
    procedure append(x: tGuiComponent);
    procedure draw(screen: tScreen);
    procedure update(elapsed: single);
  end;

  tGuiLabel = class(tGuiComponent)
  protected
    fText: string;
  public
    textColor: RGBA;
    centered: boolean;
  protected
    procedure doDraw(screen: tScreen); override;
    procedure setText(aText: string);
  public
    constructor create(aPos: tPoint; aText: string='');
    property text: string read fText write setText;
  end;

implementation

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
begin
  for gc in elements do gc.update(elapsed);
end;

{--------------------------------------------------------}
{ UI Components }

constructor tGuiComponent.create();
begin
  inherited create();
  self.alpha := 1;
  self.targetAlpha := 1;
  self.showForSeconds := 0;
  self.autoFade := false;
  self.visible := true;
  self.bounds.init(0,0,0,0);
  self.font := DEFAULT_FONT;
end;

procedure tGuiComponent.update(elapsed: single);
const
  FADE_IN = 0.04;
  FADE_OUT = 0.03;
var
  delta: single;
begin
  if autoFade then begin
    if showForSeconds > 0 then
      targetAlpha := 1.0
    else
      targetAlpha := 0.0;
    showForSeconds -= elapsed;
    // todo: respect elapsed
    delta := targetAlpha - alpha;
    if delta < 0 then
      alpha += delta * FADE_OUT
    else
      alpha += delta * FADE_IN
  end;
end;

procedure tGuiComponent.draw(screen: tScreen);
begin
  if not visible then exit;
  doDraw(screen);
end;

procedure tGuiComponent.doDraw(screen: tScreen);
begin
  // pass
end;

{-----------------------}

constructor tGuiLabel.create(aPos: tPoint; aText: string='');
begin
  inherited create();
  self.bounds.x := aPos.x;
  self.bounds.y := aPos.y;
  self.centered := false;
  self.textColor := RGB(250, 250, 250);
  self.text := aText;
end;

procedure tGuiLabel.setText(aText: string);
begin
  fText := aText;
  bounds := font.textExtents(text, bounds.topLeft);
  if centered then bounds.x -= bounds.width div 2;
end;

procedure tGuiLabel.doDraw(screen: tScreen);
var
  c: RGBA;
begin
  c.init(textColor.r, textColor.g, textColor.b, round(textColor.a * alpha));
  if c.a = 0 then exit;
  font.textOut(screen.canvas, bounds.x, bounds.y, text, c);
  screen.markRegion(bounds);
end;


begin
end.
