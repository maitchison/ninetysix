{for tracing through a 2d world of voxels}
unit uVoxelScene;

interface

uses
  uTest,
  uDebug,
  uUtils,
  uVertex,
  uRect,
  uGraph32,
  uPoly,
  uColor,
  uVoxel;

type
  tVoxelScene = class
  protected
    procedure drawCell(const dc: tDrawContext;x,y: integer);
  public
    cameraPos: V3D;
    cameraAngle: single; {radians, 0=north}
    procedure  render(const dc: tDrawContext);
    constructor Create();
  end;

implementation

constructor tVoxelScene.Create();
begin
  cameraPos := V3(5, 21,0);
  cameraAngle := 0;
end;

procedure tVoxelScene.drawCell(const dc: tDrawContext; x,y: integer);
var
  i: integer;
  {screen midpoint}
  screenMid: tPoint;
  {points in object space}
  p: array[1..8] of V3D;
  {points in screen space}
  s: array[1..8] of V3D;
  pos: V3D;

  function worldToScreen(p: V3D): V3D;
  begin
    result.x := 10*(p.x / (1+p.z)) + screenMid.x;
    result.y := 10*(p.y / (1+p.z)) + screenMid.y;
    result.z := p.z;
  end;

  procedure traceFace(faceID: byte; p1,p2,p3,p4: V3D);
  var
    bounds: tRect;
    y: integer;
  begin
    {scan the sides of the polygon}
    polyDraw.scanPoly(dc, p1.toPoint, p2.toPoint, p3.toPoint, p4.toPoint);
    bounds := polyDraw.bounds;
    if bounds.area <= 0 then exit;
    {draw color}
    for y := bounds.top to bounds.bottom-1 do
      dc.hline(
        Point(polyDraw.scanLine[y].xMin, y), polyDraw.scanLine[y].len,
        VX_FACE_COLOR[faceid]);
      exit;
  end;


begin
  screenMid := Point((dc.clip.left + dc.clip.right) div 2-dc.offset.x, (dc.clip.top + dc.clip.bottom) div 2-dc.offset.y);

  pos := V3(x+0.5, y+0.5, 0.5);

  p[1] := V3(-0.5, -0.5, -0.5);
  p[2] := V3(+0.5, -0.5, -0.5);
  p[3] := V3(+0.5, +0.5, -0.5);
  p[4] := V3(-0.5, +0.5, -0.5);
  p[5] := V3(-0.5, -0.5, +0.5);
  p[6] := V3(+0.5, -0.5, +0.5);
  p[7] := V3(+0.5, +0.5, +0.5);
  p[8] := V3(-0.5, +0.5, +0.5);
  for i := 1 to 8 do begin
    s[i] := worldToScreen(p[1]+pos-cameraPos);
  end;
  polyDraw.backfaceCull := true;
  traceFace(1, s[1], s[2], s[3], s[4]);
  traceFace(2, s[8], s[7], s[6], s[5]);
  traceFace(3, s[4], s[8], s[5], s[1]);
  traceFace(4, s[2], s[6], s[7], s[3]);
  traceFace(5, s[5], s[6], s[2], s[1]);
  traceFace(6, s[4], s[3], s[7], s[8]);
end;

procedure tVoxelScene.render(const dc: tDrawContext);
begin
  {for the moment just draw one cell}
  dc.fillRect(dc.clip, RGB(12,12,12));
  drawCell(dc, 7, 20);
  drawCell(dc, 7, 18);
  drawCell(dc, 9, 23);
end;

begin
end.
