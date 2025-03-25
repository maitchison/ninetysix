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
  public
    jobs: tJobs;
    procedure cleanUpJobs();
    procedure startJob(aJob: tJob);
    procedure update(timeSlice: single=0.005);
  end;

implementation

{-----------------------------------------}

procedure tJob.update(timeSlice: single);
begin
end;

procedure tJob.start();
begin
end;

procedure tJob.stop();
begin
end;

{-----------------------------------------}

procedure tJobSystem.cleanUpJobs();
var
  activeJobs: integer;
  newJobs: tJobs;
  job: tJob;
  i: integer;
begin
  {clean up}
  activeJobs := 0;
  for job in jobs do if job.state = jsActive then inc(activeJobs);
  if activeJobs <> length(jobs) then begin
    setLength(newJobs, activeJobs);
    i := 0;
    for job in jobs do if job.state = jsActive then begin
      newJobs[i] := job;
      inc(i);
    end;
  end;
end;

procedure tJobSystem.startJob(aJob: tJob);
begin
  aJob.state := jsActive;
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

begin
end.
