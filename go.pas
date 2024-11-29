{Super simple git replacement}
program go;

{$MODE delphi}

{

got commit "Comments"
	Commit all changes

got status
	List changes since last commit.

got revert
	Revert back to previous commit. (but save a stash first)

got loc
	Write line counts per day


Block header

[MD5] [Path] [Date] [Comment]

}

uses
	test,
  debug,
  utils,
  dos;


procedure commit(msg: string);
var
  sourcePath, destinationPath, command, folderName: string;
  t: text;
  time: tMyDateTime;
begin
	sourcePath := getENV('CWD');
  if sourcePath = '' then
  	sourcePath := '.';

  time := now;

  destinationPath := 'got\'+time.YYMMDD('')+'_'+time.HHMMSS('');
  {$I-}
  mkDIR(destinationPath);
  {$I+}
  dos.exec(getEnv('COMSPEC'), '/C copy *.pas '+destinationPath);

  assign(t,destinationPath+'/message.txt');
  rewrite(t);
  writeln(t, msg);
  close(t);

  {it's handy to have a daily folder aswell}
  destinationPath := 'got\'+time.YYMMDD('');
  {$I-}
  mkDIR(destinationPath);
  {$I+}
  dos.exec(getEnv('COMSPEC'), '/C copy *.pas '+destinationPath);

end;

type
	tLineDif = record
  	difType: char;
		line: string;
  end;


{----------------------------------------------------}
{ tSlice }
{----------------------------------------------------}

type
	{A python style sliced array}
	tSlice = record
  	{[startPos..endPos)}
  	startPos,endPos: int32;
    data: tDwords;
    constructor create(const data: array of dword);
    function len: int32;
    function slice(aStartPos, aEndPos: int32): tSlice;
    procedure append(x: dword);
		function clone(): tSlice;
    function head: dWord;
    function tail: tSlice;

    function toString: string;

    function getItem(index: int32): dword;
    procedure setItem(index: int32;value:dword);

  	property items[index: int32]: dWord read getItem write setItem; default;
  	class operator add(a: tSlice;b: dword): tSlice;

  private
    function deref(index: int32): int32;

  end;

function tSlice.toString: string;
var
	i: int32;
begin
	result := '[';
	for i := startPos to endPos-1 do
		result += intToStr(data[i]) + ',';
  result[length(result)] := ']';    	
end;

function tSlice.deref(index: int32): int32;
begin
	if index < 0 then index += endPos else index += startPos;
  result := index;
end;

function tSlice.head: dWord;
begin
	result := self[-1];
end;

function tSlice.tail: tSlice;
begin
	result := slice(0, -1);
end;

class operator tSlice.add(a: tSlice;b: dword): tSlice;
begin
	result := a.clone();
  result.append(b);
end;


function tSlice.getItem(index: int32): dword;
begin

  result := data[deref(index)];
end;

procedure tSlice.setItem(index: int32;value:dWord);
begin
  data[deref(index)] := value;
end;


constructor tSlice.create(const data: array of dword);
var
	i: int32;
begin
	startPos := 0;
  endPos := 0;
	for i := 0 to length(data)-1 do
  	append(data[i]);	
end;

function tSlice.len: int32;
begin
	result := endPos-startPos;
end;

procedure tSlice.append(x: dword);
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
function tSlice.slice(aStartPos, aEndPos: int32): tSlice;
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
function tSlice.clone(): tSlice;
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


{output the longest common subsequence.
e.g. ABCD, ABXXEDA -> ABD

strings are a[a1:a2], b[b1:b2]}
function lcs(a,b: tSlice): tSlice;
var
	option1, option2: tSlice;
begin
	{todo: implement DP cache}
	
  {abcde, e is head, abcd is tail}

  if (a.len = 0) or (b.len = 0) then
  	exit(tSlice.create([]));

	{case 1}
	if (a.head = b.head) then
  	exit(LCS(a.tail,b.tail) + a.head);
  {case 2}
  option1 := LCS(a, b.tail);
  option2 := LCS(a.tail, b);
  if option1.len > option2.len then
  	exit(option1)
  else
  	exit(option2);

end;


{compare files
filename1 is new
filename2 is original
}
procedure fileDif(filename1,filename2: string);
var
	t1,t2: Text;
  line1, line2: string;
  lineNumber: int32;
  eof1,eof2: boolean;
begin
	assign(t1, filename1);
  reset(t1);
  assign(t2, filename2);
  reset(t2);

  lineNumber := 0;
  eof1 := false;
  eof2 := false;

  while not (eof1 and eof2) do begin

  	line1 := '';
    line2 := '';

  	if not EOF(t1) then
    	readln(t1, line1)
    else
    	eof1 := true;

    if not EOF(t2) then
    	readln(t2, line2)
    else
    	eof2 := true;

    inc(lineNumber);

    if (not eof1) and (not eof2) then begin
    	if line1 <> line2 then
      	writeln('-', line1);
        writeln('+', line2);
    end else if (not eof1) then begin
    	writeln('+', line1);
    end else if (not eof2) then begin
    	writeln('-', line2);
    end;

  end;

  close(t1);
  close(t2);
        	
end;	

procedure testSlice();
var
	slice: tSlice;
begin
	slice := tSlice.create([1,2,3,4,5,6]);
  assertEqual(slice.len, 6);
  assertEqual(slice[0], 1);
  assertEqual(slice[-1], 6);
  assertEqual(slice[-2], 5);

  slice := slice.slice(2,3);
  assertEqual(slice.len, 1);
  assertEqual(slice[0], 3);

  slice := slice + 22;
  assertEqual(slice.len, 2);
  assertEqual(slice[-1], 22);
  assertEqual(slice[-2], 3);

  slice := slice.clone();
  assertEqual(slice.len, 2);
  assertEqual(slice[-1], 22);
  assertEqual(slice[-2], 3);
  assertEqual(length(slice.data), 2);
	
end;

procedure testLCS();
var
	data1: array of dword = [1,2,3,4,5];
  data2: array of dword = [3,7,5,1];
  s1,s2: tSlice;
  sln: tSlice;
begin
	
  s1 := tSlice.create(data1);
  s2 := tSlice.create(data2);
  sln := LCS(s1, s1);
  assertEqual(sln.toString, '[1,2,3,4,5]');

  sln := LCS(s1, s2);
  assertEqual(sln.toString, '[3,5]');
	
end;


procedure runTests();
begin		
	testSlice();
	testLCS();
end;

var
	msg: string;

{
	todo: status
  todo: diff
  todo: stats
}


begin
	runTests;
  write('Message:');
  readln(msg);
  commit(msg);
{  fileDif('./lc96.pas', './got/20241129/lc96.pas');}
end.




