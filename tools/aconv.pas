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

{compulate a low pass filter via IIR filter
fc: Frequency cutoff}
function IIR(s1: tSoundEffect;fc: single): tSoundEffect;
var
  i: int32;
  y, sample: tAudioSampleF32;
  alpha: single;
begin
  alpha := exp(-2.0 * pi * fc / 44100);
  writeln(format('%.2f %.2ff', [alpha, pi]));
  result := tSoundEffect.create(AF_16_STEREO, s1.length);
  y := s1.getSample(i);
  for i := 0 to result.length-1 do begin
    sample := s1.getSample(i);
    y.left := alpha * y.left + (1-alpha) * sample.left;
    y.right := alpha * y.right + (1-alpha) * sample.right;
    result.setSample(i, y);
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
  music16 := tSoundEffect.loadFromWave('..\airtime\res\music2.wav', SAMPLE_LENGTH);
  mixer.play(music16, SCS_FIXED1);
  musicL := IIR(music16, 10000);
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
