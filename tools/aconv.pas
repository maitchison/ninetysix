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
  QUANT_BITS = 12; {this is 5}
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

{stocastic rounding}
function roundX(x: single): integer;
begin
  x += (rnd+rnd)/512; {0..1, centered at 0.5}
  result := trunc(x);
end;

function vlcBits(x: int32): integer;
begin
  x := abs(round(x));
  if x < 8 then exit(4+1);
  if x < 64 then exit(8+1);
  if x < 512 then exit(12+1);
  if x < 4096 then exit(16+1);
  exit(20+1);
end;

{triangle noise, centered at 0, with width of 1.0}
function triangleNoise: single;
begin
  result := ((rnd+rnd)-256) / 256;
end;

function maskDistortion(prevX, newX: single): single;
var
  delta: single;
  noise: single;
begin
  delta := prevX - newX;
  if delta < 0 then delta := 0;
  noise := delta / 5;
  if noise > 2 then
    result := newX + round(triangleNoise * noise)
  else
    result := newX;
end;

function applyDeltaULaw2(sfx: tSoundEffect): tSoundEffect;
var
  i: integer;
  uLeft, uRight: int32;
  sample: tAudioSample16S;
  xLeft, xRight: single;
  prevXleft, prevXright: single;
  centerLeft, centerRight: single;
  estimatedBits: double;
  prevULeft, prevURight: int32;
  ULAWMUL: int32;
  cntrL,cntrR: int32;

  fastRms: double;
  slowRms: double;
const
  {0 = off
   0.01 = tracks around 100hz or so I guess
   0.05 = removes all kickdrum distortion
   1= complete tracking
  }
  centeringAlpha = 1;

  alphaSlow = 1/(44100*3); {three seconds}
  alphaFast = 1/(44100*0.05); {50 ms}
begin
  ULAWMUL := 1 shl ULAW_BITS;
  result := sfx.clone();
  xLeft := 0;
  xRight := 0;
  prevXLeft := 0;
  prevXRight := 0;
  centerLeft := 0; centerRight := 0;
  prevULeft := 0; prevURight := 0;
  estimatedBits := 0;

  fastRMS := 0;
  slowRMS := 0;

  for i := 0 to sfx.length-1 do begin

    sample := sfx[i];

    fastRMS := fastRMS * (1-alphaFast) + alphaFast*(sample.left*sample.left);
    slowRMS := slowRMS * (1-alphaSlow) + alphaSlow*(sample.left*sample.left);

    {I think this works, we just need to lead it by 50ms}
    {if (sqrt(fastRMS) - sqrt(slowRMS)) > 3000 then
      ULAWMUL := 1 shl (ULAW_BITS+2)
    else
      ULAWMUL := 1 shl (ULAW_BITS);}

    cntrL := round(centerLeft/256)*256;
    cntrR := round(centerRight/256)*256;

    uLeft  := round(uLaw((sample.left-cntrL) div DIV_FACTOR) * ULAWMUL);
    uRight := round(uLaw((sample.right-cntrR) div DIV_FACTOR) * ULAWMUL);
    {ema only needed for low quality mode}
    xLeft := EMA * xLeft + (1-EMA) * clamp16((uLawInv(uLeft/ULAWMUL) * DIV_FACTOR)+cntrL);
    xRight := EMA * xRight + (1-EMA) * clamp16((uLawInv(uRight/ULAWMUL) * DIV_FACTOR)+cntrR);

    {mask distortion with noise}
    {xLeft := maskDistortion(prevXLeft, xLeft);
    xRight := maskDistortion(prevXRight, xRight);}

    {xLeft  := uLawInv(uLeft) * DIV_FACTOR;
    xRight := uLawInv(uRight) * DIV_FACTOR;}
    sample.left  := clamp16(xLeft);
    sample.right := clamp16(xRight);

    {stub:}
    {
    if (sqrt(fastRMS) - sqrt(slowRMS)) > 3000 then begin
      sample.left := clamp16(triangleNoise * 64 * 256);
      sample.right := clamp16(triangleNoise * 64 * 256);
    end;
    }

    if i and $fff = 0 then begin
      writeln(format('%d %d %d %d' , [i, sqrt(fastRMS) - sqrt(slowRMS) , sqrt(fastRMS), sqrt(slowRMS)]));
    end;

    {roughly 100hz}
    {I think this will kill the compression ratio though}
    {actually it only slightly adjusts it}
    centerLeft := (1-centeringAlpha) * centerLeft + (centeringAlpha * sample.left);
    centerRight := (1-centeringAlpha) * centerRight + (centeringAlpha * sample.right);

    estimatedBits += vlcBits(uLeft-prevULeft) + vlcBits(uRight-prevURight);

    prevULeft := uLeft;
    prevURight := uRight;
    prevXLeft := xLeft;
    prevXRight := xRight;

    result[i] := sample;
  end;

  writeln(format('My guess is that this is %f bits per sample (%f KB)', [estimatedBits/sfx.length, estimatedBits/8/1024]));

end;

procedure ABTest();
var
  music16, musicL, musicD: tSoundEffect;
  SAMPLE_LENGTH: int32;
begin

  SAMPLE_LENGTH := 44100 * 60;

  writeln('Loading music.');
  music16 := tSoundEffect.loadFromWave('c:\dev\masters\bearing 320kbps.wav', SAMPLE_LENGTH);
  mixer.play(music16, SCS_FIXED1);
  mixer.channels[1].looping := true;
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
    if keyDown(key_r) then mixer.channels[1].sampleTick := 0;
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
  log2mu, ulawBits, quantBits: integer;
  outStream: tStream;
begin

  writeln('--------------------------');
  writeln('Loading music.');
  music16 := tSoundEffect.loadFromWave('c:\dev\masters\bearing sample.wav', 10*44100);

  //mixer.play(music16, SCS_FIXED1);
  //mixer.channels[1].looping := true;

  writeln('--------------------------');
  writeln('Compressing.');
  LA96_ENABLE_STATS := false;

  for profile in [ACP_VERYLOW, ACP_LOW, ACP_MEDIUM, ACP_HIGH, ACP_Q10, ACP_Q12, ACP_Q16, ACP_LOSSLESS] do begin
    music16.tag := 'c:\dev\tmp\'+profile.tag+'_'+format('%d_%d_%d_new', [profile.quantBits, profile.ulawBits, profile.log2mu]);
    if not fs.exists(music16.tag+'.a96') then begin
      outStream := encodeLA96(music16, profile);
      outStream.writeToDisk(music16.tag+'.a96');
      outStream.free;
    end;
  end;

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
  //ABTest();

  textAttr := LIGHTGRAY;

  {silly bug in dosbox not showing video}
  for i := 0 to 25 do writeln();

end.
