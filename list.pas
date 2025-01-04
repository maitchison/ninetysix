unit list;

interface

uses
  test,
  debug,
  utils;

type
  {A python style sliced array of strings}
  tList = record
    {[startPos..endPos)}
    startPos,endPos: int32;
    data: tDwords;
    constructor create(const data: array of dword);
    function len: int32;
    function slice(aStartPos, aEndPos: int32): tList;
    procedure append(x: dword);
    function clone(): tList;
    function head: dWord;
    function tail: tList;

    function toString: string;

    function getItem(index: int32): dword;
    procedure setItem(index: int32;value:dword);

    property items[index: int32]: dWord read getItem write setItem; default;
    class operator add(a: tList;b: dword): tList;

  private
    function deref(index: int32): int32;

  end;


implementation

{----------------------------------------------------}
{ tList }
{----------------------------------------------------}

function tList.toString: string;
var
  i: int32;
begin
  result := '[';
  for i := startPos to endPos-1 do
    result += intToStr(data[i]) + ',';
  result[length(result)] := ']';
end;

function tList.deref(index: int32): int32;
begin
  if index < 0 then index += endPos else index += startPos;
  result := index;
end;

function tList.head: dWord;
begin
  result := self[-1];
end;

function tList.tail: tList;
begin
  result := slice(0, -1);
end;

class operator tList.add(a: tList;b: dword): tList;
begin
  result := a.clone();
  result.append(b);
end;


function tList.getItem(index: int32): dword;
begin
  result := data[deref(index)];
end;

procedure tList.setItem(index: int32;value:dWord);
begin
  data[deref(index)] := value;
end;


constructor tList.create(const data: array of dword);
var
  i: int32;
begin
  startPos := 0;
  endPos := 0;
  for i := 0 to length(data)-1 do
    append(data[i]);
end;

function tList.len: int32;
begin
  result := endPos-startPos;
end;

procedure tList.append(x: dword);
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
function tList.slice(aStartPos, aEndPos: int32): tList;
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
function tList.clone(): tList;
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
  list: tList;
begin
  list := tList.create([1,2,3,4,5,6]);
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

end;

initialization
  tListTest.create('List');
end.
