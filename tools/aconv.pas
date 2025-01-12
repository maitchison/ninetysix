{audio conversion and testing tool}
program aconv;

uses
  {$I baseunits.inc},
  sound,
  audioFilter,
  la96,
  keyboard,
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

begin
  initKeyboard();
  runTestSuites();
  testCompression();
end.
