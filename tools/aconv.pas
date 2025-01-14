{audio conversion and testing tool}
program aconv;

uses
  {$I baseunits.inc},
  sound,
  audioFilter,
  mixLib,
  la96,
  keyboard,
  timer,
  stream,
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

function getStd(sfx: tSoundEffect): double;
var
  m1,m2,prevValue,value: double;
  variance, mu: double;
  n: int32;
  i: integer;
  x: double;
begin
  m1 := 0;
  m2 := 0;
  n := sfx.length;
  prevValue := 0;
  for i := 0 to n-1 do begin
    value := sfx[i].left - sfx[i].right;

    x := value-prevValue;

    m1 += x;
    m2 += x*x;

    prevValue := value;
  end;
  variance := m2/n;
  mu := m1/n;
  result := sqrt(variance - mu*mu);
end;

procedure testCompression();
var
  music16, musicL, musicD: tSoundEffect;
  SAMPLE_LENGTH: int32;
  profile: tAudioCompressionProfile;
  quantBits: integer;
begin

  writeln('Loading music.');
  writeln('--------------------------');
  music16 := tSoundEffect.loadFromWave('c:\dev\masters\bearing sample.wav');

  mixer.play(music16, SCS_FIXED1);
  mixer.channels[1].looping := true;

  writeln('Compressing.');
  writeln('--------------------------');
  encodeLA96(music16, ACP_LOW, true).writeToDisk('c:\dev\tools\out_low_std.a96');

  printTimers();
  writeln('Done.');

  delay(3000);
end;

begin

  autoHeapSize();

  clrscr;
  textAttr := WHITE;
  debug.WRITE_TO_SCREEN := true;
  logDPMIInfo();

  runTestSuites();
  initKeyboard();
  testCompression();

  textAttr := LIGHTGRAY;

end.
