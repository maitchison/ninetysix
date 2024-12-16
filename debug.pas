{Setup logging and debugging}
unit Debug;

{$MODE Delphi}

interface

uses
  crt;

var
  oldErrorProc: Pointer;

CONST
  HOOK_EXIT: boolean = True;

CONST
  LOG_NOTE = 1;
  LOG_INFO = 2;
  LOG_WARNING = 3;
  LOG_ERROR = 4;

  LOG_COLOR : array[LOG_NOTE..LOG_ERROR] of byte = (
    LightGray, Green, Yellow, Red
  );

type

  tLogEntry = record
    time: tDateTime;
    msg: string;
    level: byte;
    function toString: String;
  end;

var
  LogEntries: array of TLogEntry;
  LogCount: integer;

  LogFile: Text;
  LogFileOpen: Boolean = False;

procedure Log(s: string; level: byte=LOG_NOTE);
procedure Note(s: string);
procedure Info(s: string);
procedure Warn(s: string);
procedure Error(s: string;code: byte=100);

procedure BasicPrintLog();
procedure PrintLog(maxEntries: integer=20);

function GetIOError(code: word): string;

procedure Assert(condition: boolean; msg: string='');
procedure RunError(code: word);
procedure RunErrorSkipFrame(code: word);

const
  IO_FILE_NOT_FOUND = 2;
  IO_PATH_NOT_FOUND = 3;
  IO_ACCESS_DENIED = 5;

var
  WRITE_TO_LOG: boolean = true;
  WRITE_TO_SCREEN: boolean = true;

implementation

uses
  utils,
  vga;

function tLogEntry.toString(): String;
begin
  result := self.Msg;
end;

{write entry to log}
procedure Log(s: string; level: byte=LOG_NOTE);
var
  Entry: TLogEntry;
  isText: boolean;
begin
  SetLength(LogEntries, LogCount+1);

  Entry.Time := Now;
  Entry.Msg := s;
  Entry.Level := level;

  {Save to memory}
  LogEntries[LogCount] := entry;
  {Write to disk}
  If WRITE_TO_LOG and logFileOpen then begin
    writeln(logFile, tMyDateTime(entry.time).YYMMDD + ' ' +tMyDateTime(entry.time).HHMMSS + ' ' + entry.toString);
    flush(logFile);
  end;

  if WRITE_TO_SCREEN and assigned(videoDriver) and videoDriver.isText then begin
    writeln(entry.toString);
  end;

  Inc(LogCount);
end;

procedure Warn(s: string);
begin
  Log(s, LOG_WARNING);
end;

procedure Error(s: string; code: byte=100);
begin
  Log(s, LOG_ERROR);
  RunErrorSkipFrame(code);
end;

procedure Note(s: string);
begin
  Log(s, LOG_NOTE);
end;

procedure Info(s: string);
begin
  Log(s, LOG_INFO);
end;

procedure Assert(condition: boolean; msg: string='');
begin
  if not condition then
    Error('Assertion failure:' + msg);
end;

procedure PrintLog(MaxEntries: integer = 20);
var
  i: integer;
  oldTextAttr: byte;
  firstEntry: integer;

  begin

  firstEntry := LogCount-MaxEntries;
  if firstEntry < 0 then firstEntry := 0;

  if firstEntry > 0 then
    writeln('...');

  oldTextAttr := textAttr and $0F;
  for i := firstEntry to LogCount-1 do begin
    textAttr := LOG_COLOR[LogEntries[i].level];
    writeln(LogEntries[i].ToString());
  end;
  textAttr := oldTextAttr;
end;

procedure BasicPrintLog();
var
  i: int32;
begin
  for i := 0 to LogCount-1 do
    writeln(LogEntries[i].msg);
end;


function GetIOError(code: word): string;
begin
  case code of
    IO_FILE_NOT_FOUND: result := 'File not found';
    IO_PATH_NOT_FOUND: result := 'Path not found';
    IO_ACCESS_DENIED: result := 'Access Denied';
    else result := '('+IntToStr(code)+')';
  end;
end;

{my version of dump stack from system}
procedure dumpStack(fp: pointer);
var
  i : longint;
  addr: codePointer;
  prevfp : pointer;
begin
  addr := nil;
  prevfp := get_frame;
  i := 0;
  while true do begin
    if (fp < prevfp) then begin
      warn('Stack frame corrupted');
      exit;
    end;
    if (fp = prevfp) then begin
      warn('Stack frame has loop');
      exit;
    end;
    if (fp >= StackTop) then begin
      warn('Stack frame out of bounds');
      exit;
    end;
    prevfp:=fp;
    get_caller_stackinfo(fp, addr);
    if (addr=nil) then break;
    note(backTraceStrFunc(addr));
    if (fp=nil) then break;
    inc(i);
    if (i > 256) then break;
  end;
end;

procedure CustomErrorProc(ErrNo: longint; address:CodePointer; frame: Pointer);
var
  CallerAddr: Pointer;
  FramePtr: Pointer;
  InfoStr: string;
  FrameCount: integer;
  RunError: string;

const
  MAX_FRAMES = 16;
begin

  if assigned(videoDriver) then begin
    if not videoDriver.isText then begin
      videoDriver.setText();
      clrscr;
    end;
  end;

  warn('An error has occured!');

  case ErrNo of
    100: RunError := 'General Error (100)';
    215: RunError := 'Arithmetic Overflow (215)';
    else RunError := 'Runtime error '+IntToStr(ErrNo);
  end;

  warn(RunError);
  note(backTraceStrFunc(address));
  dumpStack(frame);

  if assigned(OldErrorProc) then
    tErrorProc(OldErrorProc)(ErrNo, Address, Frame);

  Halt(ErrorCode);
end;

{
A drop-in replacement for RunError with a few changes.
Calls CustomErrorProc for a common exit point, and so that logs are shown.

This is needed, as the built in RunError does not call ErrorProc
(for some reason).
}
procedure RunError(code: word);
var
  Address: CodePointer;
  Frame: Pointer;
begin
  asm
  // FPC will complain that this is not a valid way to access parameters,
  // but I'm instead looking at the stack frame.

  // [MA] Actually this might be wrong.. need to check this out.
  mov  eax, [ebp+4]    // get current frame pointer
  mov  [Address], eax

  // get callers return address
  mov  eax, ebp
  mov  [frame], eax
  end;
  CustomErrorProc(code, Address, Frame);
end;

{
A drop-in replacement for RunError with a few changes.
Calls CustomErrorProc for a common exit point, and so that logs are shown.
Removes one entry of the stack frame.
}
procedure RunErrorSkipFrame(code: word);
var
  Address: CodePointer;
  Frame: Pointer;
begin
  asm
  mov  eax, [ebp]    // get current frame pointer
  mov  ebx, [eax]    // get caller's pointer
  mov  [Frame], ebx

  // get callers return address
  mov  eax, [eax+4]
  mov  [Address], eax
  end;
  CustomErrorProc(code, Address, Frame);
end;


procedure CustomExceptProc(obj: TObject; Address:CodePointer; Frame: Pointer);
begin
  CustomErrorProc(255, Address, Frame);
end;

procedure ShutdownLog();
begin
  Info('[close] Logging');
  Close(LogFile);
  LogFileOpen := False;
end;


var
  small: integer;
  programFilename: string;

begin

  if assigned(ExceptProc) then begin
    {
    sysutils removes runerrors, making it so that I can not hook the errorProc.
    I could try to support exceptions, but for the moment just exit.
    Also, we don't really want sysutils because...
      1. It's really big
      2. It's not in the 'stuff from 1996' theme
    }
    warn('Sysutils has been detected, but not not compatiable with the debug unit.');
  end;

  // Open Log File
  programFilename := toLowerCase(extractFilename(paramStr(0)));
  Assign(LogFile, removeExtension(programFilename)+'.log');
  Rewrite(LogFile);
  LogFileOpen := True;

  if HOOK_EXIT then begin

    // Install Error Hooks
    ErrorProc := @CustomErrorProc;
    {This shouldn't be needed, but will help in the future if we want to
     support exceptions.}
    ExceptProc := @CustomExceptProc;

    // Make sure to clean up log when we shutdow.
    AddExitProc(@shutdownLog);
  end;

  info('[init] Logging');

  showCPUInfo();

end.
