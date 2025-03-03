unit uResLib;

{$mode delphi}

interface

uses
  debug,
  test,
  fileSystem,
  sound,
  utils,
  la96,
  lc96;

type
  tResourceInfo = record
    srcFile: string;
    dstFile: string;
    modifiedTime: int64;
    procedure clear();
    function isEmpty: boolean;
  end;

  tResourceLibrary = class

    resources: array of tResourceInfo;

    procedure addResource(res: tResourceInfo);

    constructor Create(); overload;
    constructor Create(filename: string); overload;
    constructor CreateOrLoad(filename: string); overload;
    destructor Destroy; override;

    function  len(): integer;

    procedure serialize(fileName: string);
    procedure deserialize(fileName: string);

    function  findResourceIndex(dstFile: string): integer;
    procedure updateResource(res: tResourceInfo);
    function  needsUpdate(dstFile: string): boolean;

  end;

{-----------------------------------------------}

implementation

{-----------------------------------------------}

procedure tResourceInfo.clear();
begin
  srcFile := '';
  dstFile := '';
  modifiedTime := 0;
end;

function tResourceInfo.isEmpty(): boolean;
begin
  result := dstFile = '';
end;
{-----------------------------------------------}

constructor tResourceLibrary.Create(); overload;
begin
  inherited create();
end;

function tResourceLibrary.len(): integer;
begin
  result := length(resources);
end;

constructor tResourceLibrary.Create(fileName: string); overload;
begin
  create();
  deserialize(fileName);
end;

constructor tResourceLibrary.createOrLoad(fileName: string);
begin
  if fs.exists(fileName) then
    create(fileName)
  else
    create();
end;

destructor tResourceLibrary.destroy();
begin
  inherited destroy();
end;

procedure tResourceLibrary.addResource(res: tResourceInfo);
begin
  setLength(resources, length(resources)+1);
  resources[len-1] := res;
end;

{returns index of resource, or -1 of not found}
function tResourceLibrary.findResourceIndex(dstFile: string): integer;
var
  i: int32;
begin
  for i := 0 to len-1 do
    if resources[i].dstFile = dstFile then exit(i);
  exit(-1);
end;

{updates or adds resource}
procedure tResourceLibrary.updateResource(res: tResourceInfo);
var
  id: int32;
begin
  id := findResourceIndex(res.dstFile);
  if id < 0 then
    addResource(res)
  else
    resources[id] := res;
end;

{returns true if resource source file changed, or if no entry exists}
function tResourceLibrary.needsUpdate(dstFile: string): boolean;
var
  id: int32;
begin
  result := false;
  {does it exit}
  id := findResourceIndex(dstFile);
  if id < 0 then
    exit(true);
  {has it changed}
  if resources[id].modifiedTime <> fs.getModified(resources[id].srcFile) then
    exit(true);
end;

procedure tResourceLibrary.serialize(fileName: string);
var
  t: text;
  ioError: word;
  res: tResourceInfo;
  i: integer;
begin
  assign(t, filename);
  {$I-}
  rewrite(t);
  {$I+}
  ioError := ioResult;
  if ioError <> 0 then fatal('Error writing '+fileName+' (error:'+intToStr(ioError)+')');

  {todo: update to new inifile unit}
  try
    for i := 0 to len-1 do begin
      res := resources[i];
      writeln(t, '[resource]');
      writeln(t, 'srcFile=',res.srcFile);
      writeln(t, 'dstFile=',res.dstFile);
      writeln(t, 'modifiedTime=',res.modifiedTime);
      writeln(t);
    end;
  finally
    close(t);
  end;

end;

procedure tResourceLibrary.deserialize(fileName: string);
var
  t: text;
  s,k,v: ansistring;
  ioError: word;
  res: tResourceInfo;
begin
  assign(t, filename);
  {$I-}
  reset(t);
  {$I+}
  ioError := ioResult;
  if ioError <> 0 then fatal('Error reading '+fileName+' (error:'+intToStr(ioError)+')');

  res.clear();

  try

    while not eof(t) do begin
      readln(t, s);
      s := trim(s);
      if s = '[resource]' then begin
        if not res.isEmpty then addResource(res);
        res.clear();  {add previous resource}
        continue;
      end;
      split(s, '=', k, v);
      if k = 'srcFile' then begin
        res.srcFile := v;
      end else if k = 'dstFile' then begin
        res.dstFile := v;
      end else if k = 'modifiedTime' then begin
        res.modifiedTime := strToInt(v);
      end else begin
        {ignore all others}
      end;
    end;

    {write final}
    if not res.isEmpty then addResource(res);

  finally
    close(t);
  end;

end;

{-------------------------------------------------}

type
  tResourceLibraryTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tResourceLibraryTest.run();
var
  rl: tResourceLibrary;
  res: tResourceInfo;
begin
  rl := tResourceLibrary.Create();
  res.srcFile := 'a';
  res.dstFile := 'b';
  res.modifiedTime := 123;
  rl.addResource(res);
  res.srcFile := 'x';
  res.dstFile := 'y';
  res.modifiedTime := 321;
  rl.addResource(res);
  rl.serialize('_test.ini');
  rl.free();

  rl := tResourceLibrary.Create('_test.ini');
  assertEqual(rl.len, 2);
  res := rl.resources[0];
  assertEqual(res.srcFile, 'a');
  assertEqual(res.dstFile, 'b');
  assertEqual(res.modifiedTime, 123);
  assertEqual(rl.findResourceIndex('b'), 0);
  assertEqual(rl.findResourceIndex('c'), -1);
  rl.free();
end;

{--------------------------------------------------}

initialization
  tResourceLibraryTest.create('ResourceLibray');
end.
