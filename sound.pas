{Unit for saving and loading sound files.}
unit sound;

{$MODE delphi}

interface

uses
	test,
  debug,
	utils,
  sbDriver;

type

	tWaveform = array of word;

	tSoundFile = class

  public

  	data: tWaveform;

  public

  	constructor create(filename: string='');

  	procedure loadFromWave(filename: string);
    procedure loadFromLA96(filename: string);
    procedure saveToLA96(filename: string);
    procedure saveToWave(filename: string);

    procedure play();

  end;


implementation

type
	tWaveFileHeader = packed record
  	fileTypeBlockID: array[0..3] of char;
    fileSize: dword;
    fileFormatId: array[0..3] of char;
    formatBlockID: array[0..3] of char;
    blockSize: dword;
    audioFormat: word;
    numChannels: word;
    frequency: dword;
    bytePerSec: dword;
    bytesPerBlock: word;
    bitsPerSample: word;
  end;

  tChunkHeader = packed record
  	chunkBlockID: array[0..3] of char;
    chunkSize: dword;
  end;

{--------------------------------------------------------}

{create soundfile, optionally loading it from disk.}
constructor tSoundFile.create(filename: string='');
var
	extension: string;
begin

	data := nil;

	extension := getExtension(filename);
  if extension = 'wav' then
  	loadFromWave(filename)
  else if extension = 'la9' then
  	loadFromLA96(filename);
end;

procedure tSoundFile.loadFromWave(filename: string);
var
	f: file;
  fileHeader: tWaveFileHeader;
  chunkHeader: tChunkHeader;
  samples: int32;
  i,j: integer;
  wordsToRead: dword;
  chunkWords: dword;

function wordAlign(x: int32): int32;
  begin
  	result := (x+1) div 2 * 2;
  end;

begin

	try
    fileMode := 0;
  	assign(f, filename);
    reset(f,1);

    blockread(f, fileHeader, sizeof(fileHeader));

    with fileHeader do begin
  	  if fileTypeBlockID <> 'RIFF' then
    		Error('Invalid BlockID '+fileTypeBLockID);

  	  if fileFormatID <> 'WAVE' then
      	Error('Invalid FormatID '+fileFormatID);

      if formatBlockID <> 'fmt ' then
      	Error('Invalid formatBlockID '+formatBlockID);

      if numChannels <> 2 then
      	Error('numChannels must be 2');

      if frequency <> 44100 then
      	Error('frequency must be 44100');

  	end;

    {process the chunks}
    while True do begin
  	  blockRead(f, chunkHeader, sizeof(chunkHeader));
      with chunkHeader do begin
      	if chunkBlockID <> 'data' then begin
        	writeln('skipping '+chunkBlockID);
        	seek(f, wordAlign(filePos(f) + chunkSize));
          continue;
        end;
        chunkWords := chunkSize div 2;
        wordsToRead := min(chunkWords, 32*1024*1024);
        if (wordsToRead < chunkWords) then
        	warn(format('Wave file too large to read (%f MB), reading partial file.', [chunkSize/1024/1024]));
  			data := nil;
        setLength(data, wordsToRead);
        blockRead(f, data[0], wordsToRead*2);
        break;
      end;
    end;

  finally      	
	  close(f);
  end;
	
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

procedure tSoundFile.play();
begin
	{for the moment just play as 'music'}
  sbDriver.backgroundPCMData(self.data);
end;

{------------------------------------------------------}

procedure runTests();
begin
end;

begin
	runTests();
end.
