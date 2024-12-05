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
  diff,
  debug,
  utils,
  hashMap,
  dos;

{copies all '.pas' files from current path to destination folder.
if destination folder exists it is renamed, and then a new folder is
created. If back exists, it is removed.}

procedure safeCopy(destinationPath: string);
begin
  dos.exec(getEnv('COMSPEC'), '/C rmdir '+destinationPath+'_tmp /s');
  dos.exec(getEnv('COMSPEC'), '/C move '+destinationPath+' '+destinationPath+'_tmp');
  mkDIR(destinationPath);
  dos.exec(getEnv('COMSPEC'), '/C copy *.pas '+destinationPath);
  dos.exec(getEnv('COMSPEC'), '/C rmdir '+destinationPath+'_tmp /s');
end;


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

  destinationPath := '$rep\'+time.YYMMDD('')+'_'+time.HHMMSS('');
  {$I-}
  mkDIR(destinationPath);
  {$I+}
  dos.exec(getEnv('COMSPEC'), '/C copy *.pas '+destinationPath);

  assign(t,destinationPath+'/message.txt');
  rewrite(t);
  writeln(t, msg);
  close(t);

  {it's handy to have a daily folder aswell}
  safeCopy('$rep\'+time.YYMMDD(''));

  {and head...}
  safeCopy('$rep\head');

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

var
  newLines, oldLines: tLines;

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


{-----------------------------------------------------}

var
	LINES_SINCE_PAGE: byte = 0;

function textRows: byte;
begin
(*
	asm
  	pushad
  	mov ax, $0300
    mov bh, 0
    int $10
    inc dl
    mov [result], dl
    popad
  	end;
  *)
  result := mem[$0040:$0084]+1;
end;
	

procedure output(s: string);
begin
	{todo: detect line wrap}
	write(s);
end;

{outputs a line of text, with support for paging}
procedure outputLn(s: string);
begin
	writeln(s);
	inc(LINES_SINCE_PAGE);
  if LINES_SINCE_PAGE+2 >= textRows() then begin
  	textAttr := 15;
  	write('---- Continue -----');
    case readkey of
    	#27: halt;
      'q': halt;
    end;
    LINES_SINCE_PAGE := 0;
    writeln();
  end;  	
end;

{-----------------------------------------------------}

function readFile(filename: string): tLines;
var
	t: text;
  line: string;
  lines: tLines;
begin
	assign(t, filename);
  reset(t);
  lines := nil;
  while not EOF(t) do begin
    readln(t, line);
    setLength(lines, length(lines)+1);
    lines[length(lines)-1] := line;
  end;
  close(t);
  result := lines;
end;

{output the longest common subsequence.}
procedure printDif(newLines,oldLines: tLines;matching: tSlice);
var
	i,j,k,z: int32;
  map: tHashMap;
  hash: word;
  oldS,newS: tSlice;
  new,old,cur: string;
  linesRemoved: int32;
  linesAdded: int32;
  isFirst: boolean;
  netLines: int32;
  plus: string;
  clock: int32;

var
	importantLines: array[0..1024-1] of boolean;

procedure markImportant(pos: int32);
var
	i: int32;
begin
	
	for i := pos-2 to pos+2 do
  	if (i >= 0) and (i < 1024) then
    	importantLines[i] := true;
end;

function fix(s: string): string;
var
	i: integer;
  c: byte;
begin
	result := '';
  for i := 1 to length(s) do begin
  	c := ord(s[i]);
    if c = 9 then
    	result += '  '
    else if (c < 32) or (c >= 128) then
    	result += '#('+intToStr(c)+')'
    else
    	result += chr(c);
  end;

  if length(result) > 60 then begin
  	setLength(result,60);
	  result += '...';
  end;
end;

begin

	{which lines in old file should be shown for context}
	fillchar(importantLines, sizeof(importantLines), false);

  oldS := tSlice.create([]);
  for i := 1 to length(oldLines) do
  	oldS.append(i);

  newS := tSlice.create([]);
  for i := 1 to length(newLines) do
  	newS.append(i);

  {fast path for identical files}

  if matching.len = max(oldS.len, newS.len) then begin
  	textAttr := 15;
  	outputLn('Files are identical.');
    exit;
  end;

  {------------------------------------}
  { first pass to get important lines }

	i := 0;
  j := 0;
  k := 0;
  clock := 0;

  while k < matching.len do begin
  	inc(clock);
    if clock > 1000 then exit;
    cur := oldLines[matching[k]-1];
    while (newLines[i] = cur) and (oldLines[j] = cur) do begin
      inc(i);
	    inc(j);
	    inc(k);
    	if k < matching.len then begin      		
	    	cur := oldLines[matching[k]-1]
      end	else begin
    		cur := '';
        break;
      end;
    end;

    while (j < length(oldLines)) and (oldLines[j] <> cur) do begin
      markImportant(j);
      inc(j);
    end;

    while (i < length(newLines)) and (newLines[i] <> cur) do begin
      markImportant(j);
      inc(i);
    end;
  end;


  {------------------------------------}

  i := 0;
  j := 0;
  k := 0;
  clock := 0;

  linesAdded := 0;
  linesRemoved := 0;

  outputLn('');

  while k < matching.len do begin
  	inc(clock);
    if clock > 1000 then exit;

    cur := oldLines[matching[k]-1];
    isFirst := true;	

	  textAttr := 7; // light gray

    while (newLines[i] = cur) and (oldLines[j] = cur) do begin
    	if isFirst then begin
        isFirst := false;
      end;

    	if (j > 0) and (not importantLines[j-1]) and (importantLines[j]) then begin
      	{chunk header}
      	textAttr := 8;
        for z := 1 to 14 do
	      	output(' ');
        for z := 1 to 55 do
	      	output(chr(196));
        outputLn('');
      	textAttr := 7; //cyan}
      end;
      if importantLines[j] then
	    	outputLn(intToStr(j, 4, '0')+'     '+fix(cur));

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
    	outputLn(intToStr(j, 4, '0')+' [-] '+fix(oldLines[j]));
      inc(j);
      inc(linesRemoved);
    end;

    while (i < length(newLines)) and (newLines[i] <> cur) do begin
    	textAttr := 10; // light green
    	outputLn('     [+] '+fix(newLines[i]));
      inc(i);
      inc(linesAdded);
    end;

  end;

  netLines := linesAdded-linesRemoved;
  if netLines > 0 then plus := '+' else plus := '';

  outputLn('');
  textAttr := 15; // white
  outputLn('Added '+intToStr(linesAdded)+' lines.');
  outputLn('Removed '+intToStr(linesRemoved)+' lines.');
  outputLn('Net '+plus+intToStr(netLines)+' lines.');
  outputLn('Total lines changed '+intToStr(linesAdded+linesRemoved)+' lines.');

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

procedure runTests();
begin		
	testSlice();
end;

var
	msg: string;

procedure benchmark();
var
	startTime, elapsed: double;
  merge: tSlice;
  sln: tLineRefs;
  new,old: tLines;
  diff: tDiff;
begin
  {
  	sln seems to be +140 / -13 = total of 153 lines
    464 lines match
  	start: 14.2
    no writeln: 12.4
    sln from backtrace: 1.6
  }	
  new := readFile('sample_new.txt');
  old := readFile('sample_old.txt');

  diff := tDiff.create();

  startTime := getSec;
  sln := diff.run(new, old);
  elapsed := getSec-startTime;

  merge := tSlice.create([]);
  for i := 0 to length(sln)-1 do
  	merge.append(sln[i]);
  writeln(merge.toString);

  {printDif(new, old, merge);}

  writeln('final score -> ',diff.scores[(length(new)*length(old))-1]);

  writeln(format('Took %f seconds', [elapsed]));
  writeln(merge.len);
  writeln('new        ',length(new));
  writeln('old        ',length(old));
  writeln('NM         ',length(new)*length(old));
end;


procedure diff(filename: string);
var
  merge: tSlice;
  sln: tLineRefs;
  new,old: tLines;
  diff: tDiff;
begin
	{for the moment just show diff on go.pas}
  new := readFile(filename);
  old := readFile('$rep/head/'+filename);

  diff := tDiff.create();

  sln := diff.run(new, old);
  merge := tSlice.create([]);
  for i := 0 to length(sln)-1 do
  	merge.append(sln[i]);
  printDif(new, old, merge);
end;

procedure promptAndCommit();
begin
	write('Message:');
	readln(msg);
	commit(msg);
end;

{todo: change to string list}
function listFiles(path: string): tLines;
var
	sr: SearchRec;
begin
	result := nil;
	findFirst(path, AnyFile, sr);
  while DosError = 0 do begin
  	if sr.size > 0 then begin
	    setLength(result, length(result)+1);
	    result[length(result)-1] := toLowerCase(sr.name);
    end;
    findNext(sr);
  end;
  findClose(sr);
end;

function listContains(l: tLines;item: string): boolean;
var
	s: string;
begin
	for s in l do
  	if s = item then exit(true);
  exit(false);
end;

(*
function filesMatch(file1, file2: string): boolean;
var
	a,b: tLines;
  i: int32;
begin
	a := readLines(file1);
	b := readLines(file2);
	if length(a) <> length(b) exit(false);
	for i := 0 to length(a)-1 do
		if a[i] <> b[i] then
 			exit(false);
	exit(true);
end;
*)

function wasModified(file1, file2: string): boolean;
var
	t1,t2: longint;
  f1,f2: file;
begin
	t1 := 0;
  t2 := 0;
	assign(f1, file1);
  assign(f2, file2);
  reset(f1);
  reset(f2);
  getFTime(f1, t1);
  getFTime(f2, t2);
  close(f1);
  close(f2);
	result := t1 <> t2;
end;

{show all changed / added / deleted files}
procedure status();
var
	workingSpaceFiles: tLines;
  headFiles: tLines;
  filename: string;
  added,removed,changed: int32;
begin
	writeln();
	workingSpaceFiles := listFiles('*.pas');
	headFiles := listFiles('$rep\head\*.pas');
  added := 0;
  removed := 0;
  changed := 0;

  for filename in workingSpaceFiles do begin
		if not listContains(headFiles, filename) then begin
    	textattr := 10;
    	writeln('[+] added ', filename);
      inc(added);
    end else begin
    	if wasModified(filename, '$rep\head\'+filename) then begin
      	textattr := 15;
      	writeln('[~] modified ', filename);
        inc(changed);
      end;
    end;
  end;

  for filename in headFiles do begin
		if not listContains(workingSpaceFiles, filename) then begin
    	textattr := 12;
    	writeln('removed ', filename);
      inc(removed);
		end;
  end;

  textattr := 15;
  if (added = 0) and (removed = 0) and (changed = 0) then
  	writeln('No changes.');
  writeln();
end;

{show all diff on all modified files}
procedure diffOnModified();
var
	workingSpaceFiles: tLines;
  headFiles: tLines;
  filename: string;
  changed: int32;
begin
	workingSpaceFiles := listFiles('*.pas');
	headFiles := listFiles('$rep\head\*.pas');
  changed := 0;

  outputLn('');

  for filename in workingSpaceFiles do begin
		if not listContains(headFiles, filename) then begin
    end else begin
    	if wasModified(filename, '$rep\head\'+filename) then begin
      	outputLn('----------------------------------------');
      	outputLn('Modifications to '+filename);
        diff(filename);
      end;
    end;
  end;

  textattr := 15;
end;


{--------------------------------------------------}

var
	command: string;

begin

	runTests();

  if (paramCount = 0) then
		command := 'status'
  else
	  command := paramSTR(1);

  if command = 'diff' then
		diffOnModified()
  else if command = 'commit' then
  	promptAndCommit()
  else if command = 'benchmark' then
  	benchmark()
  else if command = 'status' then
  	status()
  else
  	Error('Invalid command "'+command+'"');

end.
