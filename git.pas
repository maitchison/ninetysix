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


function getFolderName(): string;
var
	time: double;
begin
	time := now();
  re
	
end;

procedure commit();
var
  sourcePath, destPath, command, folderName: string;
  time: tMyDateTime;
begin
	sourcePath := getENV('CWD');
  if sourcePath = '' then
  	sourcePath := '.';

  time := now;

  destinationPath := 'got/'+time.YYMMDD+time.HHMMSS;
  mkDIR(destinationPath);


  dos.exec(sourcePath, 'copy *.pas '+destinationPath);
  			
end;

begin
	commit();
end.




