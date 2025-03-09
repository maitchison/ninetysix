{reference routines for graph32, with full DrawContext support}

{note:
 at this point we assume all clipping and transform is done
}

{very slow blending}
procedure blend_REF(pixels: pRGBA;count: int32;col: RGBA);
var
  i: integer;
  f: single;
begin
  f := (col.a/255);
  for i := 0 to count-1 do begin
    pixels^ := RGBA.Lerp(pixels^, col, f);
    inc(pixels);
  end;

end;
