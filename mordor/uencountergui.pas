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
  public
    monster: pointer;
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

constructor tEncounterGUI.Create();
var
  i: integer;
begin
  inherited Create();
  col := RGBA.Clear;
  setBounds(Rect(0, 0, 500, 180));
  case mode of
    egmType1: begin
      dungeonView := tGuiPanel.Create(Rect(10, 10, 96, 128), 'View');
      self.append(dungeonView);
      for i := 1 to 4 do begin
        monsterFrame[i] := tMonsterFrame.Create();
        monsterFrame[i].pos := Point(10+(10+96*i), 10);
        monsterFrame[i].text := 'Monster';
        self.append(monsterFrame[i]);
      end;
    end;
  end;
end;

begin
end.
