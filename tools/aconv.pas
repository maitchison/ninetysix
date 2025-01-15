{audio conversion and testing tool}
program aconv;

uses
  {$I baseunits.inc},
  sound,
  audioFilter,
  mixLib,
  la96,
  keyboard,
  timer,
  stream,
  crt;

function sign(x: integer): integer; overload;
begin
  if x < 0 then exit(-1);
  if x > 0 then exit(1);
  exit(0);
end;

function sign(x: single): integer; overload;
begin
  if x < 0 then exit(-1);
  if x > 0 then exit(1);
  exit(0);
end;

function applyDeltaULaw(sfx: tSoundEffect): tSoundEffect;
var
  i: integer;
  delta: int32;
  prevX, prevY, x, y: integer;
  yReal: single;
  yErr, currentError: int32;
  ySqr: int32;
  avCode: double;
  avRMS: double;
  sample: tAudioSample16S;
const
  MU = 1024;
  BITS = 7;
begin
  result := sfx.clone();
  prevX := 0;
  prevY := 0;
  currentError := 0;
  avCode := 0;
  avRMS := 0;
  for i := 0 to sfx.length-1 do begin
    {try to represent the actual delta we observed in x}
    x := sfx[i].left;
    delta := x - prevX;
    yReal := sign(delta)*(ln(1.0+abs(MU*delta/(32*1024)))/ln(1+MU));
    {account for drift... very slowly}
    y := round(yReal*(1 SHL (BITS-1)));
    ySqr := sign(y) * round(32*1024/MU*power(1+MU, abs(y/(1 SHL (BITS-1))))-1);
    currentError := (prevX+ySqr) - x;
    if currentError > abs(yReal) then dec(y);
    if currentError < -abs(yReal) then inc(y);
    ySqr := sign(y) * round(32*1024/MU*power(1+MU, abs(y/(1 SHL (BITS-1))))-1);
    sample := result[i];
    sample.left := clamp16(prevY + ySqr);
    avCode := avCode * (0.999) + (1-0.999) * abs(y);
    avRMS := avCode * (0.999) + (1-0.999) * abs(delta*delta);
    prevX := x;
    prevY := sample.left;
    if i and $ffff = 0 then begin
      writeln(format('%d %d %f %f', [y, currentError, avCode, avRMS]));
    end;
    result[i] := sample;
  end;
  for i := 0 to sfx.length-1 do begin
    {try to represent the actual delta we observed in x}
    x := sfx[i].right;
    delta := x - prevX;
    yReal := sign(delta)*(ln(1.0+abs(MU*delta/(32*1024)))/ln(1+MU));
    {account for drift... very slowly}
    y := round(yReal*(1 SHL (BITS-1)));
    ySqr := sign(y) * round(32*1024/MU*power(1+MU, abs(y/(1 SHL (BITS-1))))-1);
    currentError := (prevX+ySqr) - x;
    if currentError > abs(yReal) then dec(y);
    if currentError < -abs(yReal) then inc(y);
    ySqr := sign(y) * round(32*1024/MU*power(1+MU, abs(y/(1 SHL (BITS-1))))-1);
    sample := result[i];
    sample.right := clamp16(prevY + ySqr);
    prevX := x;
    prevY := sample.right;
    {if i and $ffff = 0 then begin
      writeln(format('%d %d', [y, currentError]));
    end;}
    result[i] := sample;
  end;

end;


{
Settings

ULow:
UMedium:     12bit-256-7    (3.1x?)
UHigh:

(no ulaw)
QLow:   8bit      (3.0x) (sounds terriable)
QMed:   10bit;    (2.2x) (not bad)
QHigh:  12bit;    (1.7x) (I can't tell the difference)

(no ulaw)
QNearlossless: 16bit;  (1.2x)
Qlossless: 17bit;      (?.?x)
}
const
  MU = 128;
  ULAW_BITS = 7;
  QUANT_BITS = 12;
  DIV_FACTOR = 1 SHL (16-QUANT_BITS);
  EMA = 0; {0=off, 0.9 = very strong}

{input is -32k..32k, output is -1..1}
function uLaw(x: int32): single;
begin
  result := sign(x)*(ln(1.0+abs(MU*x/(32*1024)))/ln(1+MU));
end;

{input is -1..1, output is -32k..32k}
function uLawInv(y: single): single;
begin
  result := sign(y) * round(32*1024/MU*(power(1+MU, abs(y))-1));
end;

function applyDeltaULaw2(sfx: tSoundEffect): tSoundEffect;
var
  i: integer;
  uLeft, uRight: single;
  sample: tAudioSample16S;
  xLeft, xRight: single;
  centerLeft, centerRight: single;
begin
  result := sfx.clone();
  xLeft := 0;
  xRight := 0;
  centerLeft := 0; centerRight := 0;
  for i := 0 to sfx.length-1 do begin
    sample := sfx[i];
    uLeft  := round(uLaw((sample.left-round(centerLeft)) div DIV_FACTOR)  * (1 shl ULAW_BITS)) / (1 shl ULAW_BITS);
    uRight := round(uLaw((sample.right-round(centerRight)) div DIV_FACTOR) * (1 shl ULAW_BITS)) / (1 shl ULAW_BITS);
    {ema only needed for low quality mode}
    xLeft := EMA * xLeft + (1-EMA) * clamp16((uLawInv(uLeft) * DIV_FACTOR)+round(centerLeft));
    xRight := EMA * xRight + (1-EMA) * clamp16((uLawInv(uRight) * DIV_FACTOR)+round(centerRight));

    {xLeft  := uLawInv(uLeft) * DIV_FACTOR;
    xRight := uLawInv(uRight) * DIV_FACTOR;}
    sample.left  := clamp16(xLeft);
    sample.right := clamp16(xRight);
    {roughly 100hz}
    {I think this will kill the compression ratio though}
    centerLeft := 0.985 * centerLeft + 0.015 * sample.left;
    centerRight := 0.985 * centerRight + 0.015 * sample.right;
    result[i] := sample;
  end;

end;

procedure go();
var
  music16, musicL, musicD: tSoundEffect;
  SAMPLE_LENGTH: int32;
begin

  SAMPLE_LENGTH := 44100 * 60;

  writeln('Loading music.');
  music16 := tSoundEffect.loadFromWave('c:\dev\masters\bearing 320kbps.wav', SAMPLE_LENGTH);
  mixer.play(music16, SCS_FIXED1);
  writeln('Processing.');
  //musicL := afButterworth(music16, 16000);
  //musicL := afLowPass(music16, 16000);
  //musicL := tSoundEffect.loadFromWave('c:\dev\masters\bearing 128kbps.wav', SAMPLE_LENGTH);
  musicL := applyDeltaULaw2(music16);
  {musicL := afHighPass(music16, 10);     }
  musicD := afDelta(music16, musicL);
  writeln('Done.');
  while true do begin
    if keyDown(key_esc) then break;
    if keyDown(key_q) then break;
    if keyDown(key_1) then mixer.channels[1].sfx := music16;
    if keyDown(key_2) then mixer.channels[1].sfx := musicL;
    if keyDown(key_3) then mixer.channels[1].sfx := musicD;
  end;
  writeln('Exiting.');
end;

function getStd(sfx: tSoundEffect): double;
var
  m1,m2,prevValue,value: double;
  variance, mu: double;
  n: int32;
  i: integer;
  x: double;
begin
  m1 := 0;
  m2 := 0;
  n := sfx.length;
  prevValue := 0;
  for i := 0 to n-1 do begin
    value := sfx[i].left - sfx[i].right;

    x := value-prevValue;

    m1 += x;
    m2 += x*x;

    prevValue := value;
  end;
  variance := m2/n;
  mu := m1/n;
  result := sqrt(variance - mu*mu);
end;

procedure testCompression();
var
  music16, musicL, musicD: tSoundEffect;
  SAMPLE_LENGTH: int32;
  profile: tAudioCompressionProfile;
  quantBits: integer;
begin

  writeln('--------------------------');
  writeln('Loading music.');
  music16 := tSoundEffect.loadFromWave('c:\dev\masters\bearing sample.wav', 10*44100);

  mixer.play(music16, SCS_FIXED1);
  mixer.channels[1].looping := true;

  writeln('--------------------------');
  writeln('Compressing.');
  encodeLA96(music16, ACP_LOW, False).writeToDisk('c:\dev\tools\out_low_std.a96');

  printTimers();
  writeln('Done.');

  delay(3000);
end;

var
  i: integer;

begin

  autoHeapSize();

  clrscr;
  textAttr := WHITE;
  debug.WRITE_TO_SCREEN := true;
  logDPMIInfo();

  runTestSuites();
  initKeyboard();

  testCompression();
  //go();

  textAttr := LIGHTGRAY;

  {silly bug in dosbox not showing video}
  for i := 0 to 25 do writeln();

end.
