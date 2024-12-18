{Airtime game}
program airtime;

uses
  startup,
  debug,
  utils,
  vga,
  vesa,
  graph32,
  graph2d,
  test,
  sbDriver,
  mouse,
  keyboard,
  vertex,
  sprite,
  gui,
  lc96,
  voxel,
  screen,
  mix,
  font,
  sound,
  go32;


var

  {screen}
  screen: tScreen;

  {resources}
  titleBackground: tSprite;
  music: tSoundEffect;
  trackSprite: tSprite;
  carVox: tVoxelSprite;

  {global time keeper}
  elapsed: double = 0;
  smoothElapsed: double = 0;
  gameTime: double = 0;
  frameCount: dword = 0;

  carDrawTime: double = 0;

procedure mainLoop(); forward;

type
  tCar = class
    pos: V3D;
    vel: V3D;
    zAngle: single;
    tilt: single;
    constructor create();
    procedure draw();
    procedure update();
  end;


constructor tCar.create();
begin
  pos := V3D.create(videoDriver.width div 2,videoDriver.height div 2,0);
  vel := V3D.create(0,0,0);
  zAngle := 0;
  tilt := 0;
end;

procedure tCar.draw();
var
  startTime: double;
  dx, dy: int32;
const
  PADDING = 25;
begin

  {correct for isometric}
  dx := round(pos.x);
  dy := round(pos.rotated(0.955, 0,0).y);

  if not screen.rect.isInside(dx, dy) then exit;

  startTime := getSec;
  carVox.draw(screen.canvas, dx, dy, zAngle, 0, 0, 0.5);
  if carDrawTime = 0 then
    carDrawTime := (getSec - startTime)
  else
    carDrawTime := (carDrawTime * 0.95) + 0.05*(getSec - startTime);

  screen.markRegion(tRect.create(dx-PADDING, dy-PADDING, PADDING*2, PADDING*2));
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

procedure tCar.update();
var
  drag, coefficent: single;
  slipAngle: single;

  dir: v3d;

  engineForce: v3d;
  lateralForce: v3d;
  dragForce: v3d;

  tractionForce: v3d;
  targetVelocity: v3d;
  lateralForceCap: single;

  x,y: single;

const
  mass: single = 1;
  slipThreshold = 10/180*3.1415926;   {point at which tires start to slip}
  BOUNDARY = 50;

begin

  dir := v3d.create(-1,0,0).rotated(0,0,zAngle);
  dragForce := v3d.create(0,0,0);
  engineForce := v3d.create(0,0,0);
  lateralForce := v3d.create(0,0,0);

  {process input}
  if keyDown(key_left) then begin
    zAngle -= elapsed*2.5;
    tilt += elapsed*1.0;
  end;
  if keyDown(key_right) then begin
    zAngle += elapsed*2.5;
    tilt -= elapsed*1.0;
  end;
  if keyDown(key_up) then
    engineForce := dir * 500;

  {movement from last rame}
  {note: we correct for isometric projection here}
  pos += vel * elapsed; {stub on the *100}


  {-----------------------------------}
  {engine in 'spaceship' mode}

  vel += engineForce * (1/mass) * elapsed;

  {-----------------------------------}
  {tire traction}

  (*
  {calculate the slip angle}
  slipAngle := arcCos(vel.dot(dir) / vel.abs);

  {linear until a point then constant, but really I want this to
   decrease after a point}
  lateralForceCap := min(slipAngle, slipThreshold) * 40000;
  if keyDown(key_x) then
    lateralForceCap := 0;
  if keyDown(key_z) then
    lateralForceCap := 99999999999;

  targetVelocity := v3d.create(-vel.abs,0,0).rotated(0,0,zAngle);

  tractionForce := ((targetVelocity-vel)*mass).rotated(0,0,-zAngle);

  tractionForce.x := 0;  {logatudinal, could be used for breaking.}
  tractionForce.y := clamp(tractionForce.y, -lateralForceCap, +lateralForceCap);
  tractionForce.z := 0;

  screen.clearRegion(tRect.create(300, 300, 200, 20));
  textOut(screen.canvas, 300, 300, format('%f %f %f',[log2(1+abs(tractionForce.x)), log2(1+abs(tractionForce.y)), log2(1+tractionForce.z)]), RGBA.create(255,255,255));
  screen.copyRegion(tRect.create(300, 300, 200, 20));

   tractionForce := tractionForce.rotated(0,0,+zAngle);

  vel += tractionForce * (1/mass);
  *)

  {simplified model}
  targetVelocity := v3d.create(-vel.abs,0,0).rotated(0,0,zAngle);
  tractionForce := ((targetVelocity-vel)*mass);
  if keyDown(key_x) then begin
    {perfect traction}
  end else if keyDown(key_z) then begin
    tractionForce.clip(0) {no traction}
  end else begin
    {standard traction}
    {note: tires are usually better than engine in terms of acceleration}
    tractionForce.clip(1000);
  end;

  vel += tractionForce * (elapsed/mass);

  {-----------------------------------}
  {drag
    constant is static resistance
    linear is rolling sitance nad internal friction
    quadratic is due to air resistance
  }

  (*
  drag := 30000.0 + 100.0*vel.abs + 10.0*vel.abs2;
  if (drag*elapsed/mass > vel.abs) then
    vel *= 0
  else begin
    dragForce := vel.normed() * drag;
    vel -= dragForce * (elapsed/mass);
  end;
  *)

  {again a simpler model}
  drag := 3.0 + 1.5 * vel.abs;
  dragForce := vel.normed() * drag;
  dragForce *= (elapsed/mass);
  dragForce.clip(vel.abs);

  vel -= dragForce;

  {-----------------------------------}

  {boundaries}
  x := pos.x;
  y := round(pos.rotated(0.955, 0,0).y);

  if x < BOUNDARY then vel.x += (BOUNDARY-x) * 1.0;
  if y < BOUNDARY then vel.y += (BOUNDARY-y) * 1.0;
  if x > 1024-BOUNDARY then vel.x -= (x-(1024-BOUNDARY)) * 1.0;
  if y > 480-BOUNDARY then vel.y -= (y-(480-BOUNDARY)) * 1.0;

  tilt *= decayFactor(0.5);
end;

{-------------------------------------------------}

function loadSprite(filename: shortstring): tSprite;
var
  startTime: double;
begin
  startTime := getSec;
  result := tSprite.create(loadLC96('res\'+filename+'.p96'));
  note(format(' -loaded %s (%dx%d) in %fs', [filename, result.width, result.height, getSec-startTime]));
end;

procedure loadResources();
begin

  note('Loading Resources.');

  titleBackground := loadSprite('title');
  trackSprite := loadSprite('track1');

  carVox := tVoxelSprite.loadFromFile('res\car1', 32);

  if cpuInfo.ram > 40*1024*1024 then
    {16bit music if we have the ram for it}
    music := tSoundEffect.loadFromWave('res\music16.wav')
  else
    music := tSoundEffect.loadFromWave('res\music8.wav');
end;

procedure drawGUI();
var
  fps: double;
  tpf: double;
  mixerCpuUsage: double;
begin

  if elapsed > 0 then fps := 1.0 / elapsed else fps := -1;
  tpf := VX_TRACE_COUNT;

  if lastChunkTime > 0 then
    mixerCpuUsage := 100 * lastChunkTime / (HALF_BUFFER_SIZE/4/44100)
  else
    mixerCpuUsage := -1;

  GUILabel(screen.canvas, 10, 10, format('FPS:%f Car:%fms SFX: %f%%', [fps,carDrawTime*1000,mixerCpuUsage]));
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

begin

  logHeapStatus('Title screen started');

  b := 0;
  benchmarkMode := false;
  carScale := 0.75;

  titleBackground.page.fillRect(tRect.create(0, 360-25, 640, 50), RGBA.create(25,25,50,128));
  titleBackground.page.fillRect(tRect.create(0, 360-24, 640, 48), RGBA.create(25,25,50,128));
  titleBackground.page.fillRect(tRect.create(0, 360-23, 640, 46), RGBA.create(25,25,50,128));

  textOut(titleBackground.page, 640-140+1, 480-25+1, 'v0.1a (09/12/2024)', RGBA.create(0,0,0));
  textOut(titleBackground.page, 640-140, 480-25, 'v0.1a (09/12/2024)', RGBA.create(250,250,250,240));

  screen.background := titleBackground;
  screen.clear();

  screen.pageFlip();

  startClock := getSec;
  lastClock := startClock;

  while True do begin

    if keyDown(key_1) then
      VX_GHOST_MODE := not keyDown(key_leftshift);
    if keyDown(key_2) then
      VX_SHOW_TRACE_EXITS := not keyDown(key_leftshift);

    {time keeping}
    thisClock := getSec;
    elapsed := thisClock-lastClock;
    smoothElapsed := smoothElapsed * 0.95 + elapsed * 0.05;
    if keyDown(key_space) then
      elapsed /= 100;
    gameTime += elapsed;
    lastClock := thisClock;
    inc(frameCount);

    {subRegion.blit(screen.canvas, 320-30, 360-30);}

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

    padding := round(60 * carScale/0.75);

    screen.clearRegion(tRect.create(320-(padding div 2), 360-(padding div 2), padding, padding));

    startTime := getSec;
    if benchmarkMode then begin
      carVox.draw(screen.canvas, 320, 360, 0.3, 0, 0.2, carScale);
    end else
      carVox.draw(screen.canvas, 320, 360, xTheta, 0, zTheta, carScale);
    if carDrawTime = 0 then
      carDrawTime := (getSec - startTime)
    else
      carDrawTime := (carDrawTime * 0.90) + 0.10*(getSec - startTime);

    drawGUI();

    screen.copyRegion(tRect.create(10, 10, 300, 25));
    screen.copyRegion(tRect.create(320-(padding div 2), 360-(padding div 2), padding, padding));

    mixer.mute := keyDown(key_m);
    mixer.noise := keyDown(key_n);

    if keyDown(key_b) then begin
      benchmarkMode := true;
      carScale := 2.0;
    end;

    if keyDown(key_e) then begin
      {force an error}
      asm
        mov edi, 0
        mov ecx, 4
        stosd
      end;
    end;

    if keyDown(key_p) and keyDown(key_l) and keyDown(key_y) then mainLoop();

    if keyDown(key_q) or keyDown(key_esc) then break;
  end;
end;

procedure mainLoop();
var
  startClock,lastClock,thisClock: double;
  startTime: double;
  car: tCar;
  camX, camY: single;

begin
  note('Main loop started');

  videoDriver.setMode(320,240,32);
  videoDriver.setLogicalSize(1024,480);

  screen.reset();
  screen.background := trackSprite;
  screen.clear();
  screen.pageFlip();

  car := tCar.create();
  car.pos := V3D.create(300,300,0);

  startClock := getSec;
  lastClock := startClock;

  camX := 0;
  camY := 0;

  while True do begin


    {time keeping}
    thisClock := getSec;
    elapsed := thisClock-lastClock;
    if keyDown(key_space) then
      elapsed /= 100;
    gameTime += elapsed;
    lastClock := thisClock;
    inc(frameCount);

    screen.clearAll();

    car.update();

    camX += ((car.pos.x-CamX)*0.05);
    camY += ((car.pos.rotated(0.955, 0,0).y-CamY)*0.05);
    car.draw();

    // not really needed
    //screen.waitVSync();
    screen.setViewPort(round(camX)-(videoDriver.physicalWidth div 2), round(camY)-(videoDriver.physicalHeight div 2));
    screen.flipAll();

    drawGUI();

    if keyDown(key_q) or keyDown(key_esc) then break;
  end;
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

  screen.create();
  mixer.play(music);

  initMouse();
  initKeyboard();

  titleScreen();

  videoDriver.setText();
  printLog();
end.
