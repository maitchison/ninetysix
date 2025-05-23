unit resources;
{resources units for airtime}

interface

uses
  debug,
  test,
  utils,
  resLib,
  sound,
  voxel,
  configFile,
  filesystem,
  mixLib,
  graph32,
  vertex,
  car,
  la96,
  lc96;

var
  rl: tResourceLibrary;

  {todo: remove global resources, and instead get from resourceLibrary via a tag}

  {global resources}
  startSFX: tSoundEffect;

  {car resources}
  slideSFX, landSFX, boostSFX, engineSFX: tSoundEffect;
  wheelVox: tVoxelSprite;

var
  CC_RED,
  CC_POLICE,
  CC_BOX,
  CC_SANTA: tCarChassis;

procedure loadResources();
procedure freeResources();
function loadSound(tag: string): tSoundEffect;

{----------------------------}

implementation

procedure loadCarResources();
begin

  wheelVox := tVoxelSprite.create('res\wheel', 8);

  {the sound engine is currently optimized for 16bit stereo sound}
  slideSFX := loadSound('skid');
  if config.XMAS then
    engineSFX := loadSound('bell')
  else
    engineSFX := loadSound('engine2');

  landSFX := loadSound('land');
  boostSFX := loadSound('boost');

end;

function loadSound(tag: string): tSoundEffect;
var
  startTime: double;
  srcPath: string;
  reader: tLA96Reader;
begin
  startTime := getSec;

  srcPath := joinPath('res', tag+'.a96');
  if not fs.exists(srcPath) then fatal(format('Missing audio file "%s".', [srcPath]));
  reader := tLA96Reader.create();
  reader.open(srcPath);
  result := reader.readSFX();
  reader.free;

  note(format(' - loaded %s in %.2fs.', [tag, getSec - startTime]));
end;

procedure loadResources();
begin

  info('Loading Resources...');

  {start with music... because why not :) }
  if config.XMAS then
    musicPlay('res\music2.a96')
  else
    musicPlay('res\music1.a96');

  musicUpdate(44*5); // 5 seconds buffer (if we can)

  {todo: store all resources in resource library, and address
   by a 'tag' (which is kind of like what i've started doing here}

  rl := tResourceLibrary.CreateOrLoad('resources.ini');

  {setup chassis}
  {todo: have these as meta data}
  {also move this into car}
  with CC_RED do begin
    setDefault();
    wheelPos := V3D.create(8, 7, 0);
    wheelOffset := V3D.create(-1, 0, 0);
    vox := tVoxelSprite.create('res\carRed', 16);;
  end;
  with CC_POLICE do begin
    setDefault();
    wheelPos := V3D.create(10, 7, 0);
    wheelOffset := V3D.create(+1, 0, 3);
    vox := tVoxelSprite.create('res\carPol', 16);
  end;
  with CC_BOX do begin
    setDefault();
    wheelPos := V3D.create(9, 7, 0);
    wheelOffset := V3D.create(-1, 0, 1);
    vox := tVoxelSprite.create('res\carBox', 16);
  end;
  with CC_SANTA do begin
    setDefault();
    wheelPos := V3D.create(10, 7, 0);
    wheelOffset := V3D.create(+1, 0, 3);
    wheelSize := 0;
    vox := tVoxelSprite.create('res\carSan', 16);
  end;

  if config.XMAS then begin
    CC_RED := CC_SANTA;
    CC_BOX := CC_SANTA;
  end;

  startSFX := loadSound('start');

  loadCarResources();
end;

procedure freeResources();
begin
  {todo: have some resource manager do this for me}
  freeAndNil(CC_RED.vox);
  freeAndNil(CC_POLICE.vox);
  freeAndNil(CC_BOX.vox);
  freeAndNil(CC_SANTA.vox);
  freeAndNil(startSFX);
  {car resources}
  freeAndNil(wheelVox);
  freeAndNil(slideSFX);
  freeAndNil(engineSFX);
  freeAndNil(landSFX);
  freeAndNil(boostSFX);

  rl.free();

end;

begin
end.
