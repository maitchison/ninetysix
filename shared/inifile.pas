{for handling reading / writing ini files}
unit inifile;

interface

uses
  debug,
  list,
  utils;

type

  tINIWriter = class;
  tINIReader = class;

  iIniSerializable = interface
    ['{ff7cb00f-dbc4-4a26-a718-ec1b03d0f1e3}']
    procedure writeToIni(const ini: tINIWriter);
    procedure readFromIni(const ini: tINIReader);
  end;

  tINIWriter = class
  private
    t: text;
  public

    procedure writeInteger(name: string; value: int64);
    procedure writeBool(name: string; value: boolean);
    procedure writeFloat(name: string; value: double);
    procedure writeString(name: string; value: string);
    procedure writeSection(name: string);
    procedure writeObject(sectionName: string; value: iIniSerializable);
    procedure writeBlank();

    constructor Create(filename: string);
    destructor Destroy(); override;
  end;

  tObjectConstructorProc = function(s: string): tObject of object;

  tINIReader = class
  private
    lines: tStringList;
    lineOn: int32;
    fCurrentSection: string;
  public

    factory: tObjectConstructorProc;

    function  eof(): boolean;
    function  readLine(): string;
    function  peekLine(): string;
    function  nextLine(): string;

    property currentSection: string read fCurrentSection;

    function  readObject(): tObject;

    constructor Create(filename: string;aFactory: tObjectConstructorProc = nil);
    destructor Destroy(); override;
  end;

implementation

{----------------------------------------------}

procedure tINIWriter.writeInteger(name: string; value: int64);
begin
  writeln(t, format('%s=%d', [name, value]));
end;

procedure tINIWriter.writeBool(name: string; value: boolean);
begin
  if value then
    writeln(t, name+'=true')
  else
    writeln(t, name+'=false');
end;

procedure tINIWriter.writeFloat(name: string; value: double);
begin
  writeln(t, format('%s=%.9f', [name, value]));
end;

procedure tINIWriter.writeString(name: string; value: string);
begin
  writeln(t, format('%s="%s"', [name, value]));
end;

procedure tINIWriter.writeSection(name: string);
begin
  writeln(t, format('[%s]', [name]));
end;

procedure tINIWriter.writeBlank();
begin
  writeln(t);
end;

{writes object out to text file}
procedure tINIWriter.writeObject(sectionName: string; value: iINISerializable);
begin
  writeSection(sectionName);
  value.writeToINI(self);
  writeBlank();
end;

constructor tINIWriter.create(filename: string);
begin
  inherited create();
  assign(t, filename);
  rewrite(t);
end;

destructor tINIWriter.destroy();
begin
  close(t);
  inherited destroy();
end;

{----------------------------------------------}

function tINIReader.eof(): boolean;
begin
  result := lineOn >= lines.len;
end;

{raw read line}
function tINIReader.readLine(): string;
begin
  result := trim(lines[lineOn]);
  lineOn += 1;
end;

{read next content line}
function tINIReader.nextLine(): string;
var
  line: string;
begin
  while not eof do begin
    line := readLine();
    if line = '' then continue;
    if line.startsWith('#') then continue;
    if line.startsWith('[') then begin
      fCurrentSection := copy(line, 2, length(line)-2);
      continue;
    end;
    exit(line);
  end;
  {eof}
  result := '';
end;

function tINIReader.peekLine(): string;
begin
  if eof then result := '';
  result := trim(lines[lineOn]);
end;

{read next object from ini file}
function tINIReader.readObject(): tObject;
var
  line: string;
  sectionName: string;
  obj: tObject;
  key, value: string;
  so: iIniSerializable;
begin
  line := readLine;
  if not line.startsWith('[') then error(format('Expected section header, but found "%s"', [line]));

  if not assigned(factory) then error('Must assign a factory to read objects.');

  sectionName := copy(line, 2, length(line)-2);

  obj := factory(sectionName);
  result := obj;

  if not assigned(obj) then error(format('Factory failed to construct object of type "%s"', [sectionName]));

  if obj.getInterface(iIniSerializable, so) then
    so.readFromIni(self);
end;

constructor tINIReader.create(filename: string; aFactory: tObjectConstructorProc = nil);
begin
  inherited create();
  factory := aFactory;
  lines.load(filename);
  lineOn := 0;
end;

destructor tINIReader.destroy();
begin
  inherited destroy();
end;

{----------------------------------------------}

begin
end.
