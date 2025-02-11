unit resource;

interface

type
  tResource = class
    tag: string;
  end;

  tResourceLoadProc = function(filename: string): tResource;

function getResourceLoader(aExtension: string): tResourceLoadProc;
procedure registerResourceLoader(aExtension: string; aProc: tResourceLoadProc);

implementation

uses
  utils;

type
  tRegistryEntry = record
    extension: string;
    proc: tResourceLoadProc;
  end;

var
  resourceLoaderRegistery: array of tRegistryEntry;

{--------------------------------------------------------}

{returns imageLoader for extension, or nil if none assigned.}
function getResourceLoader(aExtension: string): tResourceLoadProc;
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

procedure registerResourceLoader(aExtension: string; aProc: tResourceLoadProc);
begin
  setLength(resourceLoaderRegistery, length(resourceLoaderRegistery)+1);
  with resourceLoaderRegistery[length(resourceLoaderRegistery)-1] do begin
    extension := toLowerCase(aExtension);
    proc := aProc;
  end;
end;


begin
end.
