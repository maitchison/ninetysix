{very simple unit for handling CSV writing}
unit uCSV;

interface

uses
  uDebug,
  uTest,
  uUtils;

type
  tCSVWriter = class
    t: textFile;
    constructor create(aFilename: string);
    destructor destroy(); override;
    procedure writeHeader(s: string);
    procedure writeRow(args: array of const);
    procedure close();
  end;

implementation

constructor tCSVWriter.create(aFilename: string);
begin
  assign(t, aFilename);
  rewrite(t);
end;

destructor tCSVWriter.destroy();
begin
  close();
  inherited destroy;
end;

procedure tCSVWriter.writeHeader(s: string);
begin
  writeln(t, s);
end;

procedure tCSVWriter.writeRow(args: array of const);
var
  line: string;
  a: tVarRec;
begin
  line := '';
  for a in args do
    case a.vType of
      vtInteger: line += IntToStr(a.vInteger) + ',';
      vtInt64: line += IntToStr(a.vInt64^) +',';
      vtExtended: line += format('%.6f', [a.vExtended^])+',';
      vtString: line += '"'+string(a.vString^)+'",';
      vtAnsiString: line += '"'+AnsiString(a.vAnsiString)+'",';
      else raise ValueError('Invalid variant type '+intToStr(a.vType));
    end;

  if line.endswith(',') then line := copy(line, 1, length(line)-1);
  writeln(t,line);
end;

procedure tCSVWriter.close();
begin
  system.close(t);
end;


begin
end.
