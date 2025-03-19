{test / benchmark for voxel stuff}
program voxTest;

uses
  uTest,
  uDebug,
  uUtils,
  uMouse,
  uKeyboard,
  uScreen,
  uVESADriver,
  uVGADriver;

var
  screen: tScreen;

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

begin
  setup();
end.