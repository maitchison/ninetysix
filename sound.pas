{Unit for saving and loading sound files.}
unit sound;

{$MODE delphi}

{todo:
	support load load of wave files (via getsample)
  support pitch and volume (via get sample)
  support fade and and fade out (via get sample)

  todo: split mixer and sound
}


interface

uses
	test,
  debug,
	utils,
  sbDriver;

type
	{time in samples from start of application.}
  tTimeCode = int64;

  tAudioSample = packed record
  {16 bit stereo sample}
  case byte of
		0: (left,right: int16);
  	1: (value: dword);
  end;

  pAudioSample = ^tAudioSample;

  tAudioSampleF32 = packed record
  {32 bit stereo sample, used for mixing}
		left,right: single;
  end;
  tAudioSampleI32 = packed record
  {32 bit stereo sample, used for mixing}
		left,right: int32;
  end;

	tSoundEffect = class

  	sample: array of tAudioSample;

    constructor create(filename: string='');

  	procedure loadFromWave(filename: string);
    procedure loadFromLA96(filename: string);
    procedure saveToLA96(filename: string);
    procedure saveToWave(filename: string);

  end;

implementation

uses
	mix;

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
constructor tSoundEffect.create(filename: string='');
var
	extension: string;
begin

	sample := nil;

	extension := getExtension(filename);
  if extension = 'wav' then
  	loadFromWave(filename)
  else if extension = 'la9' then
  	loadFromLA96(filename);
end;


{-----------------------------------------------------}

procedure tSoundEffect.loadFromWave(filename: string);
var
	f: file;
  fileHeader: tWaveFileHeader;
  chunkHeader: tChunkHeader;
  samples: int32;
  i,j: integer;
  samplesToRead: dword;
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
        samplesToRead := min(chunkWords div 2, 16*1024*1024);
        if (samplesToRead < chunkWords div 2) then
        	warn(format('Wave file too large to read (%f MB), reading partial file.', [chunkSize/1024/1024]));
  			sample := nil;
        setLength(sample, samplesToRead);
        blockRead(f, sample[0], samplesToRead*4);
        break;
      end;
    end;

  finally      	
	  close(f);
  end;
	
end;

procedure tSoundEffect.loadFromLA96(filename: string);
begin
end;

procedure tSoundEffect.saveToLA96(filename: string);
begin
end;

procedure tSoundEffect.saveToWave(filename: string);
begin
end;


{----------------------------------------------------------}

procedure runTests();
begin
end;

{----------------------------------------------------------}

begin
	runTests();
end.
