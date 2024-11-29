{Super simple git replacement}
program go;

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

type
	tLineDif: record
  	difType: char;
		line: string;
  end;

function fileDif(filename1,filename2: string);
var
	t1,t2: Text;
  line1, line2: string;
  lineNumber: int32;
  eof1,eof2: boolean;
begin
	assign(f1, filename1);
  reset(f1);
  assign(f2, filename2);
  reset(f2);

  lineNumber := 0;
  eof1 := false;
  eof2 := false;

  while not (eof1 and eof2) do begin

  	line1 := '';
    line2 := '';

  	if not EOF(f1) then
    	readln(f1, line1);
    else
    	eof1 := true;

    if not EOF(f2) then
    	readln(f2, line2);
    else
    	eof2 := true;

    inc(lineNumber);

    if (not eof1) and (not eof2) then begin
    	if line1 <> line2 then
      	writeln('-', line1);
        writeln('+', line2);
    end else if (not eof1) then begin
    	writeln('+', line1);
    end else if (not eof2) then begin
    	writeln('-', line2);
    end;

  end;

  close(f1);
  close(f2);
        	
end;	

procedure runTests();
begin
	
end;

var
	msg: string;

begin
 {todo: show changes}
  write('Message:');
  readln(msg);
  commit(msg);
{  fileDif('}
end.




