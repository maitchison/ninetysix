unit list;

interface

uses
  test,
  types,
  debug;

type

  tIntList = record
    {includes startPos, excludes endPos}
    startPos,endPos: int32;
    data: array of int32;
    constructor create(len: integer);
    constructor create(const aData: array of int32);
    function len: int32;
    function slice(aStartPos, aEndPos: int32): tIntList;
    procedure append(x: int32);
    function clone(): tIntList;
    function head: int32;
    function tail: tIntList;

    function toString: string;
    function dumpS: string;
    procedure loadS(s: string);

    procedure clear();

    function getItem(index: int32): int32; inline;
    procedure setItem(index: int32; value: int32); inline;

    property items[index: int32]: int32 read getItem write setItem; default;
    class operator add(a: tIntList;b: int32): tIntList;

  private
    function deref(index: int32): int32;

  end;

  tEnumerator = record
    private
      fIndex: Integer;
      fArray: array of string;
      function GetCurrent: string;
    public
      function moveNext: boolean;
      property current: string read getCurrent;
    end;


  tStringList = record

    startPos,endPos: int32;
    data: array of string;
    constructor create(len: integer); overload;
    constructor create(const data: array of string); overload;
    function len: int32;
    function slice(aStartPos, aEndPos: int32): tStringList;
    procedure append(const x: string); overload;
    procedure append(const x: tStringList); overload;
    function clone(): tStringList;
    procedure clear();
    function head: string;
    function tail: tStringList;
    function contains(const item: string): boolean;

    procedure sort();
    procedure reverse();

    function toString: string;

    function getItem(index: int32): string;
    procedure setItem(index: int32; value: string);

    procedure save(filename: string);
    procedure load(filename: string);

    property items[index: int32]: string read getItem write setItem; default;
    class operator add(a: tStringList;b: string): tStringList;
    class operator add(a: tStringList;b: tStringList): tStringList;

    function getEnumerator(): tEnumerator;

  private
    function deref(index: int32): int32;

  end;


implementation

uses utils;

{----------------------------------------------------}
{ tIntList }
{----------------------------------------------------}

function tIntList.toString: string;
var
  i: int32;
begin
  if len = 0 then exit('[]');
  result := '[';
  for i := startPos to endPos-1 do
    result += intToStr(int32(data[i])) + ',';
  result[length(result)] := ']';
end;

function tIntList.dumpS: string;
begin
  result := self.toString;
end;

procedure tIntList.loadS(s: string);
var
  i: integer;
  start: integer;
  value: integer;
  numberLength: integer;
begin
  self.clear();
  numberLength := 0;
  for i := 1 to length(s) do begin
    case s[i] of
      '[': continue;
      '0'..'9': inc(numberLength);
      ',': begin
        if numberLength = 0 then
          error('Invalid tIntList string');
        value := strToInt(copy(s,i-numberLength,numberLength));
        self.append(value);
        numberLength := 0;
      end;
      ']': begin
        if i <> length(s) then error('Found characters after ]');
        {process final number (if any)}
        if numberLength = 0 then exit;
        value := strToInt(copy(s,i-numberLength,numberLength));
        self.append(value);
        exit;
      end;
      else error('Invalid character "'+s[i]+'" in tIntList string.');
    end;
  end;
  error('String missing ]');
end;

function tIntList.deref(index: int32): int32;
begin
  if index < 0 then index += endPos else index += startPos;
  result := index;
end;

function tIntList.head(): int32;
begin
  result := self[-1];
end;

function tIntList.tail(): tIntList;
begin
  result := slice(0, -1);
end;

class operator tIntList.add(a: tIntList;b: int32): tIntList;
begin
  result := a.clone();
  result.append(b);
end;

function tIntList.getItem(index: int32): int32;
begin
  result := data[deref(index)];
end;

procedure tIntList.setItem(index: int32;value:int32);
begin
  data[deref(index)] := value;
end;

constructor tIntList.create(const aData: array of int32);
var
  i: int32;
begin
  clear();
  endPos := length(aData);
  setLength(data, length(aData));
  for i := 0 to length(aData)-1 do
    self.data[i] := aData[i];
end;

constructor tIntList.create(len: integer);
begin
  clear();
  endPos := len;
  setLength(data, len);
end;

procedure tIntList.clear();
begin
  startPos := 0;
  endPos := 0;
  setlength(data, 0);
end;

function tIntList.len: int32;
begin
  result := endPos-startPos;
end;

procedure tIntList.append(x: int32);
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
{includes startPos, excludes endPos}
function tIntList.slice(aStartPos, aEndPos: int32): tIntList;
begin
  aStartPos := deref(aStartPos);
  aEndPos := deref(aEndPos);
  if (aStartPos < 0) or (aStartPos >= length(data)) then runError(201);
  if (aEndPos < 0) or (aEndPos > length(data)) then runError(201);
  if aStartPos > aEndPos then runError(201);
  result.startPos := aStartPos;
  result.endPos := aEndPos;
  result.data := self.data;
end;

{create a copy of this slice without any slicing}
function tIntList.clone(): tIntList;
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

{----------------------------------------------------}
{ tStringList }
{----------------------------------------------------}

function tStringList.toString: string;
var
  i: int32;
begin
  if len = 0 then exit('[]');
  result := '[';
  for i := startPos to endPos-1 do
    result += '"'+data[i] + '",';
  result[length(result)] := ']';
end;

function tStringList.deref(index: int32): int32;
begin
  if index < 0 then index += endPos else index += startPos;
  result := index;
end;

function tStringList.head(): string;
begin
  result := self[-1];
end;

function tStringList.tail(): tStringList;
begin
  result := slice(0, -1);
end;

class operator tStringList.add(a: tStringList;b: string): tStringList; overload;
begin
  result := a.clone();
  result.append(b);
end;

class operator tStringList.add(a: tStringList;b: tStringList): tStringList; overload;
begin
  result := a.clone();
  result.append(b);
end;

function tStringList.getItem(index: int32): string;
begin
  result := data[deref(index)];
end;

procedure tStringList.setItem(index: int32;value: string);
begin
  data[deref(index)] := value;
end;

constructor tStringList.create(len: int32); overload;
begin
  clear();
  endPos := len;
  setLength(data, len);
end;

constructor tStringList.create(const data: array of string); overload;
var
  s: string;
begin
  clear();
  for s in data do
    append(s);
end;

function tStringList.len: int32;
begin
  result := endPos-startPos;
end;

procedure tStringList.append(const x: string); overload;
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

procedure tStringList.append(const x: tStringList); overload;
var
  s: string;
begin
  for s in x do
    self.append(s);
end;

function tStringList.contains(const item: string): boolean;
var
  s: string;
begin
  for s in self.data do
    if s = item then exit(true);
  exit(false);
end;

{create a sliced copy}
function tStringList.slice(aStartPos, aEndPos: int32): tStringList;
begin
  aStartPos := deref(aStartPos);
  aEndPos := deref(aEndPos);
  if (aStartPos < 0) or (aStartPos >= length(data)) then runError(201);
  if (aEndPos < 0) or (aEndPos > length(data)) then runError(201);
  if aStartPos > aEndPos then runError(201);
  result.startPos := aStartPos;
  result.endPos := aEndPos;
  result.data := self.data;
end;

procedure tStringList.reverse();
var
  i: integer;
  tmp: tStringList;
begin
  tmp := self.clone();
  for i := 0 to len-1 do
    self[i] := tmp[len-i-1]
end;

{sorts elements within this slice}
procedure tStringList.sort();
var
  mid: int32;
  leftHalf,rightHalf: tStringList;
  i,j,k: int32;
  value: string;
  goLeft: boolean;
begin
  {base case}
  if len <= 1 then exit;
  {merge sort, because quicksort is hard}
  mid := len div 2;

  leftHalf := slice(0, mid).clone();
  rightHalf := slice(mid, len).clone();

  leftHalf.sort();
  rightHalf.sort();

  {perform merge}
  i := 0;
  j := 0;
  for k := 0 to len-1 do begin
    if (i >= leftHalf.len) then
      goLeft := false
    else if (j >= rightHalf.len) then
      goLeft := true
    else
      goLeft := (leftHalf[i] < rightHalf[j]);

    if goLeft then begin
      value := leftHalf[i];
      i += 1;
    end else begin
      value := rightHalf[j];
      j += 1;
    end;
    self[k] := value;
  end;

end;

procedure tStringList.clear();
begin
  startPos := 0;
  endPos := 0;
  data := nil;
end;

{create a copy of this slice without any slicing}
function tStringList.clone(): tStringList;
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


function tEnumerator.moveNext: boolean;
begin
  inc(fIndex);
  result := fIndex < length(fArray);
end;

function tEnumerator.getCurrent: string;
begin
  result := fArray[fIndex];
end;

function tStringList.getEnumerator(): tEnumerator;
begin
  result.fArray := data;
  result.fIndex := -1;
end;

procedure tStringList.save(filename: string);
var
  t: text;
  line: string;
begin
  assign(t, filename);
  rewrite(t);
  for line in self do
    writeln(t, line);
  close(t);
end;

procedure tStringList.load(filename: string);
var
  t: text;
  line: string;
begin
  self.clear();
  assign(t, filename);
  reset(t);
  while not eof(t) do begin
    readln(t, line);
    self += line;
  end;
  close(t);
end;


{-----------------------------------------------------}

type
  tListTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tListTest.run();
var
  list, list2: tIntList;
  s1,s2,s3: tStringList;
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

  list := tIntList.create([11,2,32,4,5,6]);
  list2 := tIntList.create([5]);
  list2.loadS(list.dumpS);
  assertEqual(list2.toString, '[11,2,32,4,5,6]');

  list.loads('[]');
  assertEqual(list.len, 0);

  list := tIntList.create([]);
  assertEqual(list.toString, '[]');

  s1 := tStringList.create(['a','b']);
  s2 := tStringList.create(['c','d']);
  s3 := (s1+s2);
  assertEqual(s3.toString, '["a","b","c","d"]');
  assertEqual(s3.slice(0,1).toString, '["a"]');
  assertEqual(s3.slice(1,2).toString, '["b"]');
  assertEqual(s3.slice(2,3).toString, '["c"]');
  assertEqual(s3.slice(3,4).toString, '["d"]');

  s1 := tStringList.create(['101','202','103']);

  s1.sort();
  assertEqual(s1.toString, '["101","103","202"]');

  s1.reverse();
  assertEqual(s1.toString, '["202","103","101"]');

  s1.save('test.txt');
  s2.load('test.txt');
  assertEqual(s2.toString, '["202","103","101"]');

end;

initialization
  tListTest.create('List');
end.
