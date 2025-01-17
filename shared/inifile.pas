{for handling reading / writing ini files}
unit inifile;

interface

uses
  typinfo,
  debug,
  list,
  utils;

type

  tINIWriter = class
  private
    t: text;
  public

    procedure writeInteger(name: string; value: int64);
    procedure writeBool(name: string; value: boolean);
    procedure writeFloat(name: string; value: double);
    procedure writeString(name: string; value: string);
    procedure writeSection(name: string);
    procedure writeObject(sectionName: string; value: tObject);
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
procedure tINIWriter.writeObject(sectionName: string; value: tObject);
var
  i: integer;
  propCount: integer;
  propInfo: pPropInfo;

  pt: pTypeData;
  pi: pTypeInfo;
  pp: pPropList;

begin
  writeSection(sectionName);

  pi := value.ClassInfo;
  pt := getTypeData(pi);

  try
    getMem(pp, pt^.propCount * sizeof(pointer));
    propCount := getPropList(value, pp);
    for i := 0 to propCount-1 do begin
      propInfo := pp^[i];

      case propInfo^.propType^.kind of
        tkInteger, tkInt64: writeInteger(propInfo^.name, getOrdProp(value, propInfo));
        tkFloat: writeFloat(propInfo^.name, getFloatProp(value, propInfo));
        tkString, tkLString, tkWString, tkUString, tkAString: writeString(propInfo^.name, getStrProp(value, propInfo));
        tkBool: writeBool(propInfo^.name, getOrdProp(value, propInfo) < 0);
        else warning(format('unknown property type %s on %s.%s', [propInfo^.propType^.kind, sectionName, propInfo^.name]));
      end;
    end;
  finally
    freeMem(pp);
  end;

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

{writes value published property of an object}
procedure writeProperty(obj: tObject; key, value: string);
var
  pt: pTypeData;
  pi: pTypeInfo;
  pp: pPropList;
  propInfo: pPropInfo;
  i, propCount: int32;
begin
  {there must be a better way than this!}

  pi := obj.ClassInfo;
  pt := getTypeData(pi);

  try
    getMem(pp, pt^.propCount * sizeof(pointer));
    propCount := getPropList(obj, pp);
    for i := 0 to propCount-1 do begin
      propInfo := pp^[i];
      if propInfo.name <> key then continue;
      case propInfo^.propType^.kind of
        tkInteger, tkInt64:
          setOrdProp(obj, propInfo, strToInt(value));
        tkFloat:
          setFloatProp(obj, propInfo, strToFlt(value));
        tkString, tkLString, tkWString, tkUString, tkAString: begin
          // strings should be in quotes
          value := value.trim();
          if not value.startsWith('"') or not value.endsWith('"') then error(format('String property not quoted %s=%s', [key, value]));
          value := copy(value, 2, length(value)-2);
          setStrProp(obj, propInfo, value);
        end;
        tkBool:
          setOrdProp(obj, propInfo, ord(strToBool(value)));
        else
          warning(format('unknown property type %s on %s.%s', [propInfo^.propType^.kind, pi^.name, propInfo^.name]));
      end;
      exit;
    end;

    error(format('No propery named %s found on %s', [key, pi.name]));

  finally
    freeMem(pp);
  end;
end;


{read next object from ini file}
function tINIReader.readObject(): tObject;
var
  line: string;
  sectionName: string;
  obj: tObject;
  key, value: string;
begin
  line := readLine;
  if not line.startsWith('[') then error(format('Expected section header, but found "%s"', [line]));

  if not assigned(factory) then error('Must assign a factory to read objects.');

  sectionName := copy(line, 2, length(line)-2);

  obj := factory(sectionName);
  result := obj;

  if not assigned(obj) then error(format('Factory failed to construct object of type "%s"', [sectionName]));

  while not eof do begin

    {check if we're at the start of a new section}
    if peekLine.startsWith('[') then exit;

    line := readLine();

    {ignore comments and blank lines}
    if line = '' then continue;
    if line.startsWith('#') then continue;

    {read properties}
    if not split(line, '=', key, value) then
      error(format('Could not process line "%s", expecting key=value', [line]));

    writeProperty(obj, key, value);
  end;
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
