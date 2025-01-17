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

function generateSample(midCode, difCode: int32;frameSpec: pFrameSpec): tAudioSample16S; {stub: inline}
var
  mid, dif: int32;
  left,right: int32;
  shift: byte;
begin

  mid := midCode;
  dif := difCode;

  {we inline these as it's a bit faster}
  if assigned(frameSpec^.midUTable) then begin
    mid := frameSpec^.midUTable^.table.data[abs(mid)];
    if midCode < 0 then mid := - mid;
  end;
  if assigned(frameSpec^.difUTable) then begin
    dif := frameSpec^.difUTable^.table.data[abs(dif)];
    if difCode < 0 then dif := - dif;
  end;

  mid := (mid shl frameSpec^.midShift) + frameSpec^.cMid;
  dif := (dif shl frameSpec^.difShift) + frameSpec^.cDif;

  {keep track of centering}
  shift := frameSpec^.centerShift;
  frameSpec^.cMid := mid shr shift shl shift;
  frameSpec^.cDif := dif shr shift shl shift;

  left := (mid + dif);
  right := (mid - dif);

  {$ifdef DEBUG}
  if (left > high(int16)) then
    warn(format('Clipping LO:%d mid:%d dif:%d shift:%d %d [%d]', [abs(left)-high(int16), midCode, difCode, frameSpec^.midShift, frameSpec^.difShift, frameSpec^.idx]));
  if (left < low(int16)) then
    warn(format('Clipping LU:%d mid:%d dif:%d shift:%d %d [%d]', [abs(left)-high(int16), midCode, difCode, frameSpec^.midShift, frameSpec^.difShift, frameSpec^.idx]));
  if (right > high(int16)) then
    warn(format('Clipping RO:%d mid:%d dif:%d shift:%d %d [%d]', [abs(right)-high(int16), midCode, difCode, frameSpec^.midShift, frameSpec^.difShift, frameSpec^.idx]));
  if (right < low(int16)) then
    warn(format('Clipping RU:%d mid:%d dif:%d shift:%d %d [%d]', [abs(right)-high(int16), midCode, difCode, frameSpec^.midShift, frameSpec^.difShift, frameSpec^.idx]));
  result.left := clamp16(left);
  result.right := clamp16(right);
  {$else}
  result.left := left;
  result.right := right;
  {$endif}
end;

procedure process_REF(sfxSamplePtr: pAudioSample16S; midCode, difCode: int32; midCodes,difCodes,midSigns,difSigns: tDwords; frameSpec: pFrameSpec);
var
  i: int32;
begin
  // reference, 0.5ms
  for i := 0 to (frameSpec^.length-1)-1 do begin
    if midSigns[i] > 0 then midCode -= midCodes[i] else midCode += midCodes[i];
    if difSigns[i] > 0 then difCode -= difCodes[i] else difCode += difCodes[i];
    frameSpec^.idx := i+1;
    sfxSamplePtr^ := generateSample(midCode, difCode, frameSpec);
    inc(sfxSamplePtr);
  end;
end;
