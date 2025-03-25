unit uJob;

interface

uses
  uUtils;

type

  tJobState = (jsActive, jsIdle, jsDone);

  tJob = class
  public
    state: tJobState;
    procedure update(timeSlice: single); virtual;
    procedure start; virtual;
    procedure stop; virtual;
  end;

  tJobs = array of tJob;

  tJobSystem = class
  protected
    jobIdx: integer;
    jobs: tJobs;
    procedure cleanUpJobs();
    procedure addJob(aJob: tJob);
  public
    procedure update(timeSlice: single=0.005);
  end;

var
  jobs: tJobSystem;

implementation

{-----------------------------------------}

procedure tJob.update(timeSlice: single);
begin
  // decendant should override
end;

procedure tJob.start();
begin
  state := jsActive;
  jobs.addJob(self);
end;

procedure tJob.stop();
begin
  state := jsDone;
end;

{-----------------------------------------}

procedure tJobSystem.cleanUpJobs();
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

procedure tJobSystem.addJob(aJob: tJob);
begin
  setLength(jobs, length(jobs)+1);
  jobs[length(jobs)-1] := aJob;
end;

procedure tJobSystem.update(timeSlice: single=0.005);
var
  startTime: double;
  job: tJob;
  slices: integer;
const
  {1 ms to time slice}
  TIME_SLICE = 0.001;
  MAX_SLICES = 100;
begin

  {wake everyone up}
  for job in jobs do if job.state = jsIdle then job.state := jsActive;

  {round robin}
  startTime := getSec;
  slices:= 0;
  while (getSec < (startTime + timeSlice)) and (slices < MAX_SLICES) do begin
    if length(jobs) = 0 then exit;
    case jobs[jobIdx].state of
      jsActive: jobs[jobIdx].update(TIME_SLICE);
    end;
    inc(jobIdx);
    if jobIdx >= length(jobs) then
      jobIdx := 0;
    inc(slices)
  end;

  cleanUpJobs();

end;

initialization
  jobs := tJobSystem.Create();
finalization
  {todo: shut down jobs properly}
  jobs.free;
end.
