unit resLib;

{todo: this needs a big update, or perhaps to just be removed.
 airtime uses this... but no one else
 also tResource overlaps with the resources unit}

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
  end;

  tResourceLibrary = class

    numResources: word;

    resource: array[0..63] of tResourceInfo;

    procedure addResource(res: tResourceInfo);

    constructor Create(); overload;
    constructor Create(filename: string); overload;
    constructor CreateOrLoad(filename: string); overload;
    destructor Destroy; override;

    procedure serialize(fileName: string);
    procedure deserialize(fileName: string);

    function findResourceIndex(dstFile: string): integer;
    procedure updateResource(res: tResourceInfo);

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

{-----------------------------------------------}

constructor tResourceLibrary.Create(); overload;
begin
  inherited create();
  numResources := 0;
  fillchar(resource, sizeOf(resource), 0);
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
  if numResources = length(resource) then
    fatal('Too many resources, limit is '+intToStr(length(resource)));
  resource[numResources] := res;
  inc(numResources);
end;

{returns index of resource, or -1 of not found}
function tResourceLibrary.findResourceIndex(dstFile: string): integer;
var
  i: int32;
begin
  for i := 0 to numResources-1 do
    if resource[i].dstFile = dstFile then exit(i);
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
    resource[id] := res;
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
    for i := 0 to numResources-1 do begin
      res := resource[i];
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

  try

    numResources := 0;

    while not eof(t) do begin
      readln(t, s);
      s := trim(s);
      if s = '[resource]' then begin
        if numResources > 0 then
          resource[numResources-1] := res;
        res.clear();
        inc(numResources);
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
    if numResources > 0 then
      resource[numResources-1] := res;

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
  assertEqual(rl.numResources, 2);
  res := rl.resource[0];
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
