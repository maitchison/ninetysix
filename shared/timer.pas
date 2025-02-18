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
    elapsed, maxElapsed, avElapsed, totalElapsed, lastStop: double;
    cycles: int32;
    constructor Create(aTag: string);
    procedure reset(aTag: string);
    procedure start();
    procedure stop(iterations: integer=1);
    function  toString(): string; override;
  end;

procedure startTimer(aTag: string);
procedure stopTimer(aTag: string; iterations: integer=1);
function  getTimer(aTag: string): tTimer;

procedure logTimers();

var TIMERS: array of tTimer;

implementation

procedure logTimers();
var
  timer: tTimer;
begin
  for timer in TIMERS do
    note(timer.toString);
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

procedure stopTimer(aTag: string;iterations: integer=1);
var
  timer: tTimer;
begin
  timer := getTimer(aTag);
  if not assigned(timer) then
    fatal('No timer called '+aTag);
  timer.stop(iterations);
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
  lastStop := getSec;
end;

procedure tTimer.start();
begin
  startTime := getSec;
end;

{Stop the timer.
 pass in the number of iterations that occured since start.
 timings will be divided by this number.
 }
procedure tTimer.stop(iterations: integer=1);
var
  alpha: single;
  timeSinceLastStop: double;
begin
  {decay max elapsed}
  timeSinceLastStop := getSec - lastStop;
  lastStop := getSec;
  if iterations <= 0 then exit;
  {this means we average roughly over 1-second}
  alpha := 1-clamp(timeSinceLastStop, 0.01, 0.5);
  maxElapsed *= alpha;
  avElapsed *= alpha;

  elapsed := (getSec-startTime) / iterations;
  if cycles = 0 then
    avElapsed := elapsed
  else begin
    avElapsed += (1-alpha) * elapsed;
  end;
  if elapsed > maxElapsed then
    maxElapsed := elapsed;

  totalElapsed += elapsed * iterations;
  cycles += iterations;
end;

function tTimer.toString(): string;
begin
  if avElapsed < 0.1 then
    result := format('%s %fms (%fms) [total:%.2fs]', [pad(tag,20), 1000*avElapsed, 1000*maxElapsed, totalElapsed])
  else
    result := format('%s %fs (%fs) [total:%.2fs]', [pad(tag, 20), avElapsed, maxElapsed, totalElapsed]);
end;

var timer: tTimer;

initialization

finalization

  for timer in Timers do
    timer.free;

end.
