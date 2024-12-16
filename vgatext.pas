program vgatext;

{

Test out some ideas for a vga text mode.

[ ] How fast can we scroll a large amount of text?
[ ] What font size / choice
[ ] Can we do two 80 column files for diffs?
[ ] How fast is double buffering in video?

We can use this for
- Go diff viewer
- Stats plots?
- Maybe an editor
- Maybe a dos command prompt.



Options
- Use 1600x1200 with 8x8 font grid.
- Double buffering in video memory?

}

uses
  utils,
  s3video,
  mouse,
  graph32,
  crt,
  debug,
  screen;

var
  c: rgba;
  videoWords: dword;
  s3: tS3Driver;
  i: integer;

begin

  setMode(1024,768,8);
  initMouse();

  s3 := tS3Driver.create();

  s3.fgColor.init(0,0,0);

  for i := 0 to 100 do begin
    s3.fgColor.b := rnd;
    s3.fillRect(10,10,600,600);
    delay(20);
  end;

  crt.readkey;

  setText;
  printLog;

end.
