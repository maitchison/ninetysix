{code to be called at startup}
unit startup;

interface

uses
  crt, debug;

implementation

begin
  textAttr := $1f;
  clrscr();
  writeln('Airtime is starting up.');
  debug.VERBOSE_SCREEN := llInfo;
end.
