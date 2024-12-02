{used to prototype music}
program music;

uses
	screen,
  graph32,
	debug,
  test,
  utils,
  sbDriver,
	sound;

var
	sfx: tSoundFile;

  background: tPage;

begin

	setMode(640,480,32);

	sfx := tSoundFile.create('music\music2.wav');

  setText();
  printLog();
end.
