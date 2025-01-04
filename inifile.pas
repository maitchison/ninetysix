{for handling reading / writing ini files}
unit inifile;

interface

uses
  typinfo,
  debug,
  utils;

type

  tIniFile = class
  private
    t: text;
  public

    procedure writeInteger(name: string; value: int64);
    procedure writeBool(name: string; value: boolean);
    procedure writeFloat(name: string; value: double);
    procedure writeString(name: string; value: string);
    procedure writeSection(name: string);
    procedure writeObject(name: string; value: tObject);

    constructor Create(filename: string);
    destructor Destroy(); override;
  end;

implementation

{----------------------------------------------}

constructor tIniFile.create(filename: string);
begin
  inherited create();
  assign(t, filename);
  rewrite(t);
end;

destructor tIniFile.destroy();
begin
  close(t);
  inherited destroy();
end;

procedure tIniFile.writeInteger(name: string; value: int64);
begin
  writeln(t, format('%s=%d', [name, value]));
end;

procedure tIniFile.writeBool(name: string; value: boolean);
begin
  if value then
    writeln(t, name+'=true')
  else
    writeln(t, name+'=false');
end;

procedure tIniFile.writeFloat(name: string; value: double);
begin
  writeln(t, format('%s=%f', [name, value]));
end;

procedure tIniFile.writeString(name: string; value: string);
begin
  writeln(t, format('%s="%s"', [name, value]));
end;

procedure tIniFile.writeSection(name: string);
begin
  writeln(t, format('[%s]', [name]));
end;

{writes object out to text file}
procedure tIniFile.writeObject(name: string; value: tObject);
var
  i: integer;
  propCount: integer;
  propInfo: pPropInfo;
  section: string;

  pt: pTypeData;
  pi: pTypeInfo;
  pp: pPropList;

begin
  writeSection(name);

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
        else warn(format('unknown property type %s on %s.%s', [propInfo^.propType^.kind, name, propInfo^.name]));
      end;
    end;
  finally
    freeMem(pp);
  end;

  writeln(t);
end;

{----------------------------------------------}

begin
end.
