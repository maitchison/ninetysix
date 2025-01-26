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
  {todo: aa}
  for y := round(y1) to round(y2) do page.addValue(x, y, value);
end;

function getTracking(samplePtr: pAudioSample16S; midX, sampleLen, sampleMax: integer): integer;
var
  pSample: pAudioSample16S;
  xlp: integer;
  mid: single;
  trackingOffset: integer;

  function getSmooth(idx: integer): pAudioSample16S; inline;
  begin
    idx := clamp(idx, 0, sampleMax-1);
    result := @sampleBuffer[idx];
  end;

  function getSlope(idx: integer): single; inline;
  begin
    result := (getSmooth(idx - 10).left - getSmooth(idx + 10).left) / 20;
  end;

  {tunes the tracking offset}
  procedure tuneTracking(scale: integer);
  var
    bestScore, score, slope: single;
    prevOffset, xlp: integer;
  begin
    bestScore := -99999;
    prevOffset := trackingOffset;
    for xlp := -16 to +16 do begin
      pSample := getSmooth(midX + xlp*scale + prevOffset);
      slope := getSlope(midX + xlp*scale + prevOffset);
      score := 0;
      score -= 0.1 * abs(xlp*scale + prevOffset);             // drift loss
      score -= abs(pSample^.left);
      score += (slope * 10);
      if score > bestScore then begin
        bestScore := score;
        trackingOffset := xlp*scale + prevOffset;
      end;
    end;
  end;

begin

  if sampleLen > 16*1024 then error('Sorry buffers larger than 16K are not supported.');

  {smooth out the waveform for processing}
  mid := samplePtr^.left + samplePtr^.right;
  pSample := samplePtr;
  for xlp := 0 to sampleLen-1 do begin
    mid := mid * 0.95 + (pSample^.mid) * 0.05;
    sampleBuffer[xlp].left := clamp16(mid);
    inc(pSample);
  end;

  {perform some sync}
  trackingOffset := 16*4;
  tuneTracking(4);
  tuneTracking(1);

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

  trackingOffset := getTracking(samplePtr, sampleLen, sampleMax, midX);

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

  trackingOffset := getTracking(samplePtr, sampleLen, sampleMax, midX);

  prevMid := 0;
  for xlp := dstRect.left to dstRect.right do begin
    pSample := getSample(trackingOffset + round((xlp - dstRect.left) * xScale));
    mid := (pSample^.left+pSample^.right)*yScale;
    vLineHDR(page, xlp, midY+prevMid, midY+mid, value);
    prevMid := mid;
  end;

end;

begin
end.
