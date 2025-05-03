{test memory leak}
program tml;

uses
  {$I baseunits.inc},
  go32,
  stream,
  sound,
  la96,
  lc96,
  graph32,
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
  reader: tLA96Reader;
  page: tPage;
  i: int32;
  data: tBytes;
begin

  {look for memory leak}
  initialMem := mem;

  note('Testing tSoundEffect');
  music16 := tSoundEffect.loadFromWave(joinPath('sample','sample.wav'));
  note('Testing tLA96Writer');
  writer := tLA96Writer.create();
  writer.open('test.a96');
  writer.writeSFX(music16);
  writer.free();
  music16.free();

  {LA96 reader}
  note('Testing tLA96reader');
  reader := tLA96Reader.create();
  reader.open('test.a96');
  music16 := reader.readSFX();
  music16.free();
  reader.free();

  {page}
  note('Testing tPage');
  page := tPage.load('res\background.p96');
  page.free;

  endMem := mem;

  writeln(format('Memory still allocated %,', [endMem-initialMem]));
end;

begin
  autoHeapSize();
  testMemoryLeak();
end.
