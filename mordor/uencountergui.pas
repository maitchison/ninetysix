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
    monster: pointer;
    frame: tSprite;
    monsterImage: tPage;
  public
    procedure  doDraw(const dc: tDrawContext); override;
    constructor Create();
  end;

  tEncounterGUI = class(tGuiContainer)
  public
    mode: tEncounterGuiMode;
    dungeonView: tDungeonViewGui;
    monsterFrame: array[1..4] of tMonsterFrame;
    procedure  doDraw(const dc: tDrawContext); override;
    constructor Create(map: tMDRMap);
  end;

implementation

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
  monsterImage:= gfx['wolf96'];
end;

procedure tMonsterFrame.doDraw(const dc: tDrawContext);
begin
  {portrait}
  dc.asBlendMode(bmBlit).drawImage(monsterImage, Point(4,15));
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

constructor tEncounterGUI.Create(map: tMDRMap);
var
  i: integer;
begin
  inherited Create();
  background := nil;
  backgroundCol := RGB(0,0,0,0);
  image := DEFAULT_GUI_SKIN.gfx.getWithDefault('innerwindow128', nil);
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
      fImageCol := RGBA.White;
    end;
  end;
end;

procedure tEncounterGUI.doDraw(const dc: tDrawContext);
var
  envImage: tPage;
  xPadding: integer;
begin
  inherited doDraw(dc);
  envImage := gfx['bg1_hq'];
  xPadding := (dc.width - envImage.width) div 2;
  dc.asTint(RGB(255,255,255,220)).drawImage(envImage, Point(xPadding, 0));
  dc.fillRect(Rect(0,0,xPadding, dc.height), RGB(0,0,0,220));
  dc.fillRect(Rect(dc.width-xPadding,0,xPadding, dc.height), RGB(0,0,0,220));
end;

begin
end.
