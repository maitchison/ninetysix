{dynamic function construction}
unit uAsm;

interface

type
  tDrawContext = class
    width, height: word;
    blend: tBlendMode;
    hasMMX: boolean;
  end;

implementation

procedure putPixel(x,y: integer; col: RGBA;dc: tDrawContext);
begin
  {bounds}
  {push}
  {addressing}
  case dc.width of
  if dc.width = 256 then begin
  end else if isPowerTwo(dc.width) then begin
  end else if dc.width=640 then begin
    {special case}
  end;
  {write}
  case bend of
    BM_BLIT: begin
    end;
    BM_BLEND: begin
    end;
    BM_ADD: begin
    end;
  {pop}
end;

begin
end.