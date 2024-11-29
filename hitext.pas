{Experiment with high resolution text modes}
program hitext;

{try

 [x] using dos int - doesn't seem to work
 [x] using vesa - only works with univbe, and only 132x43, I think this is a s3 card problem.
 [...] using vga registers - ah, S3 doc say 132x42 is max, so just skip this unless
 	we want to avoid univbe

}

uses
	mouse,
	crt;

var
	i: integer;

begin
	

{	asm
  	mov ax, $0003
    int $10
  end;}
	asm

{  	mov ax, $010b
    int $10}

    {
    	with univbe:
    	$10A is 132x43
      B, and C don't work, maybe there's no font?
    }

  	mov ax, $4f02
    mov bx, $010a {10b and 10c would be great!}
    int $10
    {note: 10a already has this}
{    mov ax, $1112
    xor bx, bx
    int $10}
  	end;

	{  initMouse();}

clrscr;
  gotoXY(1,1);
  for i := 1 to 40 do begin
	  textAttr := i;
	  writeln('row', i);
  end;
  for i := 1 to 80 do
  	write('-');

  for i := 0 to 132*40 do
  	write('z');

  writeln('start');
  for i := 0 to 132*41 do
  	write('x');
  write('finish');

  readkey;
end.
