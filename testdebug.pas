program testdebug;

{
LineNumber is wrong if 'const' is used.
Only is a problem when using 'debug', which means I'm doing something
wrong.
}

uses
  debug;

procedure a();
const
  x = 20;
begin
  runError(216);
end;

begin
  a();
end.
