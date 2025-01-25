{a tool for FPC that allows for various insight like features}
program look;

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

Title5="Find"
Params5="$CAP_MSG(look $EDNAME $LINE $COL)"
HotKey5=3840

Where 3840 is shift-tab... see

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
  fileSystem;

const
  //todo: get this from the current repo.
  ROOT = 'c:\dev';
  OUT_T = '_filter_.out';
  SIGNATURE: string[10] = 'BI#PIP#OK'+#0;

var
  primary: tStringList;
  secondary: tStringList;

var
  outT: text;
  ref: string;
  token: string;

procedure openFile();
begin
  ioResult;
  info('Open file');

  (*
  assign(outT, OUT_T);
  {$i-} Erase(outT); {$i+}
  ioResult;
  *)

  assign(outT, OUT_T);
  rewrite(outT);
  write(outT, SIGNATURE);
end;

procedure closeFile();
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
  closeFile();
  halt(error);
end;

{search all source files in root folder and report lines containing that string}
procedure globalFind(subStr: string);
var
  files: tStringList;
  lines: tStringList;
  lineNo: int32;
  filePath: string;
  glob: tGlob;
  line: string;
  ignoreFilename: string;
  first: boolean;
  msgString: string;
  filePart, refPart: string;
begin
  glob := tGlob.create();
  ignoreFilename := joinPath(ROOT, 'ignore.ini');
  if fs.exists(ignoreFilename) then
    glob.loadIgnoreFile(ignoreFilename);
  files := glob.getFiles(ROOT, '*.pas');
  for filePath in files do begin
    lines := fs.readText(joinPath(ROOT, filePath));
    lineNo := 0;
    first := true;
    for line in lines do begin
      inc(lineNo);
      if line.contains(subStr, True) then begin
        filePart := #0 + joinPath(ROOT, filePath) + #0;
        refPart := #1 + code(lineNo) + code(1) + line + #0;
        msgString := filePart + refPart;
        if line.startsWith('procedure', true) or line.startsWith('function', true) then
          primary.append(msgString)
        else
          secondary.append(msgString);
        first := false;
      end;
    end;
  end;
  glob.free();
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
  while (col > 0) and ((s[col+1] in tokenChars)) do dec(col);
  inc(col);
  {then get our token}
  while (col < length(s)) and (s[col+1] in tokenChars) do begin
    result += s[col+1];
    inc(col);
  end;
end;

begin

  openFile();

  if paramCount <> 3 then
    fatalMessage(55, 'Error, wrong number of parameters (found '+intToStr(paramCount)+', expected 3)');

  token := getTokenAt(paramStr(1), strToInt(paramStr(2)), strToInt(paramStr(3)));

  if token = '' then
    fatalMessage(91, 'No token found.');

  writeln(token);

  primary.clear();
  secondary.clear();

  globalFind(token);

  {output what I think is probably the link to the definition}

  if primary.len > 0 then begin
    write(outT, primary[primary.len-1]);
  end;

  writeMessage('---------------------------------------');
  writeMessage('Matches lfor "'+token+'"');
  writeMessage('---------------------------------------');

  for ref in primary do write(outT, ref);
  for ref in secondary do write(outT, ref);

  closeFile();

  halt(0);
end.
