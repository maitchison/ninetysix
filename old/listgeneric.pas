unit list;

{generics seem to crash FPC when compiling, so I'll just do it by hand.}

interface

uses
  test,
  types,
  debug;

type
  {A python style sliced list}
  tList<T> = record
    {[startPos..endPos)}
    startPos,endPos: int32;
    data: array of T;
    constructor create(const data: array of T);
    function len: int32;
    function slice(aStartPos, aEndPos: int32): tList<T>;
    procedure append(x: T);
    function clone(): tList<T>;
    function head: T;
    function tail: tList<T>;

    function toString: string;

    function getItem(index: int32): T;
    procedure setItem(index: int32; value:T);

    property items[index: int32]: T read getItem write setItem; default;
    class operator add(a: tList<T>;b: T): tList<T>;

  private
    function deref(index: int32): int32;

  end;

  tIntList = tList<int32>;
  tStringList = tList<string>;

implementation

uses utils;

{----------------------------------------------------}
{ tList }
{----------------------------------------------------}

function tList<T>.toString: string;
var
  i: int32;
begin
  result := '[';
  for i := startPos to endPos-1 do begin
    if TypeInfo(T) = TypeInfo(int32) then
      result += intToStr(int32(data[i])) + ','
    else if TypeInfo(T) = TypeInfo(string) then
      result += string(data[i]) + ','
    else
      result += '?,'
  end;
  result[length(result)] := ']';
end;

function tList<T>.deref(index: int32): int32;
begin
  if index < 0 then index += endPos else index += startPos;
  result := index;
end;

function tList<T>.head(): T;
begin
  result := self[-1];
end;

function tList<T>.tail(): tList<T>;
begin
  result := slice(0, -1);
end;

class operator tList<T>.add(a: tList<T>;b: T): tList<T>;
begin
  result := a.clone();
  result.append(b);
end;


function tList<T>.getItem(index: int32): T;
begin
  result := data[deref(index)];
end;

procedure tList<T>.setItem(index: int32;value:T);
begin
  data[deref(index)] := value;
end;

constructor tList<T>.create(const data: array of T);
var
  i: int32;
begin
  startPos := 0;
  endPos := 0;
  for i := 0 to length(data)-1 do
    append(data[i]);
end;

function tList<T>.len: int32;
begin
  result := endPos-startPos;
end;

procedure tList<T>.append(x: T);
begin
  {note: this is not a good way to handle append, maybe a different
    'stringbuilder' like class}
  if (startPos = 0) and (endPos = length(self.data)) then begin
    setLength(self.data, length(self.data)+1);
    data[length(self.data)-1] := x;
    inc(endPos);
  end else begin
    {cannot append to non-trivial slice}
    error(format('Tried to append to a non-trival slice. (%d, %d) length:%d ',[startPos, endPos, len]));
  end;

end;

{create a sliced copy}
function tList<T>.slice(aStartPos, aEndPos: int32): tList<T>;
begin
  aStartPos := deref(aStartPos);
  aEndPos := deref(aEndPos);
  if (aStartPos < 0) or (aStartPos >= length(data)) then runError(201);
  if (aEndPos < 0) or (aEndPos >= length(data)) then runError(201);
  if aStartPos > aEndPos then runError(201);
  result.startPos := aStartPos;
  result.endPos := aEndPos;
  result.data := self.data;
end;

{create a copy of this slice without any slicing}
function tList<T>.clone(): tList<T>;
var
  i: int32;
begin
  result.startPos := 0;
  result.endPos := len;
  result.data := nil;
  setLength(result.data, len);
  for i := 0 to len-1 do
    result.data[i] := self.data[startPos+i];
end;

{-----------------------------------------------------}

type
  tListTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tListTest.run();
var
  list: tIntList;
  s1,s2: tStringList;
begin
  list := tIntList.create([1,2,3,4,5,6]);
  assertEqual(list.len, 6);
  assertEqual(list[0], 1);
  assertEqual(list[-1], 6);
  assertEqual(list[-2], 5);

  list := list.slice(2,3);
  assertEqual(list.len, 1);
  assertEqual(list[0], 3);

  list := list + 22;
  assertEqual(list.len, 2);
  assertEqual(list[-1], 22);
  assertEqual(list[-2], 3);

  list := list.clone();
  assertEqual(list.len, 2);
  assertEqual(list[-1], 22);
  assertEqual(list[-2], 3);
  assertEqual(length(list.data), 2);

  s1 := list.create(['a','b']);
  s2 := list.create(['c','d']);
  assertEqual((s1+s2).toString, 'a,b,c,d');

end;

initialization
  tListTest.create('List');
end.
