{test / benchmark for voxel stuff}
program voxTest;

uses
  uTest,
  uDebug,
  uUtils,
  uMouse,
  uKeyboard,
  uScreen,
  uScene,
  uTimer,
  uSound,
  uMixer,
  uInput,
  uRect,
  uVertex,
  uVoxel,
  uColor,
  uGraph32,
  {$i gui.inc}
  uMDRMap,
  uTileBuilder,
  uVESADriver,
  uVGADriver;

type
  tTestScene = class(tScene)
  protected
    function generateTile(lightingMode: tLightingMode): tVoxel;
  public
    procedure run(); override;
  end;

var
  screen: tScreen;
  scene: tTestScene;

procedure setup();
begin
  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    fatal('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    fatal('Requires 1MB video card.');
  videoDriver.setTrueColor(800, 600);
  initMouse();
  initKeyboard();
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;
end;

function tTestScene.generateTile(lightingMode: tLightingMode): tVoxel;
var
  tileBuilder: tTileBuilder;
  tile: tTile;
  walls: array[1..4] of tWall;
begin

  startTimer('TileGenerate');
  tileBuilder := tTileBuilder.Create();
  tile.floor := ftStone;
  walls[1].t := wtWall;
  walls[2].t := wtWall;
  walls[3].t := wtNone;
  walls[4].t := wtNone;

  startTimer('TileCompose');
  tileBuilder.composeVoxelCell(tile, walls);
  stopTimer('TileCompose');

  result := tVoxel.Create(tileBuilder.page, 32);

  startTimer('TileSDF');
  result.generateSDF(sdfFull);
  stopTimer('TileSDF');

  startTimer('TileLighting');
  result.generateLighting(lightingMode);
  stopTimer('TileLighting');

  tileBuilder.free;

  stopTimer('TileGenerate');
end;

procedure tTestScene.run();
var
  timer: tTimer;
  elapsed: single;
  dc: tDrawContext;
  tileVox: tVoxel;
  tileCanvas: tPage;
  bounds: tRect;


begin
  timer := startTimer('main');

  dc := screen.getDC();

  tileVox := generateTile(lmAO);

  tileCanvas := tPage.Create(128,128);

  repeat

    timer.start();

    elapsed := clamp(timer.elapsed, 0.001, 0.1);
    if timer.avElapsed > 0 then
      fpsLabel.text := format('%.1f', [1/timer.avElapsed]);

    musicUpdate();

    input.update();

    {draw our tile}
    tileCanvas.clear(RGB(12,12,12));
    tileVox.draw(tileCanvas.getDC(), V3(64,64,0), V3(0,0,getSec), 2.0);
    screen.getDC.asBlendMode(bmBlit).drawImage(
      tileCanvas,
      Point((screen.canvas.bounds.width-128) div 2, (screen.canvas.bounds.height-128) div 2)
    );

    gui.update(elapsed);
    gui.draw(dc);
    screen.flipAll();

    timer.stop();

  until keyDown(key_esc);

end;

begin
  setup();
  scene := tTestScene.Create();
  scene.run();
  videoDriver.setText();
  logTimers();
  printLog(32);
end.
