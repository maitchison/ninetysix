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

type
  tSamples16S = array[0..65536-1] of tAudioSample16S;
  pSamples16S = ^tSamples16S;
  tSamples16M = array[0..65536-1] of tAudioSample16M;
  pSamples16M = ^tSamples16M;

  tProcessAudioProc = procedure(
    sampleTick: int32; samplePtr: pointer; sampleLength: dword;
    bufferPos: int32; count: int32;
    startVolume: int32 = 256*256;
    endVolume: int32 = 256*256;
    pitch: int32 = 256
  );

procedure process16S_REF(
  sampleTick: int32; samplePtr: pointer; sampleLength: dword;
  bufferPos: int32; count: int32;
  startVolume: int32 = 256*256;
  endVolume: int32 = 256*256;
  pitch: int32 = 256
);
var
  i: int32;
  volume, volumeDelta: int32;
  sample: pSamples16S;
begin

  if count <= 0 then exit;
  sample := samplePtr;

  volume := startVolume;
  volumeDelta := int32(endVolume-startVolume) div count;

  for i := 0 to count-1 do begin
    scratchBufferI32[bufferPos+i].left += int32(sample^[sampleTick shr 8].left) * (volume div 256);
    scratchBufferI32[bufferPos+i].right += int32(sample^[sampleTick shr 8].right) * (volume div 256);
    sampleTick += pitch;
    volume += volumeDelta;
  end;
end;

procedure process16M_REF(
  sampleTick: int32; samplePtr: pointer; sampleLength: dword;
  bufferPos: int32; count: int32;
  startVolume: int32 = 256*256;
  endVolume: int32 = 256*256;
  pitch: int32 = 256
);
var
  i: int32;
  volume, volumeDelta: int32;
  sample: pSamples16M;
  value: int32;
begin

  if count <= 0 then exit;
  sample := samplePtr;

  volume := startVolume;
  volumeDelta := int32(endVolume-startVolume) div count;

  for i := 0 to count-1 do begin
    value := int32(sample^[sampleTick shr 8].value) * (volume div 256);
    scratchBufferI32[bufferPos+i].left += value;
    scratchBufferI32[bufferPos+i].right += value;
    sampleTick += pitch;
    volume += volumeDelta;
  end;
end;

