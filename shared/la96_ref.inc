
function generateSample(midCode, difCode: int32;frameSpec: pFrameSpec): tAudioSample16S; inline;
var
  mid, dif: int32;
  left,right: int32;
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
{  frameSpec^.cMid := mid and frameSpec^.centerMask;
  frameSpec^.cDif := dif and frameSpec^.centerMask;}
  frameSpec^.cMid := (mid shr 8) shl 8;
  frameSpec^.cDif := (dif shr 8) shl 8;

  result.left := (mid + dif) div 2;
  result.right := (mid - dif) div 2;

  {$ifdef DEBUG}
  //if (result.left <> left) or (result.right <> right) then
  //  writeln(format('Clipping L:%d R:%d mid:%d dif:%d shift:%d %d', [left, right, midCode, difCode, frameSpec^.midShift, frameSpec^.difShift]));
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
    sfxSamplePtr^ := generateSample(midCode, difCode, frameSpec);
    inc(sfxSamplePtr);
  end;
end;
