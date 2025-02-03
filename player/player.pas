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
  {todo: make a flag}
  EXPORT_WAVE: boolean = false;

  {only compresses HIGH profile in test mode, but also always recompresses}
  FAST_TEST: boolean = true;

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
  self.visible := true;
end;

procedure tGuiComponent.update(elapsed: single);
const
  FADE_IN = 0.04;
  FADE_OUT = 0.03;
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

function profileToTagName(profile: tAudioCompressionProfile): string;
begin
  result := joinPath('sample', profile.tag+'_'+format('%d_%d_%d_v4', [profile.quantBits, profile.ulawBits, profile.log2mu]));
end;

{allow user to switch between compression samples}
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

  if FAST_TEST then profiles := [ACP_MEDIUM];

  writeln();
  writeln('--------------------------');
  writeln('Loading Source Music.');
  music16 := tSoundEffect.loadFromWave(joinPath('sample','sample.wav'));
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
    if FAST_TEST or not fs.exists(music16.tag+'.a96') then begin
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

    tag := profileToTagName(profile);
    {read it}
    reader := tLA96Reader.create();
    reader.load(tag+'.a96');
    startTimer('decode');
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

  width := 300;
  height := length(tracks) * 20 + 7;
  atX := (screen.width-width) div 2;
  atY := (screen.height-height) div 2 + 100;
  screen.markRegion(tRect.create(atX,atY,width,height));
  screen.canvas.fillRect(tRect.create(atX,atY,width,height), RGBA.create(20,20,20,round(alpha*200)));
  screen.canvas.drawRect(tRect.create(atX,atY,width,height), RGBA.create(0,0,0,round(alpha*128)));
  for i := 0 to length(tracks)-1 do begin
    if (i = selectedTrackIndex) then begin
      screen.canvas.fillRect(tRect.create(atX+1,atY+5+i*20, width-2, 18), RGBA.create(15,20,250,round(alpha*128)));
      textColor.init(255,255,0,round(255*alpha));
    end else
      textColor.init(250,250,250,round(240*alpha));
    textOut(screen.canvas, atX+5, atY+5+i*20, tracks[i].title, textColor);
    textOut(screen.canvas, atX+width-5-50, atY+5+i*20, format('(%s:%s)', [intToStr(tracks[i].minutes), intToStr(tracks[i].seconds,2)]), textColor);
  end;
end;

procedure applySelection();
var
  track: tTrack;
begin
  note('Applying selection song');

  track := tracks[selectedTrackIndex];
  guiTitle.text := track.title;
  guiTitle.showForSeconds := 3.5;

  {buffer 0.5 seconds, enough time to read the next file}
  if musicReader.isLoaded then begin
    note('Prebuffering before load');
    musicUpdate(20);
  end;

  note('Loading new track');
  musicReader.load(track.filename);
  note('Starting playback');
  musicPlay(musicReader);
end;

procedure moveTrackSelection(delta: integer);
begin
  selectedTrackIndex := clamp(selectedTrackIndex + delta, 0, length(tracks)-1);
  uiShowForSeconds := 2.0;
end;

procedure nextSong();
var
  track: tTrack;
begin
  note('Moving to next song');
  selectedTrackIndex := (selectedTrackIndex + 1) mod length(tracks);
  {we need todo a soft reset here, a previous is still playing...}
  track := tracks[selectedTrackIndex];
  guiTitle.text := track.title;
  guiTitle.showForSeconds := 3.5;
  musicReader.close();
  musicReader.load(track.filename);
  musicPlay(musicReader);
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
  gui: tGuiComponents;
  key: tKeyPair;
  decodeSpeed: single;
  exitFlag: boolean;
  cpuUsage: single;
  statsString: string;
  refMusic: tSoundEffect;

begin

  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    error('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    error('Requires 1MB video card.');

  videoDriver.setTrueColor(640,480);
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;

  {init vars}
  oldBufferPos := 0;

  {setup gui}
  setLength(gui, 0);

  guiTitle := tGuiLabel.create(point(screen.width div 2, screen.height div 4-60));
  guiTitle.centered := true;
  guiTitle.autoFade := true;
  guiTitle.alpha := 0;
  gui.append(guiTitle);

  guiStats := tGuiLabel.create(point(10, screen.height-30));
  guiStats.visible := false;
  gui.append(guiStats);

  {load tracks}
  files := fs.listFiles('music\*.a96');
  files.sort();
  setLength(tracks, 0);
  for filename in files do begin
    tracks.append(tTrack.init(joinPath('music', filename)));
  end;
  if length(tracks) = 0 then error('No music found');

  {start playing}
  musicReader := tLA96Reader.Create();
  musicReader.playbackFinishedHook := nextSong();
  // start with 'crazy', as it's shorter (tmp for getting this working on
  // P200 MMX
  selectedTrackIndex := 2 mod length(tracks);
  applySelection();

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

    musicUpdate();

    {only update waveform if our music buffer has updated}
    if keyDown(key_z) or (oldBufferPos <> musicBufferReadPos()) and (not keyDown(key_space)) then begin

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
      rect := tRect.create((640-hdrPhase.width) div 2-10, (480-hdrPhase.height) div 2-74, hdrPhase.width, hdrPhase.height);
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
      {
      textOut(screen.canvas, 6, 3, format('%f', [1/elapsed]), RGB(250,250,250,240));
      screen.markRegion(tRect.create(6,3,40,20));
      }

      {stats}
      guiStats.text := format('CPU: %f%% RAM:%.2fMB', [100*getMusicStats.cpuUsage, getUsedMemory/1024/1024]);
      if mixClickDetection > 0 then
        guiStats.text += ' click:'+intToStr(mixClickDetection);

      key := getKey();
      if key.code <> 0 then case key.code of
        key_up: moveTrackSelection(-1);
        key_down: moveTrackSelection(+1);
        key_enter: applySelection();
        key_esc: exitFlag := true;
        key_s: guiStats.visible := not guiStats.visible;
      end;

      {fade change at 1 per s}
      if uiShowForSeconds > 0 then
        uiTargetAlpha := 1.0
      else
        uiTargetAlpha := 0.0;
      uiShowForSeconds -= elapsed;
      uiAlpha += (uiTargetAlpha - uiAlpha) * 0.12;
      drawTrackUI(uiAlpha);

      {gui stuff}
      gui.update(elapsed);
      gui.draw(screen);

      {screen.flipAll();}
      {stub:}
      screen.pageFlip();

      oldBufferPos := musicBufferReadPos;

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

  // this seems to cause problems for the P200?
  //autoHeapSize();

  textAttr := White + Blue*16;
  clrscr;

  debug.VERBOSE_SCREEN := llNote;

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
