{audio conversion and testing tool}
program aconv;

uses
  {$I baseunits.inc},
  sound,
  keyboard,
  mix,
  crt;

function soundDelta(s1,s2: tSoundEffect): tSoundEffect;
var
  i: int32;
  deltaSample: tAudioSample16S;
begin
  assert(s1.length = s2.length);
  result := tSoundEffect.create(AF_16_STEREO, s1.length);
  {$R-,Q-}
  for i := 0 to result.length-1 do begin
    deltaSample.left := s1.getSample(i).left - s2.getSample(i).left;
    deltaSample.right := s1.getSample(i).right - s2.getSample(i).right;
    result.setSample(i, deltaSample);
  end;
  {$R+,Q+}
end;

procedure go();
var
  music16, music8, musicD: tSoundEffect;
  SAMPLE_LENGTH: int32;
begin

  SAMPLE_LENGTH := 44100 * 60;

  writeln('Loading music.');
  music16 := tSoundEffect.loadFromWave('..\airtime\res\music2.wav', SAMPLE_LENGTH);
  mixer.play(music16, SCS_FIXED1);
  music8 := tSoundEffect.loadFromWave('..\airtime\res\music2.wav', SAMPLE_LENGTH).asFormat(AF_8_STEREO);
  writeln('Processing.');
  musicD := soundDelta(music16, music8);
  writeln('Done.');
  while true do begin
    if keyDown(key_esc) then break;
    if keyDown(key_q) then break;
    if keyDown(key_1) then mixer.channels[1].sfx := music16;
    if keyDown(key_2) then mixer.channels[1].sfx := music8;
    if keyDown(key_3) then mixer.channels[1].sfx := musicD;
  end;
  writeln('Exiting.');
end;

begin
  initKeyboard();
  runTestSuites();
  go();
end.
