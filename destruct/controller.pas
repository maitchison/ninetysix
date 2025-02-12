unit controller;

interface

uses
  obj;

type
  tController = class
  public
    doFire: boolean;
    xVel, yVel: single;
    tank: tTank;
    target: tTank;
    constructor create(aTank: tTank);
    procedure apply(elapsed: single);
    procedure process(); virtual;
  end;

  tNullController = class(tController)
  end;

  tHumanController = class(tController)
    procedure process(); override;
  end;

  tAIController = class(tController)
    target: tGameObject;
    procedure process(); override;
  end;

implementation

uses
  keyboard;

{--------------------------------------------}

constructor tController.create(aTank: tTank);
begin
  tank := aTank;
end;

procedure tController.apply(elapsed: single);
begin
  if doFire then tank.fire();
  tank.adjust(xVel * elapsed, yVel *elapsed);
end;

procedure tController.process();
begin
  doFire := false;
  xVel := 0;
  yVel := 0;
end;

{--------------------------------------------}

procedure tHumanController.process();
begin
  inherited process();
  if keyDown(key_space) then doFire := true;
  if keyDown(key_left) then xVel := -100;
  if keyDown(key_right) then xVel := +100;
  if keyDown(key_up) then yVel := +10;
  if keyDown(key_down) then yVel := -10
end;

{--------------------------------------------}

procedure tAIController.process();
begin
  inherited process();

  {work on an iterative firing solution}
end;

begin
end.
