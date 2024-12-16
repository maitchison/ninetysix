{code to be called at startup}
unit startup;

interface

uses
  crt;

implementation

begin
  textAttr := $1f;
  clrscr();
  writeln('Airtime is starting up.');
end.
