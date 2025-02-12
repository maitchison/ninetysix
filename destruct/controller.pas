unit controller;

interface

type
  tController = class
  public
    fire: boolean;
    xVel, yVel: single;
    procedure process(); virtual;
  end;

  tNullController = class(tController)
  end;

  tHumanController = class(tController)
    procedure process(); override;
  end;

implementation

uses
  keyboard;

{--------------------------------------------}

procedure tController.process();
begin
  fire := false;
  xVel := 0;
  yVel := 0;
end;

{--------------------------------------------}

procedure tHumanController.process();
begin
  inherited process();
  if keyDown(key_space) then fire := true;
  if keyDown(key_left) then xVel := -100;
  if keyDown(key_right) then xVel := +100;
  if keyDown(key_up) then yVel := +10;
  if keyDown(key_down) then yVel := -10
end;

{--------------------------------------------}

begin
end.
