unit uEncounterGUI;

interface

uses
  uTest,
  uDebug,
  uUtils,
  uRect,
  uVGADriver,
  uGraph32,
  uSprite,
  uScreen,
  uColor,
  uVertex,
  uKeyboard,
  uFont,
  {$i gui.inc}
  {game stuff}
  uMDRRes,
  uTileEditorGui,
  uDungeonViewGui,
  uMDRMap;

type

  tEncounterGuiMode = (egmType1, egmType3);

  tMonsterFrame = class(tGuiComponent)
  protected
    id: integer;
    monster: pointer;
    frame: tSprite;
    monsterImage: tSprite;
  public
    procedure  doDraw(const dc: tDrawContext); override;
    constructor Create();
  end;

  tSimpleMonsterFrame = class(tMonsterFrame)
  public
    procedure  doDraw(const dc: tDrawContext); override;
    procedure  doUpdate(elapsed: single); override;
    constructor Create();
  end;

  tEncounterGUI = class(tGuiContainer)
  public
    mode: tEncounterGuiMode;
    dungeonView: tDungeonViewGui;
    monsterFrame: array[1..4] of tMonsterFrame;
    procedure  doUpdate(elapsed: single); override;
    procedure  doDraw(const dc: tDrawContext); override;
    constructor Create(map: tMDRMap);
  end;

implementation

{-------------------------------------------------------}

constructor tSimpleMonsterFrame.Create();
begin
  inherited Create();
  doubleBufferMode := dbmBlend;
end;

procedure tSimpleMonsterFrame.doDraw(const dc: tDrawContext);
var
  atX, atY: integer;
  ambiance, monsterCol: RGBA;
begin
  dc.clear(RGBA.Clear);
  atX := 20; atY := 30;
  if assigned(parent) and assigned(parent.getCanvas()) then begin
    ambiance := parent.getCanvas().getPixelArea(Rect(fPos.x+atX+(16*3 div 2)-4, fPos.y+atY+(24*3 div 2)-4, 8, 8));
  end else
    ambiance := RGBA.White;
  monsterCol := RGBA.Blend(ambiance, RGB($ff9e720c), 96);
  monsterImage.drawScaled(dc.asFilter(tfNearest).asTint(RGB(0,0,0,200)).asBlendMode(bmBlend), atX+2, atY+2, 3);
  monsterImage.drawScaled(dc.asFilter(tfNearest).asTint(monsterCol).asBlendMode(bmBlend), atX+1, atY+1, 3);
end;

procedure tSimpleMonsterFrame.doUpdate(elapsed: single);
var
  animationFrame: integer;
  oldImage: tSprite;
begin
  inherited doUpdate(elapsed);
  animationFrame := (round(id*12.37+getSec*1.5) mod 2)*19;
  oldImage := monsterImage;
  monsterImage := monsterSprites.byIndex(11+(4*19)+animationFrame);
  if monsterImage <> oldImage then
    isDirty := true;
end;

{-------------------------------------------------------}

constructor tMonsterFrame.Create();
begin
  inherited Create();
  guiStyle := DEFAULT_GUI_SKIN.styles['panel'].clone();
  doubleBufferMode := dbmBlit;
  scale := V2(0.75, 0.75);
  setBounds(Rect(0,0, 96+8, 128+38));
  frame := tSprite.Create(gfx['frame']);
  frame.border := Border(15,15,15,15);
  monsterImage:= tSprite.Create(gfx['wolf96']);
end;

procedure tMonsterFrame.doDraw(const dc: tDrawContext);
begin
  {portrait}
  monsterImage.draw(dc.asBlendMode(bmBlit), 4, 15);
  {header}
  dc.fillRect(Rect(0,0,bounds.width,25), MDR_LIGHTGRAY);
  dc.drawRect(Rect(0,0,bounds.width,25), RGB(0,0,0,128));
  font.textOut(dc, 39,7, 'Wolf', RGBF(0,0,0,0.9));
  {footer}
  dc.fillRect(Rect(0,bounds.height-25,bounds.width,25), RGBA.Lerp(MDR_DARKGRAY, RGBA.Black, 0.5));
  dc.drawRect(Rect(0,bounds.height-25,bounds.width,25), RGB(0,0,0,128));
  {frame}
  frame.drawNineSlice(dc.asBlendMode(bmBlend), bounds);
end;

{-------------------------------------------------------}

constructor tEncounterGUI.Create(map: tMDRMap);
var
  i: integer;
begin
  inherited Create();
  fHasTransparientChildren := true;
  background := nil;
  backgroundCol := RGB(0,0,0,0);
  image := DEFAULT_GUI_SKIN.gfx.getWithDefault('innerwindow', nil);
  imageCol := RGBA.White;
  setBounds(Rect(0, 0, 500, 180));
  mode := egmType3;
  case mode of
    egmType1: begin
      dungeonView := tDungeonViewGui.Create(map);
      self.append(dungeonView);
      for i := 1 to 4 do begin
        monsterFrame[i] := tMonsterFrame.Create();
        monsterFrame[i].pos := Point(40+(90*i), 10);
        monsterFrame[i].text := 'Monster';
        self.append(monsterFrame[i]);
      end;
    end;
    egmType3: begin
      for i := 1 to 4 do begin
        monsterFrame[i] := tSimpleMonsterFrame.Create();
        monsterFrame[i].id := i;
        monsterFrame[i].pos := Point(10+(90*i), round(95+sin(i*2)*10));
        monsterFrame[i].text := 'Monster';
        self.append(monsterFrame[i]);
      end;
    end;
  end;
end;

procedure tEncounterGUI.doUpdate(elapsed: single);
var
  i: integer;
  anyDirty: boolean;
begin
  {big stub...}
  anyDirty := false;
  for i := 1 to 4 do if monsterFrame[i].isDirty then anyDirty := true;
  for i := 1 to 4 do monsterFrame[i].isDirty := anyDirty;
  inherited doUpdate(elapsed);
end;

procedure tEncounterGUI.doDraw(const dc: tDrawContext);
var
  envImage: tPage;
  xPadding: integer;
begin
  inherited doDraw(dc);
  {
  envImage := gfx['bg1'];
  dc.asBlendMode(bmBlit).asFilter(tfNearest).stretchImage(envImage, Rect((dc.clip.width-(82*5)) div 2,0,82*5, 42*5));
  }

  envImage := gfx['bg1_hq'];
  xPadding := (dc.width - envImage.width) div 2;
  dc.asBlendMode(bmBlit).drawImage(envImage, Point(xPadding, 0));
  dc.fillRect(Rect(0,0,xPadding, dc.height), RGB(0,0,0,220));
  dc.fillRect(Rect(dc.width-xPadding,0,xPadding, dc.height), RGB(0,0,0,220));

end;

begin
end.
