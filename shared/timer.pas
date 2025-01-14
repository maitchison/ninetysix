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
    elapsed, maxElapsed, avElapsed, totalElapsed: double;
    cycles: int32;
    constructor Create(aTag: string);
    procedure reset(aTag: string);
    procedure start();
    procedure stop();
    function  toString(): string;
  end;

procedure startTimer(aTag: string);
procedure stopTimer(aTag: string);
function getTimer(aTag: string): tTimer;

procedure printTimers();

var TIMERS: array of tTimer;

implementation

procedure printTimers();
var
  timer: tTimer;
begin
  for timer in TIMERS do
    writeln(timer.toString);
end;

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
  elapsed := 0;
  maxElapsed := 0;
  avElapsed := 0;
  cycles := 0;
  totalElapsed := 0;
end;

procedure tTimer.start();
begin
  startTime := getSec;
end;

procedure tTimer.stop();
var
  alpha: single;
begin
  elapsed := getSec-startTime;
  if cycles = 0 then
    avElapsed := elapsed
  else begin
    // this means we average roughly over 1-second
    alpha := clamp(elapsed, 0.01, 0.5);
    avElapsed := ((1-alpha) * avElapsed) + (alpha * elapsed);
  end;
  if elapsed > maxElapsed then
    maxElapsed := elapsed
  else
    maxElapsed *= 0.995;
  totalElapsed += elapsed;
  inc(cycles);
end;

function tTimer.toString(): string;
begin
  result := format('%s: %f (%f) [total:%f]', [tag, elapsed, maxElapsed, totalElapsed]);
end;

begin
end.
