{a tool for FPC that allows for various insight like features}
program look;

{$MODE Delphi}

{
Todo
  [ ] match complete word only
  [ ] implement a 'does this file have this word' bloom filter.

Improved IDE Support

- What we want is alt enter to follow link. There's a few ways to do this

1. Build this into the IDE (required symbols to be built I guess)
2. Modify tools to make this work (I think I'll do this).

Here's how we modify the tools.

1. Remove the line that outputs the tool name and params to messages.
  (block containing line 92 of fpmtools.inc).
2. Add special "!follow" to follow previously added link
3. Add special "!next" to increment currently selected message
4. Add special "!clear" to clear messages
5. Perhap find a way to get alt-enter to work.

Config settings

Title5="Refs"
Params5="$CAP_MSG(look refs $EDNAME $LINE $COL)"
HotKey5=3840

Title6="Find"
Params6="$CAP_MSG(look find $PROMPT(Text))"
HotKey6=8454

Where
  3840=shift-tab
  8454=ctrl-f

see
  fv/src/drivers.inc for alternatives.

Future tools
- [ ] Find - this one
- [ ] Jump - auto jump to definition
- [ ] Peek - show code in message window, useful for doc strings.
- [ ] Rename - for bulk renamining of variables

}

uses
  test,
  debug,
  crt,
  list,
  utils,
  glob,
  timer,
  fileSystem;

const
  //todo: get this from the current repo.
  ROOT = 'c:\dev';
  OUT_T = '_filter_.out';
  SIGNATURE: string[10] = 'BI#PIP#OK'+#0;
  VERSION = 'v0.3';

var
  mainList: tStringList;
  auxList: tStringList;
  files: tStringList;

var
  outT: text;
  ref: string;
  token: string;
  inputHook: procedure(s: string);

type
  tSearchOptions = record
    detectDeclarations: boolean;  // put declarations in auxList
    wholeWord: boolean;           // is does not match with fish
    caseSensitive: boolean;       // if true search is case sensitive.
    procedure init();
  end;

{defaults to a case insensitive standard search}
procedure tSearchOptions.init();
begin
  detectDeclarations := false;
  wholeWord := false;
  caseSensitive := false;
end;

procedure deleteMessageFile();
begin
  ioResult;
  info('Delete file');

  assign(outT, OUT_T);
  {$i-} Erase(outT); {$i+}
  ioResult;
end;

procedure openMessageFile();
begin
  ioResult;
  info('Open file');

  assign(outT, OUT_T);
  rewrite(outT);
  write(outT, SIGNATURE);
end;

procedure closeMessageFile();
begin
  info('Close file');
  write(outT, #127);
  close(outT);
end;

function code(x: word): string;
begin
  result := '';
  setLength(result, 2);
  result[1] := chr(x mod 256);
  result[2] := chr(x div 256);
end;

procedure writeMessage(s: string);
begin
  note(s);
  write(outT, #0 + '' + #0);
  write(outT, #1 + code(0) + code(0) + s + #0);
end;

procedure fatalMessage(error: byte;s: string);
begin
  warning('Error: '+s);
  writeMessage(s);
  closeMessageFile();
  halt(error);
end;

function getWholeWords(s: string): tStringList;
var
  i,n: integer;
begin
  result.clear();
  i := 1;
  while nextWholeWord(s, i, n) do begin
    result.append(copy(s, i, n));
    i += n;
  end;
end;

function containsWholeWord(s, substr: string): boolean;
var
  i,n: integer;
begin
  {s.contains is much faster, so use that to filter out strings
   that can not match}
  if not s.contains(substr) then exit(false);
  result := false;
  i := 1;
  while nextWholeWord(s, i, n) do begin
    if (n = length(subStr)) and subStringMatch(s, i, substr) then exit(true);
    i += n;
  end;
end;

{message format for FPC}
function messageRef(filename: string;lineNo: integer;msg: string): string;
var
  filePart, refPart: string;
begin
  filePart := #0 + filename + #0;
  refPart := #1 + code(lineNo) + code(1) + msg + #0;
  result := filePart + refPart;
end;

function getExtensionScore(ext: string): integer;
begin
  ext := ext.toLower();
  result := 0;
  if ext = 'pas' then result := 3;
  if ext = 'inc' then result := 2;
  if ext = 'bat' then result := 1;
  if ext = 'txt' then result := 1;
  if ext = 'log' then result := 1;
end;

{search all source files in root folder and report lines containing that string
if detectDeclarations is true then lines that looks like function or procedure
declarations will be put into an auxilary list.
}
procedure globalFind(subStr: string;so: tSearchOptions);
var
  lines: tStringList;
  lineNo: int32;
  filePath: string;
  line,searchLine: string;
  ignoreFilename: string;
  first: boolean;
  msgString: string;
  containsStr: boolean;
  extension: string;
  score: integer;
begin

  subStr := subStr.toLower();

  note('----------------------------------------');
  note(format('Performing search for "%s"', [subStr]));
  note('----------------------------------------');

  for filePath in files do begin
    extension := extractExtension(filePath).toLower();
    if getExtensionScore(extension) < 2 then continue;
    lines := fs.readText(joinPath(ROOT, filePath));
    lineNo := 0;
    first := true;
    for line in lines do begin
      inc(lineNo);
      if length(line) < length(subStr) then continue;
      if so.caseSensitive then
        searchLine := line
      else
        searchLine := line.toLower();
      if so.wholeWord then
        containsStr := containsWholeWord(searchLine, subStr)
      else
        containsStr := searchLine.contains(subStr);
      if containsStr then begin
        {todo: use a function to handle encoding of reference}
        msgString := messageRef(joinPath(ROOT, filePath), lineNo, line);
        if so.detectDeclarations then begin
          if line.startsWith('procedure', true) or line.startsWith('function', true) then
            auxList.append(msgString)
          else
            mainList.append(msgString);
          first := false;
        end else
          mainList.append(msgString);
        // maybe this slows things down too much?
        note(line);
      end;
    end;
  end;
  note('<done>');
end;

{returns the word at given location. Might not work with tabs
lines and col both start at 1
returns empty string if not valid
}
function getTokenAt(filename: string; line, col: word): string;
var
  lines: tStringList;
  s: string;
  tokenChars: set of char;
begin
  result := '';
  dec(line);
  dec(col);
  if not fs.exists(filename) then exit();
  lines := fs.readText(filename);
  if not (line < lines.len) then exit();
  s := lines[line];
  if col > length(s) then exit();

  tokenChars := ['a'..'z', 'A'..'Z', '0'..'9'];

  {backtrack to just before token}
  while (col > 0) and (s[col] in tokenChars) do dec(col);
  {then get our token}
  while (col < length(s)) and (s[col+1] in tokenChars) do begin
    result += s[col+1];
    inc(col);
  end;
end;

{-----------------------------------------------------}

procedure updateFilenameMatches(token: string);
var
  filename, extension: string;
begin
  mainList.clear();
  auxList.clear();
  for filename in files do begin
    extension := extractExtension(filename).toLower();
    if not filename.contains(token, true) then continue;
    if getExtensionScore(extension) >= 3 then
      mainList.append(filename)
    else
      auxList.append(filename);
  end;
end;

procedure processRefs();
var
  so: tSearchOptions;
begin
  if paramCount <> 4 then
    fatalMessage(55, 'Error, wrong number of parameters (found '+intToStr(paramCount)+', expected 4)');

  token := getTokenAt(paramStr(2), strToInt(paramStr(3)), strToInt(paramStr(4)));

  if token = '' then
    fatalMessage(91, 'No token found.');

  mainList.clear();
  auxList.clear();

  startTimer('search');
  so.init();
  so.detectDeclarations := true;
  so.wholeWord := true;
  globalFind(token, so);
  stopTimer('search');

  {output what I think is probably the link to the definition}
  if auxList.len > 0 then begin
    write(outT, auxList[auxList.len-1]);
  end;

  writeMessage('---------------------------------------');
  writeMessage(format('[%s] Matches for "%s" (in %.2fs)', [VERSION, token, getTimer('search').elapsed]));
  writeMessage('---------------------------------------');

  for ref in auxList do write(outT, ref);
  for ref in mainList do write(outT, ref);

end;

procedure doSearchFeedback(s: string);
var
  oldX,oldY,oldAttr: integer;
  filename: string;
  counter: integer;

  procedure displayLine(s: string);
  begin
    textAttr := White;
    counter += 1;
    if counter > 10 then exit;
    gotoXY(10, oldY+counter);
    write(pad(s, 40));
  end;

begin
  oldX := crt.whereX;
  oldY := crt.whereY;
  oldAttr := crt.textAttr;

  updateFilenameMatches(s);

  textAttr := White;
  gotoXY(10, oldY+1);
  counter := 0;
  for filename in mainList do
    displayLine(filename);
  for filename in auxList do
    displayLine(filename);
  while counter < 10 do
    displayLine('');

  crt.gotoXY(oldX, oldY);
  crt.textAttr := oldAttr;

end;

function readInput(): string;
var
  ch: char;
begin
  result := '';
  if assigned(inputHook) then inputHook(result);
  repeat
    ch := readkey;
    if ch = #27 then exit('');
    if ch = #13 then exit;
    if ch = #8 then begin
      if result = '' then continue;
      result := copy(result, 1, length(result)-1);
      if assigned(inputHook) then inputHook(result);
      write(#8,' ',#8);
      continue;
    end;
    result += ch;
    if assigned(inputHook) then inputHook(result);
    write(ch);
  until false;
end;

procedure processFind();
var
  so: tSearchOptions;
  atX,atY: integer;
begin
  {todo: search current file first}
  if paramCount = 1 then begin
    textAttr := LightGray*16 + White;
    atX := 10; atY := 30;
    gotoxy(atX, atY);
    write('                                                               ');
    gotoxy(atX, atY+1);
    write(' Enter search text:                                            ');
    gotoxy(atX, atY+2);
    write('                                                               ');
    gotoxy(atX+20, atY+1);
    token := readInput();
    if token = '' then begin
      {this way message box will not get focus (I hope!)}
      closeMessageFile();
      deleteMessageFile();
      halt(0);
    end;
  end else if paramCount = 2 then begin
    token := paramStr(2);
  end else
    fatalMessage(55, 'Error, wrong number of parameters (found '+intToStr(paramCount)+', expected 2)');

  mainList.clear();
  auxList.clear();

  startTimer('search');
  so.init;
  globalFind(token, so);
  stopTimer('search');

  writeMessage('---------------------------------------');
  writeMessage(format('[%s] Matches for "%s" (in %.2fs)', [VERSION, token, getTimer('search').elapsed]));
  writeMessage('---------------------------------------');

  for ref in mainList do write(outT, ref);
  for ref in auxList do write(outT, ref);
end;

procedure getFileNames();
var
  glob: tGlob;
  filename, extension: string;
  ignoreFilename: string;
begin
  startTimer('scan');
  glob := tGlob.create();
  ignoreFilename := joinPath(ROOT, 'ignore.ini');
  if fs.exists(ignoreFilename) then
    glob.loadIgnoreFile(ignoreFilename);
  files.clear();
  for filename in glob.getFiles(ROOT, '*.*') do begin
    extension := extractExtension(filename).toLower();
    if getExtensionScore(extension) <= 0 then continue;
    files.append(filename);
  end;
  glob.free();
  stopTimer('scan');
  note('Scan took %fs', [getTimer('scan').elapsed]);
end;

procedure processOpen();
var
  so: tSearchOptions;
  atX,atY: integer;
  filename, extension: string;
  priority: integer;

begin
  inputHook := doSearchFeedback;
  if paramCount = 1 then begin
    textAttr := LightGray*16 + White;
    atX := 10; atY := 30;
    gotoxy(atX, atY);
    write('                                                               ');
    gotoxy(atX, atY+1);
    write(' File:                                            ');
    gotoxy(atX, atY+2);
    write('                                                               ');
    gotoxy(atX+20, atY+1);
    token := readInput();
    if token = '' then begin
      {this way message box will not get focus (I hope!)}
      closeMessageFile();
      deleteMessageFile();
      halt(0);
    end;
  end else if paramCount = 2 then begin
    token := paramStr(2);
  end else
    fatalMessage(55, 'Error, wrong number of parameters (found '+intToStr(paramCount)+', expected 2)');

  updateFilenameMatches(token);
  for filename in mainList do
    write(outT, messageRef(filename, 1, extractPath(filename)));
  for filename in auxList do
    write(outT, messageRef(filename, 1, extractPath(filename)));
end;

{-----------------------------------------------------}

var
  mode: string;

begin

  inputHook := nil;
  openMessageFile();

  if paramCount < 1 then fatalMessage(55, 'Usage: look.exe refs [filename] [line] [col]');

  getFileNames();

  mode := paramStr(1).toLower();
  if mode = 'refs' then
    processRefs()
  else if mode = 'find' then
    processFind()
  else if mode = 'open' then
    processOpen()
  else
    fatalMessage(66, 'Invalid mode '+mode);

  closeMessageFile();

  halt(0);
end.
