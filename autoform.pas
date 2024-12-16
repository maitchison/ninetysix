{auto formatter}
program autoform;

{$MODE delphi}

uses
  sysutils,
  utils,
  crt;

var
  TABS_CONVERTED: int32 = 0;
  WS_REMOVED: int32 = 0;

function convertTabs(s: string;tabWidth:integer=2): string;
var
  c: char;
  i: integer;
begin
  result := '';
  for c in s do begin
    if c = #9 then begin
      inc(TABS_CONVERTED);
      for i := 1 to tabWidth do
        result += ' '
    end else
      result += c;
  end;
end;

{for the moments just converts tabs to spaces}
procedure processFile(fileName: string);
var
  sIn, sOut: string;
  tIn,tOut: text;
begin
  TABS_CONVERTED := 0;
  WS_REMOVED := 0;
  assign(tIn, filename);
  reset(tIn);
  assign(tOut, filename+'.tmp');
  rewrite(tOut);
  while not eof(tIn) do begin
    readln(tIn, sIn);
    sOut := convertTabs(sIn);
    WS_REMOVED += length(sOut)-length(trimRight(sOut));
    sOut := trimRight(sOut);
    writeln(tOut, sOut);
  end;
  close(tIn);
  close(tOut);

  if (TABS_CONVERTED = 0) and (WS_REMOVED = 0) then begin
    writeln(pad(filename,20), ' - no changes');
    deleteFile(filename+'.tmp');
    exit;
  end;

  writeln(pad(filename,20),' - removed ', TABS_CONVERTED, ' tabs, and ', WS_REMOVED, ' whitespace characters.');

  deleteFile(filename);
  renameFile(filename+'.tmp', filename);
end;

var
  searchRec: tSearchRec;
  resultCode: integer;

begin
  resultCode := findFirst('./*.pas', faAnyFile, searchRec);
  while resultCode = 0 do begin
    processFile(searchRec.name);
    resultCode := findNext(searchRec);
  end;
  findClose(searchRec);
end.
