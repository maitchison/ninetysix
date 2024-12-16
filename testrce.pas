{test range check error}
program testrce;

var
  b: byte;
  i: integer;

begin
  for i := 0 to 1000 do
    inc(b);
end.