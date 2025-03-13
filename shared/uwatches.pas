{handles watch variables}
unit uWatches;

interface

uses
  uDebug,
  uUtils,
  uVertex;

type
  tWatch = class
    tag: string;
    value: string;
    lastUpdated: double;
    constructor Create(aTag: string);
    function toString(): string; override;
  end;

procedure Watch(aTag: string; aValue: string); overload;
procedure Watch(aTag: string; aValue: single); overload;
procedure Watch(aTag: string; aValue: V3D); overload;

var
  WATCHES: array of tWatch;
  ENABLE_WATCHES: boolean = false;

implementation

function getWatch(aTag: string): tWatch;
var
  i: integer;
begin
  for i := 0 to length(WATCHES)-1 do
    if WATCHES[i].tag = aTag then exit(WATCHES[i]);
  exit(nil);
end;

procedure addWatch(watch: tWatch);
begin
  if length(WATCHES) > 1000 then
    fatal('Too many watches');
  setLength(WATCHES, length(WATCHES)+1);
  WATCHES[length(WATCHES)-1] := watch;
end;

procedure Watch(aTag, aValue: string); overload;
var
  watch: tWatch;
begin
  if not ENABLE_WATCHES then exit;
  watch := getWatch(aTag);
  if not assigned(watch) then begin
    watch := tWatch.Create(aTag);
    addWatch(watch);
  end;
  watch.value := aValue;
  watch.lastUpdated := getSec;
end;

procedure Watch(aTag: string; aValue: single); overload;
begin
  if not ENABLE_WATCHES then exit;
  Watch(aTag, format('%f', [aValue]));
end;

procedure Watch(aTag: string; aValue: V3D); overload;
begin
  if not ENABLE_WATCHES then exit;
  Watch(aTag, aValue.toString);
end;

{------------------------------------------------------}

constructor tWatch.Create(aTag: string);
begin
  inherited Create();
  tag := aTag;
  value := '';
  lastUpdated := 0;
end;

function tWatch.toString(): string;
begin
  result := tag + ': ' + value;
end;

{------------------------------------------------------}

initialization
  WATCHES := nil;
end.
