{A simple immedate mode gui}
Unit gui;
{$MODE delphi}

uses

interface

implementation

(*

var i: dword;


var
	{setup screen}
  c: RGBA;

  StartTime: Double;
  EndTime: Double;

  CallsPerSecond: Double;
  Buffer: TPage;

  za,zb,zc,zd: dword;
  zx: dword;


procedure InitGUI()

begin

	{LoadGFX();}
  (*

	SetMode(640, 480, 32);

  Buffer := TPage.Create(640, 480);

  {InitMouse();}

  c := RGBA.Create(255,255,255);

  StartTime := GetSec;

  Buffer.Clear(RGBA.Create(128,128,128,128));
  *)

  {

  	putPixel, solid, buffer = 2.30M
    	-> 28.25M (switch to fillchar, rep stosd is the same)
    putPixel, solid, screen = 1.83M
    	-> 6.8M

    putPixel, alpha, buffer = 1.1M
    	-> 18.28M (switched to MMX, wow! this is fast)
    	
    putPixel, alpha, screen = 0.30M
    	-> 0.73M (switch to MMX, I think we're bandwidth capped)

	}
  {
  for i := 0 to 65535 do begin
  	c.a := i and $FF;
  	Screen.PutPixel(i and $FF, i shr 8, c);
  end;}

{  EndTime := GetSec;}



{	PanelSprite.NineSlice(10,10,200,200);


	ButtonSprite.NineSlice(100,100,150,40);

  cursorX := 100+(150-Extents('Start').width) div 2;
  cursorY := 111;
  cursorCol := RGBA.Create(250,250,250,127);
  printShadow('Start');

  FrameSprite.NineSlice(50,50,50,50);}

  i := 0;

  (*
	
  while True do begin

  	i := i + 1;

    SetDisplayStart(Mouse_X, Mouse_Y);

{  	PanelSprite.NineSlice(5,205,150,25);
  	cursorX := 10;
    cursorY := 208;
    cursorCol := RGBA.create(20,20,20,200);
  	print(IntToStr(Mouse_X)+','+IntToStr(Mouse_Y)+' '+IntToStr(Mouse_B)+' '+IntToStr(i*640));
 }
    sleep(10);

    if (Mouse_B) = 3 then break;

  end;
                 *)
  {CloseMouse();}

  (*

  readkey;

	TextMode();

  CallsPerSecond := 640*480 / (EndTime-StartTime);

  writeln((CallsPerSecond/1000/1000):0:2);
  readkey;
*)

begin
end.
