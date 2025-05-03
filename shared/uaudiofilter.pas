{a collection of audio filters}
unit uAudiofilter;

{these need to be fast}
{$R-,Q-}

interface

uses
  uDebug,
  uTest,
  uUtils,
  uSound;

function afDelta(s1,s2: tSound;phase: integer=0): tSound;
function afQuantize(s1: tSound;bits: integer): tSound;
function afLowPass(x: tSound;fc: single): tSound;
function afHighPass(const x: tSound;fc: single): tSound;
function afButterworth(x: tSound;fc: single): tSound;

implementation

{----------------------------------------------------------}

function afDelta(s1,s2: tSound;phase: integer=0): tSound;
var
  i: int32;
  deltaSample: tAudioSample16S;
begin
  assert(s1.length = s2.length);
  result := tSound.create(AF_16_STEREO, s1.length);
  for i := 0 to result.length-1 do begin
    deltaSample := s1[i] - s2[i+phase];
    result[i] := deltaSample;
  end;
end;

function afQuantize(s1: tSound;bits: integer): tSound;
var
  i: int32;
  sample: tAudioSample16S;
begin
  result := tSound.create(AF_16_STEREO, s1.length);
  for i := 0 to result.length-1 do begin
    sample := s1[i];
    sample.left := (sample.left shr bits) shl bits;
    sample.right := (sample.right shr bits) shl bits;
    result[i] := sample;
  end;
end;

{compulate a low pass filter via IIR filter
fc: Frequency cutoff}
function afLowPass(x: tSound;fc: single): tSound;
var
  i: int32;
  alpha: single;
  y: tSound;
begin
  alpha := exp(-2.0 * pi * fc / 44100);
  y := tSound.create(AF_16_STEREO, x.length);
  for i := 0 to x.length-1 do
    y[i] := (alpha * tAudioSampleF32(y[i-1])) + ((1-alpha) * tAudioSampleF32(x[i]));
  result := y;
end;

{compulate a low pass filter via IIR filter
fc: Frequency cutoff}
function afHighPass(const x: tSound;fc: single): tSound;
var
  i: int32;
  alpha: single;
  y: tSound;
begin
  alpha := exp(-2.0 * pi * fc / 44100);
  y := tSound.create(AF_16_STEREO, x.length);
  for i := 0 to x.length-1 do
    y[i] := (alpha * tAudioSampleF32(y[i-1])) + (alpha * (tAudioSampleF32(x[i]) - tAudioSampleF32(x[i-1])));
  result := y;
end;

{compulate a low pass filter via Butterworth
fc: Frequency cutoff}
function afButterworth(x: tSound;fc: single): tSound;
var
  i: int32;
  w0, alpha, Q: single;
  b0,b1,b2,a0,a1,a2: single;
  y: tSound;

begin

  // see Audio-EQ-Cookbook.txt

  w0 := 2.0 * pi * fc / 44100;
  Q := 1 / sqrt(2);
  alpha := sin(w0) / (2 * Q);

  b0 := (1 - cos(w0)) / 2;
  b1 := 1 - cos(w0);
  b2 := (1 - cos(w0)) / 2;

  a0 := 1 + alpha;
  a1 := -2 * cos(w0);
  a2 := 1 - alpha;

  b0 /= a0;
  b1 /= a0;
  b2 /= a0;
  a1 /= a0;
  a2 /= a0;
  a0 /= a0;

  y := tSound.create(AF_16_STEREO, x.length);
  for i := 0 to y.length-1 do begin
    y[i] :=
      (b0 * tAudioSampleF32(x[i-0])) +
      (b1 * tAudioSampleF32(x[i-1])) +
      (b2 * tAudioSampleF32(x[i-2])) -
      (a1 * tAudioSampleF32(y[i-1])) -
      (a2 * tAudioSampleF32(y[i-2]));
    if i and $ffff = 0 then write('.');
  end;
  writeln();
  result := y;
end;

begin
end.
