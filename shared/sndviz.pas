{sound vizualizor... very simple}
unit sndViz;

interface

uses
  debug,
  test,
  sound,
  utils,
  graph2d,
  myMath,
  hdr,
  graph32;

procedure displayWaveForm(page: tPage; dstRect: tRect; samplePtr: pAudioSample16S; sampleLen, sampleMax: integer; color: RGBA);
procedure displayWaveFormHDR(page: tHDRPage; dstRect: tRect; samplePtr: pAudioSample16S; sampleLen, sampleMax: integer; value: integer);
procedure displayPhaseScopeHDR(page: tHDRPage; dstRect: tRect; samplePtr: pAudioSample16S; sampleLen, value: integer);

{stub: pass in}
type
  tSyncInfo = record
    offset: integer;
    value: integer;
    slope: single;
    debugStr: string;
    procedure clear();
  end;

var
  prevSync: tSyncInfo;

implementation

var
  sampleBuffer: array[0..16*1024-1] of tAudioSample16S;

{draw a vertical line with AA on the edges}
procedure vLineAA(page: tPage; x: integer;y1,y2: single; col: RGBA);
var
  tmp: single;
begin
  if y2 < y1 then begin tmp := y1; y1 := y2; y2 := tmp; end;
  page.vLine(x, ceil(y1), floor(y2), col);
  col.a := round((1-frac(y1))*255);
  page.putPixel(x, floor(y1), col);
  col.a := round((frac(y2))*255);
  page.putPixel(x, ceil(y2)+1, col);
end;

{draw a vertical line with AA on the edges}
procedure vLineHDR(page: tHDRPage; x: integer;y1,y2: single; value: integer);
var
  tmp: single;
  y: integer;
begin
  if y2 < y1 then begin tmp := y1; y1 := y2; y2 := tmp; end;
  for y := round(y1) to round(y2) do page.addValue(x, y, value);
end;

function getTracking(samplePtr: pAudioSample16S; sampleLen, sampleMax: integer): integer;
var
  pSample: pAudioSample16S;
  xlp, midX: integer;
  mid: single;
  trackingOffset: integer;
  padding: integer;
  debugStr: string;
  deltaValue: integer;

  function getSmooth(idx: integer): integer; inline;
  begin
    idx := clamp(idx, 0, sampleMax-1);
    result := sampleBuffer[idx].left;
  end;

  function getSlope(idx: integer): single; inline;
  begin
    result := (getSmooth(idx - 2) - getSmooth(idx + 2)) / 4;
  end;

  {tunes the tracking offset}
  procedure tuneTracking(scale: integer);
  var
    bestScore, score, slope: single;
    scoreDelta, scoreValue, scoreSlope: single;
    prevOffset, xlp: integer;
    delta: integer;
  begin
    bestScore := -99999;
    prevOffset := trackingOffset;
    for xlp := -64 to +64 do begin
      delta := xlp*scale + prevOffset;
      scoreDelta := -1   * abs(delta);
      scoreValue := -10  * abs(getSmooth(midX + delta));
      scoreSlope := -5   * getSlope(midX + delta);
      score := scoreDelta + scoreValue + scoreSlope;
      if score > bestScore then begin
        bestScore := score;
        trackingOffset := delta;
        //debugStr := format('%d %d %d %d', [score, scoreDelta, scoreValue, scoreSlope]);
      end;
    end;
  end;

begin

  if sampleMax > 16*1024 then error('Buffers larger than 16K are not supported.');

  {this is how far we can shift in each direction}
  padding := (sampleMax - sampleLen) div 2;
  if padding <= 0 then exit(0);

  midX := sampleMax div 2;

  {smooth out the waveform for processing}
  mid := samplePtr^.left + samplePtr^.right;
  pSample := samplePtr;
  for xlp := 0 to sampleMax-1 do begin
    // this roughly matches voice, which is 300 hz.
    mid := mid * 0.92 + (pSample^.toMid) * 0.08;
    sampleBuffer[xlp].left := clamp16(mid);
    inc(pSample);
  end;

  debugStr := '';

  {perform tracking}
  trackingOffset := 0;
  tuneTracking(2);

  {best guess at how many samples we moved}
  deltaValue := (trackingOffset - prevSync.offset);

  prevSync.offset := trackingOffset;
  prevSync.value := getSmooth(midX + trackingOffset);
  prevSync.slope := getSlope(midX + trackingOffset);
  prevSync.debugStr := debugStr;

  result := trackingOffset;

end;

{display waveform in given rect

samplePtr    pointer to buffer to display
sampleLen    how many samples we want to show in window
sampleMax    how many samples the buffer contains
syncData:    used to attempt to sync the waveform to the last call
}
{todo: we really want some kind of sampleBuffer, not just a pointer and length}
procedure displayWaveForm(page: tPage; dstRect: tRect; samplePtr: pAudioSample16S; sampleLen, sampleMax: integer; color: RGBA);
var
  prevMid: single;
  mid: single;
  xlp: integer;
  midX, midY: integer;
  xScale, yScale: single;
  pSample: pAudioSample16S;
  trackingOffset: integer;

  function getSample(idx: integer): pAudioSample16S; inline;
  begin
    idx := clamp(idx, 0, sampleMax-1);
    result := pointer(dword(samplePtr) + (idx * 4));
  end;

begin

  xScale := sampleLen / dstRect.width;
  yScale := dstRect.height / 65536 / 2;
  midX := round(dstRect.width/2*xScale);
  midY := (dstRect.top + dstRect.bottom) div 2;

  trackingOffset := getTracking(samplePtr, sampleLen, sampleMax);

  prevMid := 0;
  for xlp := dstRect.left to dstRect.right do begin
    pSample := getSample(trackingOffset + round((xlp - dstRect.left) * xScale));
    mid := (pSample^.left+pSample^.right)*yScale;
    vLineAA(page, xlp, midY+prevMid, midY+mid, color);
    prevMid := mid;
  end;

end;

procedure displayWaveFormHDR(page: tHDRPage; dstRect: tRect; samplePtr: pAudioSample16S; sampleLen, sampleMax: integer; value: integer);
var
  prevSampleValue: single;
  sampleValue: single;
  i: integer;
  midDrawY: integer;
  xScale, yScale: single;
  pSample: pAudioSample16S;
  trackingOffset: integer;
  attenuation: single;

  function getSample(idx: integer): pAudioSample16S; inline;
  begin
    idx := clamp(idx, 0, sampleMax-1);
    result := pointer(dword(samplePtr) + (idx * 4));
  end;

begin

  xScale := sampleLen / dstRect.width;    // converts pixel -> sample
  yScale := dstRect.height / 65536;       // converts sample -> pixel
  midDrawY := dstRect.mid.y;

  trackingOffset := getTracking(samplePtr, sampleLen, sampleMax);

  prevSampleValue := 0;
  for i := 0 to dstRect.width-1 do begin
    attenuation := sqrt(1-(abs((dstRect.width/2)-i) / (dstRect.width/2)));
    pSample := getSample(trackingOffset + round(i * xScale));
    sampleValue := ((pSample^.left+pSample^.right)*0.5)*yScale*attenuation;
    vLineHDR(page, i+dstRect.x, midDrawY+prevSampleValue, midDrawY+sampleValue, round(value*attenuation));
    prevSampleValue := sampleValue;
  end;

end;

procedure displayPhaseScopeHDR(page: tHDRPage; dstRect: tRect; samplePtr: pAudioSample16S; sampleLen, value: integer);
var
  i: integer;
  x,y: integer;
  xScale, yScale: single;
  midX, midY: integer;
begin
  midX := dstRect.mid.x;
  midY := dstRect.mid.y;
  xScale := dstRect.width / 65536;
  yScale := dstRect.height / 65536;

  for i := 0 to sampleLen-1 do begin
    x := midX + round(samplePtr^.left * xScale);
    y := midY - round(samplePtr^.right * yScale);
    page.addValue(x, y, value);
    inc(samplePtr);
  end;

end;

{--------------------------------------------}

procedure tSyncInfo.clear();
begin
  offset := 0;
  value := 0;
  slope := 0;
  debugStr := '';
end;

{--------------------------------------------}

begin
  prevSync.clear();
end.
