{A simple hash map}
unit uHashMap;

{$MODE delphi}

interface

uses
  uTest,
  uDebug,
  uUtils,
  uTypes,
  uList;

type

  tValueOrPointer = record
    case byte of
      0: (value: dword);
      1: (ptr: pDword);
    end;

  {a simple int list. needed as freepascal dynamic arrays crash if
   resized too many times...

   A short list will take 8 bytes of memory for 0 or 1 items, with
   fast local reading. For lists longer it allocates a buffer
   which has some overhead

   }
  tShortList = record
  private
    fLen: dword;
    fData: tValueOrPointer;
  public
    function  len: int32;
    procedure init();
    procedure done();
    procedure append(x: dword);
    procedure makeSpace(n: integer);
    function  getItem(index: int32): dword;
    procedure setItem(index: int32; x: dword);
    property  items[index: int32]: dword read getItem write setItem; default;
  end;

  {records multiple instantances of keys.}
  tHashMap = class
    maxBinSize: integer;
    matches: array[0..65535] of tShortList;
    constructor create(aMaxBinSize: integer=32);
    destructor destroy(); override;
    procedure addReference(key: word; pos: dword);
    procedure trim(minPos: dword);
  end;

  {records a single instances of a key}
  tHashMapX = class
    match: array[0..65535] of word;
    constructor create();
    procedure addReference(key: word; pos: word);
  end;

  tSparseMap = class
    {sparse word -> word map}
    keys: array[0..255] of array of word;
    values: array[0..255] of array of word;
    constructor Create();
    function largestBin: integer;
    function usedBins: integer;
    function getValue(key: word): word;
    procedure setValue(key, value: word);
  end;

  tStringToStringMap = class
    {maps from string to string}
    {todo: dynamically resize hash table }
    keys, values: tStringList;
    bins: array[0..255] of tIntList;
    constructor Create;
    destructor Destroy; override;

  private
    function lookupKey(aKey: string; out i: int32; out j: int32): boolean;
  public

    procedure load(filename: string);
    procedure save(filename: string; maxEntries: integer=-1);

    procedure clear();
    procedure setValue(aKey, aValue: string);
    function  hasKey(aKey: string): boolean;
    function  getValue(aKey: string): string;
    function  len: int32;
  end;

function hashW2B(x:word): byte; register; inline; assembler;
function hashD2W(key: dword): word; register; inline; assembler;

implementation

uses
  uInfo;

{----------------------------------------}

function hashW2B(x:word): byte; register; assembler;
asm
  {ax=x}
  rol al, 4
  xor al, ah
  {output = al}
  end;

function hashD2W(key: dword): word; register; assembler;
asm
  push bx
  {eax is key}
  rol al, 3
  rol ax, 5
  rol eax, 13
  rol ax, 2
  rol al, 5

  mov bx, ax
  shr eax, 16
  xor ax, bx
  pop bx
  {ax is result}
  end;

function hashStr(s: string): dword;
var
  strPointer: pointer;
  strLen: int32;
  hash: dword;
begin
  if length(s) = 0 then exit(0);
  strPointer := @s[1];
  strLen := length(s);
  asm
    pushad

    mov esi, [strPointer]
    mov ecx, strLen

    mov eax, 0

  @LOOP:

    ror eax, 3
    xor al, [esi]
    inc esi

    loop @LOOP

    mov [hash], eax

    popad

  end;

  result := hash;

end;

{----------------------------------------}

constructor tHashMap.create(aMaxBinSize: integer=32);
begin
  inherited create();
  fillchar(matches, sizeof(matches), 0);
  maxBinSize := aMaxBinSize;
end;

destructor tHashMap.destroy();
var
  i: integer;
begin
  for i := 0 to 65536-1 do
    matches[i].done;
  fillchar(matches, sizeof(matches), 0);
  inherited destroy();
end;

procedure tHashMap.addReference(key: word; pos: dword);
begin
  if (maxBinSize > 0) and (matches[key].len >= maxBinSize) then
    exit;
  matches[key].append(pos);
end;

{Remove old references}
procedure tHashMap.trim(minPos: dword);
var
  i,j: int32;
  newMatches: tShortList;
begin
  for i := 0 to 65536-1 do begin
    newMatches.init();
    for j := 0 to matches[i].len-1 do
      if matches[i][j] >= minPos then
        newMatches.append(matches[i][j]);
    matches[i].done;
    matches[i] := newMatches;
  end;
end;

{----------------------------------------}

constructor tHashMapX.create();
begin
  fillchar(match, sizeof(match), 0);
end;

procedure tHashMapX.addReference(key: word; pos: word);
begin
  {note: I think we do better if we don't overwrite}
  match[key] := pos;
end;


{----------------------------------------}

constructor tSparseMap.Create();
begin
  filldword(keys, sizeof(keys) shr 2, 0);
  filldword(values, sizeof(values) shr 2, 0);
end;

{returns the number of entries in the largest bin}
function tSparseMap.largestBin(): integer;
var
  i: integer;
  maxItems: integer;
begin
  maxItems := -1;
  for i := 0 to 255 do
    maxItems := max(maxItems, length(keys[i]));
  result := maxItems;
end;

{returns the number of entries in the largest bin}
function tSparseMap.usedBins(): integer;
var
  i: integer;
  bins: integer;
begin
  result := 0;
  for i := 0 to 255 do
    if length(keys[i]) > 0 then
      inc(result);
end;


function tSparseMap.getValue(key: word): word;
var
  hash: byte;
  i: integer;
begin
  hash := hashW2B(key);
  if not assigned(keys[hash]) then exit(0);
  for i := 0 to length(keys[hash])-1 do
    if keys[hash][i] = key then exit(values[hash][i]);
  exit(0);
end;

procedure tSparseMap.setValue(key, value: word);
var
  hash: byte;
  i: integer;

begin

  {compression should be 2.14x}

  {
  Note: all pairs is 64k, so we expect... ah yes this is the problem...
  For 64k bytes, we really do have 64k entries...
   maybe

  }

  {
  xor hash
  53.9s mixing is 36+128 -> 40+256
  46s 13->34
  }

  hash := hashW2B(key);
  if not assigned(keys[hash]) then begin
    setLength(keys[hash], 1);
    setLength(values[hash], 1);
    keys[hash][0] := key;
    values[hash][0] := value;
    exit;
  end;

  for i := 0 to length(keys[hash])-1 do begin
    if keys[hash][i] = key then begin
      values[hash][i] := value;
      exit
    end;
  end;

  i := length(keys[hash]);

  setLength(keys[hash], i+1);
  setLength(values[hash], i+1);
  keys[hash][i] := key;
  values[hash][i] := value;

end;

{-------------------------------------------------}
{ tStringToStringMap }
{-------------------------------------------------}

constructor tStringToStringMap.Create();
begin
  inherited create;
  clear();
end;

destructor tStringToStringMap.Destroy();
begin
  clear();
  inherited Destroy;
end;

procedure tStringToStringMap.clear();
var
  i: integer;
begin
  for i := 0 to 255 do
    bins[i].clear();
end;

{finds key within hash table, returns if found or not.
 If found i,j will be such that key=keys[i][j], otherwise
 i will be the bucket where key should live and j is undefined}
function tStringToStringMap.lookupKey(aKey: string; out i: int32; out j: int32): boolean;
var
  jj, k: integer;
begin
  i := hashW2B(hashD2W(hashStr(aKey)));
  for jj := 0 to bins[i].len-1 do begin
    j := jj; // can't use j as a loop varaible.
    k := bins[i][j];
    if keys[k] = aKey then
      exit(true);
  end;
  exit(false);
end;

procedure tStringToStringMap.load(filename: string);
var
  t: text;
  line: string;
  key, value: string;
begin
  assign(t, filename);
  reset(t);
  clear();
  while not eof(t) do begin
    readln(t, line);
    split(line, '=', key, value);
    setValue(key, value);
  end;
  close(t);
end;

procedure tStringToStringMap.save(filename: string; maxEntries: integer=-1);
var
  t: text;
  i, j, k: int32;
  line: string;
  startK: integer;
begin
  assign(t, filename);
  rewrite(t);
  if maxEntries >= 0 then
    startK := max(self.len - maxEntries, 0)
  else
    startK := 0;
  for k := startK to self.len-1 do begin
    if keys[k].contains('=') then fatal('Serialized keys can not contain "="');
    if values[k].contains('=') then fatal('Serialized values can not contain "="');
    line := keys[k]+'='+values[k];
    writeln(t, line);
  end;
  close(t);
end;

procedure tStringToStringMap.setValue(aKey: string; aValue: string);
var
  i,j,k: integer;
begin
  if not lookupKey(aKey, i, j) then begin
    keys.append(aKey);
    values.append(aValue);
    k := self.len-1;
    bins[i].append(k);
  end else begin
    k := bins[i][j];
    values[k] := aValue;
  end;
end;

function tStringToStringMap.hasKey(aKey: string): boolean;
var
  i,j: integer;
begin
  result := lookupKey(aKey, i, j);
end;

function tStringToStringMap.getValue(aKey: string): string;
var
  i,j,k: integer;
begin
  if not lookupKey(aKey, i, j) then
    fatal(format('No such key %s', [aKey]))
  else begin
    k := bins[i][j];
    result := values[k];
  end;
end;

function tStringToStringMap.len: int32;
begin
  result := values.len;
end;

{-------------------------------------------------}

type
  tHashMapTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tHashMapTest.run();
var
  map: tSparseMap;
  stringMap: tStringToStringMap;
  hm: tHashMap;
  i: int32;
begin

  map := tSparseMap.create();
  assertEqual(map.getValue(97), 0);
  map.setValue(97, 1);
  assertEqual(map.getValue(97), 1);
  map.setValue(1, 5);
  map.setValue(1, map.getValue(1) + 5);
  assertEqual(map.getvalue(1), 10);
  map.free;

  {check hash atleast works}
  hashStr('hello');
  hashStr('fish');
  hashStr('');

  stringMap := tStringToStringMap.create();
  assert(not stringMap.hasKey('fish'));
  stringMap.setValue('fish', 'bad');
  assert(stringMap.hasKey('fish'));
  assertEqual(stringMap.getValue('fish'), 'bad');
  stringMap.setValue('fish', 'good');
  assertEqual(stringMap.getValue('fish'), 'good');
  stringMap.free;

  {make sure hashmap is robust}
  hm := tHashMap.create();
  for i := 0 to 64*1024 do begin
    hm.addReference(random(65536), random(256*65536));
  end;
  hm.free;

end;

{-------------------------------------------------}

procedure tShortList.init();
begin
  self.fLen := 0;
  self.fData.value := 0;
end;

function tShortList.len: int32; inline;
begin
  result := fLen;
end;

procedure tShortList.done();
begin
  if len > 1 then begin
    freemem(self.fData.ptr);
    self.fData.ptr := nil;
  end;
  self.fLen := 0;
  self.fData.value := 0;
end;

{make room for atleast n elements}
procedure tShortList.makeSpace(n: integer);
var
  newLen: int32;
  requestedSpace: int32;
  allocatedSpace: int32;
begin
  requestedSpace := roundUpToPowerOfTwo(n);
  allocatedSpace := roundUpToPowerOfTwo(len);
  if requestedSpace < allocatedSpace then
    reallocMem(self.fData.ptr, requestedSpace*4);
end;

procedure tShortList.append(x: dword);
begin
  if fLen = 0 then begin
    fLen := 1;
    self.fData.value := x;
  end else begin
    makeSpace(fLen+1);
    self[fLen-1] := x;
  end;
end;

function tShortList.getItem(index: int32): dword; inline;
begin
  //if index >= len then fatal('Bounds error on small list');
  //if index < 0 then fatal('Bounds error on small list');
  if fLen = 1 then
    result := self.fData.value
  else
    result := self.fData.ptr[index];
end;

procedure tShortList.setItem(index: int32; x: dword); inline;
begin
  //if index >= fLen then fatal('Bounds error on small list');
  //if index < 0 then fatal('Bounds error on small list');
  if fLen = 1 then
    self.fData.value := x
  else
    self.fData.ptr[index] := x;
end;

{-------------------------------------------------}

initialization
  tHashMapTest.create('HashMap');
end.
