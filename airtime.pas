{Airtime game}
program airtime;

uses
  startup,
  debug,
  utils,
  myMath,
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
  raceTrack,
  timer,
  go32,
  s3;


CONST

  VSYNC: boolean = False;
  XMAS: boolean = False;

  DEFAULT_CAR_SCALE = 1.0; //0.75
  SKID_VOLUME = 0.5; // 1.0

  ENGINE_RANGE = 0.75; // 4.0
  ENGINE_START = 0.5; // 0.5

var
  {screen}
  screen: tScreen;

  {resources}
  titleBackground: tPage;
  music: tSoundEffect;
  slideSFX: tSoundEffect;
  engineSFX: tSoundEffect;
  startSFX: tSoundEffect;
  track: tRaceTrack;
  wheelVox: tVoxelSprite;

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
  tCarChassis = record
    carHeight: single;
    wheelPos: V3D;
    wheelOffset: V3D;
    wheelSize: single;
    vox: tVoxelSprite;
  end;

  tTerrainDef = record
    tag: string;
    friction: single;
    traction: single;
    bumpiness: single;
  end;

const
  TD_SPACE = 0;
  TD_DIRT = 1;
  TD_GRASS = 2;
  TD_BARRIER = 3;

var
  TERRAIN_DEF: array[0..3] of tTerrainDef = (
    (tag:'space';   friction:0.0; traction:410;  bumpiness:0.00),
    (tag:'dirt';    friction:0.0; traction:410;  bumpiness:0.00),
    (tag:'grass';   friction:4.0; traction:210;  bumpiness:0.03),
    (tag:'barrier'; friction:0.0; traction:1000; bumpiness:0.00)
  );

{-----------------------------------------------------------}

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

type
  tCar = class
  protected
    procedure drawWheels(side: integer);
    procedure tireModel();
  public

    pos: V3D;
    vel: V3D;
    angle: V3D;
    steeringAngle: single;
    currentTerrain: tTerrainDef;
    isOnGround: boolean;

    chassis: tCarChassis;
    scale: single;

    mass: single;
    tireTractionModifier: single;
    tireHeat: single;       //reduces traction
    enginePower: single;
    dragCoefficent: single;
    constantDrag: single;
    tireRotation: double;

    constructor create(aChassis: tCarChassis);

    function getWheelPos(dx,dy: integer): V3D;
    function getWheelAngle(dx,dy: integer): single;
    function vox: tVoxelSprite;

    procedure processMap();
    procedure draw();
    procedure update();
  end;

constructor tCar.create(aChassis: tCarChassis);
begin
  inherited create();
  pos := V3D.create(0,0,0);
  vel := V3D.create(0,0,0);
  angle := V3D.create(0,0,0);
  steeringAngle := 0;
  mass := 1;
  enginePower := 300;
  tireTractionModifier := 1;
  tireHeat := 0;
  dragCoefficent := 0.0025;
  constantDrag := 50;
  tireRotation := 0.0;
  chassis := aChassis;
  scale := DEFAULT_CAR_SCALE;
end;

{draws tires. If side < 0 then tires behind car are drawn,
 if side > 0 then tires infront are draw, and if side = 0 then all
 tires are drawn}
procedure tCar.drawWheels(side: integer);
var
  i,j, dx, dy: int32;
  tireAngle: single;
  flip: single;
begin
  if chassis.wheelSize <= 0 then exit;
  for i := 0 to 1 do
    for j := 0 to 1 do begin
      dx := i*2-1;
      dy := j*2-1;
      tireAngle := getWheelAngle(dx, dy);
      if cos(tireAngle) * side < 0 then continue;
      screen.markRegion(wheelVox.draw(
        screen.canvas,
        getWheelPos(dx, dy),
        V3D.create(pi/2, tireRotation * dy, tireAngle),
        chassis.wheelSize*scale)
      );
    end;
end;

procedure tCar.draw();
var
  startTime: double;
  p: V3D;
begin

  startTime := getSec;

  p := pos;
  p.z := 0;
  screen.markRegion(vox.draw(screen.canvas, p, angle, scale*0.9, true));
  screen.markRegion(vox.draw(screen.canvas, p, angle, scale*1.0, true));
  screen.markRegion(vox.draw(screen.canvas, p, angle, scale*1.1, true));

  drawWheels(-1);
  p := pos;
  p.z -= chassis.carHeight;
  screen.markRegion(vox.draw(screen.canvas, p, angle, scale));
  drawWheels(+1);

  if carDrawTime = 0 then
    carDrawTime := (getSec - startTime)
  else
    carDrawTime := (carDrawTime * 0.95) + 0.05*(getSec - startTime);
end;

function tCar.vox: tVoxelSprite;
begin
  result := chassis.vox;
end;

{returns wheel positon in world space, e.g. -1, -1 for front left tire}
function tCar.getWheelPos(dx,dy: integer): V3D;
var
  p: V3D;
begin
  p := chassis.wheelPos * V3D.create(dx, dy, 0) + chassis.wheelOffset;
  result := p.rotated(angle.x, angle.y, angle.z) * scale + self.pos;
end;

function tCar.getWheelAngle(dx,dy: integer): single;
var
  i,j: integer;
begin
  i := (dx + 1) div 2;
  j := (dy + 1) div 2;
  result := angle.z+(pi*(1-j));
  if i = 0 then
    result -= steeringAngle
  else
    result -= steeringAngle*(3/5);
end;

procedure addSkidMark(pos: V3D);
var
  drawPos: tPoint;
begin
  pos.x += ((rnd-rnd) / 256)*1.5;
  pos.y += ((rnd-rnd) / 256)*1.5;
  drawPos := worldToCanvas(pos);
  screen.background.putPixel(
    drawPos.x, drawPos.y,
    RGBA.create(0,0,0,16)
  );
end;

procedure tCar.tireModel();
var
  slipAngle: single;
  facingDir, wheelDir: V3D;
  requiredTractionForce, tractionForce: v3d;
  targetVelocity: v3d;
  slidingPower: int32;
  skidVolume: single;
  alpha: single;
  drawPos: tPoint;
  i: integer;
  t: single;
  marks: integer;
begin

  facingDir := v3d.create(-1,0,0).rotated(angle.x, angle.y, angle.z);
  wheelDir := v3d.create(-1,0,0).rotated(angle.x, angle.y, angle.z + steeringAngle * (3/5));
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
    slipAngle := radToDeg(arcCos(vel.dot(wheelDir) / vel.abs));

    targetVelocity := v3d.create(-vel.abs,0,0).rotated(0,0,angle.z);
    {force required to correct velocity *this* frame}
    requiredTractionForce := (targetVelocity-vel)*(mass/elapsed);
    tractionForce := requiredTractionForce;

    if keyDown(key_z) then
      tractionForce.clip(0) {no traction}
    else if keyDown(key_x) then
      tractionForce.clip(9999999) {perfect traction}
    else begin
      {model how well our tires work}
      tractionForce.clip(tireTractionModifier * clamp(currentTerrain.traction-(tireHeat*2), 0, currentTerrain.traction));
    end;

    slidingPower := trunc(requiredTractionForce.abs - tractionForce.abs);

    tireHeat += slidingPower / 1000;
    tireHeat := 0.93 * tireHeat;

    {sound is always playing, we only adjust the volume}
    skidVolume := clamp(slidingPower/5000, 0, 1.0) * SKID_VOLUME;
    mixer.channels[2].volume := skidVolume * 0.65;

    // write skidmarks to map
    if (skidVolume > 0.05) and assigned(screen.background) then begin
      marks := trunc(skidVolume * 20);
      for i := 1 to marks do begin
        t := (rnd/256) * elapsed;
        addSkidmark(getWheelPos(+1, -1)+vel*t);
        addSkidmark(getWheelPos(+1, +1)+vel*t);
      end;
    end;

    // for the moment engine sound is speed, which is not quiet right
    // should be 'revs'
    mixer.channels[3].volume := clamp(vel.abs/200, 0, 1.0);
    mixer.channels[3].pitch := (ENGINE_START + clamp(vel.abs/250, 0, ENGINE_RANGE));

    //debugTextOut(drawPos.x, drawPos.y-50, format('%.1f %.1f', [slidingPower/5000, tireHeat]));

    vel += tractionForce * (elapsed / mass);

  end;

  {debugTextOut(
    drawPos.x-120, drawPos.y+50,
    format('vel:%.1f slipa:%.1f tf:%.1f/%.1f fps:%.2f',
    [vel.abs, slipAngle, tractionForce.abs, requiredTractionForce.abs, 1/elapsed]
  ));}

end;

{return terrain at world position}
function sampleTerrain(pos: V3D): tTerrainDef;
var
  drawPos: tPoint;
  col: RGBA;
begin

  // unlike the canvas, terrain and height are projected onto the xy plane
  pos.z := 0;
  drawPos := worldToCanvas(pos);

  {figure out why terrain we are on}
  {note: this is a bit of a weird way to do it, but oh well}
  col := track.terrainMap.getPixel(drawPos.x, drawPos.y);

  case col.to32 of
    $FFFF0000: result := TERRAIN_DEF[TD_DIRT];
    $FF00FF00: result := TERRAIN_DEF[TD_GRASS];
    $FFFFFF00: result := TERRAIN_DEF[TD_BARRIER];
    else result := TERRAIN_DEF[TD_SPACE];
  end;

end;

{return height at world position}
function sampleHeight(pos: V3D): single;
var
  drawPos: tPoint;
  col: RGBA;
begin
  // unlike the canvas, terrain and height are projected onto the xy plane
  pos.z := 0;
  drawPos := worldToCanvas(pos);
  {figure out why terrain we are on}
  {note: this is a bit of a weird way to do it, but oh well}
  col := track.heightMap.getPixel(drawPos.x, drawPos.y);
  result := (128-col.r)/3;
end;

{figure out what terrain we are on and handle height}
procedure tCar.processMap();
var
  terrainColor: RGBA;
  terrain: tTerrainDef;
  i,j: integer;
  height: array[0..1, 0..1] of single;
  wheelPos: array[0..1, 0..1] of V3D;
begin
  // for the moment assume we are on the ground
  self.isOnGround := true;

  self.currentTerrain := sampleTerrain(self.pos);
  self.pos.z := sampleHeight(self.pos);

  for i := 0 to 1 do
    for j := 0 to 1 do begin
      wheelPos[i,j] := getWheelPos(i*2-1, j*2-1);
      terrain := sampleTerrain(wheelPos[i,j]);
      height[i,j] := sampleHeight(wheelPos[i,j]);
      self.currentTerrain.traction += terrain.traction;
      self.currentTerrain.friction += terrain.friction;
      self.currentTerrain.bumpiness += terrain.bumpiness;
    end;

  {sample slope}
  self.angle.x := (height[0, 1] - height[0, 0]) / (wheelPos[0, 1]- wheelPos[0, 0]).abs;
  self.angle.y := -(height[1, 0] - height[0, 0]) / (wheelPos[1, 0]- wheelPos[0, 0]).abs;

  self.currentTerrain.traction /= 5;
  self.currentTerrain.friction /= 5;
  self.currentTerrain.bumpiness /= 5;

end;

procedure tCar.update();
var
  drag: single;
  dir: v3d;
  engineForce, lateralForce, dragForce: v3d;
  targetVelocity: v3d;
  drawPos: tPoint;

const
  BOUNDARY = 50;
begin

  dir := v3d.create(-1,0,0).rotated(0,0,angle.z);
  dragForce := v3d.create(0,0,0);
  engineForce := v3d.create(0,0,0);
  lateralForce := v3d.create(0,0,0);

  {process input}
  if keyDown(key_left) then begin
    angle.z -= elapsed*2.5;
    steeringAngle += elapsed*0.3;
  end;
  if keyDown(key_right) then begin
    angle.z += elapsed*2.5;
    steeringAngle -= elapsed*0.3;
  end;
  if keyDown(key_up) then
    engineForce := dir * enginePower;

  {movement from last frame}
  pos += vel * elapsed;
  drawPos := worldToCanvas(pos);

  self.processMap();

  debugTextOut(drawPos.x-100, drawPos.y,
    format('%s %f (%s)', [currentTerrain.tag, currentTerrain.friction, pos.toString])
  );

  {engine in 'spaceship' mode}
  vel += engineForce * (1/mass) * elapsed;
  tireRotation += elapsed * vel.abs / 20;

  {handle traction}
  self.tireModel();

  {handle drag}
  drag := self.constantDrag + currentTerrain.friction * vel.abs + (dragCoefficent) * vel.abs2;
  dragForce := vel.normed() * drag;
  dragForce *= (elapsed/mass);
  dragForce.clip(vel.abs);
  vel -= dragForce;

  {handle bumps}
  angle.x += ((rnd/256)-0.5) * vel.abs * elapsed * currentTerrain.bumpiness;
  angle.y += ((rnd/256)-0.5) * vel.abs * elapsed * currentTerrain.bumpiness;
  angle.z += ((rnd/256)-0.5) * vel.abs * elapsed * currentTerrain.bumpiness;

  {apply boundaries}
  if drawPos.x < BOUNDARY then vel.x += (BOUNDARY-drawPos.x) * 1.0;
  if drawPos.y < BOUNDARY then vel.y += (BOUNDARY-drawPos.y) * 1.0;
  if drawPos.x > screen.canvas.width-BOUNDARY then vel.x -= (drawPos.x-(screen.canvas.width-BOUNDARY)) * 1.0;
  if drawPos.y > screen.canvas.height-BOUNDARY then vel.y -= (drawPos.y-(screen.canvas.height-BOUNDARY)) * 1.0;

  {return setting back to zero}
  steeringAngle *= decayFactor(0.5);

  {return angles back to 0}
  if isOnGround then begin
    angle.x *= decayFactor(0.2);
    angle.y *= decayFactor(0.2);
  end;


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
  // grr, otherwise the letter 'p' gets left behind.
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
  if XMAS then
    music := tSoundEffect.loadFromWave('res\music2'+musicPostfix+'.wav')
  else
    music := tSoundEffect.loadFromWave('res\music1'+musicPostfix+'.wav');

  mixer.play(music, SCS_FIXED1);

  if XMAS then
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
    wheelPos := V3D.create(10, 7, 0);
    wheelOffset := V3D.create(+1, 0, 3);
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

  if XMAS then begin
    CC_RED := CC_SANTA;
    CC_BOX := CC_SANTA;
  end;

  wheelVox := tVoxelSprite.loadFromFile('res\wheel1', 8);

  {the sound engine is currently optimized for 16bit stereo sound}
  slideSFX := tSoundEffect.loadFromWave('res\skid.wav').asFormat(AF_16_STEREO);
  if XMAS then
    engineSFX:= tSoundEffect.loadFromWave('res\slaybells.wav').asFormat(AF_16_STEREO)
  else
    engineSFX:= tSoundEffect.loadFromWave('res\engine2.wav').asFormat(AF_16_STEREO);
  startSFX := tSoundEffect.loadFromWave('res\start.wav').asFormat(AF_16_STEREO);

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

  if xmas then snow := tSnowField.create() else snow := nil;

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

    drawGUI();

    mixer.mute := keyDown(key_m);
    mixer.noise := keyDown(key_n);

    if keyDown(key_b) then begin
      benchmarkMode := true;
      carScale := 3.0;
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

procedure mainLoop();
var
  startClock,lastClock,thisClock: double;
  car: tCar;
  camX, camY: single;
  drawPos: tPoint;
begin

  note('Main loop started');

  track := tRaceTrack.Create('res/track2');

  videoDriver.setMode(320,240,32);
  videoDriver.setLogicalSize(track.width, track.height);

  // super inefficent... but needed for dosbox-x due to vsync issues
  screen.scrollMode := SSM_COPY;

  setTrackDisplay(track.background);

  // turn off music
  if not XMAS then
    mixer.channels[1].reset();

  // start our sliding sound
  mixer.playRepeat(slideSFX, SCS_FIXED2);
  mixer.channels[2].volume := 0.0;

  mixer.playRepeat(engineSFX, SCS_FIXED3);
  mixer.channels[3].volume := 0.0;

  if not XMAS then
    mixer.play(startSFX);

  car := tCar.create(CC_BOX);
  car.pos := V3D.create(screen.canvas.width div 2, screen.canvas.height div 2+300,0);

  startClock := getSec;
  lastClock := startClock;

  camX := 0;
  camY := 0;

  while True do begin

    startTimer('frame');

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
    camX += ((drawPos.x-CamX)*decayFactor(0.5));
    camY += ((drawPos.y-CamY)*decayFactor(0.5));

    startTimer('draw_car');
    car.draw();
    stopTimer('draw_car');

    startTimer('gui');
    drawGUI();
    stopTimer('draw_car');

    {debugging}
    startTimer('debug');
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
    debugShowTimers(drawPos);
    stopTimer('debug');

    startTimer('vsync');
    if VSYNC then
      videoDriver.waitVSync();
    stopTimer('vsync');

    startTimer('setOfs');
    screen.setViewPort(
      round(camX)-(videoDriver.physicalWidth div 2), round(camY)-(videoDriver.physicalHeight div 2),
      false
    );
    stopTimer('setOfs');

    screen.flipAll();

    if keyDown(key_q) or keyDown(key_esc) then break;

    stopTimer('frame');
  end;

  track.free;

end;

procedure processArgs();
var
  i: integer;
begin
  for i := 1 to ParamCount do begin
    if toLowerCase(paramStr(i)) = '--xmas' then
      XMAS := true;
    if toLowerCase(paramStr(i)) = '--vsync' then
      VSYNC := true;
  end;
end;

begin

  processArgs();

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
