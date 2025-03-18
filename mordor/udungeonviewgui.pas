unit uDungeonViewGui;

interface

uses
  {$i gui.inc}
  uTest,
  uDebug,
  uRect,
  uUtils,
  uMDRRes,
  uVertex,
  uGraph32;

type
  tDungeonViewGui = class(tGuiPanel)
    procedure doUpdate(elapsed: single); override;
    procedure doDraw(const dc: tDrawContext); override;
    constructor Create();
  end;

implementation

procedure tDungeonViewGui.doDraw(const dc: tDrawContext);
var
  pos, angle: V3D;
begin
  inherited doDraw(dc);
  pos := V3(32+32,32+64,0);
  angle := V3(0,getSec,0);
  doorVoxel.draw(dc, pos, angle);
end;

procedure tDungeonViewGui.doUpdate(elapsed: single);
begin
  isDirty := true;
end;

constructor tDungeonViewGui.Create();
begin
  inherited Create(Rect(20, 10, 96, 124), 'View');
  backgroundCol := MDR_LIGHTGRAY;
end;

begin
end.
