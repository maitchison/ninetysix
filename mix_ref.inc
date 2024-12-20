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

procedure process16S_REF(
  samplePos: int32; sample: pSamples16S; sampleLength: dword;
  samplesToProcess: dword;
  looping: boolean=false
);
var
  i: int32;
begin

  for i := 0 to samplesToProcess-1 do begin
    scratchBufferI32[i].left += int32(sample^[samplePos].left) * 256;
    scratchBufferI32[i].right += int32(sample^[samplePos].right) * 256;
    inc(samplePos);
    if samplePos >= sampleLength then begin
      if looping then
        samplePos := 0
      else
        exit;
    end;
  end;
end;

