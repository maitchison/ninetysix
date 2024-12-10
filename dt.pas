{set date and time env variables}
program dt;

uses utils;

var
	t: text;
	time: tMyDateTime;

begin
	time := now;
	assign(t,'dt.bat');
  rewrite(t);
  writeln(t,'SET DATE='+time.YYMMDD(''));
  writeln(t,'SET TIME='+time.HHMMSS(''));
  close(t);
end.
