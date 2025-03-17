unit uEncounterGUI;

interface

uses
  uTest,
  uDebug,
  uUtils,
  uRect,
  uGraph32,
  uSprite,
  uScreen,
  uColor,
  uVertex,
  uKeyboard,
  uFont,
  {$i gui.inc}
  {game stuff}
  uRes,
  uTileEditorGui,
  uMDRMap;

type

  tEncounterGuiMode = (egmType1);

  tMonsterFrame = class(tGuiComponent)
  protected
    monster: pointer;
    frameImage: tPage;
    monsterImage: tPage;
  public
    procedure  doDraw(const dc: tDrawContext); override;
    constructor Create();
  end;

  tEncounterGUI = class(tGuiContainer)
  public
    mode: tEncounterGuiMode;
    dungeonView: tGuiPanel;
    monsterFrame: array[1..4] of tMonsterFrame;
    constructor Create();
  end;

implementation

{-------------------------------------------------------}

constructor tMonsterFrame.Create();
begin
  inherited Create();
  guiStyle := DEFAULT_GUI_SKIN.styles['panel'].clone();
  doubleBufferMode := dbmBlit;
  scale := V2(0.75, 0.75);
  setBounds(Rect(0,0, 96, 128));
  frameImage := gfx['frame'];
  monsterImage:= gfx['wolf96'];
end;

procedure tMonsterFrame.doDraw(const dc: tDrawContext);
begin
  dc.asBlendMode(bmBlit).drawImage(monsterImage, Point(0,0));
  dc.asBlendMode(bmBlend).drawImage(frameImage, Point(0,0));
end;

constructor tEncounterGUI.Create();
var
  i: integer;
begin
  inherited Create();
  backgroundCol := RGBA.Clear;
  setBounds(Rect(0, 0, 500, 180));
  case mode of
    egmType1: begin
      dungeonView := tGuiPanel.Create(Rect(10, 10, 96, 128), 'View');
      self.append(dungeonView);
      for i := 1 to 4 do begin
        monsterFrame[i] := tMonsterFrame.Create();
        monsterFrame[i].pos := Point(10+(100*i), 10);
        monsterFrame[i].text := 'Monster';
        self.append(monsterFrame[i]);
      end;
    end;
  end;
end;

begin
end.
