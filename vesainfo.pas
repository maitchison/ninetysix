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
  driver.logInfo();
  driver.logModes();
end.
