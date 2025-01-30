{audio conversion and testing tool}
program player;

uses
  {$i baseunits.inc},
  sound,
  audioFilter,
  mixLib,
  la96,
  keyboard,
  timer,
  stream,
  {graphics stuff}
  screen,
  vga,
  vesa,
  graph2d,
  graph32,
  sndViz,
  sprite,
  lc96,
  vlc,
  hdr,
  font,
  {other stuff}
  myMath,
  crt;

const
  {if true exports compressed audio and deltas to wave files for analysis}
  EXPORT_WAVE: boolean = false;

{globals}
var
  screen: tScreen;
  hdrWave: tHDRPage;
  hdrPhase: tHDRPage;
  music16: tSoundEffect;    // our original sound.

{--------------------------------------------------------}

type
  tTrack = record
    title: string;
    filename: string;
    duration: single;
    constructor init(aFilename: string);
    function minutes: integer;
    function seconds: integer;
  end;

  tTracks = array of tTrack;

  {todo: bounds at component level}
  tGuiComponent = class
    pos: tPoint;
    alpha: single;
    targetAlpha: single;
    showForSeconds: single;
    visible: boolean;
    autoFade: boolean;
  protected
    procedure doDraw(screen: tScreen); virtual;
  public
    procedure draw(screen: tScreen);
    procedure update(elapsed: single); virtual;
    constructor create(aPos: tPoint);
  end;

  tGuiComponents = array of tGuiComponent;

  tGuiLabel = class(tGuiComponent)
    textColor: RGBA;
    text: string;
    centered: boolean;
  protected
    procedure doDraw(screen: tScreen); override;
  public
    constructor create(aPos: tPoint);
  end;

type
  tTracksHelper = record helper for tTracks
    procedure append(x: tTrack);
  end;

  tGuiComponentsHelper = record helper for tGuiComponents
    procedure append(x: tGuiComponent);
    procedure draw(screen: tScreen);
    procedure update(elapsed: single);
  end;


var
  tracks: tTracks;
  guiComponets: tGuiComponents;
  selectedTrackIndex: integer;
  {todo: these would be good as some kind of UI component}
  uiAlpha: single;
  uiTargetAlpha: single;
  uiShowForSeconds: single;

  musicReader: tLA96Reader;

  {gui stuff}
  guiTitle: tGUILabel;
  guiStats: tGUILabel;

{--------------------------------------------------------}
{ Helpers }

procedure tGuiComponentsHelper.append(x: tGuiComponent);
begin
  setLength(self, length(self)+1);
  self[length(self)-1] := x;
end;

procedure tGuiComponentsHelper.draw(screen: tScreen);
var
  c: tGuiComponent;
begin
  for c in self do c.draw(screen);
end;

procedure tGuiComponentsHelper.update(elapsed: single);
var
  c: tGuiComponent;
begin
  for c in self do c.update(elapsed);
end;

{----------------}

procedure tTracksHelper.append(x: tTrack);
begin
  setLength(self, length(self)+1);
  self[length(self)-1] := x;
end;

{--------------------------------------------------------}
{ UI Components }

constructor tGuiComponent.create(aPos: tPoint);
begin
  inherited create();
  self.pos := aPos;
  self.alpha := 1;
  self.targetAlpha := 1;
  self.showForSeconds := 0;
  self.autoFade := false;
end;

procedure tGuiComponent.update(elapsed: single);
const
  FADE_IN = 0.08;
  FADE_OUT = 0.04;
var
  delta: single;
begin
  if autoFade then begin
    if showForSeconds > 0 then
      targetAlpha := 1.0
    else
      targetAlpha := 0.0;
    showForSeconds -= elapsed;
    // todo: respect elapsed
    delta := targetAlpha - alpha;
    if delta < 0 then
      alpha += delta * FADE_OUT
    else
      alpha += delta * FADE_IN
  end;
end;

procedure tGuiComponent.draw(screen: tScreen);
begin
  if not visible then exit;
  doDraw(screen);
end;

procedure tGuiComponent.doDraw(screen: tScreen);
begin
  //pass
end;

{-----------------------}

constructor tGuiLabel.create(aPos: tPoint);
begin
  inherited create(aPos);
  self.centered := false;
  self.textColor := RGB(250, 250, 250);
  self.text := '';
end;

procedure tGuiLabel.doDraw(screen: tScreen);
var
  bounds: tRect;
  c: RGBA;
begin
  c.init(textColor.r, textColor.g, textColor.b, round(textColor.a * alpha));
  if c.a = 0 then exit;
  bounds := textExtents(text, pos);
  if centered then bounds.x -= bounds.width div 2;
  textOut(screen.canvas, bounds.x, bounds.y, text, c);
  screen.markRegion(bounds);
end;

{--------------------------------------------------------}

constructor tTrack.init(aFilename: string);
var
  reader: tLA96Reader;
begin
  filename := aFilename;
  reader := tLA96Reader.create();
  reader.load(filename);

  {this is a hack until we get metadata going}
  title := extractFilename(aFilename);
  if title = 'blue.a96' then
    title := 'Out of The Blue'
  else if title = 'clowns.a96' then
    title := 'Send In The Clowns'
  else if title = 'crazy.a96' then
    title := 'Crazy'
  else if title = 'sunshine.a96' then
    title := 'You Are My Sunshine';

  duration := reader.duration;
  reader.close();
end;

function tTrack.minutes(): integer;
begin
  result := floor(duration) div 60;
end;

function tTrack.seconds(): integer;
begin
  result := floor(duration) mod 60;
end;

{--------------------------------------------------------}

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

    estimatedBits += VLCBits(2*abs(uLeft-prevULeft)) + VLCBits(2*abs(uRight-prevURight));

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
  music16 := tSoundEffect.loadFromWave('res\sample.wav', SAMPLE_LENGTH);
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

function profileToTagName(profile: tAudioCompressionProfile): string;
begin
  result := 'res\'+profile.tag+'_'+format('%d_%d_%d_xv4', [profile.quantBits, profile.ulawBits, profile.log2mu]);
end;

procedure testCompression();
var
  music16, musicL, musicD: tSoundEffect;
  SAMPLE_LENGTH: int32;
  profile: tAudioCompressionProfile;
  log2mu, ulawBits, quantBits: integer;
  outStream: tStream;
  reader: tLA96Reader;
  outSFX: array of tSoundEffect;
  deltaSFX: array of tSoundEffect;
  curSFX, errSFX: tSoundEffect;
  i: integer;
  profiles: array of tAudioCompressionProfile;
  selection: integer;
  delta: boolean;
  tag: string;
  star: string;

  procedure redrawUI();
  var
    i: integer;
  begin
    textAttr := White + Blue*16;
    gotoxy(1,10);
    writeln(format('Press [0..%d] to select audio file.', [length(outSFX)-1]));

    for i := 0 to length(outSFX)-1 do begin
      if selection = i then
        star := ' * '
      else
        star := '   ';
      writeln(format('%s[%d] %s',[star, i, outSFX[i].tag]));
    end;
  end;

  procedure setSelection(newSelection: integer);
  begin
    if selection = newSelection then exit;
    selection := newSelection;
    redrawUI();
  end;

begin

  setLength(outSFX, 0);
  setLength(deltaSFX, 0);

  profiles := [
    ACP_LOW, ACP_MEDIUM, ACP_HIGH, ACP_VERYHIGH,
    ACP_Q8, ACP_Q10, ACP_Q12, ACP_Q16
  ];

  writeln();
  writeln('--------------------------');
  writeln('Loading Source Music.');
  music16 := tSoundEffect.loadFromWave('res\sample.wav');
  writeln(format('Source RMS: %f',[music16.calculateRMS()]));

  setLength(outSfx, length(outSFX)+1);
  outSFX[length(outSFX)-1] := music16;
  setLength(deltaSfx, length(deltaSFX)+1);
  deltaSFX[length(deltaSFX)-1] := music16;

  writeln();
  writeln('--------------------------');
  writeln('Compressing....');
  LA96_ENABLE_STATS := false;

  for profile in PROFILES do begin
    {todo: stop using music16.tag for filename}
    music16.tag := profileToTagName(profile);
    if not fs.exists(music16.tag+'.a96') then begin
      outStream := encodeLA96(music16, profile, true);
      outStream.writeToFile(music16.tag+'.a96');
      outStream.free;
    end;
  end;

  music16.tag := 'original';

  writeln();
  writeln('--------------------------');
  writeln('Reading compressed files...');

  for profile in PROFILES do begin
    startTimer('decode');
    tag := profileToTagName(profile);
    {read it}
    reader := tLA96Reader.create();
    reader.load(tag+'.a96');
    curSFX := reader.readSFX();
    setLength(outSFX, length(outSFX)+1);
    outSFX[length(outSFX)-1] := curSFX;
    curSFX.tag := tag; //shouldn't be needed. but is for some reason
    reader.free;
    stopTimer('decode');
    {find delta}
    errSFX := afDelta(curSFX, music16);
    setLength(deltaSFX, length(deltaSFX)+1);
    deltaSFX[length(deltaSFX)-1] := errSFX;
    {rms}
    writeln(format('FILE RMS: %f',[curSFX.calculateRMS()]));
    writeln(format('FILE Size: %fkb',[fs.getFileSize(tag+'.a96')/1024]));
    writeln(format('ERROR RMS: %f',[errSFX.calculateRMS()]));
    writeln(format('Decoded at %fx', [(curSFX.length/44100)/getTimer('decode').elapsed]));
    {export}
    if EXPORT_WAVE then begin
      curSFX.saveToWave(tag+'.wav');
      errSFX.saveToWave(tag+'_delta.wav');
    end;
  end;

  printTimers();

  {start playing sound}
  mixer.play(outSFX[0], SCS_FIXED1); writeln(outSFX[0].tag);
  mixer.channels[1].looping := true;
  writeln('All done.');

  delta := false;
  selection := 0;
  redrawUI();

  setSelection(1);

  repeat
    if keyDown(key_0) then setSelection(0);
    delta := keyDown(key_leftshift);
    for i := 1 to length(outSFX)-1 do
      if keyDown(key_1+i-1) then setSelection(i);
    if selection = 0 then
      mixer.channels[1].sfx := outSFX[0]
    else begin
      if delta then mixer.channels[1].sfx := deltaSFX[selection] else mixer.channels[1].sfx := outSFX[selection];
    end;
    until keyDown(key_esc);
end;


procedure testADPCM();
var
  music16, musicL, musicD: tSoundEffect;
  i: integer;

begin

  writeln('--------------------------');
  writeln('Loading music.');
  music16 := tSoundEffect.loadFromWave('res\sample.wav', 10*44100);
  writeln(format('Source RMS: %f',[music16.calculateRMS()]));
  musicL := tSoundEffect.loadFromWave('res\smample_ADPCM.wav', 10*44100);
  musicD := afDelta(music16, musicL);
  {rms}
  writeln(format('ERROR RMS: %f',[musicD.calculateRMS()]));

  {start playing sound}
  mixer.play(MusicL, SCS_FIXED1);
  mixer.channels[1].looping := true;

  repeat
    writeln(mixer.channels[1].sfx.tag);
    if keyDown(key_1) then mixer.channels[1].sfx := musicL;
    if keyDown(key_2) then mixer.channels[1].sfx := music16;
    if keyDown(key_3) then mixer.channels[1].sfx := musicD;
    until keyDown(key_esc);
end;

procedure maybeDelta(frameOn: int32; samplePtr: pAudioSample16S; frameLength: int32);
var
  i: int32;
  srcPtr: pAudioSample16S;
begin
  if not keyDown(key_leftshift) then exit;
  srcPtr := (music16.data + (frameOn * 1024 * 4));
  for i := 0 to frameLength-1 do begin
    samplePtr^ := samplePtr^ - srcPtr^;
    inc(samplePtr);
    inc(srcPtr);
  end;
end;

{draw track selection UI}
procedure drawTrackUI(alpha: single);
var
  atX, atY: integer;
  width, height: integer;
  mm,ss: integer;
  i: integer;
  textColor: RGBA;
begin
  if alpha < (1/255) then exit;
  alpha := clamp(alpha, 0, 1);
  textColor.init(250,250,250,round(240*alpha));
  width := 300;
  height := length(tracks) * 20 + 7;
  atX := (screen.width-width) div 2;
  atY := (screen.height-height) div 2 + 100;
  screen.markRegion(tRect.create(atX,atY,width,height));
  screen.canvas.fillRect(tRect.create(atX,atY,width,height), RGBA.create(20,20,20,round(alpha*200)));
  screen.canvas.drawRect(tRect.create(atX,atY,width,height), RGBA.create(0,0,0,round(alpha*128)));
  for i := 0 to length(tracks)-1 do begin
    if (i = selectedTrackIndex) then
      screen.canvas.fillRect(tRect.create(atX+1,atY+5+i*20, width-2, 18), RGBA.create(16,16,128,round(alpha*128)));
    textOut(screen.canvas, atX+5, atY+5+i*20, tracks[i].title, textColor);
    textOut(screen.canvas, atX+width-5-50, atY+5+i*20, format('(%s:%s)', [intToStr(tracks[i].minutes), intToStr(tracks[i].seconds,2)]), textColor);
  end;
end;

procedure makeSelection();
var
  track: tTrack;
begin
  track := tracks[selectedTrackIndex];
  guiTitle.text := track.title;
  guiTitle.showForSeconds := 4.5;
  uiShowForSeconds := 1.0;

  musicReader.load(track.filename);
  musicPlay(musicReader);
end;

procedure moveTrackSelection(delta: integer);
begin
  selectedTrackIndex := clamp(selectedTrackIndex + delta, 0, length(tracks)-1);
  uiShowForSeconds := 2.0;
end;

{play sound with some graphics}
procedure soundPlayer();
var
  files: tStringList;
  filename: string;
  i: integer;
  tag: string;
  selected: integer;
  background: tSprite;
  rect: tRect;
  oldBufferPos: dword;
  elapsed: double;
  x,y: integer;
  textColor: RGBA;
  gui: tGuiComponents;
  key: tKeyPair;
  decodeSpeed: single;
  exitFlag: boolean;
  cpuUsage: single;

begin

  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    error('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 2*1024*1024 then
    error('Requires 2MB video card.');
  videoDriver.setMode(640,480,32);
  screen := tScreen.create();

  {init vars}
  oldBufferPos := 0;

  {setup gui}
  setLength(gui, 0);

  guiTitle := tGuiLabel.create(point(screen.width div 2, screen.height div 4-40));
  guiTitle.centered := true;
  guiTitle.autoFade := true;
  gui.append(guiTitle);

  guiStats := tGuiLabel.create(point(10, screen.height-30));
  guiStats.visible := false;
  gui.append(guiStats);

  {load tracks}
  files := fs.listFiles('music\*.a96');
  setLength(tracks, 0);
  for filename in files do begin
    tracks.append(tTrack.init(joinPath('music', filename)));
  end;
  if length(tracks) = 0 then error('No music found');

  {start playing}
  musicReader := tLA96Reader.Create();
  selectedTrackIndex := 0;
  makeSelection();

  hdrWave := tHDRPage.create(64,32);
  hdrPhase := tHDRPage.create(64,64);

  {load background and refresh screen}
  screen.background := tPage.Load('res\background.p96');

  screen.pageClear();
  screen.pageFlip();

  {todo: remove and use new gui system}
  uiAlpha := 0;
  uiTargetAlpha := 0;
  uiShowForSeconds := 0;

  exitFlag := false;

  {main loop}
  repeat

    musicUpdate(1);

    {only update waveform if our music buffer has updated}
    if (oldBufferPos <> musicBufferPos()) and (not keyDown(key_space)) then begin

      startTimer('main');

      screen.clearAll();

      {waveform}
      startTimer('waveform');
      rect := tRect.create((640-hdrWave.width) div 2, 480-hdrWave.height-(hdrWave.height div 2), hdrWave.width, hdrWave.height);
      hdrWave.fade(0.92);
      displayWaveFormHDR(hdrWave, tRect.create(0, 0, rect.width, rect.height), mixLib.scratchBufferPtr, 256, 512, 8*1024);
      hdrWave.mixTo(screen.canvas, rect.x, rect.y);
      screen.markRegion(rect);
      stopTimer('waveform');

      {phase}
      startTimer('phase');
      rect := tRect.create((640-hdrPhase.width) div 2, (480-hdrPhase.height) div 2, hdrPhase.width, hdrPhase.height);
      hdrPhase.fade(0.95);
      displayPhaseScopeHDR(hdrPhase, tRect.create(0, 0, rect.width, rect.height), mixLib.scratchBufferPtr, 512, 256);
      hdrPhase.mulTo(screen.canvas, rect.x, rect.y);
      screen.markRegion(rect);
      stopTimer('phase');

      {fps:}
      if assigned(getTimer('main')) then
        elapsed := getTimer('main').avElapsed
      else
        elapsed := -1;
      textOut(screen.canvas, 6, 3, format('%f', [1/elapsed]), textColor);
      screen.markRegion(tRect.create(6,3,40,20));

      {debug info}
      {
      screen.markRegion(tRect.create(0,0,200,200));
      textOut(screen.canvas, 10, 10, format('Offset:%d', [prevSync.offset]), textColor);
      textOut(screen.canvas, 10, 30, format('Value:%d', [prevSync.value]), textColor);
      textOut(screen.canvas, 10, 50, format('Slope:%d', [prevSync.slope]), textColor);
      textOut(screen.canvas, 10, 70, format('Debug:%s', [prevSync.debugStr]), textColor);
      }

      {stats}
      guiStats.text := format('CPU: %f%% RAM:%f/%f', [100*getMusicStats.cpuUsage, getUsedMemory/1024/1024, getTotalMemory/1024/1024]);

      key := getKey();
      if key.code <> 0 then case key.code of
        key_up: moveTrackSelection(-1);
        key_down: moveTrackSelection(+1);
        key_enter: makeSelection();
        key_esc: exitFlag := true;
        key_s: guiStats.visible := not guiStats.visible;
      end;

      {fade change at 1 per s}
      if uiShowForSeconds > 0 then
        uiTargetAlpha := 1.0
      else
        uiTargetAlpha := 0.0;
      uiShowForSeconds -= elapsed;
      uiAlpha += (uiTargetAlpha - uiAlpha) * 0.08;
      drawTrackUI(uiAlpha);

      {gui stuff}
      gui.update(elapsed);
      gui.draw(screen);

      screen.flipAll();

      oldBufferPos := musicBufferPos;

      stopTimer('main');
    end;

    if keyDown(key_esc) then exitFlag := true;

    idle();

  until exitFlag;

  videoDriver.setText();

end;

var
  i: integer;
  mode: string;

begin

  autoHeapSize();

  textAttr := White + Blue*16;
  clrscr;

  debug.VERBOSE_SCREEN := llNote;
  logDPMIInfo();

  runTestSuites();
  initKeyboard();

  if paramCount = 0 then
    mode := 'play'
  else
    mode := paramStr(1).toLower();

  if mode = 'play' then
    soundPlayer()
  else if mode = 'test' then
    testCompression()
  else
    error('Invalid mode '+mode);

  textAttr := LIGHTGRAY;

end.
