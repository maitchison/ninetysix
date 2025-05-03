procedure clipAndConvert_REF(bufSamples:int32);
var
  i: int32;
  left,right: int32;
begin
  for i := 0 to bufSamples-1 do begin
    left := (scratchBufferI32[i].left) div 256;
    right := (scratchBufferI32[i].right) div 256;
    if left > 32767 then left := 32767 else if left < -32768 then left := -32768;
    if right > 32767 then right := 32767 else if right < -32768 then right := -32768;
    scratchBuffer[i].left := left;
    scratchBuffer[i].right := right;
  end;
end;

{outputs largest delta between samples}
function clickDetection_REF(prevSample: tAudioSample16S;samplePtr: pAudioSample16S; bufSamples:dword): int32;
var
  i : integer;
  best: int32;
  delta: int32;
begin
  best := 0;
  for i := 0 to bufSamples-1 do begin
    delta := abs(samplePtr^.left-prevSample.left);
    if delta > best then best := delta;
    delta := abs(samplePtr^.right-prevSample.right);
    if delta > best then best := delta;
    prevSample := samplePtr^;
    inc(samplePtr);
  end;
  result := best;
end;

{Copies a 16S source directly into the 32bit buffer (e.g. for initialization)}
procedure initializeBuffer_REF(samplePtr: pAudioSample16S; bufSamples: int32);
var
  i: int32;
  left,right: int32;
begin
  for i := 0 to bufSamples-1 do begin
    scratchBufferI32[i].left := samplePtr^.left*256;
    scratchBufferI32[i].right := samplePtr^.right*256;
    inc(samplePtr);
  end;
end;

type
  tProcessAudioProc = function(
    af: tAudioFormat;
    sampleTick: int32; samplePtr: pointer; sampleLength: dword;
    bufferPos: int32; count: int32;
    startVolume: int32 = 256*256;
    endVolume: int32 = 256*256;
    pitch: int32 = 256
  ): boolean;

function processAudio_REF(
  af: tAudioFormat;
  sampleTick: int32; samplePtr: pointer; sampleLength: dword;
  bufferPos: int32; count: int32;
  startVolume: int32 = 256*256;
  endVolume: int32 = 256*256;
  pitch: int32 = 256
): boolean;
var
  i: int32;
  volume, volumeDelta: int32;
  left, right: int32;
  sampleWidth: integer;
  bits: byte;
  channels: byte;
  sample: pointer;
begin

  if count <= 0 then exit(true);

  sampleWidth := AF_SIZE[af];
  if sampleWidth = 0 then exit(false);

  volume := startVolume;
  volumeDelta := int32(endVolume-startVolume) div count;

  for i := 0 to count-1 do begin

    sample := samplePtr + (sampleTick shr 8) * sampleWidth;

    case af of
      AF_16_STEREO: begin
        left := int32(pInt16(sample)^);
        right := int32(pInt16(sample+2)^);
        end;
      AF_8_STEREO: begin
        left := (int32(pByte(sample)^) - 128) * 256;
        right := (int32(pByte(sample+1)^) - 128) * 256;
        end;
      AF_16_MONO: begin
        left := int32(pInt16(sample)^);
        right := left;
        end;
      AF_8_MONO: begin
        left := (int32(pByte(sample)^) - 128) * 256;
        right := left;
        end;
      else begin
        left := 0;
        right := 0;
        end;
    end;

    scratchBufferI32[bufferPos].left += left * (volume div 256);
    scratchBufferI32[bufferPos].right += right * (volume div 256);

    sampleTick += pitch;
    volume += volumeDelta;
    inc(bufferPos);
  end;

  exit(true);
end;
