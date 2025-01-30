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

  if assigned(frameSpec^.midUTable) then
    mid := frameSpec^.midUTable^.lookup(mid);
  if assigned(frameSpec^.difUTable) then
    dif := frameSpec^.difUTable^.lookup(dif);

  mid := mid shl frameSpec^.midShift;
  dif := dif shl frameSpec^.difShift;

  left := mid + dif;
  right := mid - dif;

  //note(format('LR:%d,%d MD:%d,%d CLR:%d,%d CODE:%d,%d', [left, right, mid, dif, frameSpec^.cMid, frameSpec^.cDif, midCode, difCode]));

  {$ifdef DEBUG}
  if (left > high(int16)) then
    warning(format('Clipping LO:%d mid:%d dif:%d shift:%d %d [%d]', [abs(left)-high(int16), midCode, difCode, frameSpec^.midShift, frameSpec^.difShift, frameSpec^.idx]));
  if (left < low(int16)) then
    warning(format('Clipping LU:%d mid:%d dif:%d shift:%d %d [%d]', [abs(left)-high(int16), midCode, difCode, frameSpec^.midShift, frameSpec^.difShift, frameSpec^.idx]));
  if (right > high(int16)) then
    warning(format('Clipping RO:%d mid:%d dif:%d shift:%d %d [%d]', [abs(right)-high(int16), midCode, difCode, frameSpec^.midShift, frameSpec^.difShift, frameSpec^.idx]));
  if (right < low(int16)) then
    warning(format('Clipping RU:%d mid:%d dif:%d shift:%d %d [%d]', [abs(right)-high(int16), midCode, difCode, frameSpec^.midShift, frameSpec^.difShift, frameSpec^.idx]));
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
  for i := 0 to (frameSpec^.length-1)-1 do begin
    if midSigns[i] = 0 then midCode += midCodes[i] else midCode -= midCodes[i];
    if difSigns[i] = 0 then difCode += difCodes[i] else difCode -= difCodes[i];
    frameSpec^.idx := i+1;
    sfxSamplePtr^ := generateSample(midCode, difCode, frameSpec);
    inc(sfxSamplePtr);
  end;
end;
