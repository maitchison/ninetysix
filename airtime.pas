{Airtime game}
program airtime;

uses
  startup,
  debug,
  utils,
  math,
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
  slideSFX: tSoundEffect;
  engineSFX: tSoundEffect;
  startSFX: tSoundEffect;
  trackSprite: tSprite;
  carVox, wheelVox: tVoxelSprite;

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
procedure debugTextOut(dx,dy: integer; s: string); forward;
function worldToCanvas(p: V3D): tPoint; forward;

{---------------------------------------------------------------------}

type
  tCar = class
  const
    CAR_SCALE = 0.5; // 0.5
  protected
    procedure drawTires(side: integer);
    procedure tractionSimple();
    procedure tractionComplex();
  public
    pos: V3D;
    vel: V3D;
    zAngle: single;
    tilt: single;

    mass: single;
    tireTraction: single;
    tireHeat: single;       //reduces traction
    enginePower: single;
    dragCoefficent: single;
    constantDrag: single;
    vox: tVoxelSprite;

    constructor create(aVox: tVoxelSprite);

    function getWheelPosition(dx,dy: integer): V3D;

    procedure draw();
    procedure update();
  end;

constructor tCar.create(aVox: tVoxelSprite);
begin
  inherited create();
  pos := V3D.create(videoDriver.width div 2,videoDriver.height div 2,0);
  vel := V3D.create(0,0,0);
  vox := aVox;
  zAngle := 0;
  tilt := 0;
  mass := 1;
  enginePower := 300;
  tireTraction := 410;
  tireHeat := 0;
  dragCoefficent := 0.0025;
  constantDrag := 50;
end;

{draws tires. If side < 0 then tires behind car are drawn,
 if side > 0 then tires infront are draw, and if side = 0 then all
 tires are drawn}
procedure tCar.drawTires(side: integer);
var
  i,j, dx, dy: int32;
  tireAngle: single;
  flip: single;
begin
  for i := 0 to 1 do
    for j := 0 to 1 do begin
      dx := i*2-1;
      dy := j*2-1;
      tireAngle := zAngle+(pi*(1-j));
      if cos(tireAngle) * side >= 0 then
      screen.markRegion(wheelVox.draw(
        screen.canvas,
        getWheelPosition(dx, dy),
        tireAngle, getSec*dy*vel.abs/200, pi/2,
        1.85*CAR_SCALE) //slightly oversized wheels
      );
    end;
end;

procedure tCar.draw();
var
  startTime: double;
begin

  startTime := getSec;

  drawTires(-1);
  screen.markRegion(vox.draw(screen.canvas, pos, zAngle, 0, tilt/2, CAR_SCALE));
  drawTires(+1);

  if carDrawTime = 0 then
    carDrawTime := (getSec - startTime)
  else
    carDrawTime := (carDrawTime * 0.95) + 0.05*(getSec - startTime);
end;

{returns wheel positon in world space, e.g. -1, -1 for front left tire}
function tCar.getWheelPosition(dx,dy: integer): V3D;
var
  p: V3D;
  t1: single;
begin
  p := V3D.create(-2+16*dx, 12*dy, +2).rotated(0, 0, zAngle) * CAR_SCALE;
  result := p + pos;
end;

procedure tCar.tractionSimple();
var
  targetVelocity: v3d;
  tractionForce: v3d;
  drag, coefficent: single;
  dragForce: v3d;
begin

  {simplified traction model}
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

end;

procedure tCar.tractionComplex();
var
  slipAngle, dirAngle, velAngle: single;
  dir: v3d;
  requiredTractionForce, tractionForce: v3d;
  targetVelocity: v3d;
  slidingPower: int32;
  skidVolume: single;
  alpha: single;
  drawPos: tPoint;
begin

  dir := v3d.create(-1,0,0).rotated(0,0,zAngle);
  drawPos := worldToCanvas(pos);

  if elapsed <= 0 then exit;

  {-----------------------------------}
  {tire traction}

  if vel.abs < 0.1 then begin
    {perfect traction for small speeds}
    slipAngle := 0;
    //...
  end else begin
    {calculate the slip angle}
    slipAngle := radToDeg(arcCos(vel.dot(dir) / vel.abs));

    targetVelocity := v3d.create(-vel.abs,0,0).rotated(0,0,zAngle);
    {force required to correct velocity *this* frame}
    requiredTractionForce := (targetVelocity-vel)*(mass/elapsed);
    tractionForce := requiredTractionForce;

    if keyDown(key_z) then
      tractionForce.clip(0) {no traction}
    else if keyDown(key_x) then
      tractionForce.clip(9999999) {perfect traction}
    else begin
      {model how well our tires work}
      tractionForce.clip(clamp(tireTraction-(tireHeat*2), 0, tireTraction));
    end;

    slidingPower := trunc(requiredTractionForce.abs - tractionForce.abs);

    tireHeat += slidingPower / 1000;
    tireHeat := 0.93 * tireHeat;

    {sound is always playing, we only adjust the volume}
    skidVolume := clamp(slidingPower/5000, 0, 1.0);
    //if skidVolume < mixer.channels[2].volume then alpha := EASE_OUT else alpha := EASE_IN;
    //mixer.channels[2].volume := alpha * mixer.channels[2].volume + (1-alpha)*skidVolume;
    mixer.channels[2].volume := skidVolume * 0.65;
    //mixer.channels[2].pitch := clamp(0.85+tireHeat/400, 0.85, 2.0);

    // write skidmarks to map
    if (skidVolume > 0.1) and assigned(screen.background) then begin
      // todo: find wheel locations
      screen.background.page.putPixel(
        drawPos.x+(rnd-rnd) div 64, drawPos.y+(rnd-rnd) div 64,
      RGBA.create(0,0,0,32));
      screen.background.page.putPixel(
        drawPos.x+(rnd-rnd) div 64, drawPos.y+(rnd-rnd) div 64,
      RGBA.create(0,0,0,32));
    end;

    // for the moment engine sound is speed, which is not quiet right
    // should be 'revs'
    mixer.channels[3].volume := clamp(vel.abs/200, 0, 1.0);
    mixer.channels[3].pitch := 0.5 + clamp(vel.abs/250, 0, 4.0);

    debugTextOut(drawPos.x, drawPos.y-50, format('%.1f %.1f', [slidingPower/5000, tireHeat]));

    vel += tractionForce * (elapsed / mass);

  end;

  debugTextOut(
    drawPos.x-120, drawPos.y+50,
    format('vel:%.1f slipa:%.1f tf:%.1f/%.1f fps:%.2f',
    [vel.abs, slipAngle, tractionForce.abs, requiredTractionForce.abs, 1/elapsed]
  ));

  (*

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

  screen.copyRegion(tRect.create(300, 300, 200, 20));

   tractionForce := tractionForce.rotated(0,0,+zAngle);

  vel += tractionForce * (1/mass);
  *)
end;

procedure tCar.update();
var
  drag: single;
  dir: v3d;
  engineForce, lateralForce, dragForce: v3d;
  targetVelocity: v3d;
  x,y: single;
  drawPos: tPoint;
const
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
    engineForce := dir * enginePower;

  {movement from last rame}
  {note: we correct for isometric projection here}
  pos += vel * elapsed; {stub on the *100}

  {engine in 'spaceship' mode}
  vel += engineForce * (1/mass) * elapsed;

  {handle traction}
  self.tractionComplex();

  {handle drag}
  drag := constantDrag + dragCoefficent * vel.abs2;
  dragForce := vel.normed() * drag;
  dragForce *= (elapsed/mass);
  dragForce.clip(vel.abs);
  vel -= dragForce;

  {boundaries}
  drawPos := worldToCanvas(pos);

  if drawPos.x < BOUNDARY then vel.x += (BOUNDARY-drawPos.x) * 1.0;
  if drawPos.y < BOUNDARY then vel.y += (BOUNDARY-drawPos.y) * 1.0;
  if drawPos.x > 1024-BOUNDARY then vel.x -= (drawPos.x-(1024-BOUNDARY)) * 1.0;
  if drawPos.y > 480-BOUNDARY then vel.y -= (drawPos.y-(480-BOUNDARY)) * 1.0;

  tilt *= decayFactor(0.5);
end;

{---------------------------------------------------------------------}

{applies our isometric transformation}
function worldToCanvas(p: V3D): tPoint;
begin
  result.x := round(p.x);
  result.y := round(p.rotated(-0.615, 0, 0).y);
end;

procedure debugTextOut(dx,dy: integer; s: string);
var
  r: tRect;
begin
  r := textExtents(s).padded(2);
  r.x += dx;
  r.y += dy;
  screen.markRegion(r);
  textOut(
    screen.canvas,
    dx, dy, s,
    RGBA.create(255,255,255)
  )
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
  wheelVox := tVoxelSprite.loadFromFile('res\wheel1', 8);

  if cpuInfo.ram > 40*1024*1024 then
    {16bit music if we have the ram for it}
    music := tSoundEffect.loadFromWave('res\music16.wav')
  else
    music := tSoundEffect.loadFromWave('res\music8.wav');

  {the sound engine is currently optimized for 16bit stereo sound}
  slideSFX := tSoundEffect.loadFromWave('res\skid.wav').asFormat(AF_16_STEREO);
  engineSFX:= tSoundEffect.loadFromWave('res\engine2.wav').asFormat(AF_16_STEREO);
  startSFX := tSoundEffect.loadFromWave('res\start.wav').asFormat(AF_16_STEREO);

end;

procedure drawGUI();
var
  fps, tpf: double;
  mixerCpuUsage: double;
begin

  if elapsed > 0 then fps := 1.0 / elapsed else fps := -1;
  tpf := VX_TRACE_COUNT;

  if lastChunkTime > 0 then
    mixerCpuUsage := 100 * lastChunkTime / (HALF_BUFFER_SIZE/4/44100)
  else
    mixerCpuUsage := -1;

  GUILabel(screen.canvas, 10, 10, format('FPS:%f Car:%fms SFX: %f%%', [fps,carDrawTime*1000,mixerCpuUsage]));
  screen.markRegion(tRect.create(10, 10, 300, 22), FG_FLIP);
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

    screen.clearAll();

    startTime := getSec;

    if benchmarkMode then begin
      screen.markRegion(carVox.draw(screen.canvas, V3D.create(320, 440, 0), 0.3, 0, 0.2, carScale));
    end else
      screen.markRegion(carVox.draw(screen.canvas, V3D.create(320, 440, 0), xTheta, 0, zTheta, carScale));

    if carDrawTime = 0 then
      carDrawTime := (getSec - startTime)
    else
      carDrawTime := (carDrawTime * 0.90) + 0.10*(getSec - startTime);

    drawGUI();

    mixer.mute := keyDown(key_m);
    mixer.noise := keyDown(key_n);

    if keyDown(key_b) then begin
      benchmarkMode := true;
      carScale := 2.0;
    end;

    if keyDown(key_s) and (getSec > nextBellSound) then begin
      mixer.play(slideSFX, SCS_NEXTFREE, (256+rnd)/512, (rnd+64)/256);
      if getSec > nextBellSound + (30/136) then
        nextBellSound := getSec + (30/136)
      else
        nextBellSound += (30/136)
    end;

    screen.flipAll();

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
  car: tCar;
  camX, camY: single;
  drawPos: tPoint;

begin
  note('Main loop started');

  videoDriver.setMode(320,240,32);
  videoDriver.setLogicalSize(1024,480);

  screen.reset();
  screen.background := trackSprite;
  screen.clear();
  screen.pageFlip();

  // turn off music
  // todo: find a better way of doing this
  mixer.channels[1].reset();

  // start our sliding sound
  mixer.playRepeat(slideSFX, SCS_FIXED2);
  mixer.channels[2].volume := 0.0;

  mixer.playRepeat(engineSFX, SCS_FIXED3);
  mixer.channels[3].volume := 0.0;

  mixer.play(startSFX);

  car := tCar.create(carVox);
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

    drawPos := worldToCanvas(car.pos);
    camX += ((drawPos.x-CamX)*0.10);
    camY += ((drawPos.y+50-CamY)*0.10); // why +50?
    car.draw();

    drawGUI();

    {debugging}
    screen.SHOW_DIRTY_RECTS := keyDown(key_d);

    {more debuggug}
    if keyDown(key_1) then
      car.tireTraction -= 10;
    if keyDown(key_2) then
      car.tireTraction += 10;

    if keyDown(key_3) then
      delay(100); // pretend to be slow

    screen.setViewPort(
      round(camX)-(videoDriver.physicalWidth div 2), round(camY)-(videoDriver.physicalHeight div 2),
      false
    );
    videoDriver.waitVSync();
    screen.flipAll();

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

  screen := tScreen.create();
  mixer.play(music, SCS_FIXED1);

  initMouse();
  initKeyboard();

  titleScreen();

  videoDriver.setText();
  printLog();
end.
