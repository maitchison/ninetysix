{a program to test VC compression}
program vctest;

uses
  test,
  debug,
  vga,
  vesa,
  mouse,
  crt,
  sysInfo,
  utils,
  keyboard,
  graph32,
  screen;

var
  screen: tScreen;

procedure testCompression();
begin
  repeat
  until keyDown(key_esc);
end;

begin
  debug.VERBOSE_SCREEN := llNote; // startup should have done this?

  textAttr := LightGray + Blue * 16;
  clrscr;

  log('Starting VC_TEST', llImportant);
  log('---------------------------', llImportant);

  if cpuInfo.ram < 30*1024*1024 then
    error('Application required 30MB of ram.');

  {setup heap logging before units start.}
  {$if declared(Heaptrc)}
  heaptrc.setHeapTraceOutput('heaptrc.txt');
  heaptrc.printfaultyblock := true;
  heaptrc.printleakedblock := true;
  heaptrc.maxprintedblocklength := 64;
  {$endif}

  enableVideoDriver(tVesaDriver.create());

  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    error('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 2*1024*1024 then
    error('Requires 2MB video card.');

  runTestSuites();

  videoDriver.setMode(640,480,32);

  screen := tScreen.create();

  initMouse();
  initKeyboard();

  testCompression();

  videoDriver.setText();
  printLog();

end.
