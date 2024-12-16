{test refresh rate under emulation}
program framerate;

uses

  utils,
  keyboard,
  vga, vesa,
  sbDriver,
  screen;

var
  lfb_seg: word;
  counter: int32;
  rate: integer = 60;

begin
  videoDriver := tVesaDriver.create();
  videoDriver.setMode(320,240,32);
  videoDriver.setLogicalSize(320,480);
  lfb_seg := videoDriver.LFB_SEG;

  asm
    pushad
    push es

    mov es, lfb_seg
    xor edi, edi
    mov ecx, 320*240
    mov eax, $00FF00FF
    rep stosd

    pop es
    popad
  end;

  initKeyboard();

  counter := 0;

  {
  on my machine, I see the frames up to 120FPS
  this means 80 HZ is fine

  testing on 10 frames

  130 dropped 1
  120 dropped 1 @9
  90 all good 20/20

  }

  rate := 80;

  while not keyDown(key_q) do begin
    {pass}
    {videoDriver.setDisplayStart(0, counter mod 240);}
    videoDriver.setDisplayStart(0, 240);
    if counter mod 27 = 0 then
      directNoise(0.01);
    if counter mod 27 = 2 then begin
      videoDriver.setDisplayStart(0, 0);
    end;
    inc(counter);
    delay(1000/rate);
  end;

end.
