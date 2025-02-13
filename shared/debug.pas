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

type
  tLogLevel = (
    llDebug=0,
    llNote=1,
    llInfo=2,
    llImportant=3,
    llWarning=4,
    llError=5,
    llNone=6
  );

type

  tLogEntry = record
    time: tDateTime;
    msg: string;
    level: tLogLevel;
    function toString: String;
  end;

var
  LogEntries: array of TLogEntry;
  LogCount: integer;

  LogFile: Text;
  LogFileOpen: Boolean = False;

procedure log(s: string; level: tLogLevel=llNote);
procedure debug(s: string);
procedure note(s: string); overload;
procedure note(fmt: string; args: array of const); overload;
procedure info(s: string);
procedure warning(s: string);
procedure error(s: string);
procedure fatal(fmt: string; args: array of const); overload;
procedure fatal(s: string; code: byte=255); overload;

function GetLogLevelColor(level: tLogLevel): byte;

procedure BasicPrintLog();
procedure PrintLog(maxEntries: integer=20);

function GetIOErrorString(code: word): string;

procedure assert(condition: boolean; msg: string='');
procedure runError(code: word);
procedure runErrorSkipFrame(code: word);

const
  IO_FILE_NOT_FOUND = 2;
  IO_PATH_NOT_FOUND = 3;
  IO_ACCESS_DENIED = 5;

var
  {todo: make these both levels, not bools}
  VERBOSE_SCREEN: tLogLevel = llWarning;
  VERBOSE_LOG: tLogLevel = {$ifdef debug} llDebug; {$else} llNote; {$endif}

type
  Exception = class(tObject)
  private
    fMessage: string;
  public
    constructor create(const msg: string); overload;
    constructor create(const fmt: string; const args: array of const); overload;
    function toString(): string; override;
    property message: string read fMessage write fMessage;
  end;

  GeneralError = class(Exception);
  ValueError = class(Exception);
  IOError = class(Exception);
  FileNotFoundError = class(Exception);
  AssertionError = class(Exception);

implementation

uses
  utils,
  sysInfo,
  vga;

{------------------------------------------------}

constructor Exception.create(const msg: string);
begin
  fMessage := msg;
end;

constructor Exception.create(const fmt: string; const args: array of const);
begin
  create(format(fmt, args));
end;

function Exception.toString(): string;
begin
  result := ClassName+': ' + fMessage;
end;

{------------------------------------------------}

function tLogEntry.toString(): String;
begin
  result := self.Msg;
end;

{write entry to log}
procedure log(s: string; level: tLogLevel=llNote);
var
  entry: TLogEntry;
  isText: boolean;
  oldTextAttr: byte;
begin
  SetLength(LogEntries, LogCount+1);

  Entry.Time := Now;
  Entry.Msg := s;
  Entry.Level := level;

  {Save to memory}
  LogEntries[LogCount] := entry;
  {Write to disk}
  If (level >= VERBOSE_LOG) and logFileOpen then begin
    writeln(logFile, tMyDateTime(entry.time).YYYYMMDD + ' ' +tMyDateTime(entry.time).HHMMSS + ' ' + entry.toString);
    flush(logFile);
  end;

  if (level >= VERBOSE_SCREEN) and assigned(videoDriver) and videoDriver.isText then begin
    oldTextAttr := textAttr;
    textAttr := (textAttr and $f0) + getLogLevelColor(entry.level);
    writeln(entry.toString);
    textAttr := oldTextAttr;
  end;

  Inc(LogCount);
end;

procedure warning(s: string);
begin
  log(s, llWarning);
end;

procedure error(s: string);
begin
  log(s, llError);
end;

{todo: remove this and have caller use raise GeneralError instead}
procedure fatal(s: string; code: byte=255); noreturn;
begin
  log(s, llError);
  raise GeneralError.create(s);
end;

{todo: remove this and have caller use raise GeneralError instead}
procedure fatal(fmt: string; args: array of const); overload; noreturn;
var
  s: string;
begin
  s := format(fmt, args);
  log(s, llError);
  raise GeneralError.create(s);
end;

procedure note(s: string);
begin
  log(s, llNote);
end;

procedure note(fmt: string; args: array of Const);
begin
  log(format(fmt, args), llNote);
end;

procedure debug(s: string);
begin
  log(s, llDebug);
end;

procedure info(s: string);
begin
  log(s, llInfo);
end;

procedure assert(condition: boolean; msg: string='');
begin
  if not condition then
    raise AssertionError(msg);
end;

procedure printLog(MaxEntries: integer = 20);
var
  i: integer;
  oldTextAttr: byte;
  firstEntry: integer;

  begin

  firstEntry := LogCount-MaxEntries;
  if firstEntry < 0 then firstEntry := 0;

  textAttr := LightGray;
  if firstEntry > 0 then
    writeln('...');

  oldTextAttr := textAttr and $0F;
  for i := firstEntry to logCount-1 do begin
    textAttr := getLogLevelColor(LogEntries[i].level);
    writeln(LogEntries[i].ToString());
  end;

  textAttr := oldTextAttr;
end;

function getLogLevelColor(level: tLogLevel): byte;
begin
  case level of
    llDebug: result := DarkGray;
    llNote: result := LightGray;
    llInfo: result := Green;
    llImportant: result := White;
    llWarning: result := Yellow;
    llError: result := Red;
    else result := White;
  end;
end;

procedure BasicPrintLog();
var
  i: int32;
begin
  for i := 0 to LogCount-1 do
    writeln(LogEntries[i].msg);
end;


function GetIOErrorString(code: word): string;
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
      warning('Stack frame corrupted');
      exit;
    end;
    if (fp = prevfp) then begin
      warning('Stack frame has loop');
      exit;
    end;
    if (fp >= StackTop) then begin
      warning('Stack frame out of bounds');
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

  func, source: shortstring;
  line: longint;

const
  MAX_FRAMES = 16;
begin

  if assigned(videoDriver) then begin
    if not videoDriver.isText then begin
      videoDriver.setText();
      clrscr;
    end;
  end;

  PrintLog(5);

  case ErrNo of
    100: RunError := 'General Error (100)';
    215: RunError := 'Arithmetic Overflow (215)';
    216: RunError := 'General Protection Fault (216)';
    else RunError := 'Runtime error '+IntToStr(ErrNo);
  end;

  warning(RunError);
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
procedure runError(code: word);
var
  address: codePointer;
  frame: pointer;
  basePointer: pointer;
begin
  asm
    mov eax, ebp
    mov basePointer, eax
  end;
  frame := get_caller_frame(basePointer);
  address := get_caller_addr(frame);
  CustomErrorProc(code, Address, Frame);
end;

{
A drop-in replacement for RunError with a few changes.
Calls CustomErrorProc for a common exit point, and so that logs are shown.
Removes one entry of the stack frame.
}
procedure RunErrorSkipFrame(code: word);
var
  address: CodePointer;
  frame: Pointer;
  basePointer: pointer;
begin
  asm
    mov eax, ebp
    mov basePointer, eax
  end;
  frame := get_caller_frame(basePointer);
  frame := get_caller_frame(frame);
  address := get_caller_addr(get_caller_frame(basePointer));
  CustomErrorProc(code, Address, Frame);
end;


{this is called for any uncaught exceptions}
{$push}
{$s-}
procedure CustomExceptProc(obj: tObject; address:codePointer; frameCount: longint; frames: PCodePointer);
var
  CallerAddr: Pointer;
  FramePtr: Pointer;
  InfoStr: string;
  RunError: string;

  func, source: shortstring;
  i: integer;

const
  BG_COLOR = Black;
  MAX_FRAMES = 32;

  procedure textColor(b: byte);
  begin
    textAttr := BG_COLOR * 16 + b;
  end;

begin

  if assigned(videoDriver) then begin
    if not videoDriver.isText then begin
      videoDriver.setText();
    end;
  end;

  VERBOSE_SCREEN := llWarning;

  textColor(White);
  clrscr;

  textColor(White);
  writeln('An error has occured:');
  writeln();
  writeln(obj.toString);

  textColor(White);
  writeln();
  writeln('Stack Trace:');
  writeln(backTraceStrFunc(address));
  for i := 0 to framecount-1 do
    writeln(backTraceStrFunc(frames[i]));

  textColor(White);
  writeln();
  writeln('Log:');
  PrintLog(MAX_FRAMES);

  {also write to log, but only after we have shown it}
  note(obj.toString);
  note(backTraceStrFunc(address));
  for i := 0 to framecount-1 do
    note(backTraceStrFunc(frames[i]));

  note('Halting program');

  Halt(255);
end;
{$pop}

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
    sysutils is actually ok to use now, previously the issue was that
      sysutils removes runerrors, making it so that I can not hook
      the errorProc.
    supporting exceptions properly will fully resolve this.
    However, I don't really like using sysutils anyway because
      1. It's really big
      2. It's not in the 'stuff from 1996' theme
    However it's fine for utility functions like go.
    }
    note('FYI has been detected, and does not work well with debug unit.');
  end;

  // Open Log File
  programFilename := toLowerCase(extractFilename(paramStr(0)));
  Assign(LogFile, removeExtension(programFilename)+'.log');
  Rewrite(LogFile);
  LogFileOpen := True;

  if HOOK_EXIT then begin

    // Install Error Hooks
    ErrorProc := CustomErrorProc;
    {This shouldn't be needed, but will help in the future if we want to
     support exceptions.}
    ExceptProc := CustomExceptProc;

    // Make sure to clean up log when we shutdow.
    AddExitProc(@shutdownLog);
  end;

  info('[init] Logging');

end.
