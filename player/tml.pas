{test memory leak}
program tml;

uses
  {$I baseunits.inc},
  go32,
  stream,
  sound,
  la96,
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
  music16: tSoundEffect;
  writer: tLA96Writer;
  i: int32;
  data: tBytes;
begin

  {look for memory leak}
  initialMem := mem;

  music16 := tSoundEffect.loadFromWave(joinPath('sample','sample.wav'));
  writer := tLA96Writer.create();
  writer.open('test.a96');
  writer.writeSFX(music16);
  writer.free();
  music16.free();

  endMem := mem;

  writeln(format('Memory still allocated %,', [endMem-initialMem]));
end;

begin
  autoHeapSize();
  testMemoryLeak();
end.
