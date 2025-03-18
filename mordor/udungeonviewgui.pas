unit uDungeonViewGui;

interface

uses
  {$i gui.inc}
  uTest,
  uDebug,
  uRect,
  uMDRRes,
  uGraph32;

type
  tDungeonViewGui = class(tGuiPanel)
    procedure doDraw(const dc: tDrawContext); override;
    constructor Create();
  end;

implementation

procedure tDungeonViewGui.doDraw(const dc: tDrawContext);
begin
  inherited doDraw(dc);
  //tVoxel.draw(const dc: tDrawContext;atPos, angle: V3D; scale: single=1;asShadow:boolean=false): tRect;
end;

constructor tDungeonViewGui.Create();
begin
  inherited Create(Rect(20, 10, 96, 124), 'View');
  backgroundCol := MDR_LIGHTGRAY;
end;

begin
end.
