{audio conversion and testing tool}
program player;

uses
  {$i baseunits.inc},
  uSound,
  uAudioFilter,
  uMixer,
  uA96,
  uP96,
  uKeyboard,
  uTimer,
  uStream,
  {graphics stuff}
  uScreen,
  uVGADriver,
  uVESADriver,
  uRect,
  uGraph32,
  uColor,
  uSndViz,
  uSprite,
  uGUI,
  uGuiLabel,
  uVLC,
  uHDR,
  uFont,
  {other stuff}
  uWave,
  uMath,
  crt;

const
  {if true exports compressed audio and deltas to wave files for analysis}
  {todo: make a flag}
  EXPORT_WAVE: boolean = false;

{globals}
var
  screen: tScreen;
  hdrWave: tHDRPage;
  hdrPhase: tHDRPage;
  music16: tSound;    // our original sound.

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

  tGuiBuffer = class(tGuiComponent)
    valueMin, valueMax, value: integer;
  protected
    procedure doDraw(const dc: tDrawContext); override;
  public
    constructor create(aPos: tPoint;aMin,aMax: integer);
  end;

type
  tTracksHelper = record helper for tTracks
    procedure append(x: tTrack);
  end;

var
  tracks: tTracks;
  selectedTrackIndex: integer;
  {todo: these would be good as some kind of UI component}
  uiAlpha: single;
  uiTargetAlpha: single;
  uiShowForSeconds: single;

  musicReader: tLA96Reader;

  {gui stuff}
  guiTitle: tGUILabel;
  guiStats: tGUILabel;
  guiBuffer: tGUIBuffer;
  guiFPS: tGUILabel;

{--------------------------------------------------------}

procedure tGuiBuffer.doDraw(const dc: tDrawContext);
var
  bounds: tRect;
  col: RGBA;
  i: integer;
begin
  bounds := Rect(pos.x, pos.y, valueMax*5+1, 6);
  dc.fillRect(bounds, rgb(0,0,0,192));
  for i := 0 to valueMax-1 do begin
    if (valueMax-i) <= valueMin then
      col := RGB(255,100,100)
    else if (valueMax-i) <= value then
      col := RGB(100,255,100)
    else
      col := RGB(200,200,200);
    dc.fillRect(Rect(bounds.x+i*5+1, bounds.y+1, 4, 4), col);
  end;
end;

constructor tGuiBuffer.create(aPos: tPoint;aMin,aMax: integer);
begin
  inherited Create();
  // todo: fix this
  setBounds(Rect(aPos.x, aPos.y, 100, 20)); // guess on dims
  valueMin := aMin;
  valueMax := aMax;
  value := 0;
end;

{----------------}

procedure tTracksHelper.append(x: tTrack);
begin
  setLength(self, length(self)+1);
  self[length(self)-1] := x;
end;

{--------------------------------------------------------}

constructor tTrack.init(aFilename: string);
var
  reader: tLA96Reader;
begin
  filename := aFilename;
  reader := tLA96Reader.create();
  reader.open(filename);

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
  result := joinPath('sample', profile.tag+'_'+format('%d_%d_%d_v5', [profile.quantBits, profile.ulawBits, profile.log2mu]));
end;

procedure updateEncodeProgress(frameOn: int32; samplePtr: pAudioSample16S; frameLength: int32);
begin
  {todo: do something fancy here, like eta, speed etc}
  if frameOn mod 16 = 15 then write('.');
end;

{allow user to switch between compression samples}
{fast: only compresses HIGH profile in test mode, but also always recompresses}
procedure testCompression(fastMode: boolean=false);
var
  music16, musicL, musicD: tSound;
  SAMPLE_LENGTH: int32;
  profile: tAudioCompressionProfile;
  log2mu, ulawBits, quantBits: integer;
  outStream: tMemoryStream;
  reader: tLA96Reader;
  writer: tLA96Writer;
  outSFX: array of tSound;
  deltaSFX: array of tSound;
  curSFX, errSFX: tSound;
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

  if fastMode then profiles := [ACP_HIGH];

  writeln();
  writeln('--------------------------');
  writeln('Loading Source Music.');
  music16 := tSound.Load(joinPath('sample','sample.wav'));
  writeln(format('Source RMS: %f',[music16.calculateRMS()]));

  setLength(outSfx, length(outSFX)+1);
  outSFX[length(outSFX)-1] := music16;
  setLength(deltaSfx, length(deltaSFX)+1);
  deltaSFX[length(deltaSFX)-1] := music16;

  writeln();
  writeln('--------------------------');
  writeln('Compressing....');
  LA96_ENABLE_STATS := false;

  writer := tLA96Writer.create();
  writer.frameWriteHook := updateEncodeProgress();

  for profile in PROFILES do begin
    {todo: stop using music16.tag for filename}
    music16.tag := profileToTagName(profile);
    if fastMode or not fileSystem.exists(music16.tag+'.a96') then begin

      startTimer('encode');
      { for the moment encode to memory, as fileStream is not yet buffered
       and therefore very slow for small writes. }
      outStream := tMemoryStream.create();
      writer.open(outStream);
      writer.writeA96(music16, profile);
      outStream.writeToFile(music16.tag+'.a96');
      outStream.free;

      stopTimer('encode');
      writeln();
      note(format('Encoded at %fx (%, exceptions)', [(music16.length/44100)/getTimer('encode').elapsed, RICE_EXCEPTIONS]));
    end;
  end;

  writer.free;

  music16.tag := 'original';

  writeln();
  writeln('--------------------------');
  writeln('Reading compressed files...');

  for profile in PROFILES do begin

    tag := profileToTagName(profile);
    {read it}
    reader := tLA96Reader.create();

    reader.open(tag+'.a96');

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
    writeln(format('FILE Size: %fkb',[fileSystem.getFileSize(tag+'.a96')/1024]));
    writeln(format('ERROR RMS: %f',[errSFX.calculateRMS()]));
    writeln(format('Decoded at %fx', [(curSFX.length/44100)/getTimer('decode').elapsed]));
    {export}
    if EXPORT_WAVE then begin
      saveWave(tag+'.wav', curSFX);
      saveWave(tag+'_delta.wav', errSFX);
    end;
  end;

  logTimers();

  {start playing sound}
  mixer.play(outSFX[0], 1.0, SCS_FIXED1); writeln(outSFX[0].tag);
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
  dc: tDrawContext;
  font: tFont;
begin
  if alpha < (1/255) then exit;
  alpha := clamp(alpha, 0, 1);

  width := 300;
  height := length(tracks) * 20 + 7;
  atX := (screen.width-width) div 2;
  atY := (screen.height-height) div 2 + 100;
  font := DEFAULT_FONT;
  dc := screen.getDC();
  dc.fillRect(Rect(atX,atY,width,height), RGBA.create(20,20,20,round(alpha*200)));
  dc.drawRect(Rect(atX,atY,width,height), RGBA.create(0,0,0,round(alpha*128)));
  for i := 0 to length(tracks)-1 do begin
    if (i = selectedTrackIndex) then begin
      dc.fillRect(Rect(atX+1,atY+5+i*20, width-2, 18), RGBA.create(15,20,250,round(alpha*128)));
      textColor.init(255,255,0,round(255*alpha));
    end else
      textColor.init(250,250,250,round(240*alpha));
    font.textOut(screen.canvas, atX+5, atY+5+i*20, tracks[i].title, textColor);
    font.textOut(screen.canvas, atX+width-5-50, atY+5+i*20, format('(%s:%s)', [intToStr(tracks[i].minutes), intToStr(tracks[i].seconds,2)]), textColor);
  end;
end;

procedure applySelection();
var
  track: tTrack;
begin
  note('Applying selection song');

  track := tracks[selectedTrackIndex];
  guiTitle.text := track.title;
  // todo: support fading again
  //guiTitle.showForSeconds := 3.5;

  {buffer 0.5 seconds, enough time to read the next file}
  if musicReader.isLoaded then begin
    note('Prebuffering before load');
    musicUpdate(20);
  end;

  note('Loading new track');
  musicReader.open(track.filename);
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
  // todo: get this working again.
  //guiTitle.showForSeconds := 3.5;
  musicReader.close();
  musicReader.open(track.filename);
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
  bounds: tRect;
  oldBufferPos: dword;
  elapsed: double;
  x,y: integer;
  key: tKeyPair;
  decodeSpeed: single;
  exitFlag: boolean;
  cpuUsage: single;
  statsString: string;
  refMusic: tSound;
  musicStats: tMusicStats;

  gui: tGui;

  showBuffer: boolean = false;

begin

  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    fatal('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    fatal('Requires 1MB video card.');

  videoDriver.setTrueColor(640,480);
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;

  {init vars}
  oldBufferPos := 0;

  {setup gui}
  gui := tGui.create();
  gui.handlesInput := false;

  guiTitle := tGuiLabel.create(point(screen.width div 2, screen.height div 4-60));
  guiTitle.fontStyle.centered := true;
  //todo:
  //guiTitle.autoFade := true;
  //guiTitle.alpha := 0;
  gui.append(guiTitle);

  guiStats := tGuiLabel.create(point(10, screen.height-30));
  guiStats.isVisible := false;
  gui.append(guiStats);

  guiFPS := tGuiLabel.create(point(10, 10));
  guiFPS.isVisible := false;
  gui.append(guiFPS);

  guiBuffer := tGuiBuffer.create(
    point(screen.width-10-5*(getMusicStats().bufferFramesMax div 4), 10),
    4, getMusicStats().bufferFramesMax div 4
  );
  guiBuffer.isVisible := false;
  gui.append(guiBuffer);

  {load tracks}
  files := fileSystem.listFiles('music\*.a96');
  files.sort();
  setLength(tracks, 0);
  for filename in files do begin
    tracks.append(tTrack.init(joinPath('music', filename)));
  end;
  if length(tracks) = 0 then fatal('No music found');

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
  screen.background := tPage.Load('res\bg.p96');

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
      bounds := Rect((640-hdrWave.width) div 2, 480-hdrWave.height-(hdrWave.height div 2), hdrWave.width, hdrWave.height);
      hdrWave.fade(0.92);
      displayWaveFormHDR(hdrWave, Rect(0, 0, bounds.width, bounds.height), uMixer.scratchBufferPtr, 256, 512, 8*1024);
      hdrWave.mixTo(screen.canvas, bounds.x, bounds.y);
      screen.markRegion(bounds);
      stopTimer('waveform');

      {phase}
      startTimer('phase');
      bounds := Rect((640-hdrPhase.width) div 2-10, (480-hdrPhase.height) div 2-74, hdrPhase.width, hdrPhase.height);
      hdrPhase.fade(0.95);
      displayPhaseScopeHDR(hdrPhase, Rect(0, 0, bounds.width, bounds.height), uMixer.scratchBufferPtr, 512, 256);
      hdrPhase.mulTo(screen.canvas, bounds.x, bounds.y);
      screen.markRegion(bounds);
      stopTimer('phase');

      {fps:}
      if assigned(getTimer('main')) then
        elapsed := getTimer('main').avElapsed
      else
        elapsed := -1;
      guiFPS.text := format('%f', [1/elapsed]);

      {stats}
      guiStats.text := format('CPU: %f%% RAM:%.2fMB', [100*getMusicStats().cpuUsage, getUsedMemory/1024/1024]);
      if mixClickDetection > 0 then
        guiStats.text := guiStats.text + ' click:'+intToStr(mixClickDetection);

      {buffer}
      guiBuffer.value := getMusicStats().bufferFramesFilled div 4;
      guiBuffer.isVisible := showBuffer or (guiBuffer.value < 4);

      key := dosGetKey();
      if key.code <> 0 then case key.code of
        key_up: moveTrackSelection(-1);
        key_down: moveTrackSelection(+1);
        key_enter: applySelection();
        key_esc: exitFlag := true;
        key_s: guiStats.isVisible := not guiStats.isVisible;
        key_f: guiFPS.isVisible := not guiFPS.isVisible;
        key_b: showBuffer := not showBuffer;
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
      gui.draw(screen.getDC());

      screen.flipAll();

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

  autoHeapSize();

  textAttr := White + Blue*16;
  clrscr;

  uDebug.VERBOSE_SCREEN := llNote;

  runTestSuites();
  initKeyboard();

  if paramCount = 0 then
    mode := 'play'
  else
    mode := paramStr(1).toLower();

  if mode = 'play' then
    soundPlayer()
  else if mode = 'test' then
    testCompression(false)
  else if mode = 'fast' then
    testCompression(true)
  else
    fatal('Invalid mode '+mode);

  textAttr := LIGHTGRAY;

end.
