{audio conversion and testing tool}
program aconv;

uses
  {$I baseunits.inc},
  sound,
  audioFilter,
  la96,
  keyboard,
  stream,
  mix,
  crt;

procedure go();
var
  music16, musicL, musicD: tSoundEffect;
  SAMPLE_LENGTH: int32;
begin

  SAMPLE_LENGTH := 44100 * 60;

  writeln('Loading music.');
  music16 := tSoundEffect.loadFromWave('c:\dev\masters\bearing 320kbps.wav', SAMPLE_LENGTH);
  mixer.play(music16, SCS_FIXED1);
  writeln('Processing.');
  //musicL := afButterworth(music16, 16000);
  //musicL := afLowPass(music16, 16000);
  musicL := tSoundEffect.loadFromWave('c:\dev\masters\bearing 128kbps.wav', SAMPLE_LENGTH);
  {musicL := afHighPass(music16, 10);     }
  musicD := afDelta(music16, musicL);
  writeln('Done.');
  while true do begin
    if keyDown(key_esc) then break;
    if keyDown(key_q) then break;
    if keyDown(key_1) then mixer.channels[1].sfx := music16;
    if keyDown(key_2) then mixer.channels[1].sfx := musicL;
    if keyDown(key_3) then mixer.channels[1].sfx := musicD;
  end;
  writeln('Exiting.');
end;

procedure testCompression();
var
  music16, musicL, musicD: tSoundEffect;
  SAMPLE_LENGTH: int32;
begin

  writeln('Loading music.');
  music16 := tSoundEffect.loadFromWave('c:\dev\masters\bearing sample.wav', SAMPLE_LENGTH);
  mixer.play(music16, SCS_FIXED1);

  writeln('Compressing.');
  encodeLA96(music16, ACP_MEDIUM).writeToDisk('c:\dev\tools\sample_1.a96');

  writeln('Done.');
end;

function mem: int64;
begin
  result := getUsedMemory;
end;

procedure testMemoryLeak1();
var
  s: tStream;
  initialMem, startMem, endMem, prevMem: int64;
  i: integer;
  data: tBytes;
begin

  {notes:
   no change in free memory until 256k allocated
   no change in used memory until 512k allocated

   }

  {
   I've allocated 1000*4k blocks, so 4 megs, but this has
   taken up all 128MB of ram

  For 16 allocations I'm expecting 64k deltas.

  Ok, delta increases... so yeah we have a resizing problem.

  }

  data := nil;
  setLength(data, 4*1024);

  {look for memory leak}
  initialMem := mem;
  s := tStream.Create(0);
  startMem := mem;
  prevMem := startMem;
  for i := 0 to 512-1 do begin
    if i mod 16 = 0 then begin
      writeln(format('%d: Delta:%, SinceInit:%, Total:%, Pos:%,',[i, prevMem-mem, initialMem-mem, mem, s.pos]));
      prevMem := mem;
    end;
    s.writeBytes(data);
  end;
  s.free;
  endMem := mem;
  writeln(format('Memory still allocated %,', [initialMem-endMem]));
  writeln(format('Initial commit %,', [initialMem-startMem]));
  repeat until keyDown(key_esc);
end;

procedure testMemoryLeak2();
var
  x: tStream;
  initialMem: int64;
  i: integer;
  data: array of byte;
begin
  x := tStream.create();
  initialMem := mem;
  writeln(comma(mem-initialMem));

  data := nil;
  setLength(data, 1024*1024);

  for i := 0 to 15 do begin
    x := tStream.create();
    x.writeBytes(data);
    x.free;
    writeln(comma(mem-initialMem));
  end;

  repeat until keyDown(key_esc);
end;

begin
  runTestSuites();
  initKeyboard();
  //testCompression();
  testMemoryLeak1();
  //testMemoryLeak2();
end.
