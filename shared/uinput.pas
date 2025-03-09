{handles mouse/keyboard input}
unit uInput;

interface

{
This unit handles per frame input. That is, input is locked at the start of
the frame. This allows for things like when the mouse button is first
pressed to be detected
}

uses
  uMouse,
  graph2d;

type
  tInput = class
    mouseX, mouseY: integer;
    mouseLB, mouseRB: boolean;
    prevMouseX, prevMouseY: integer;
    prevMouseLB, prevMouseRB: boolean;
    procedure update();
    function mousePressed: boolean;
  end;


var
  input: tInput;

implementation

procedure tInput.update();
begin
  prevMouseX := mouseX;
  prevMouseY := mouseY;
  prevMouseLB := mouseLB;
  prevMouseRB := mouseRB;
  mouseX := mouse.x;
  mouseY := mouse.y;
  mouseLB := mouse.leftButton;
  mouseRB := mouse.rightButton;
end;

{returns true if mouse button was pressed this frame}
function tInput.mousePressed(): boolean;
begin
  result := mouseLB and not prevMouseLB;
end;

begin
  input := tInput.create();
end.
