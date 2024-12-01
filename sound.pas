{Unit for saving and loading sound files.}
unit sound;

{$MODE delphi}

interface

uses
	test,
  debug,
	utils;

type
	tSoundFile = class

  	constructor create(filename: string='');

  	procedure loadFromWave(filename: string);
    procedure loadFromLA96(filename: string);
    procedure saveToLA96(filename: string);
    procedure saveToWave(filename: string);

  end;


implementation


{create soundfile, optionally loading it from disk.}
constructor tSoundFile.create(filename: string='');
var
	extension: string;
begin
	extension := getExtension(filename);
  if extension = 'wav' then
  	loadFromWave(filename)
  else if extension = 'la9' then
  	loadFromLA96(filename);
end;

procedure tSoundFile.loadFromWave(filename: string);
begin
end;

procedure tSoundFile.loadFromLA96(filename: string);
begin
end;

procedure tSoundFile.saveToLA96(filename: string);
begin
end;

procedure tSoundFile.saveToWave(filename: string);
begin
end;

{------------------------------------------------------}

procedure runTests();
begin
end;

begin
	runTests();
end.