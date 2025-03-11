{unit to handle byte pair encoding}
unit uBpe;

interface

uses
  types;

function bpeEncode(bytes:tBytes;useByte: byte; out a,b: int32;minFreq:integer=3): tBytes;
function doBPE(data: tDwords; maxReplacements: integer=256; out dictionary: tDwords): tDwords;

implementation

{---------------------------------------------------------------}
{ Byte Pair Encoding}
{---------------------------------------------------------------}

function bpeFindMostFrequentPair_REF(bytes:tBytes;out freq:word): word;
var
  i, value: word;
  allPairsFreq: array[0..255,0..255] of word;
begin
  fillword(allPairsFreq, sizeof(allPairsFreq) div 2, 0);
  result := 0;
  freq := 0;
  for i := 0 to length(bytes)-2 do begin
    inc(allPairsFreq[bytes[i], bytes[i+1]]);
    value := allPairsFreq[bytes[i], bytes[i+1]];
    if value > freq then begin
      freq := value;
      result := pWord(@bytes[i])^;
    end;
  end;
end;

function bpeFindMostFrequentPair(bytes:tBytes;out freq:word): word;
var
  allPairsFreq: array[0..255,0..255] of word;
  pair, bestFreq: word;

  bytesLength:word;
  bytesPtr: pointer;
  allPairsPtr: pointer;

  t1,t2: word;

begin

  fillword(allPairsFreq, sizeof(allPairsFreq) div 2, 0);

  bytesLength := length(bytes);
  bytesPtr := @bytes[0];
  allPairsPtr := @allPairsFreq;

  asm
    pushad
    {
    ax = bestFreq
    bx = pair
    cx = loop counter
    dx = count(pair)
    }
    xor eax, eax
    xor ecx, ecx
    mov cx, [bytesLength]
    dec ecx
    xor edx, edx
    mov edi, [bytesPtr]
    mov esi, [allPairsPtr]
    xor ebx, ebx

    {note: think we could do this 4 pairs at a time using PCMPGTW}

  @LOOP:

    mov bx, [edi]        //bx <- pair
    mov dx, [esi+ebx*2]    //dx <- count(pair)
    inc dx
    mov [esi+ebx*2], dx

    cmp dx, ax
    jbe @SKIP

    mov ax, dx
    mov [pair], bx

  @SKIP:

    inc edi
    dec ecx
    jnz @LOOP

    {
    ax is maxFreq
    [pair] is pair
    }
    mov [bestFreq], ax

    popad

  end;

  result := pair;
  freq := bestFreq;
end;

function bpeReplacePair(bytes: tBytes;pair:word;useByte:byte): tBytes;
var
  srcPtr, dstPtr, srcStopPtr: pointer;
  srcLen: dword;
  actualLength: dword;
begin
  result := nil;
  srcLen := length(bytes);
  setLength(result, srcLen);
  srcPtr := @bytes[0];
  srcStopPtr := @bytes[srcLen-2]; {stop at penaltimate byte}
  dstPtr := @result[0];
  asm
    pushad

    mov esi, [srcPtr]
    mov edi, [dstPtr]
    mov ecx, [srcLen]
    mov bx, [pair]
    mov dl, [useByte]

    {
    ax=src pair
    bx=pair
    dl=useByte
    }

  @LOOP:

    {could do a resonablly fast MMX check if any words match, i.e. check
    4 at a time, then if one matches do them the slow way... would be fast
    for spare matches}
    {could also do a scan for the first byte I guess? but then we can't
     copy as we go}

    mov ax, [esi]
    cmp ax, bx
    jne @SKIPCODE

  @WRITECODE:
    mov al, dl
    inc esi
    dec ecx

  @SKIPCODE:

    mov [edi], al
    inc edi
    inc esi
    dec ecx

    cmp ecx, 1

    ja @LOOP

    // process final byte
    cmp ecx, 0
    je @SKIPSETLASTBYTE

    {we stop one byte early to avoid reading too far,
     so now output the last byte. If we matched the last word
     esi will be one more than the stopPointer}
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi

  @SKIPSETLASTBYTE:

    mov eax, edi
    sub eax, [dstPtr]
    mov [actualLength], eax

    popad
  end;
  setLength(result, actualLength);
end;

function bpeFirstFreeByte(data: tBytes): int16; pascal;
var
  used: array[0..255] of byte;
  dataPtr: pointer;
  usedPtr: pointer;
  value: int16;
  len: dword;
begin
  dataPtr := @data[0];
  usedPtr := @used;
  value := 101;
  len := length(data);
  asm
    pushad

  {---- clear buffer ----------}


    mov edi, [usedPtr]
    mov eax, 0
    mov ecx, 256/4
    cld
    rep stosd

{---- loop through bytes ------}

    mov ecx, [len]
    xor edx, edx
    xor eax, eax
    mov esi, [dataPtr]
    mov edi, [usedPtr]

  @LOOP:

    mov al, byte ptr esi[edx]
    mov  byte ptr [edi+eax], 1

    inc edx
    dec ecx
    jnz @LOOP


  {---- scan through codewords ------}

    mov ecx, 256
    xor edx, edx

  @SCAN:

    mov al, byte ptr edi[edx]
    cmp al, 0
    jne @SKIP

    mov [value], dx
    jmp @FINISH


  @SKIP:

    inc edx
    dec ecx
    jnz @SCAN

    mov [value], -1


  @FINISH:
    popad
  end;
  result := value;
end;

{finds some minumum x not contained within data, or -1 if all
 256 codewords have been used.}
function bpeFirstFreeByte_REF(data: tBytes): integer;
var
  i: int32;
  used: array[0..255] of boolean;
begin
  fillchar(used, sizeof(used), False);
  for i := 0 to length(data)-1 do
    used[data[i]] := True;
  for i := 0 to 255 do
    if not used[i] then exit(i);
  exit(-1);
end;


{Apply bytepair encoding to input}
function bpeEncode(bytes:tBytes;useByte: byte; out a,b: int32;minFreq:integer=3): tBytes;
var
  freq: word;
  i: word;
  pair: word;
begin

  pair := findMostFrequentPair(bytes, freq);

  if freq < minFreq then begin
    {it costs ~2 tokens to output the BPE code, so if we get 2 or fewer
     matches, then this conversion is not worthwhile}
    a := -1;
    b := -1;
    exit(bytes);
  end else begin
    a := pair and $ff;
    b := pair shr 8;
  end;

  result := replacePair(bytes,pair,useByte);
end;

{Perform byte pair encoding.}
function doBPE(data: tDwords; maxReplacements: integer=256; out dictionary: tDwords): tDwords;
var

  i: int32;
  numReplacements: integer;
  useToken : int32;

  a,b: int32;

  {freq: array of word;}
  pair, value, freq : word;

begin

  dictionary := nil;

  if maxReplacements <= 0 then exit(data);

  {initialization}
  numReplacements := 0;

  {work out which token to use in substitutions}
  useToken := firstFreeToken(data);

  {no free codespace for BPE}
  if useToken < 0 then begin
    findMostFrequentPair(bytes, freq);
    writeln('No codespace for BPE, but if we had space first substitution would have saved ~',freq, ' bytes');
    exit(bytes);
  end;

  while (numReplacements < maxReplacements) do begin

    data := bytePairEncode(data, useToken, a, b);
    if a < 0 then
      {no more good pairs}
      break;

    {write out the substitution we just performed}
    dictionary.append(useByte);
    dictionary.append(a);
    dictionary.append(b);

    useToken := firstFreeToken(bytes);

    if useToken < 0 then break;

    inc(numReplacements);
  end;

  writeln('Added ', numReplacements, ' new tokens');

  result := data;
end;


{---------------------------------------------------------------}
{ Token Pair Encoding}
{---------------------------------------------------------------}
{max supported token is 1024 right now}

(*
function tpeFindMostFrequentPair_REF(data:tDwords;out freq:word): dword;
var
  i, value: word;
  {um... this is going to be very slow!}
  allPairsFreq: array[0..1024-1,0..1024-1] of word;
begin
  fillword(allPairsFreq, sizeof(allPairsFreq) div 2, 0);
  result := 0;
  freq := 0;
  for i := 0 to length(data)-2 do begin
    inc(allPairsFreq[data[i], data[i+1]]);
    value := allPairsFreq[data[i], data[i+1]];
    if value > freq then begin
      freq := value;
      result := pWord(@data[i])^;
    end;
  end;
end;

function tpeFirstFreeToken(data: tDwords): int32; pascal;
var
  used: array[0..1024-1] of byte;
  dataPtr: pointer;
  usedPtr: pointer;
  value: int32;
  len: dword;
begin
  dataPtr := @data[0];
  usedPtr := @used;
  value := 101;
  len := length(data);
  asm
    pushad

  {---- clear buffer ----------}

    mov edi, [usedPtr]
    mov eax, 0
    mov ecx, 1024/4
    cld
    rep stosd

{---- loop through tokens ------}

    mov ecx, [len]
    xor edx, edx
    xor eax, eax
    mov esi, [dataPtr]
    mov edi, [usedPtr]

  @LOOP:

    mov eax, dword ptr esi[edx]
    mov byte ptr [edi+eax*4], 1

    add edx, 4
    dec ecx
    jnz @LOOP


  {---- scan through codewords ------}

    mov ecx, 1024
    xor edx, edx

  @SCAN:

    mov al, byte ptr edi[edx]
    cmp al, 0
    jne @SKIP

    mov [value], edx
    jmp @FINISH


  @SKIP:

    inc edx
    dec ecx
    jnz @SCAN

    mov [value], -1


  @FINISH:
    popad
  end;
  result := value;
end;

{Apply bytepair encoding to input}
function tpeEncode(data:tDwords;useToken: int32; out a,b: int32;minFreq:integer=4): tDwords;
var
  freq: word;
  i: word;
  pair: dword;
begin

  pair := tpeFindMostFrequentTokenPair(data, freq);

  if freq < minFreq then begin
    {it costs ~2 tokens to output the BPE code, so if we get 2 or fewer
     matches, then this conversion is not worthwhile}
    a := -1;
    b := -1;
    exit(data);
  end else begin
    a := pair and $ffff;
    b := pair shr 16;
  end;

  result := tpeReplaceTokenPair(data, pair, useToken);
end;
  *)

{-------------------------------------------------------------}

type
  tBPETest = class(tTestSuite)
    procedure run; override;
  end;

procedure tBPETest.run();
var
  i: integer;
  a,b: int32;
  inBytes,outBytes,slnBytes: tBytes;
  pair, freq: word;
const
  TEST_X: array[0..9] of byte = (0,1,2,3,3,5,3,5,2,1);
  TEST_Y: array[0..7] of byte = (0,1,2,3,255,255,2,1);
begin

  {setup}
  inBytes := nil;
  outBytes := nil;
  slnBytes := nil;
  setLength(slnBytes, length(TEST_Y));
  move(TEST_Y[0], slnBytes[0], length(TEST_Y));
  setLength(inBytes, length(TEST_X));
  move(TEST_X, inBytes[0], length(TEST_X));

  {MostFrequentPair}
  pair := bpeFindMostFrequentPair_REF(inBytes, freq);
  assertEqual(pair, 3+5*256);
  assertEqual(freq, 2);
  pair := bpeFindMostFrequentPair(inBytes, freq);
  assertEqual(pair, 3+5*256);
  assertEqual(freq, 2);

  {FindFirstByte}
  assertEqual(bpeFirstFreeByte_REF(inBytes), 4);
  assertEqual(bpeFirstFreeByte(inBytes), 4);

  {BPE}
  outBytes := bpeEncode(inBytes, 255, a, b, 1);
  assertEqual(outBytes, slnBytes);
  assertEqual(a, 3);
  assertEqual(b, 5);

end;

begin
  tBPETest.create('LZ4_BPE');
end.