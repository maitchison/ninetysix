unit resource;

interface

uses
  debug;

type
  tResource = class
    tag: string;
  end;

  tResourceLoaderFilter = function(path: string): boolean;

  tLazyResource = class(tResource)
    path: string;
    constructor Create(aPath: string);
  end;

  tResourceLibrary = class
  protected
    lazy: boolean;
    resources: array of tResource;
    function getByTag(aTag: string): tResource;
    function findByTag(aTag: string): integer;
  public
    function hasResource(aTag: string): boolean;
    function addResource(filename: string): tResource; virtual;
    procedure loadFromFolder(root: string; pattern: string; filter: tResourceLoaderFilter = nil);
    constructor Create(aLazy: boolean=false);
    destructor destroy(); override;
    property items[tag: string]: tResource read getByTag; default;
  end;

  tResourceLoaderProc = function(filename: string): tResource;

function loadResource(filename: string): tResource;
function getResourceLoader(aExtension: string): tResourceLoaderProc;
procedure registerResourceLoader(aExtension: string; aProc: tResourceLoaderProc);

implementation

uses
  fileSystem,
  utils;

type
  tRegistryEntry = record
    extension: string;
    proc: tResourceLoaderProc;
  end;

var
  resourceLoaderRegistery: array of tRegistryEntry;

{--------------------------------------------------------}

constructor tLazyResource.Create(aPath: string);
begin
  path := aPath;
end;

{--------------------------------------------------------}

constructor tResourceLibrary.create(aLazy: boolean=false);
begin
  inherited create();
  lazy := aLazy;
  setLength(resources, 0);
end;

destructor tResourceLibrary.destroy;
var
  res: tResource;
begin
  for res in resources do res.free;
  setLength(resources, 0);
  inherited destroy();
end;

{-----------}

{loads and adds resource to library, returns a reference to new resource}
function tResourceLibrary.addResource(filename: string): tResource;
var
  res: tResource;
begin
  if lazy then
    res := tLazyResource.Create(filename)
  else
    res := loadResource(filename);

  setLength(resources, length(resources)+1);
  resources[length(resources)-1] := res;
  res.tag := removeExtension(extractFilename(filename)).toLower();
  result := res;
end;

procedure tResourceLibrary.loadFromFolder(root: string; pattern: string; filter: tResourceLoaderFilter = nil);
var
  filename: string;
  tag: string;
  path: string;
begin
  for filename in fs.listFiles(joinPath(root, '\'+pattern)) do begin
    path := joinPath(root, filename);
    if assigned(filter) and (not filter(path)) then continue;
    addResource(path);
  end;
end;

function tResourceLibrary.getByTag(aTag: string): tResource;
var
  id: integer;
  srcPath: string;
begin
  id := findByTag(aTag);
  if id < 0 then raise ValueError('No resource named "%s"', [aTag]);
  if (resources[id] is tLazyResource) then begin
    srcPath := tLazyResource(resources[id]).path;
    resources[id].free;
    resources[id] := loadResource(srcPath);
  end;
  result := resources[id];
end;

function tResourceLibrary.findByTag(aTag: string): integer;
var
  i: integer;
begin
  result := -1;
  for i := 0 to length(resources)-1 do
    if resources[i].tag = aTag then exit(i);
end;

function tResourceLibrary.hasResource(aTag: string): boolean;
begin
  result := findByTag(aTag) >= 0;
end;

{--------------------------------------------------------}

function loadResource(filename: string): tResource;
var
  loader: tResourceLoaderProc;
begin
  loader := getResourceLoader(extractExtension(filename));
  if assigned(loader) then
    result := loader(filename)
  else
    raise ValueError('No loader avalaible for file "'+filename+'"');
end;

{returns imageLoader for extension, or nil if none assigned.}
function getResourceLoader(aExtension: string): tResourceLoaderProc;
var
  i: integer;
begin
  aExtension := aExtension.toLower();
  for i := 0 to length(resourceLoaderRegistery)-1 do
    with resourceLoaderRegistery[i] do
      if aExtension = extension then
        exit(proc);
  exit(nil);
end;

procedure registerResourceLoader(aExtension: string; aProc: tResourceLoaderProc);
begin
  setLength(resourceLoaderRegistery, length(resourceLoaderRegistery)+1);
  with resourceLoaderRegistery[length(resourceLoaderRegistery)-1] do begin
    extension := toLowerCase(aExtension);
    proc := aProc;
  end;
end;


begin
end.
