unit uJob;

interface

uses
  uUtils;

type

  tJobState = (jsActive, jsIdle, jsDone);
  tJobPriority = (jpHigh, jpMedium, jpLow);

  tJob = class
  public
    state: tJobState;
    priority: tJobPriority;
    constructor Create();
    procedure update(timeSlice: single); virtual;
    procedure start(aPriority: tJobPriority); overload;
    procedure start(); overload;
    procedure stop; virtual;
  end;

  tJobs = array of tJob;

  tJobQueue = class
  protected
    jobIdx: integer;
    jobs: tJobs;
    procedure cleanUpJobs();
    procedure addJob(aJob: tJob);
    function  activeJobs: integer;
    procedure wakeAll();
  public
    procedure update(timeSlice: single=0.001);
  end;

  tJobSystem = class
  protected
    jobQueue: array[tJobPriority] of tJobQueue;
    procedure addJob(aJob: tJob);
  public
    constructor Create();
    procedure update(timeSlice: single=0.005);
  end;

var
  {job queues for each of our job priorities}
  js: tJobSystem;

implementation

{-----------------------------------------}

constructor tJob.Create();
begin
  priority := jpMedium;
end;

procedure tJob.update(timeSlice: single);
begin
  // decendant should override
end;

procedure tJob.start(aPriority: tJobPriority); overload;
begin
  state := jsActive;
  priority := aPriority;
  js.addJob(self);
end;

procedure tJob.start(); overload;
begin
  state := jsActive;
  js.addJob(self);
end;

procedure tJob.stop();
begin
  state := jsDone;
end;

{-----------------------------------------}

procedure tJobQueue.cleanUpJobs();
var
  currentJobCount: integer;
  newJobs: tJobs;
  job: tJob;
  i: integer;
begin
  {clean up}
  currentJobCount := 0;
  for job in jobs do if job.state <> jsDone then inc(currentJobCount);
  if currentJobCount <> length(jobs) then begin
    setLength(newJobs, currentJobCount);
    i := 0;
    for job in jobs do begin
      if job.state = jsDone then begin
        job.free;
      end else begin
        newJobs[i] := job;
        inc(i);
      end;
    end;
    jobs := newJobs;
  end;
end;

procedure tJobQueue.addJob(aJob: tJob);
begin
  setLength(jobs, length(jobs)+1);
  jobs[length(jobs)-1] := aJob;
end;

procedure tJobQueue.wakeAll();
var
  job: tJob;
begin
  for job in jobs do if job.state = jsIdle then job.state := jsActive;
end;

function tJobQueue.activeJobs: integer;
var
  job: tJob;
begin
  result := 0;
  for job in jobs do if job.state = jsActive then inc(result);
end;

procedure tJobQueue.update(timeSlice: single=0.001);
var
  startTime: double;
  job: tJob;
  slices: integer;
const
  {1 ms to time slice}
  TIME_SLICE = 0.001;
  MAX_SLICES = 100;
begin
  if length(jobs) = 0 then exit;
  {round robin}
  startTime := getSec;
  slices:= 0;
  while (getSec < (startTime + timeSlice)) and (slices < MAX_SLICES) do begin
    case jobs[jobIdx].state of
      jsActive: jobs[jobIdx].update(TIME_SLICE);
    end;
    inc(jobIdx);
    if jobIdx >= length(jobs) then
      jobIdx := 0;
    inc(slices);
    {only allow one round}
    if (slices >= length(jobs)) then break;
  end;
  cleanUpJobs();
end;

{-----------------------------------------}

procedure tJobSystem.addJob(aJob: tJob);
begin
  jobQueue[aJob.priority].addJob(aJob);
end;

procedure tJobSystem.update(timeSlice: single=0.005);
var
  priority: tJobPriority;
  remainingTime: single;
  startTime: single;
  totalActiveJobs: integer;
begin
  startTime := getSec;

  for priority in tJobPriority do jobQueue[priority].wakeAll;

  while true do begin

    totalActiveJobs := 0;
    for priority in tJobPriority do begin
      remainingTime := timeSlice - (getSec - startTime);
      if remainingTime <= 0 then exit;
      jobQueue[priority].update(remainingTime);
      totalActiveJobs += jobQueue[priority].activeJobs;
    end;

    if totalActiveJobs = 0 then exit;
  end;
end;

constructor tJobSystem.Create();
var
  priority: tJobPriority;
begin
  inherited Create();
  for priority in tJobPriority do jobQueue[priority] := tJobQueue.Create();
end;

{-----------------------------------------}

initialization
  js := tJobSystem.Create();
finalization
  {todo: shut down jobs properly}
  js.free;
end.
