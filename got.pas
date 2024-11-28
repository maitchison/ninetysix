{Super simple git replacement}
program got;

{

got commit "Comments"
	Commit all changes

got status
	List changes since last commit.

got revert
	Revert back to previous commit. (but save a stash first)

got loc
	Write line counts per day


Block header

[MD5] [Path] [Date] [Comment]

}

uses
  utils,
  dos;


procedure commit(msg: string);
var
  sourcePath, destinationPath, command, folderName: string;
  t: text;
  time: tMyDateTime;
begin
	sourcePath := getENV('CWD');
  if sourcePath = '' then
  	sourcePath := '.';

  time := now;

  destinationPath := 'got\'+time.YYMMDD('')+'_'+time.HHMMSS('');
  {$I-}
  mkDIR(destinationPath);
  {$I+}
  dos.exec(getEnv('COMSPEC'), '/C copy *.pas '+destinationPath);

  assign(t,destinationPath+'/message.txt');
  rewrite(t);
  writeln(t, msg);
  close(t);

  {it's handy to have a daily folder aswell}
  destinationPath := 'got\'+time.YYMMDD('');
  {$I-}
  mkDIR(destinationPath);
  {$I+}
  dos.exec(getEnv('COMSPEC'), '/C copy *.pas '+destinationPath);


end;

var
	msg: string;

begin
	{todo: show changes}
  write('Message:');
  readln(msg);
  commit(msg);
end.




