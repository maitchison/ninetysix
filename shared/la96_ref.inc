function generateSample(midValue, difValue: int16;frameSpec: pFrameSpec): tAudioSample16S;
var
  mid, dif: int32;
  left,right: int32;
  shift: byte;
begin

  mid := midValue;
  dif := difValue;

  if assigned(frameSpec^.midUTable) then
    mid := frameSpec^.midUTable^.lookup(mid);
  if assigned(frameSpec^.difUTable) then
    dif := frameSpec^.difUTable^.lookup(dif);

  mid := mid shl frameSpec^.midShift;
  dif := dif shl frameSpec^.difShift;

  left := mid + dif;
  right := mid - dif;

  //note(format('LR:%d,%d MD:%d,%d CLR:%d,%d CODE:%d,%d', [left, right, mid, dif, frameSpec^.cMid, frameSpec^.cDif, midValue, difValue]));

  {clipping on decoder is now required...}
  result.left := clamp16(left);
  result.right := clamp16(right);
end;

procedure process_REF(sfxSamplePtr: pAudioSample16S; midValue, difValue: int16; midCodes,difCodes: tWords; frameSpec: pFrameSpec);
var
  i: int32;
begin
  for i := 0 to (frameSpec^.length-1)-1 do begin
    {note: codes should wrap}
    midValue := int16(midValue + zagZig(midCodes[i]));
    difValue := int16(difValue + zagZig(difCodes[i]));
    frameSpec^.idx := i+1;
    sfxSamplePtr^ := generateSample(midValue, difValue, frameSpec);
    inc(sfxSamplePtr);
  end;
end;

procedure postProcessEMA(samplePtr: pAudioSample16S; out left: single; out right: single; count: int32; alpha: single);
var
  i: integer;
  sample: tAudioSample16S;
begin
  for i := 0 to count-1 do begin
    left := (alpha) * left + ((alpha-1) * samplePtr^.left);
    right := (alpha) * right + ((alpha-1) * samplePtr^.right);
    samplePtr^.left := round(left);
    samplePtr^.right := round(right);
    inc(samplePtr);
  end;
end;