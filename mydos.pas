unit myDos;

interface

function detectDos(): string;

implementation

uses utils;

function detectDos(): string;
var
  s: string;
  t: text;
begin
  exec(GetEnv('COMSPEC'), '/c ver > dosver.tmp');
  assign(t, 'dosver.tmp');
  reset(t);
  readln(t, s);
  close(t);
  s := toLowerCase(s);
  if pos('dosbox-x', s) > 0 then
    exit('dosbox-x');
  if pos('dosbox', s) > 0 then
    exit('dosbox');
  exit('dos');
end;

begin
end.
