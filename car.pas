unit car;

interface

uses
  {$i units.inc},
  raceTrack;

const
  DEFAULT_CAR_SCALE = 1.0;

  {todo: put as part of chassis def}
  SKID_VOLUME = 0.75;
  ENGINE_RANGE = 4.0;
  ENGINE_START = 0.5;


  //sled numbers

  //SKID_VOLUME = 0.5;
  //ENGINE_RANGE = 0.75;
  //ENGINE_START = 0.5;

  GRAVITY = 400;

type
  tCarChassis = record
    carHeight: single;
    wheelPos: V3D;
    wheelOffset: V3D;
    wheelSize: single;
    suspensionRange: single;
    vox: tVoxelSprite;
    procedure setDefault();
  end;

  tCar = class

  protected

    function getWheelPos(dx,dy: integer): V3D;
    function getWheelAngle(dx,dy: integer): single;

    procedure addSkidMark(pos: V3D);
    procedure drawWheels(screen: tScreen; side: integer);

    procedure processTireModel(elapsed: single);
    procedure processPhysics(elapsed: single);
    procedure processTerrain(elapsed: single);
    procedure processInput(elapsed: single);
    procedure processMovement(elapsed: single);

  public

    pos: V3D;
    vel: V3D;
    angle: V3D;
    steeringAngle: single;
    suspensionTravel: single;
    currentTerrain: tTerrainDef;
    nitroTimer: single;
    updateRemaining: single;

    chassis: tCarChassis;
    track: tRaceTrack;
    scale: single;

    mass: single;
    tireTractionModifier: single;
    tireHeat: single;       //reduces traction
    enginePower: single;
    dragCoefficent: single;
    constantDrag: single;
    tireRotation: double;

    constructor Create(aChassis: tCarChassis; aTrack: tRaceTrack);

    function isOnGround: boolean;
    function vox: tVoxelSprite;

    procedure draw(screen: tScreen);
    procedure update(elapsed:single);
  end;

procedure loadCarResources();
procedure initCarResources();

implementation

var
  slideSFX, landSFX, boostSFX, engineSFX: tSoundEffect;
  wheelVox: tVoxelSprite;

{--------------------------------------------------------}
{  helpers  }
{--------------------------------------------------------}

{returns decay factor for with given halflife (in seconds) over current
 elapsed time}
function decayFactor(decayTime, elapsed: single): single;
var
  rate: single;
begin
  rate := ln(2.0) / decayTime;
  result := exp(-rate*elapsed);
end;

{--------------------------------------------------------}

procedure tCarChassis.setDefault();
begin
  carHeight := 5.0;
  wheelPos := V3D.create(8, 7, 0);
  wheelOffset := V3D.create(-1, 0, 0);
  wheelSize := 1.0;
  suspensionRange := 10.0;
  vox := nil;
end;

{--------------------------------------------------------}

constructor tCar.Create(aChassis: tCarChassis;aTrack: tRaceTrack);
begin
  inherited create();
  pos := V3D.create(0,0,0);
  vel := V3D.create(0,0,0);
  angle := V3D.create(0,0,0);

  track := aTrack;

  steeringAngle := 0;
  mass := 1;
  enginePower := 300;
  tireTractionModifier := 1;
  tireHeat := 0;
  dragCoefficent := 0.0025;
  constantDrag := 50;
  tireRotation := 0.0;
  chassis := aChassis;
  nitroTimer := 0;
  updateRemaining := 0;
  scale := DEFAULT_CAR_SCALE;
end;

{draws tires. If side < 0 then tires behind car are drawn,
 if side > 0 then tires infront are draw, and if side = 0 then all
 tires are drawn}
procedure tCar.drawWheels(screen: tScreen; side: integer);
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

procedure tCar.draw(screen: tScreen);
var
  startTime: double;
  p: V3D;
begin

  startTime := getSec;

  {draw shadow}
  p := pos;
  p.z := track.sampleHeight(pos);
  screen.markRegion(vox.draw(screen.canvas, p, angle, scale*0.9, true));
  screen.markRegion(vox.draw(screen.canvas, p, angle, scale*1.0, true));
  screen.markRegion(vox.draw(screen.canvas, p, angle, scale*1.1, true));

  drawWheels(screen, -1);
  p := pos;
  p.z -= chassis.carHeight;
  screen.markRegion(vox.draw(screen.canvas, p, angle, scale));
  drawWheels(screen, +1);
end;

function tCar.vox: tVoxelSprite;
begin
  result := chassis.vox;
end;

function tCar.isOnGround: boolean;
begin
  result := currentTerrain.tag <> 'air';
end;

{returns wheel positon in world space, e.g. -1, -1 for front left tire}
function tCar.getWheelPos(dx,dy: integer): V3D;
var
  p: V3D;
begin
  p := chassis.wheelPos * V3D.create(dx, dy, 0);
  p += chassis.wheelOffset;
  p.z += suspensionTravel;
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

procedure tCar.addSkidMark(pos: V3D);
var
  drawPos: tPoint;
begin
  if not assigned(track.background) then exit;
  pos.x += ((rnd-rnd) / 256)*1.5;
  pos.y += ((rnd-rnd) / 256)*1.5;
  drawPos := track.worldToCanvas(pos);
  track.background.putPixel(
    drawPos.x, drawPos.y,
    RGBA.create(0,0,0,16)
  );
end;

procedure tCar.processTireModel(elapsed: single);
var
  slipAngle: single;
  wheelDir: V3D;
  requiredTractionDelta, tractionDelta: V3D;
  targetVelocity,lateralDelta: V3D;
  xyVel: V3D;
  skidVolume: single;
  slidingHeat: single;
  alpha: single;
  i: integer;
  t: single;
  marks: integer;
  tireAngle: single;
  tireGrip: single;
begin

  if elapsed <= 0 then exit;

  {-----------------------------------}
  {tire traction}

  tireHeat *= decayFactor(0.1, elapsed);
  watch('tireHeat', tireHeat);
  {sound is always playing, we only adjust the volume}
  skidVolume := clamp(tireHeat/100, 0, 1.0) * SKID_VOLUME;
  mixer.channels[2].volume := skidVolume;

  xyVel := vel; xyVel.z := 0;

  if xyVel.abs < 0.1 then
    {perfect traction for at small speeds}
    exit;

  if not isOnGround then
    exit;

  // works best if we only add a small amount of steering angle
  tireAngle := angle.z + steeringAngle * (1/5);
  wheelDir := V3D.create(-1,0,0).rotated(0,0,tireAngle);

  {note: slip angle is wrong here (in that it can be 180 degrees
   but we're not using it... why?}
  slipAngle := radToDeg(arcCos(xyVel.dot(wheelDir) / xyVel.abs));
  targetVelocity := V3D.create(-xyVel.abs,0,0).rotated(0,0,tireAngle);
  watch('slipAngle', slipAngle);
  watch('wheelDir', wheelDir.abs);
  watch('tireAngle', radToDeg(tireAngle));

  {figure out how much of the difference our tires can take care of}
  lateralDelta := (targetVelocity-xyVel);
  lateralDelta := lateralDelta.rotated(0, 0, -tireAngle);
  watch('lateralDelta', lateralDelta);
  lateralDelta.x := 0;
  lateralDelta.z := 0;
  lateralDelta := lateralDelta.rotated(0, 0, +tireAngle);

  {change in velocity required to correct velocity}
  requiredTractionDelta := lateralDelta;
  tractionDelta := requiredTractionDelta;

  if keyDown(key_z) then
    tractionDelta.clip(0) {no traction}
  else if keyDown(key_x) then
    tractionDelta.clip(9999999) {perfect traction}
  else begin
    {model how well our tires work}
    tireGrip := tireTractionModifier * clamp(currentTerrain.traction-(tireHeat), 0, currentTerrain.traction);
    watch('tireGrip', tireGrip);
    tractionDelta.clip(elapsed * tireGrip);
  end;

  {some of our sliding goes into heat}
  slidingHeat := requiredTractionDelta.abs - tractionDelta.abs;
  slidingHeat := clamp(slidingHeat/100, 0, 1000 * elapsed);

  tireHeat += slidingHeat;

  watch('tireHeat', tireHeat);
  watch('slidingHeat', slidingHeat);

  // write skidmarks to map
  if (skidVolume > 0.01) then begin
    if (skidVolume * 400) > rnd then
      addSkidmark(getWheelPos(+1, -1));
    if (skidVolume * 400) > rnd then
      addSkidmark(getWheelPos(+1, +1));
  end;

  // for the moment engine sound is speed, which is not quiet right
  // should be 'revs'
  mixer.channels[3].volume := clamp(xyVel.abs/200, 0, 1.0);
  mixer.channels[3].pitch := (ENGINE_START + clamp(xyVel.abs/250, 0, ENGINE_RANGE));

  vel += tractionDelta;

end;

procedure tCar.processPhysics(elapsed: single);
var
  terrainDelta: single;
  modelTransform: tMatrix4x4;
  carAccel, carVel: V3D;
  factor: single;
  halfSuspensionRange: single;
begin

  {apply physics}
  terrainDelta := track.sampleHeight(self.pos) - pos.z;

  {todo: part of chassis def}
  halfSuspensionRange := chassis.suspensionRange/2;

  {accleration in car frame}
  modelTransform.setRotationXYZ(angle.x, angle.y, angle.z);
  modelTransform := modelTransform.transposed();
  carAccel := modelTransform.apply(V3D.create(0, 0, GRAVITY));
  carVel := modelTransform.apply(vel);

  if (terrainDelta < 0) then begin
    // play sound scrape for big impact
    if carVel.z > 100 then
      mixer.play(landSFX, SCS_SELFOVERWRITE);
    pos.z += terrainDelta;
    if vel.z > 0 then
      vel.z := -vel.z * 0.75;
  end;

  if terrainDelta < halfSuspensionRange then begin
    // suspension pushes us up.
    factor := clamp((halfSuspensionRange - terrainDelta)/halfSuspensionRange, 0, 1);
    carAccel += V3D.create(0, 0, -2000*factor);
  end;

  if (terrainDelta > halfSuspensionRange) and (terrainDelta <= chassis.suspensionRange) then begin
    // point at which we loose some traction
    factor := halfSuspensionRange-(terrainDelta-halfSuspensionRange);
    self.currentTerrain.traction *= factor;
    self.currentTerrain.friction *= factor;
  end;

  watch('carAccel', carAccel);

  suspensionTravel := clamp(terrainDelta-halfSuspensionRange, -halfSuspensionRange, halfSuspensionRange);

  vel += modelTransform.transposed.apply(carAccel) * elapsed;

end;

{figure out what terrain we are on and handle height}
procedure tCar.processTerrain(elapsed: single);
var
  terrainColor: RGBA;
  terrain: tTerrainDef;
  terrainHeight, terrainDelta: single;
  i,j: integer;
  height: array[0..1, 0..1] of single;
  wheelPos: array[0..1, 0..1] of V3D;
  slopeX, slopeY: single;
begin

  terrainHeight := track.sampleHeight(self.pos);
  if -pos.z + terrainHeight >= chassis.suspensionRange then begin
    // point at which tires loose contact with terrain
    self.currentTerrain := TERRAIN_DEF[TD_AIR];
    exit;
  end;

  {sample terrain}
  self.currentTerrain := track.sampleTerrain(self.pos);
  for i := 0 to 1 do
    for j := 0 to 1 do begin
      wheelPos[i,j] := getWheelPos(i*2-1, j*2-1);
      terrain := track.sampleTerrain(wheelPos[i,j]);
      height[i,j] := track.sampleHeight(wheelPos[i,j]);
      self.currentTerrain.traction += terrain.traction;
      self.currentTerrain.friction += terrain.friction;
    end;

  {sample slope}
  if isOnGround then begin
    slopeX := (height[0, 1] - height[0, 0]) / (wheelPos[0, 1]- wheelPos[0, 0]).abs;
    slopeY := (height[1, 0] - height[0, 0]) / (wheelPos[1, 0]- wheelPos[0, 0]).abs;
    self.angle.x := arctan(slopeX);
    self.angle.y := arctan(-slopeY);
  end;

  self.currentTerrain.traction /= 5;
  self.currentTerrain.friction /= 5;
end;

{figure out what terrain we are on and handle height}
procedure tCar.processInput(elapsed: single);
var
  dir, engineForce: V3D;
begin

  dir := V3D.create(-1,0,0).rotated(0,0,angle.z);
  engineForce := V3D.create(0,0,0);

  {stub}
  watch('terrain', currentTerrain.tag);

  {process input}
  if keyDown(key_left) then begin
    angle.z -= elapsed*2.5
    steeringAngle += elapsed*0.3;
  end;
  if keyDown(key_right) then begin
    angle.z += elapsed*2.5
    steeringAngle -= elapsed*0.3;
  end;

  if (nitroTimer > 0) then begin
    if (isOnGround) then
      engineForce := dir * enginePower*2;
    nitroTimer -= elapsed;
    if nitroTimer < 0 then begin
      nitroTimer := -10; // 10 second cool-down
    end;
  end else begin
    if keyDown(key_down) and isOnGround then
      engineForce := dir * (-0.5 * enginePower);
    if keyDown(key_up) and isOnGround then
      engineForce := dir * enginePower;
  end;

  if keyDown(key_c) and (nitroTimer = 0) then begin
    // play sound nitro
    mixer.play(boostSFX);
    nitroTimer := 2.0;
  end;

  if (nitroTimer < 0) then
    nitroTimer := min(nitroTimer + elapsed, 0);

  {engine in 'spaceship' mode}
  vel += engineForce * (1/mass) * elapsed;
  tireRotation += elapsed * vel.abs / 20;

end;

procedure tCar.processMovement(elapsed: single);
var
  drawPos: tPoint;
  dragForce: V3D;
  drag: single;
const
  BOUNDARY = 50;
begin

  pos += vel * elapsed;

  {handle drag}
  drag := self.constantDrag + currentTerrain.friction * vel.abs + (dragCoefficent) * vel.abs2;
  dragForce := vel.normed() * drag;
  dragForce *= (elapsed/mass);
  dragForce.clip(vel.abs);
  vel -= dragForce;

  {apply boundaries}
  drawPos := track.worldToCanvas(pos);
  if drawPos.x < BOUNDARY then vel.x += (BOUNDARY-drawPos.x) * 1.0;
  if drawPos.y < BOUNDARY then vel.y += (BOUNDARY-drawPos.y) * 1.0;
  if drawPos.x > track.width-BOUNDARY then vel.x -= (drawPos.x-(track.width-BOUNDARY)) * 1.0;
  if drawPos.y > track.height-BOUNDARY then vel.y -= (drawPos.y-(track.height-BOUNDARY)) * 1.0;

  {return setting back to zero}
  steeringAngle *= decayFactor(0.5, elapsed);

  {return angles back to 0}
  if isOnGround then begin
    angle.x *= decayFactor(0.2, elapsed);
    angle.y *= decayFactor(0.2, elapsed);
  end;
end;

procedure tCar.update(elapsed: single);
const
  updatePerTick = 0.002;
var
  updates: integer;
begin
  updateRemaining += elapsed;
  updates := 0;
  while updateRemaining > updatePerTick do begin
    if updates >= 100 then
      {too many updates, we'll just move slowly in this case}
      break;
    processTerrain(updatePerTick);
    processInput(updatePerTick);
    processTireModel(updatePerTick);
    processPhysics(updatePerTick);
    processMovement(updatePerTick);
    updateRemaining -= updatePerTick;
    inc(updates);
  end;
end;

{---------------------------------------------------------------------}

procedure loadCarResources();
begin
  wheelVox := tVoxelSprite.loadFromFile('res\wheel1', 8);

  {the sound engine is currently optimized for 16bit stereo sound}
  slideSFX := tSoundEffect.loadFromWave('res\skid.wav').asFormat(AF_16_STEREO);
  if config.XMAS then
    engineSFX:= tSoundEffect.loadFromWave('res\slaybells.wav').asFormat(AF_16_STEREO)
  else
    engineSFX:= tSoundEffect.loadFromWave('res\engine2.wav').asFormat(AF_16_STEREO);

  landSFX := tSoundEffect.loadFromWave('res\land.wav').asFormat(AF_16_STEREO);
  boostSFX := tSoundEffect.loadFromWave('res\boost.wav').asFormat(AF_16_STEREO);

end;

procedure initCarResources();
begin
  // start our sliding sound
  mixer.playRepeat(slideSFX, SCS_FIXED2);
  mixer.channels[2].volume := 0.0;

  mixer.playRepeat(engineSFX, SCS_FIXED3);
  mixer.channels[3].volume := 0.0;
end;

begin
end.
