unit mydos;

interface

function getDosVersion(): string;

var
  DOS_VERSION: string;

implementation

uses utils, dos;

function getDosVersion(): string;
var
  s: string;
  t: text;
begin
  try
    {note: this seems to kill music for some reason}
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
    if pos('windows 98', s) > 0 then
      exit('win98');
    exit('dos');
  except
    exit('unknown');
  end;
end;

begin
  DOS_VERSION := getDosVersion();
end.
