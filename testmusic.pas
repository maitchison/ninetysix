{used to prototype music}
program music;

uses
	debug,
  test,
  utils,
	sound;

var
	sfx: tSoundFile;

begin
	sfx := tSoundFile.create('music\music2.wav');
end.
