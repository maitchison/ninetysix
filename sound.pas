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
  dos,
  sbDriver;

type
  {time in samples from start of application.}
  tTimeCode = int64;

  tAudioFormat = (
    AF_16_STEREO,
    AF_8_STEREO
  );

const
  AF_SIZE: array[tAudioFormat] of integer = (
    4,
    2
  );

type
  tAudioSample16S = packed record
    left, right: int16;
  end;

  tAudioSample8S = packed record
    left, right: uint8;
  end;

  pAudioSample16S = ^tAudioSample16S;
  pAudioSample8S = ^tAudioSample8S;

  tAudioSampleF32 = packed record
  {32 bit stereo sample, used for mixing}
    left,right: single;
  end;
  tAudioSampleI32 = packed record
  {32 bit stereo sample, used for mixing}
    left,right: int32;
  end;

  tAudioSample = tAudioSample16S;
  pAudioSample = ^tAudioSample;

  tSoundEffect = class

    data: pointer;
    length: int32;
    format: tAudioFormat;

    constructor create(aFormat: tAudioFormat; aLength: int32);
    destructor destroy();

    function bytesPerSample: int32; inline;

    function getSample(pos: int32): tAudioSample;
    procedure setSample(pos: int32;sample: tAudioSample);

    class function loadFromWave(filename: string): tSoundEffect;

    (*
    class function loadFromFile(filename: string): tSoundEffect;
    class function loadFromLA96(filename: string): tSoundEffect;
    procedure saveToLA96(filename: string);
    procedure saveToWave(filename: string);
    *)

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

constructor tSoundEffect.create(aFormat: tAudioFormat; aLength: int32);
begin
  inherited create();
  length := aLength;
  format := aFormat;
  getMem(data, length * AF_SIZE[format]);
end;

destructor tSoundEffect.destroy();
begin
  if assigned(data) then
    freeMem(data);
  length := 0;
  data := nil;
  inherited destroy();
end;

function tSoundEffect.getSample(pos: int32): tAudioSample;
begin
  if (pos < 0) or (pos >= length) then begin
    fillchar(result, sizeof(result), 0);
    exit;
  end;
  case format of
    AF_16_STEREO: result := pAudioSample16S(data + (pos * 4))^;
    AF_8_STEREO: begin
      result.left := int32(pAudioSample8S(data + (pos * 2))^.left) * 256 - 32768;
      result.right := int32(pAudioSample8S(data + (pos * 2))^.right) * 256 - 32768;
    end;
    else error('Invalid format');
  end;
end;

{bytes per sample}
function tSoundEffect.bytesPerSample: int32; inline;
begin
  result := AF_SIZE[format];
end;

procedure tSoundEffect.setSample(pos: int32; sample: tAudioSample);
begin
  if (pos < 0) or (pos >= length) then begin
    exit;
  end;
  case format of
    AF_16_STEREO: pAudioSample16S(data + (pos * bytesPerSample))^ := sample;
    AF_8_STEREO: begin
      pAudioSample8S(data + (pos * bytesPerSample))^.left := (sample.left div 256) + 128;
      pAudioSample8S(data + (pos * bytesPerSample))^.right := (sample.right div 256) + 128;
    end;
    else error('Invalid format');
  end;
end;

class function tSoundEffect.loadFromWave(filename: string): tSoundEffect;
const
  BLOCK_SIZE = 16*1024;
var
  f: file;
  fileHeader: tWaveFileHeader;
  chunkHeader: tChunkHeader;
  samples: int32;
  i,j: integer;
  ioError: word;
  bytesRemaining: dWord;
  blockSize: int32;
  buffer: array of byte;
  dataPtr: pointer;

function wordAlign(x: int32): int32;
  begin
    result := (x+1) div 2 * 2;
  end;

begin

  try
    fileMode := 0;
    {$I-}
    assign(f, filename);
    reset(f,1);
    {$I+}

    IOError := IOResult;
    if IOError <> 0 then
      error('Could not open file "'+FileName+'" '+GetIOError(IOError));

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
          seek(f, wordAlign(filePos(f) + chunkSize));
          continue;
        end;

        case fileHeader.bitsPerSample of
          16: result := tSoundEffect.create(AF_16_STEREO, chunkSize div 4);
          8: result := tSoundEffect.create(AF_8_STEREO, chunkSize div 2);
          else error('bitsPerSample must be either 8 or 16');
        end;

        bytesRemaining := chunkSize;
        dataPtr := result.data;

        {reading in blocks stop interrupts from being blocked for too
         long on larger files}
        while bytesRemaining > 0 do begin
          blockSize := min(BLOCK_SIZE, bytesRemaining);
          setLength(buffer, blockSize);
          blockRead(f, dataPtr^, blockSize);
          dataPtr += blockSize;
          bytesRemaining -= blocksize;
        end;

        break;
      end;
    end;

  finally
    close(f);
  end;

end;

(*
{create soundfile, optionally loading it from disk.}
function tSoundEffect.loadFromFile(filename: string=''): t;
var
  extension: string;
begin

  sample := nil;
  length := 0;

  extension := toLowerCase(extractExtension(filename));
  if extension = 'wav' then
    loadFromWave(filename)
  else if extension = 'la9' then
    loadFromLA96(filename);
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
  *)

{----------------------------------------------------------}

procedure runTests();
begin
end;

{----------------------------------------------------------}

begin
  runTests();
end.
