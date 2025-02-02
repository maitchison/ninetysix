{very simple disk benchmark}
program diskmark;

{initial:

8MB File in 4k chunks

write 2.11MB/s
read  1.96MB/s

[AFTER DMA]

4K
write 2.40MB/s
read  4.80MB/s (I think this was cached though)


}

uses
  utils,
  test,
  debug,
  timer;

var
  data: array[0..65536-1] of byte;

const
  BLOCKS = 2*1024;

procedure write4k();
var
  f: file;
  i: integer;
begin
  assign(f, 'temp.dat');
  rewrite(f, 1);
  startTimer('write4k');
  for i := 1 to BLOCKS do begin
    blockwrite(f, data, 4*1024);
    if i mod 64 = 0 then write('.');
  end;
  stopTimer('write4k');
  close(f);
  writeln();
  writeln(format('Write speed (4k)    %.2fMB/S', [(BLOCKS*4/1024)/getTimer('write4k').elapsed]));
end;

procedure read4k();
var
  f: file;
  i: integer;
begin
  assign(f, 'temp.dat');
  reset(f, 1);
   startTimer('read4k');
  for i := 1 to BLOCKS do begin
    blockread(f, data, 4*1024);
    if i mod 64 = 0 then write('.');
  end;
  stopTimer('read4k');
  close(f);
  writeln();
  writeln(format('Read speed (4k)     %.2fMB/S', [(BLOCKS*4/1024)/getTimer('read4k').elapsed]));
end;

begin
  writeln('Performing disk benchmark');
  write4k();
  read4k();
end.
