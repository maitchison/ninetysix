program sndTest;

uses
  la96,
  stream,
  sound;

var
  sfx: tSoundEffect;
  s: tStream;

begin
  sfx := tSoundEffect.create();
  sfx.LoadFromWave('res\music1.wav');
  s := encodeLA96(sfx);

  s.writeToDisk('test.a96');
end.
