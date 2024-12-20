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

  tProcessAudioProc = procedure(
    samplePos: int32; samplePtr: pointer; sampleLength: dword;
    bufferStart: dword; bufferLen: dword;
    looping: boolean=false;
    startVolume: int32 = 256*256;
    endVolume: int32 = 256*256
  );

procedure process16S_REF(
  samplePos: int32; samplePtr: pointer; sampleLength: dword;
  bufferStart: dword; bufferLen: dword;
  looping: boolean=false;
  startVolume: int32 = 256*256;
  endVolume: int32 = 256*256
);
var
  i: int32;
  volume, volumeDelta: int32;
  sample: pSamples16S;
begin

  if bufferLen = 0 then exit;
  sample := samplePtr;

  volume := startVolume;
  volumeDelta := int32(endVolume-startVolume) div bufferLen;

  for i := 0 to bufferLen-1 do begin
    scratchBufferI32[bufferStart+i].left += int32(sample^[samplePos].left) * (volume div 256);
    scratchBufferI32[bufferStart+i].right += int32(sample^[samplePos].right) * (volume div 256);
    inc(samplePos);
    volume += volumeDelta;
  end;
end;

