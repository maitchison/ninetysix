{for handling reading / writing ini files}
unit inifile;

{$interfaces corba}

interface

uses
  debug,
  list,
  utils,
  sysTypes,
  graph2d;

type

  tINIWriter = class;
  tINIReader = class;

  iIniSerializable = interface
    procedure writeToIni(ini: tINIWriter);
    procedure readFromIni(ini: tINIReader);
  end;

  tINIWriter = class
  private
    t: text;
  public
    {basic types}
    procedure writeInteger(key: string; value: int64);
    procedure writeBool(key: string; value: boolean);
    procedure writeFloat(key: string; value: double);
    procedure writeString(key: string; value: string);
    {advanced types}
    procedure writeArray(key: string; values: tInt32Array);
    procedure writeRect(key: string; value: tRect);
    {objects}
    procedure writeObject(sectionName: string; value: iIniSerializable);
    {...}
    procedure writeSection(key: string);
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
    function  peekKey(): string;
    function  nextKeyLine(): string;
    function  nextLine(): string;
    function  readKey(key: string): string;

    property  currentSection: string read fCurrentSection;

    function  readObject(): tObject;

    function  readString(key: string): string;
    function  readInteger(key: string): int32;
    function  readFloat(key: string): double;
    function  readIntArray(key: string): tInt32Array;
    function  readRect(key: string): tRect;

    constructor create(filename: string;aFactory: tObjectConstructorProc = nil);
    destructor destroy(); override;
  end;

implementation

{----------------------------------------------}

procedure tINIWriter.writeInteger(key: string; value: int64);
begin
  writeln(t, format('%s=%d', [key, value]));
end;

procedure tINIWriter.writeArray(key: string; values: tInt32Array);
begin
  writeln(t, format('%s=%s', [key, values.toString]));
end;

procedure tINIWriter.writeBool(key: string; value: boolean);
begin
  if value then
    writeln(t, key+'=true')
  else
    writeln(t, key+'=false');
end;

procedure tINIWriter.writeFloat(key: string; value: double);
begin
  writeln(t, format('%s=%.9f', [key, value]));
end;

procedure tINIWriter.writeString(key: string; value: string);
begin
  writeln(t, format('%s="%s"', [key, value]));
end;

procedure tINIWriter.writeSection(key: string);
begin
  writeln(t, format('[%s]', [key]));
end;

procedure tINIWriter.writeRect(key: string; value: tRect);
begin
  writeArray(key, [value.x, value.y, value.width, value.height]);
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

{read until we find key}
function tINIReader.readKey(key: string): string;
var
  line: string;
  lineKey, lineValue: string;
begin
  result := '';
  repeat
    line := nextKeyLine;
    split(line, '=', lineKey, lineValue);
    lineKey := lineKey.trim();
    lineValue := lineValue.trim();
    if lineKey.toLower() = key.toLower() then exit(lineValue);
  until eof;
  fatal('INI file missing key "'+key+'".');
end;

{read next content line}
function tINIReader.nextKeyLine(): string;
var
  line: string;
begin
  while not eof do begin
    line := nextLine();
    if line.startsWith('[') then begin
      fCurrentSection := copy(line, 2, length(line)-2);
      continue;
    end;
    exit(line);
  end;
  {eof}
  result := '';
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
    exit(line);
  end;
  {eof}
  result := '';
end;

function tINIReader.peekLine(): string;
begin
  if eof then exit('');
  result := trim(lines[lineOn]);
end;

function tINIReader.peekKey(): string;
var
  line: string;
  lineKey, lineValue: string;
begin
  line := peekLine;
  if line = '' then exit('');
  split(line, '=', lineKey, lineValue);
  result := lineKey.trim();
end;

{read next object from ini file}
function tINIReader.readObject(): tObject;
var
  line: string;
  sectionName: string;
  obj: tObject;
  key, value: string;
begin
  if eof then exit(nil);
  line := nextLine;
  if line = '' then exit(nil);
  if not line.startsWith('[') then fatal(format('Expected section header, but found "%s"', [line]));

  if not assigned(factory) then fatal('Must assign a factory to read objects.');

  sectionName := copy(line, 2, length(line)-2);

  obj := factory(sectionName);
  result := obj;

  if not assigned(obj) then fatal(format('Factory failed to construct object of type "%s"', [sectionName]));

  if obj is iIniSerializable then
    (obj as iIniSerializable).readFromIni(self)
  else
    warning('Ignoring unknown section tag ['+sectionName+']');
end;

function tINIReader.readString(key: string): string;
var
  value: string;
begin
  value := readKey(key);
  if length(value) < 2 then fatal('Invalid string format');
  if not value.startsWith('"') or (not value.endsWith('"')) then fatal('Invalid string format');
  result := copy(value, 2, length(value)-2);
end;

function tINIReader.readInteger(key: string): int32;
var
  value: string;
begin
  value := readKey(key);
  result := strToInt(value);
end;

function tINIReader.readFloat(key: string): double;
var
  value: string;
begin
  value := readKey(key);
  result := strToFlt(value);
end;

function tINIReader.readIntArray(key: string): tInt32Array;
var
  s: string;
  intList: tIntList;
begin
  s := readKey(key);
  intList.loadS(s);
  result := intList.data;
end;

function tINIReader.readRect(key: string): tRect;
var
  values: tInt32Array;
begin
  values := readIntArray(key);
  result.x := values[0];
  result.y := values[1];
  result.width := values[2];
  result.height := values[3];
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
