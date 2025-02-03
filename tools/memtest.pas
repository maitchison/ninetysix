{see how much mem we can actually allocate}
program memtest;

var
  i: integer;
  p: pointer;

begin

  getmem(p, 26*1024*1024);
  freemem(p);

  for i := 1 to 640 do begin
    writeln('Allocating ', 128*1024*i div 1024, 'KB');
    getMem(p, 128*1024*i);
    freeMem(p);
  end;
end.
