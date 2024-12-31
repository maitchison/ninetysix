{Airtime game}
program airtime;

uses
  startup,
  {$i units.inc},
  {other stuff}
  lc96,
  font,
  s3,
  {airtime}
  raceTrack,
  car,
  {fpc}
  go32;

var
  {screen}
  screen: tScreen;

  {resources}
  titleBackground: tPage;
  music: tSoundEffect;

  startSFX: tSoundEffect;
  track: tRaceTrack;

  {global time keeper}
  elapsed: double = 0;
  smoothElapsed: double = 0;
  gameTime: double = 0;
  frameCount: dword = 0;

  carDrawTime: double = 0;

var
  nextBellSound: double = 0;

procedure mainLoop(); forward;
function decayFactor(const decayTime: single): single; forward;

const
  SNOW_PARTICLES = 128;

type
  tSnowParticle = record
    phase: single;
    pos: V3D;
    procedure reset();
    procedure update();
    procedure draw();
  end;

  tSnowField = class
    snow: array[0..SNOW_PARTICLES-1] of tSnowParticle;
    procedure reset();
    procedure update();
    procedure draw();
    constructor Create();
  end;


procedure tSnowParticle.reset();
begin
  pos.x := (rnd*3)-384 + 320;
  pos.y := rnd div 16;
  pos.z := 0;
  phase := rnd/256;
end;

procedure tSnowParticle.update();
begin
  pos.x += sin(phase*2+getSec);
  pos.y += (3.5 + cos(getSec) + phase) * elapsed * 30;
  if pos.y > 480 then
    reset();
end;

procedure tSnowParticle.draw();
var
  dx,dy: integer;
begin
  dx := round(pos.x);
  dy := round(pos.y);
  screen.markRegion(tRect.create(dx-1, dy-1, 3, 3));
  screen.canvas.putPixel(dx, dy, RGBA.create(250, 250, 250, 240));
  screen.canvas.putPixel(dx-1, dy, RGBA.create(250, 250, 250, 140));
  screen.canvas.putPixel(dx+1, dy, RGBA.create(250, 250, 250, 140));
  screen.canvas.putPixel(dx, dy-1, RGBA.create(250, 250, 250, 140));
  screen.canvas.putPixel(dx, dy+1, RGBA.create(250, 250, 250, 140));
end;

procedure tSnowField.reset();
var
  i,j: integer;
begin
  for i := 0 to SNOW_PARTICLES-1 do begin
    snow[i].reset();
    snow[i].pos.y := rnd+rnd;
    for j := 0 to rnd do
      snow[i].update();
  end;
end;

procedure tSnowField.update();
var
  i: integer;
begin
  for i := 0 to SNOW_PARTICLES-1 do
    snow[i].update();
end;

procedure tSnowField.draw();
var
  i: integer;
begin
  for i := 0 to SNOW_PARTICLES-1 do
    snow[i].draw();
end;

constructor tSnowField.Create();
begin
  inherited Create();
  reset();
end;


{-----------------------------------------------------------}

var
  CC_RED,
  CC_POLICE,
  CC_BOX,
  CC_SANTA: tCarChassis;

procedure debugTextOut(dx,dy: integer; s: string;col: RGBA); overload;
var
  r: tRect;
begin
  // grr, otherwise the letter 'p' gets left behind.
  r := textExtents(s).padded(2);
  r.x += dx;
  r.y += dy;
  screen.markRegion(r);
  textOut(screen.canvas, dx, dy, s, col);
end;

procedure debugTextOut(dx,dy: integer; s: string); overload;
begin
  debugTextOut(dx, dy, s, RGBA.create(255,255,255));
end;

{returns decay factor for with given halflife (in seconds) over current
 elapsed time}
function decayFactor(const decayTime: single): single;
var
  rate: single;
begin
  rate := ln(2.0) / decayTime;
  result := exp(-rate*elapsed);
end;

{-------------------------------------------------}

procedure loadResources();
var
  musicPostfix: string;
begin

  note('Loading Resources.');

  if cpuInfo.ram > 70*1024*1024 then
    {8bit music if we don't have enough ram.}
    musicPostfix := '_8bit'
  else
    musicPostfix := '';


  {music first}
  if config.XMAS then
    music := tSoundEffect.loadFromWave('res\music2'+musicPostfix+'.wav')
  else
    music := tSoundEffect.loadFromWave('res\music1'+musicPostfix+'.wav');

  mixer.play(music, SCS_FIXED1);

  if config.XMAS then
    titleBackground := tPage.Load('res\XMAS_title.p96')
  else
    titleBackground := tPage.Load('res\title.p96');

  {setup chassis}
  {todo: have these as meta data}
  with CC_RED do begin
    carHeight := 5;
    wheelPos := V3D.create(8, 7, 0);
    wheelOffset := V3D.create(-1, 0, 0);
    wheelSize := 1.0;
    vox := tVoxelSprite.loadFromFile('res\carRed16', 16);;
  end;
  with CC_POLICE do begin
    carHeight := 5;
    wheelPos := V3D.create(10, 7, 0);
    wheelOffset := V3D.create(+1, 0, 3);
    wheelSize := 1.0;
    vox := tVoxelSprite.loadFromFile('res\carPolice16', 16);
  end;
  with CC_BOX do begin
    carHeight := 5;
    wheelPos := V3D.create(9, 7, 0);
    wheelOffset := V3D.create(-1, 0, 1);
    wheelSize := 1.0;
    vox := tVoxelSprite.loadFromFile('res\carBox16', 16);
  end;
  with CC_SANTA do begin
    wheelPos := V3D.create(10, 7, 0);
    wheelOffset := V3D.create(+1, 0, 3);
    wheelSize := 0.0;
    vox := tVoxelSprite.loadFromFile('res\carSanta16', 16);
    carHeight := 16;
  end;

  if config.XMAS then begin
    CC_RED := CC_SANTA;
    CC_BOX := CC_SANTA;
  end;

  startSFX := tSoundEffect.loadFromWave('res\start.wav').asFormat(AF_16_STEREO);

  loadCarResources();
end;

procedure drawGUI();
var
  fps, tpf: double;
  mixerCpuUsage: double;
begin

  //stub
  exit;

  if elapsed > 0 then fps := 1.0 / elapsed else fps := -1;
  tpf := VX_TRACE_COUNT;

  if lastChunkTime > 0 then
    mixerCpuUsage := 100 * lastChunkTime / (HALF_BUFFER_SIZE/4/44100)
  else
    mixerCpuUsage := -1;

  GUILabel(screen.canvas, 10, 10, format('FPS:%f Car:%fms SFX: %f%%', [fps,carDrawTime*1000,mixerCpuUsage]));
  screen.markRegion(tRect.create(10, 10, 300, 22), FG_FLIP);
end;

procedure drawFPS();
var
  fps: double;
  avElapsed: single;
  timer: tTimer;
  atX, atY: int32;
  bounds: tRect;
begin
  timer := getTimer('frame');
  if not assigned(timer) then exit;
  avElapsed := timer.avElapsed;
  if avElapsed <= 0 then
    fps := -1
  else
    fps := 1 / avElapsed;
  atX := screen.getViewport().right-86;
  atY := screen.getViewport().top;
  bounds := tRect.create(atX, atY, 86, 22);
  screen.canvas.fillrect(bounds, RGBA.create(0,0,0,128));
  GUIText(screen.canvas, atX+2, atY+2, format('FPS:%f', [fps]));
  screen.markRegion(bounds);
end;

procedure titleScreen();
var
  thisClock, startClock, lastClock: double;
  startTime: double;
  xAngle, zAngle: single; {in degrees}
  xTheta, zTheta: single; {in radians}
  k: single;
  b: byte;
  benchmarkMode: boolean;
  padding: integer;
  carScale: single;
  i,j: integer;
  snow: tSnowField;

begin

  logHeapStatus('Title screen started');

  b := 0;
  benchmarkMode := false;
  carScale := 1.5;

  titleBackground.fillRect(tRect.create(0, 360-25, 640, 50), RGBA.create(25,25,50,128));
  titleBackground.fillRect(tRect.create(0, 360-24, 640, 48), RGBA.create(25,25,50,128));
  titleBackground.fillRect(tRect.create(0, 360-23, 640, 46), RGBA.create(25,25,50,128));

  textOut(titleBackground, 640-140+1, 480-25+1, 'v0.1a (09/12/2024)', RGBA.create(0,0,0));
  textOut(titleBackground, 640-140, 480-25, 'v0.1a (09/12/2024)', RGBA.create(250,250,250,240));

  screen.background := titleBackground;

  screen.clear();
  screen.pageFlip();

  startClock := getSec;
  lastClock := startClock;

  if config.XMAS then snow := tSnowField.create() else snow := nil;

  while True do begin

    timer.startTimer('frame');

    if keyDown(key_1) then
      VX_GHOST_MODE := not keyDown(key_leftshift);
    if keyDown(key_2) then
      VX_SHOW_TRACE_EXITS := not keyDown(key_leftshift);

    {time keeping}
    thisClock := getSec;
    elapsed := thisClock-lastClock;
    smoothElapsed := smoothElapsed * 0.95 + elapsed * 0.05;
    gameTime += elapsed;
    lastClock := thisClock;
    inc(frameCount);

    if mouse_b and $1 = $1 then begin
      xAngle := (mouse_x-320)/640*360;
      zAngle := (mouse_y-240)/480*360;
    end else begin
      xAngle := gameTime*50;
      zAngle := gameTime*150;
    end;

    xTheta := xAngle / 180 * 3.1415;
    zTheta := zAngle / 180 * 3.1415;

    if mouse_b and $2 = $2 then begin
      {round to k-degree increments}
      k := 45;
      xTheta := round(xAngle/k)*k / 180 * 3.1415;
      zTheta := round(zAngle/k)*k / 180 * 3.1415;
    end else begin
      xTheta := xAngle / 180 * 3.1415;
      zTheta := zAngle / 180 * 3.1415;
    end;

    screen.clearAll();

    if assigned(snow) then begin
      snow.update();
      snow.draw();
    end;

    startTime := getSec;

    if benchmarkMode then begin
      screen.markRegion(CC_RED.vox.draw(screen.canvas, V3D.create(320, 440, 0), V3D.create(0.3, 0, 0.2), carScale));
    end else
      screen.markRegion(CC_RED.vox.draw(screen.canvas, V3D.create(320, 440, 0), V3D.create(xTheta, 0, zTheta), carScale));

    if carDrawTime = 0 then
      carDrawTime := (getSec - startTime)
    else
      carDrawTime := (carDrawTime * 0.90) + 0.10*(getSec - startTime);

    drawFPS();

    mixer.mute := keyDown(key_m);
    mixer.noise := keyDown(key_n);

    if keyDown(key_b) then begin
      benchmarkMode := true;
      carScale := 3.0;
    end;

    if GUIButton(screen, 320-(150 div 2), 405, 'PLAY') then
      mainLoop();

    screen.flipAll();

    if keyDown(key_e) then begin
      {force an error}
      asm
        mov edi, 0
        mov ecx, 4
        stosd
      end;
    end;

    timer.stopTimer('frame');

    if keyDown(key_p) and keyDown(key_l) and keyDown(key_y) then mainLoop();
    if keyDown(key_q) or keyDown(key_esc) then break;

  end;

  if assigned(snow) then snow.free;

end;

procedure setTrackDisplay(page: tPage);
begin
  screen.reset();
  screen.background := page;
  screen.clear();
  screen.pageFlip();
end;

procedure debugShowTimers(drawPos: tPoint);
var
  i: integer;
begin
  for i := 0 to length(TIMERS)-1 do
    debugTextOut(
      drawPos.x+50, drawPos.y-50+i*15,
      format(
        '%s: %f (%f)',
        [TIMERS[i].tag, 1000*TIMERS[i].elapsed, 1000*TIMERS[i].maxElapsed]
      ));
end;

procedure debugShowWatches();
var
  i: integer;
  secSinceUpdate: single;
  col: RGBA;
begin
  for i := 0 to length(watches.WATCHES)-1 do begin
    secSinceUpdate := getSec - watches.WATCHES[i].lastUpdated;
    if secSinceUpdate < 0.1 then
      col := RGBA.create(255,255,128)
    else
      col := RGBA.create(192,192,192);
    debugTextOut(
      screen.getViewport.x, screen.getViewport.y+i*15,
      watches.WATCHES[i].toString, col
    );
  end;
end;

procedure mainLoop();
var
  startClock,lastClock,thisClock: double;
  car: tCar;
  camX, camY: single;
  drawPos: tPoint;
  dosVersion: string;
begin

  note('Main loop started');

  track := tRaceTrack.Create('res/track2');

  videoDriver.setMode(320,240,32);
  videoDriver.setLogicalSize(track.width, track.height);

  // super inefficent... but needed for dosbox-x due to vsync issues
  dosVersion := getDosVersion();
  note('Dos version detected: '+dosVersion);
  if (dosVersion = 'dosbox-x') or (dosVersion = 'dosbox') then begin
    note(' - using copy method due to VSYNC issues.');
    screen.scrollMode := SSM_COPY;
  end;

  setTrackDisplay(track.background);

  // turn off music
  if not config.XMAS then
    mixer.channels[1].reset();

  initCarResources();

  if not config.XMAS then
    mixer.play(startSFX);

  car := tCar.create(CC_BOX, track);
  car.pos := V3D.create(810, 600, 0);
  car.angle.z := degTorad(90+60);

  startClock := getSec;
  lastClock := startClock;

  camX := 0;
  camY := 0;

  while True do begin

    startTimer('frame');

    {time keeping}
    thisClock := getSec;
    elapsed := thisClock-lastClock;
    if keyDown(key_s) then elapsed /= 10;
    gameTime += elapsed;

    lastClock := thisClock;
    inc(frameCount);

    screen.clearAll();

    car.update(elapsed);

    {move camera}
    drawPos := track.worldToCanvas(car.pos);
    camX += ((drawPos.x-CamX)*decayFactor(0.5));
    camY += ((drawPos.y-CamY)*decayFactor(0.5));
    screen.setViewPort(round(camX)-(videoDriver.physicalWidth div 2), round(camY)-(videoDriver.physicalHeight div 2));

    startTimer('draw_car');
    car.draw(screen);
    stopTimer('draw_car');

    {debugging}
    startTimer('debug');
    if keyDown(key_space) then
      car.vel.z -= 1000*elapsed;
    if keyDown(key_g) then
      {extra gravity}
      car.vel.z += 1000*elapsed;
    screen.SHOW_DIRTY_RECTS := keyDown(key_d);
    if keyDown(key_9) then
      setTrackDisplay(track.background);
    if keyDown(key_8) then
      setTrackDisplay(track.terrainMap);
    if keyDown(key_7) then
      setTrackDisplay(track.heightMap);
    if keyDown(key_b) then
      car.scale := 3.0;
    if keyDown(key_3) then
      delay(100); // pretend to be slow
    if config.DEBUG then begin
      //debugShowTimers(drawPos);
      debugShowWatches();
    end;
    stopTimer('debug');

    {gui}
    startTimer('gui');
    drawGUI();
    drawFPS();
    stopTimer('gui');

    startTimer('vsync');
    if config.VSYNC then
      videoDriver.waitVSync();
    stopTimer('vsync');

    screen.flipAll();

    if keyDown(key_q) or keyDown(key_esc) then break;

    stopTimer('frame');
  end;

  track.free;

end;

begin

  if cpuInfo.ram < 30*1024*1024 then
    error('Application required 30MB of ram.');

  {setup heap logging before units start.}
  {$if declared(Heaptrc)}
  heaptrc.setHeapTraceOutput('heaptrc.txt');
  heaptrc.printfaultyblock := true;
  heaptrc.printleakedblock := true;
  heaptrc.maxprintedblocklength := 64;
  {$endif}

  runTestSuites();

  logHeapStatus('Program start');

  loadResources();

  logHeapStatus('Resources loaded');

  videoDriver := tVesaDriver.create();

  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    error('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 2*1024*1024 then
    error('Requires 2MB video card.');

  videoDriver.setMode(640,480,32);

  screen := tScreen.create();

  initMouse();
  initKeyboard();

  titleScreen();

  videoDriver.setText();
  printLog();
end.
