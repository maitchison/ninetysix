{Super simple git replacement}
program go;

{todo: support ansi strings I guess...
	well atleast make sure long strings work, or perhaps just ignore?
}

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
  crt, {remove this?}
  debug,
  utils,
  hashMap,
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

  tLines = array of string;

var
	{todo: use my sparse map}
	CACHE: array[0..1024-1,0..1024-1] of tDWords;

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

{todo: remove global}
var
  newLines, oldLines: array of string;

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


type
	tCompareFunction = function(a,b: dword): boolean;

function cmpStandard(a, b: dword): boolean;
begin
	result := a = b;
end;

function cmpLines(a,b: dword): boolean;
begin
	result := newLines[a-1] = oldLines[b-1];
end;


{
	a is new
  b is old (ref)
}
{strings are a[a1:a2], b[b1:b2]}
function lcs(a,b: tSlice;cmp: tCompareFunction): tSlice;
var
	option1, option2: tSlice;
begin

  if (@cmp = @cmpLines) then
  	if assigned(CACHE[a.len, b.len]) then begin
    	result.startPos := 0;
      result.data := CACHE[a.len, b.len];
      result.endPos := length(result.data);
    	exit;
    end;
	
  {abcde, e is head, abcd is tail}

  if (a.len = 0) or (b.len = 0) then
  	result := tSlice.create([])
  else if cmp(a.head, b.head) then
  	result := LCS(a.tail,b.tail, cmp) + b.head
  else begin
	  option1 := LCS(a, b.tail, cmp);
	  option2 := LCS(a.tail, b, cmp);
	  if option1.len > option2.len then
  		result := option1
	  else
  		result := option2;
  end;

  if (@cmp = @cmpLines) then
	  CACHE[a.len, b.len] := result.data;

end;

function readFile(filename: string): tLines;
var
	t: text;
  line: string;
  lines: array of string;
begin
	assign(t, filename);
  reset(t);
  while not EOF(t) do begin
    readln(t, line);
    setLength(lines, length(lines)+1);
    lines[length(lines)-1] := line;
  end;
  close(t);
  result := lines;
end;

{output the longest common subsequence.
e.g. ABCD <- ABXXEDA -> ABD

This should then be written as

A
B
-X
-X
-E
+C
D
-A

Expect matching to be [1,2,6]
}

{compare files
filename1 is new
filename2 is original
}
procedure fileDif(newFileName,oldFilename: string);
var
	i,j,k: int32;
  map: tHashMap;
  hash: word;
  oldS,newS: tSlice;
  matching: tSlice;
  new,old,cur: string;
  linesRemoved: int32;
  linesAdded: int32;
  isFirst: boolean;
  netLines: int32;
  plus: string;

begin

	oldLines := readFile(oldFilename);
  newLines := readFile(newFilename);

  oldS := tSlice.create([]);
  for i := 1 to length(oldLines) do
  	oldS.append(i);

  newS := tSlice.create([]);
  for i := 1 to length(newLines) do
  	newS.append(i);

  matching := LCS(newS, oldS, cmpLines);

  {fast path for identical files}

  if matching.len = oldS.len then begin
  	writeln('Files are identical.');
    exit;
  end;

  i := 0;
  j := 0;
  k := 0;

  linesAdded := 0;
  linesRemoved := 0;

  writeln();

  while k < matching.len do begin

    cur := oldLines[matching[k]-1];
    isFirst := true;	

    while (newLines[i] = cur) and (oldLines[j] = cur) do begin
    	if isFirst then begin
	    	textAttr := 7; // light gray
      	writeln('-------');
        isFirst := false;
      end;
    	{writeln('   ',cur);}
      inc(i);
	    inc(j);
	    inc(k);
    	if k < matching.len then begin      		
	    	cur := oldLines[matching[k]-1]
      end	else begin
  	  	{this will cause trailing blank lines to be ignored.}
    		cur := '';
        break;
      end;
    end;

    while (j < length(oldLines)) and (oldLines[j] <> cur) do begin
    	textAttr := 12; // light red
    	writeln('[-]', oldLines[j]);
      inc(j);
      inc(linesRemoved);
    end;

    while (i < length(newLines)) and (newLines[i] <> cur) do begin
    	textAttr := 10; // light green
    	writeln('[+]', newLines[i]);
      inc(i);
      inc(linesAdded);
    end;

  end;

  netLines := linesAdded-linesRemoved;
  if netLines > 0 then plus := '+' else plus := '';

  writeln();
  textAttr := 15; // white
  writeln('Added ', linesAdded, ' lines.');
  writeln('Removed ', linesRemoved, ' lines.');
  writeln('Net ', plus, netLines,' lines.');

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
  sln := LCS(s1, s1, cmpStandard);
  assertEqual(sln.toString, '[1,2,3,4,5]');

  sln := LCS(s1, s2, cmpStandard);
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

	fillchar(CACHE, sizeof(CACHE), 0);

	runTests;
  write('Message:');
  readln(msg);
  commit(msg);
  {fileDif('b.txt', 'a.txt');}
  {fileDif('go.pas', 'got/20241129/go.pas');}
end.




