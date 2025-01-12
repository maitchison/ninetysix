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

  tAudioFormat = (
    AF_INVALID,
    AF_16_STEREO,
    AF_8_STEREO,
    AF_16_MONO,
    AF_8_MONO
  );

const
  AF_SIZE: array[tAudioFormat] of integer = (
    0,
    4,
    2,
    2,
    1
  );

type
  tAudioSample16S = packed record
    left, right: int16;
    class operator subtract(a,b: tAudioSample16S): tAudioSample16S;
  end;
  tAudioSample8S = packed record
    left, right: uint8;
  end;
  tAudioSample16M = packed record
  case byte of
    0: (value: int16);
    1: (left: int16);
    2: (right: int16);
  end;
  tAudioSample8M = packed record
  case byte of
    0: (value: byte);
    1: (left: byte);
    2: (right: byte);
  end;

  pAudioSample16S = ^tAudioSample16S;
  pAudioSample8S = ^tAudioSample8S;
  pAudioSample16M = ^tAudioSample16M;
  pAudioSample8M = ^tAudioSample8M;

  tAudioSampleF32 = packed record
  {32 bit stereo sample, used for mixing}
    left,right: single;
    class operator implicit(a: tAudioSampleF32): tAudioSample16S;
    class operator implicit(a: tAudioSample16S): tAudioSampleF32;
    class operator add(a,b: tAudioSampleF32): tAudioSampleF32;
    class operator subtract(a,b: tAudioSampleF32): tAudioSampleF32;
    class operator multiply(a: tAudioSampleF32;b: single): tAudioSampleF32;
    class operator multiply(b: single; a: tAudioSampleF32): tAudioSampleF32;
    class operator multiply(b: single; a: tAudioSample16S): tAudioSampleF32;
  end;
  tAudioSampleI32 = packed record
  {32 bit stereo sample, used for mixing}
    left,right: int32;
  end;

  tAudioSample = tAudioSample16S;
  pAudioSample = ^tAudioSample;

  tSoundEffect = class

    tag: string;
    data: pointer;
    length: int32;        // number of samples
    format: tAudioFormat;

    constructor create(aFormat: tAudioFormat=AF_16_STEREO; aLength: int32=0; aTag: string='');
    destructor destroy();

    function toString(): string;

    function bytesPerSample: int32; inline;

    function asFormat(af: tAudioFormat): tSoundEffect;
    function getSample(pos: int32): tAudioSample;
    procedure setSample(pos: int32;sample: tAudioSample);

    class function loadFromWave(filename: string;maxSamples: int32=-1): tSoundEffect;
    class function createNoise(duration: single): tSoundEffect;

    property items[index: int32]: tAudioSample read getSample write setSample; default;

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

function getAudioFormat(bitsPerChannel: integer; numChannels: integer): tAudioFormat;
begin
  case numChannels of
    1: case bitsPerChannel of
      8: exit(AF_8_MONO);
      16: exit(AF_16_MONO);
    end;
    2: case bitsPerChannel of
      8: exit(AF_8_STEREO);
      16: exit(AF_16_STEREO);
    end;
  end;
  exit(AF_INVALID);
end;

{--------------------------------------------------------}

class operator tAudioSample16S.subtract(a,b: tAudioSample16S): tAudioSample16S;
begin
  result.left  := clamp16(a.left - b.left);
  result.right := clamp16(a.right - b.right);
end;

class operator tAudioSampleF32.implicit(a: tAudioSample16S): tAudioSampleF32;
begin
  result.left  := a.left;
  result.right := a.right;
end;

class operator tAudioSampleF32.implicit(a: tAudioSampleF32): tAudioSample16S;
begin
  result.left  := clamp16(a.left);
  result.right := clamp16(a.right);
end;

class operator tAudioSampleF32.add(a,b: tAudioSampleF32): tAudioSampleF32;
begin
  result.left  := a.left + b.left;
  result.right := a.right + b.right;
end;

class operator tAudioSampleF32.subtract(a,b: tAudioSampleF32): tAudioSampleF32;
begin
  result.left  := a.left - b.left;
  result.right := a.right - b.right;
end;

class operator tAudioSampleF32.multiply(a: tAudioSampleF32;b: single): tAudioSampleF32;
begin
  result.left  := a.left * b;
  result.right := a.right * b;
end;

class operator tAudioSampleF32.multiply(b: single; a: tAudioSampleF32): tAudioSampleF32;
begin
  result.left  := a.left * b;
  result.right := a.right * b;
end;

class operator tAudioSampleF32.multiply(b: single; a: tAudioSample16S): tAudioSampleF32;
begin
  result.left  := a.left * b;
  result.right := a.right * b;
end;

{--------------------------------------------------------}

constructor tSoundEffect.create(aFormat: tAudioFormat; aLength: int32; aTag: string='');
begin
  inherited create();
  length := aLength;
  format := aFormat;
  tag := aTag;
  getMem(data, length * AF_SIZE[format]);
end;

destructor tSoundEffect.destroy();
begin
  if assigned(data) then
    freeMem(data);
  length := 0;
  data := nil;
  tag := '';
  inherited destroy();
end;

function tSoundEffect.toString(): string;
begin
  exit(tag);
end;

{returns copy of sound in 16bit-stereo format.}
function tSoundEffect.asFormat(af: tAudioFormat): tSoundEffect;
var
  i: int32;
begin
  result := tSoundEffect.create(af, self.length, self.tag);
  for i := 0 to self.length-1 do
    result.setSample(i, self.getSample(i));
end;


function tSoundEffect.getSample(pos: int32): tAudioSample;
begin
  if (pos < 0) or (pos >= length) then begin
    fillchar(result, sizeof(result), 0);
    exit;
  end;
  case format of
    AF_16_STEREO: result := pAudioSample16S(data + (pos * 4))^;
    AF_16_MONO: begin
      result.left := pAudioSample16M(data + (pos * 2))^.value;
      result.right := pAudioSample16M(data + (pos * 2))^.value;
    end;
    AF_8_STEREO: begin
      result.left := int32(pAudioSample8S(data + (pos * 2))^.left) * 256 - 32768;
      result.right := int32(pAudioSample8S(data + (pos * 2))^.right) * 256 - 32768;
    end;
    AF_8_MONO: begin
      result.left := int32(pAudioSample8M(data + (pos * 1))^.value) * 256 - 32768;
      result.right := int32(pAudioSample8M(data + (pos * 1))^.value) * 256 - 32768;
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

class function tSoundEffect.createNoise(duration: single): tSoundEffect;
var
  i: int32;
  numSamples: dWord;
  sample: tAudioSample;
begin
  numSamples := trunc(44100 * duration);
  result := tSoundEffect.create(AF_16_STEREO, numSamples);
  for i := 0 to numSamples-1 do begin
    sample.left := (rnd+rnd-256)*64;
    sample.right := (rnd+rnd-256)*64;
    result.setSample(i, sample);
  end;
  result.tag := 'noise';
end;

class function tSoundEffect.loadFromWave(filename: string;maxSamples: int32=-1): tSoundEffect;
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
  dataPtr: pointer;
  af: tAudioFormat;
  samplesToRead: dword;

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

      if frequency <> 44100 then
        error(utils.format('frequency must be 44100 but was %d', [frequency]));

      // will error if not valid
      af := getAudioFormat(bitsPerSample, numChannels);
      if af = AF_INVALID then
        error(utils.format('Invalid audio format %d-bit %d channels.', [bitsPerSample, numChannels]));
    end;

    {process the chunks}
    while True do begin
      blockRead(f, chunkHeader, sizeof(chunkHeader));
      with chunkHeader do begin
        if chunkBlockID <> 'data' then begin
          seek(f, wordAlign(filePos(f) + chunkSize));
          continue;
        end;

        samplesToRead := chunkSize div AF_SIZE[af];
        if maxSamples > 0 then samplesToRead := min(samplesToRead, maxSamples);

        result := tSoundEffect.create(af, samplesToRead, filename);

        bytesRemaining := samplesToRead * AF_SIZE[af];
        dataPtr := result.data;

        {reading in blocks stop interrupts from being blocked for too
         long on larger files}
        while bytesRemaining > 0 do begin
          blockSize := min(BLOCK_SIZE, bytesRemaining);
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
