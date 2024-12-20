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

procedure process8S_REF(sample, firstSample, finalSample: pAudioSample8S;count: dword);
var
  i: int32;
begin
  for i := 0 to count-1 do begin
    scratchBufferI32[i].left += (int32(sample^.left)-128) * 65536;
    scratchBufferI32[i].right += (int32(sample^.right)-128) * 65536;
    inc(sample);
    if sample >= finalSample then
      sample := pointer(firstSample);
  end;
end;

procedure process16S_REF(sample, firstSample, finalSample: pAudioSample16S;count: dword);
var
  i: int32;
begin
  for i := 0 to count-1 do begin
    scratchBufferI32[i].left += int32(sample^.left) * 256;
    scratchBufferI32[i].right += int32(sample^.right) * 256;
    inc(sample);
    if sample >= finalSample then
      sample := pointer(firstSample);
  end;
end;

