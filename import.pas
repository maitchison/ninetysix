{read master files and process / compress}
program import;

uses
	utils,
  test,
  debug,
	graph32,
  lc96;

var
	img: tPage;

procedure convertBMP(filename: string);
begin
	writeln('Processing ', filename);
	img := loadBMP('e:\airtime\'+filename+'.bmp');
  saveLC96('c:\src\gfx\'+filename+'.p96', img);
  writeln(format(' -(%dx%d)',[img.width, img.height]));
end;

procedure processAll();
begin
	convertBMP('track1');
end;

begin
	processAll();
  writeln('done.');
end.