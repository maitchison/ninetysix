{simple string map}
unit uStringMap;

{
For the moment this is a linear scan... which is fine for small maps
}

interface

uses
  test,
  debug,
  sysTypes;

type
  tStringMap<T> = class
  protected
    keys: tStrings;
    values: array of T;
    function getByKey(aKey: string): T;
    procedure setByKey(aKey: string; aValue: T);
  public
    property items[key: string]: T read getByKey write setByKey; default;
    function contains(aKey: string): boolean;
  end;

implementation

function tStringMap<T>.getByKey(aKey: string): T;
var
  i: integer;
begin
  for i := 0 to length(keys)-1 do
    if keys[i] = aKey then exit(values[i]);
  raise ValueError('Key not found '+aKey);
end;

procedure tStringMap<T>.setByKey(aKey: string; aValue: T);
var
  i: integer;
begin
  for i := 0 to length(keys)-1 do begin
    if (keys[i] = aKey) then begin
      values[i] := aValue;
      exit;
    end;
  end;
  keys.append(aKey);
  setLength(values, length(values)+1);
  values[length(values)-1] := aValue;
end;

function tStringMap<T>.contains(aKey: string): boolean;
var
  i: integer;
begin
  for i := 0 to length(keys)-1 do
    if (keys[i] = aKey) then exit(true);
  exit(false);
end;

begin
end.
