{handles timers}
unit timer;

interface

uses
  debug,
  utils;

type
  tTimer = class
    tag: string;
    startTime: double;
    endTime: double;
    maxElapsed: double;
    constructor Create(aTag: string);
    function  elapsed(): double;
    procedure reset(aTag: string);
    procedure start();
    procedure stop();
    function  toString(): string;
  end;

procedure startTimer(aTag: string);
procedure stopTimer(aTag: string);
function getTimer(aTag: string): tTimer;

var TIMERS: array of tTimer;

implementation

function getTimer(aTag: string): tTimer;
var
  i: integer;
begin
  for i := 0 to length(TIMERS)-1 do
    if TIMERS[i].tag = aTag then exit(TIMERS[i]);
  exit(nil);
end;

procedure addTimer(timer: tTimer);
begin
  setLength(TIMERS, length(TIMERS)+1);
  TIMERS[length(TIMERS)-1] := timer;
end;

procedure startTimer(aTag: string);
var
  timer: tTimer;
begin
  timer := getTimer(aTag);
  if not assigned(timer) then begin
    timer := tTimer.Create(aTag);
    addTimer(timer);
  end;
  timer.start();
end;

procedure stopTimer(aTag: string);
var
  timer: tTimer;
begin
  timer := getTimer(aTag);
  if not assigned(timer) then
    error('No timer called '+aTag);
  timer.stop();
end;

{------------------------------------------------------}

constructor tTimer.Create(aTag: string);
begin
  inherited Create();
  reset(aTag);
end;

procedure tTimer.reset(aTag: string);
begin
  tag := aTag;
  startTime := 0;
  endTime := 0;
  maxElapsed := 0;
end;

function tTimer.elapsed(): double;
begin
  result := endTime - startTime;
end;

procedure tTimer.start();
begin
  startTime := getSec;
end;

procedure tTimer.stop();
begin
  endTime := getSec;
  if elapsed > maxElapsed then
    maxElapsed := elapsed
  else
    maxElapsed *= 0.99;
end;

function tTimer.toString(): string;
begin
  result := format('%s: %f (%f)', [tag, elapsed, maxElapsed]);
end;


begin
end.