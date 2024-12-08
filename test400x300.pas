{see if we can activate 400x300 video mode}
program test400x300;

uses
	vga,
	vesa,
  utils,
  crt;

begin
	videoDriver := tVesaDriver.create();
	videoDriver.setMode(400,300,32);
  readkey;
  videoDriver.setText();
end.