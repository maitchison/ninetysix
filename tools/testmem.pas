{check for memory leaks etc.}
program testmem;

uses
  {$I baseunits.inc},
  go32,
  stream,
  crt;

function mem: int64;
begin
  result := getUsedMemory;
end;

{test appending to stream}
procedure testMemoryLeak();
var
  s: tStream;
  initialMem, startMem, endMem, prevMem: int64;
  i: int32;
  data: tBytes;
begin

  data := nil;
  setLength(data, 1*1024);

  {look for memory leak}
  initialMem := mem;
  s := tMemoryStream.Create(0);
  startMem := mem;
  prevMem := startMem;
  {allocate up to 16megs}
  for i := 0 to 16*1024-1 do begin
    if i mod 64 = 0 then begin
      writeln(format('%d: Delta:%, SinceInit:%, Total:%, Pos:%,',[i, prevMem-mem, initialMem-mem, mem, length(data)*i]));
      prevMem := mem;
    end;
    s.writeBytes(data);
    s.setSize(length(data)*i);
  end;
  s.free;
  endMem := mem;
  writeln(format('Memory still allocated %,', [initialMem-endMem]));
  writeln(format('Initial commit %,', [initialMem-startMem]));
end;

begin
  autoHeapSize();
  testMemoryLeak();
end.
