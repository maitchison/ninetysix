program vesaInfo;

uses
  crt,
  vga,vesa;

var
  vesaInfo: tVesaInfo;
  driver: tVesaDriver;

begin
  clrscr;
  driver := tVesaDriver.create();
  driver.logModes();
  driver.logInfo();
end.
