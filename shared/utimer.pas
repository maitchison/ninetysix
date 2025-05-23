{handles timers}
unit uTimer;

interface

uses
  uDebug,
  uUtils;

type

  tTimerMode = (tmDefault, tmMBS);

  tTimer = class
    tag: string;
    mode: tTimerMode;
    startTime: double;
    elapsed, maxElapsed, avElapsed, totalElapsed, lastStop: double;
    cycles: int64;
    constructor Create(aTag: string);
    procedure reset(aTag: string);
    procedure start();
    procedure stop(iterations: integer=1);
    function  toString(): string; override;
  end;

function  startTimer(aTag: string): tTimer; overload;
function  startTimer(aTag: string; mode: tTimerMode): tTimer; overload;
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

function startTimer(aTag: string): tTimer;
var
  timer: tTimer;
begin
  timer := getTimer(aTag);
  if not assigned(timer) then begin
    timer := tTimer.Create(aTag);
    addTimer(timer);
  end;
  timer.start();
  result := timer;
end;

function startTimer(aTag: string; mode: tTimerMode): tTimer;
begin
  result := startTimer(aTag);
  result.mode := mode;
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

constructor tTimer.create(aTag: string);
begin
  inherited create();
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
  mode := tmDefault;
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
  case mode of
    tmDefault: begin
      if avElapsed < 0.1 then
        result := format('%s %.2fms (%fms) [total:%.2fs]', [pad(tag, 20), 1000*avElapsed, 1000*maxElapsed, 1.0*totalElapsed])
      else
        result := format('%s %.3fs (%fs) [total:%.2fs]', [pad(tag, 20), avElapsed, maxElapsed, totalElapsed]);
    end;
    tmMBS: result := format('%s %.1f MB/S', [pad(tag, 20), (cycles/1024/1024)/totalElapsed]);
  end;
end;

var timer: tTimer;

initialization

finalization

  for timer in TIMERS do
    timer.free();
  setLength(TIMERS, 0);

end.
