unit wave;

interface

uses
  resource,
  sound;

procedure loadWave(filename: string): tSoundEffect;
procedure saveWave(filename: string;sfx: tSoundEffect);

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
    bytePerBlock: word;
    bitsPerSample: word;
  end;

  tChunkHeader = packed record
    chunkBlockID: array[0..3] of char;
    chunkSize: dword;
  end;

function loadWave(filename: string): tSoundEffect;
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
      error('Could not open file "'+FileName+'" '+getIOErrorString(IOError));

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

      if audioFormat <> 1 then
        error(utils.format('format must be 1 (PCM) but was %d', [audioFormat]));

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

{saves sound file to a wave file}
procedure saveWave(filename: string;sfx: tSoundEffect);
var
  f: file;
  fileHeader: tWaveFileHeader;
  chunkHeader: tChunkHeader;
  chunkBytes: int32;
  IOError: word;
begin

  fileMode := 0;
  {$I-}
  assign(f, filename);
  rewrite(f,1);
  {$I+}

  IOError := IOResult;
  if IOError <> 0 then
    error('Could not open file "'+FileName+'" for output.'+getIOErrorString(IOError));

  chunkBytes := length * 4;

  with fileHeader do begin
    fileTypeBlockID := 'RIFF';
    fileSize        := 36 + chunkBytes;
    fileFormatId    := 'WAVE';
    formatBlockID   := 'fmt ';
    blockSize       := 16;
    audioFormat     := 1; {PCM}
    numChannels     := 2;
    frequency       := 44100;
    bytePerSec      := chunkBytes*2;
    bytePerBlock    := 4; // chanels * bitsPerSample / 8
    bitsPerSample   := 16;
  end;

  with chunkHeader do begin
    chunkBlockID := 'data';
    chunkSize := chunkBytes;
  end;

  blockwrite(f, fileHeader, sizeof(fileHeader));
  blockwrite(f, chunkHeader, sizeof(chunkHeader));
  blockwrite(f, data^, chunkBytes);

  close(f);
end;

begin
  registerResourceLoader('wav', @loadWave);
end.