uses
  crt,
  dos;

var
  s: string;
  t: text;

begin
  clrscr;
  exec(GetEnv('COMSPEC'), '/c ver > dosver.tmp');
  assign(t, 'dosver.tmp');
  reset(t);
  readln(t, s);
  close(t);
  writeln(s);
end.