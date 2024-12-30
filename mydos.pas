unit mydos;

interface

function getDosVersion(): string;

implementation

uses utils, dos;

function getDosVersion(): string;
var
  s: string;
  t: text;
begin
  try
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
  except
    exit('unknown');
  end;
end;

begin
end.
