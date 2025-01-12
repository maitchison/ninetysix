{audio conversion and testing tool}
program aconv;

uses
  {$I baseunits.inc},
  sound,
  keyboard,
  mix,
  crt;

{these need to be fast}
{$R-,Q-}
function soundDelta(s1,s2: tSoundEffect): tSoundEffect;
var
  i: int32;
  deltaSample: tAudioSample16S;
  sample1, sample2: tAudioSample16S;
begin
  assert(s1.length = s2.length);
  result := tSoundEffect.create(AF_16_STEREO, s1.length);

  for i := 0 to result.length-1 do begin
    deltaSample := s1.getSample(i) - s2.getSample(i);
    result.setSample(i, deltaSample);
  end;
end;

function soundQuant(s1: tSoundEffect;bits: integer): tSoundEffect;
var
  i: int32;
  sample: tAudioSample16S;
begin
  result := tSoundEffect.create(AF_16_STEREO, s1.length);
  for i := 0 to result.length-1 do begin
    sample := s1.getSample(i);
    sample.left := (sample.left shr bits) shl bits;
    sample.right := (sample.right shr bits) shl bits;
    result.setSample(i, sample);
  end;
end;
{$R+,Q+}

procedure go();
var
  music16, musicL, musicD: tSoundEffect;
  SAMPLE_LENGTH: int32;
begin

  SAMPLE_LENGTH := 44100 * 45;

  writeln('Loading music.');
  music16 := tSoundEffect.loadFromWave('..\airtime\res\music1.wav', SAMPLE_LENGTH);
  mixer.play(music16, SCS_FIXED1);
  musicL := soundQuant(music16, 7);
  writeln('Processing.');
  musicD := soundDelta(music16, musicL);
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

begin
  initKeyboard();
  runTestSuites();
  go();
end.
