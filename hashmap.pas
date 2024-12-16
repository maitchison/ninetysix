{A simple hash map}
unit hashmap;

{$MODE delphi}

interface

uses
  utils,
  test;

type

  {records multiple instantances of keys.}
  tHashMap = class
    maxBinSize: integer;
    matches: array[0..65535] of array of dword;
    constructor create(aMaxBinSize: integer=32);
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

function hashW2B(x:word): byte; register; inline; assembler;
function hashD2W(key: dword): word; register; inline; assembler;

implementation

{----------------------------------------}

function hashW2B(x:word): byte; register; inline; assembler;
asm
  {ax=x}
  rol al, 4
  xor al, ah
  {output = al}
  end;

function hashD2W(key: dword): word; register; inline; assembler;
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
  fillchar(matches, sizeof(matches), 0);
  maxBinSize := aMaxBinSize;
end;

procedure tHashMap.addReference(key: word; pos: dword);
begin
  if (maxBinSize > 0) and (length(matches[key]) >= maxBinSize) then
    exit;
  SetLength(Matches[key], Length(Matches[Key])+1);
  Matches[key][Length(Matches[Key])-1] := pos;
end;

{Remove old references}
procedure tHashMap.trim(minPos: dword);
var
  i,j: int32;
  newMatches: array of dword;
begin
  for i := 0 to 65536-1 do begin
    newMatches := nil;
    for j := 0 to length(matches[i])-1 do begin
      if matches[i][j] >= minPos then begin
        setLength(newMatches, length(newMatches)+1);
        newMatches[length(newMatches)-1] := matches[i][j];
      end;
    end;
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

procedure runTests();
var
  map: tSparseMap;
begin

  map := tSparseMap.create();
  assertEqual(map.getValue(97), 0);
  map.setValue(97, 1);
  assertEqual(map.getValue(97), 1);
  map.setValue(1, 5);
  map.setValue(1, map.getValue(1) + 5);
  assertEqual(map.getvalue(1), 10);

  {check hash atleast works}
  hashStr('hello');
  hashStr('fish');
  hashStr('');

end;


begin
  runTests();
end.
