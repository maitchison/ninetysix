unit uLZ4;

{todo:
  Clean this unit up
}

{$MODE Delphi}

{$DEFINE debug}

interface

uses
  uTest,
  uTypes,
  uDebug,
  uHashMap,
  uStream,
  uUtils;

type
  tCompressionProfile = record
    lookahead: byte; {2 for best quality, 0 for fastest}
    maxBinSize: integer; {-1 for unlimited}
  end;

const
  LZ96_FAST: tCompressionProfile = (
    lookahead:  0;
    maxBinSize:  1;
    );
  LZ96_STANDARD: tCompressionProfile = (
    lookahead:  0;
    maxBinSize:  32;
    );
  LZ96_HIGH: tCompressionProfile = (
    lookahead:  1;
    maxBinSize:  128;
    );
  LZ96_VERYHIGH: tCompressionProfile = (
    lookahead:  2;
    maxBinSize:  1024;
    );
  LZ96_MAXIMUM: tCompressionProfile = (
    lookahead:  2;
    maxBinSize:  0;
    );

type

  tLZ4Stream = class(tMemoryStream)
  private
    procedure writeVLL(value: int32);
  public
    class function getSequenceSize(matchLength: integer;numLiterals: word): word;
    procedure writeSequence(matchLength: integer;offset: word;const literals: array of byte);
    procedure writeEndSequence(const literals: array of byte);
  end;

function LZ4Compress(data: tBytes): tBytes; overload;
function LZ4Compress(data: tBytes;level: tCompressionProfile): tBytes; overload;
function LZ4Decompress(bytes: tBytes;buffer: tBytes=nil):tBytes; overload;
function lz4Decompress(bytes: tBytes;outputLength: int32):tBytes; overload;
function LZ4Debug(bytes: tBytes;ref: tBytes=nil;print:boolean=False): tBytes;

implementation

{---------------------------------------------------------------}

const
  MIN_MATCH_LENGTH = 4;
  MAX_BLOCK_SIZE = 4*1024*1024;

type
  TMatchRecord = record
    gain: int32;
    length: int32;
    pos: int32;
  end;

{---------------------------------------------------------------}

{returns the number of bytes required to encode block}
class function tLZ4Stream.GetSequenceSize(matchLength: integer;numLiterals: word): word;
var
  a,b: int32;
  bytesRequired: word;
begin
  bytesRequired := 1; {for token}
  a := numLiterals;
  b := matchLength - MIN_MATCH_LENGTH;
  {looks wrong, but is right}
  a -= 14;
  while a > 0 do begin
    inc(bytesRequired);
    a -= 255;
  end;
  b -= 14;
  while b > 0 do begin
    inc(bytesRequired);
    b -= 255;
  end;

  bytesRequired += numLiterals;
  bytesRequired += 2; {offset}
  result := bytesRequired;
end;

{variable length length}
procedure tLZ4Stream.writeVLL(value: int32);
begin
  while True do begin
    if value < 255 then begin
      writeByte(value);
      exit;
    end;
    writeByte(255);
    value -= 255;
  end;
end;

procedure tLZ4Stream.writeEndSequence(const literals: array of byte);
var
  i: int32;
  a: int32;
begin
  if length(literals) < 1 then
    fatal('Must end on a literal');

  a := length(literals);
  WriteByte(min(a, 15));
  if a >= 15 then
    writeVLL(a-15);
  if length(literals) > 0 then
    for i := 0 to length(literals)-1 do
      writeByte(literals[i]);
end;

procedure tLZ4Stream.writeSequence(matchLength: integer;offset: word;const literals: array of byte);
var
  numLiterals: word;
  a,b: int32;
  i: word;
  startSize: int32;
begin

  startSize := fPos;

  {note: literals may be empty, but match and offset may not}
  {
  write('Block: ');
  if length(literals) > 0 then
    for i := 0 to length(literals)-1 do
      write(sanitize(literals[i]))
  else
    write(' <empty>');
  write(' + copy ', matchLength, ' bytes from ', offset);
  writeln();
  }

  numLiterals := length(literals);

  if matchLength < 4 then begin
    writeln('Invalid match length!');
    halt;
  end;


  a := numLiterals;
  b := matchLength-MIN_MATCH_LENGTH;

  WriteByte(min(a, 15) + min(b,15) * 16);
  if a >= 15 then writeVLL(a-15);

  if length(literals) > 0 then
    for i := 0 to length(literals)-1 do
      writeByte(literals[i]);

  writeWord(offset);

  if b >= 15 then writeVLL(b-15);

  {make sure this worked}
  {$IFDEF debug}
  if (fPos - startSize) <> getSequenceSize(matchLength, length(literals)) then
    writeln('Invalid block length!');
  {$ENDIF}
end;

{Returns the number of bytes that match at given positions.

  data: Bytes to match on
  a,b: Two indices into the bytes
  returns: number of bytes matched.
}
function MatchLength(const data: array of byte; a,b: dword): dword; inline;
var
  dataPtr: pointer;
  maxLen: int32;
  tmp: dword;
begin
  dataPtr := @data[0];
  maxLen := length(data) - max(a,b);
  if maxLen = 0 then exit(0);
asm
  {todo: switch to compare dword?}

  push esi
  push edi

  {setup}
  mov esi, dataPtr
  mov edi, dataPtr
  add esi, [a]
  add edi, [b]

  {fast initial 4-byte check}
  mov ecx, [maxLen]
  push esi

  cld
  repe cmpsb

  mov eax, esi
  pop esi
  sub eax, esi
  dec eax

  {Matching n bytes means ecx =- (n+1), and esi,edi += (n+1)
   If we stop due to ecx then it's n instead}
  cmp ecx, 0
  jne @SKIP
  inc eax

@SKIP:

  pop edi
  pop esi
  {eax is match length}
  mov [result], eax
  end;

end;

{---------------------------------------------------------------}

function LZ4Compress(data: tBytes): tBytes;
begin
  result := LZ4Compress(data, LZ96_HIGH);
end;

function LZ4Compress(data: tBytes;level: tCompressionProfile): tBytes;
var
  literalBuffer: tMemoryStream;
  pos, lastClean: int32;
  code: dword;
  bytesMatched: dword;
  srcLen: int32;
  matches: tShortList;
  i,j,k: dword;

  bestMatch: array[0..31] of TMatchRecord;
  thisMatch: TMatchRecord;
  goodMatch: TMatchRecord;

  doMatch: boolean;
  copyBytes: dword;

  a,b: int32;

  block: tLZ4Stream;
  map: tHashMap;

  function getCode(pos: int32): word; inline;
  begin
    // hash on first 4 bytes, starting from position
    result := hashD2W(pDWord(@data[pos])^);
  end;

  procedure addRef(pos: int32); inline;
  var
    code: word;
  begin
    if pos < 0 then exit;
    map.AddReference(getCode(pos), pos);
  end;

begin

  {note: assume 5 <= blocksize <= 64k}

  {todo: special case for short TBytes (i.e length <= 5)}
  if not assigned(data) then exit(nil); {null input}

  map := tHashMap.create(level.maxBinSize);
  srcLen := length(data);

  if srcLen > MAX_BLOCK_SIZE then fatal('LZ4 max block size is '+intToStr(MAX_BLOCK_SIZE)+'.');

  {greedy approach}

  {push first character}
  pos := 0;
  literalBuffer := tMemoryStream.create(128);
  literalBuffer.writeByte(data[0]);
  addRef(0);
  pos += 1;

  block := tLZ4Stream.Create();

  {todo: build all references at the start... although them
   I'm not streaming, but I think that's ok}
  lastClean := 0;

  while True do begin

    {remove stale matches}
    if (level.maxBinSize > 0) and (pos > 64*1024) and ((pos - lastClean) > 32*1024) then begin
      map.trim(pos-32*1024);
      lastClean := pos;
    end;

    {check for last byte}
    if pos > srcLen-1 then
      fatal('Processed too many bytes');
    if pos >= srcLen-1 then begin
      {we reached the end, just dump the buffer}
      while pos < srcLen do begin
        literalBuffer.writeByte(data[pos]);
        inc(pos);
      end;
       block.writeEndSequence(literalBuffer.asBytes);
      literalBuffer.free;
      map.free;
      result := block.asBytes;
      block.free;
      exit;
    end;

    fillchar(thisMatch, sizeof(thisMatch), 0);
    fillchar(bestMatch, sizeof(bestMatch), 0);

    for i := 0 to level.lookahead do begin

      {we're going to do a lookahead, to see if we get a better match
       if we delay a short amount}

      {todo: also do this for words and dwords I guess? - as they might not be in buffer}
      {check match on previous character as special case}

      if pos+i > 0 then begin
        thisMatch.length := MatchLength(data, pos+i, pos+i-1);
        thisMatch.pos := pos+i-1;
        thisMatch.gain := int32(thisMatch.length) - 3;
      end else
        thisMatch.length := 0;

      if thisMatch.length >= 4 then begin
        bestMatch[i] := thisMatch;
      end;

      {See if we can get a match from here...}
      {note: we can not do matching when near end as
       matches must be atleast 4 bytes}
      if pos+i < srcLen-4 then begin
        {hash system}

        code := getCode(pos+i);

        fillchar(thisMatch, sizeof(thisMatch), 0);

        matches := map.matches[code];
        if matches.len > 0 then begin
          for j := 0 to matches.len-1 do begin

            if (pos - matches[j]) > 65535 then
              {outside of window}
              continue;

            thisMatch.length := MatchLength(data, pos+i, matches[j]);
            thisMatch.pos := matches[j];

            if thisMatch.length < 4 then continue;
            thisMatch.gain := int32(thisMatch.length) - 3;

            if thisMatch.gain > bestMatch[i].gain then
              bestMatch[i] := thisMatch;
          end;
        end;
      end;

      {make sure to never match the final byte, so that we end on a literal}
      while (literalBuffer.len + pos + bestMatch[i].length) >= srcLen-1 do begin
        dec(bestMatch[i].length);
        dec(bestMatch[i].gain);
        bestMatch[i].gain := max(bestMatch[i].gain, 0);
      end;

      if (i = 0) and (bestMatch[0].gain = 0) then
        {no reason for lookahead if we're not performing a match}
        break;
    end;

    {consider the matches, and work out what to do...}
    if (bestMatch[0].gain = 0) then begin
      {nothing gained from matching here...}
      doMatch := False;
    end else begin
      {
      ok.. so we defer the match under the following conditions...

      there is a better match in the future, AND
      our greedy step match is exceeds it's position
      (i.e. a greedy match precludes this better option)
      }
      doMatch := True;
      if level.lookahead > 0 then begin
        {calculte oportunity cost... which is quite complicated for long
         lookahead}
        {ok, just ignore if there's a better one}
        for i := 1 to level.lookahead do begin
          if (bestMatch[i].gain > bestMatch[0].gain) then
            doMatch := False;
        end;
      end;
    end;

    {check if we found a match...}
    {note: if we found a better option in the future, we have to just
     skip the match, and reprocess... otherwise we'll find a 'greedy'
     option in the horizon}
    if doMatch then begin
      {... If so, output the match, along with the literal buffer}
      {write out buffer}
      {writeln('match ', pos, ' ',literalBuffer.len, ' ', bestMatch[0].length);}
      block.writeSequence(bestMatch[0].length, int32(pos) - bestMatch[0].pos, literalBuffer.asBytes);
      literalBuffer.softReset();
      {add references for the copied bytes we just output}
      copyBytes := bestMatch[0].length;
      while copyBytes > 0 do begin
        addRef(pos);
        inc(pos);
        dec(copyBytes);
      end;

    end else begin
      {... If not, add a literal and keep going}
      if pos > length(data)-1 then begin
        writeln(length(data), ' ', srcLen, ' ', pos, ' ',literalBuffer.len);
        fatal('ops');
      end;

      literalBuffer.writeByte(data[pos]);
      addRef(pos);
      inc(pos);
    end;
  end;

end;

procedure printStats(bytes: tBytes);
var
  entropy: double;
  ACLimit: double;
  counts: array[0..255] of int32;
  i: int32;
  total: int32;
  p: double;
  smallBins, smallest: integer;
begin
  fillchar(counts, sizeof(counts), 0);
  for i := 0 to length(bytes)-1 do
    inc(counts[bytes[i]]);

  smallBins := 0;
  smallest := 9999;
  entropy := 0;
  total := length(bytes);
  for i := 0 to 255 do begin
    if counts[i] < 10 then
      inc(smallBins);
    smallest := min(smallest, counts[i]);
    p := counts[i] / total;
    if p > 0 then
      entropy -= p * ln(p)
  end;

  // put entropy in bits rather than nats.
  entropy /= ln(2);

  // in theory we could get this level of compression with an
  // entropy encoder. (e.g. arithmetic encoding)
  ACLimit := 8 / entropy;

  writeln(Format('Length: %d entropy: %f theory: %f smallest: %d short_bins: %d',[length(bytes), entropy, ACLimit, smallest, smallBins]));
end;

{-------------------------------------------------------}
{ Decompression }
{-------------------------------------------------------}

{Returns the number of bytes that match at given positions}
function MatchLength_REF(const data: array of byte; a,b: word): dword;
var
  l,s: dword;
begin
  {todo: switch to using rep cmps}
  s := 0;
  l := length(data);
  while (a < l) and (b < l) and (data[a] = data[b]) do begin
    inc(a);
    inc(b);
    inc(s);
  end;
  result := s;
end;


function bytesToStr(bytes: tBytes): string;
var
  i: integer;
  b: byte;
  s: string;
begin
  s := '';
  for i := 0 to length(bytes)-1 do begin
    b := bytes[i];
    if (b >= 32) and (b < 128) then
      s += chr(b)
    else
      s += '#('+intToStr(b)+')';
  end;
  result := s;
end;

{reference implementation of lz4 decompress with debug printing}
function LZ4Debug(bytes: tBytes;ref: tBytes=nil;print:boolean=False): tBytes;
{todo: switch to using tStream}
var
  bufferPtr: pointer;
  buffer: tBytes;
  inPos, outPos: dword; {outpos is capped to 64k, but in pos, maybe not}
  i, ofs: int32;
  b: byte;
  numLiterals, matchLength: word;

function readByte: byte; inline; register;
begin
  result := bytes[inPos];
  inc(inPos);
end;

function readWord: word; inline; register;
begin
  result := bytes[inPos] + (bytes[inPos+1] shl 8);
  inc(inPos, 2);
end;

function peekByte: byte; inline; register;
begin
  result := bytes[inPos];
end;

function readVLL: dword; inline; register;
begin
  result := 0;
  while peekByte = 255 do
    result += readByte;
  result += readByte;
end;

function eof: boolean; inline;
begin
  result := inPos >= length(bytes)-1;
end;

begin

  {ignore buffer}
  buffer := nil;
  setLength(buffer, MAX_BLOCK_SIZE);
  bufferPtr := @buffer[0];

  inPos := 0;
  outPos := 0;
  while True do begin
    {read token}
    b := readByte;
    numLiterals := b and $f;

    {read match length}
    matchLength := b shr 4;
    if numLiterals = 15 then
      numLiterals += readVLL;

    {copy literals}

    if (inPos + numLiterals) >= length(bytes) then
      fatal('overran input by '+intToStr((inPos + numLiterals)-length(bytes)+1)+' bytes');
    if (outPos + numLiterals) >= length(buffer) then
      fatal('overran output by '+intToStr((outPos + numLiterals)-length(buffer)+1)+' bytes');

    move(bytes[inPos], buffer[outPos], numLiterals);
    inc(inPos, numLiterals);
    inc(outPos, numLiterals);

    {check for terminal sequence}
    if eof then begin
      if print then
        writeln(format('Final Token (lit:%d)',[numLiterals]));
      break;
    end;

    {preform match}
    ofs := readword;

    if matchLength = 15 then
      matchLength += readVLL;

    {min match length}
    matchLength += 4;

    if print then
      {writeln(Format('inpos:%d outpos:%d - #lit:%d match_len:%d ofs:%d', [inPos, outPos, numLiterals, matchLength, ofs]));}
      writeln(format('Token (lit:%d matchs:%d @:%d)',[numLiterals,matchLength,ofs]));

    {copy from buffer}
    {note: move is not safe if regions overlap, and I've seen it do the wrong thing
     for even with offset around t-12}
    if ofs > matchLength then
      move(buffer[outPos-ofs], buffer[outPos], matchLength)
    else
      for i := 0 to matchLength-1 do
        buffer[outPos+i] := buffer[outPos-ofs+i];

    inc(outPos, matchLength);

  end;

  if print then
    writeln('Output is ',outPos, ' bytes');

  {trim unused space}
  setLength(buffer, outPos);
  if assigned(ref) then begin
    writeln('>>>> here', length(buffer), length(ref));
    assertEqual(buffer, ref);
  end;

  result := buffer;
end;

function lz4Decompress(bytes: tBytes;buffer: tBytes=nil):tBytes; overload;
var
  bytesPtr: pointer;
  bytesLen: dword;
  bytesEnd: pointer;
  bufferPtr: pointer;
  bufferLen: dword;
  hadBuffer: boolean;
begin

  if not assigned(bytes) then
    exit(nil);

  bytesPtr := @bytes[0];
  bytesLen := length(bytes);
  bytesEnd := bytesPtr + bytesLen;
  hadBuffer := assigned(buffer);
  if not hadBuffer then begin
    {this is every inefficent.}
    {todo: support small initial buffer with buffer doubling in asm loop}
    setLength(buffer, MAX_BLOCK_SIZE);
    warning('No LZ4 output buffer given so guessed size is MAX_BLOCK_SIZE, which is slow.');
  end;
  bufferPtr := @buffer[0];
  asm
    {
      esi: bytes
      edi: buffer
     }
    cld

    pushad

    mov esi, bytesPtr
    mov edi, bufferPtr

    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx

  @DECODE_LOOP:

    // al <- token
    lodsb
    mov dl, al     // remember for later

    // ecx <- numLiterals
    xor ecx,ecx
    mov cl, al
    and cl, $f

    cmp cl, $f
    jne @SKIP_NL

    xor eax, eax

  @READ_NL:
    lodsb
    add ecx, eax
    cmp al, $ff
    je @READ_NL

    // we have a lot of literals, so do a dword at a time move
    // note: this doesn't seem to actually help. maybe because it's
    // not dword aligned? or probably just that we're memory bandwidth
    // limited
    mov ebx, ecx
    shr ecx,2
    rep movsd
    mov ecx, ebx
    and ecx, $3
    xor ebx, ebx

  @SKIP_NL:

    // copy literals
    rep movsb

    // check for eof
    cmp esi,[bytesEnd]
    jae @DONE

    // ebx <- offset
    lodsw
    mov bx, ax

    // ecx <- matchlength
    xor ecx, ecx
    mov cl, dl
    shr cl, 4

    cmp cl, $f
    jne @SKIP_ML
    xor eax, eax

  @READ_ML:
    lodsb
    add ecx, eax
    cmp al, $ff
    je @READ_ML

  @SKIP_ML:

    add ecx, 4     // a match_length of 4 is recorded as 0

    // copy matches
    push esi

    mov esi, edi
    sub esi, ebx
    rep movsb

    pop esi

    jmp @DECODE_LOOP

  @DONE:

    mov eax, edi
    sub eax, bufferPtr
    mov [bufferLen], eax

    popad

  end;

  if bufferLen > length(buffer) then
    fatal(Format('Supplied buffer did not have enough bytes, wanted %d but only had %d', [bufferLen, length(buffer)]));
  if hadBuffer and (bufferLen < length(buffer)) then
    fatal(Format('Supplied buffer did not match decode length, expected %d but only had %d', [length(buffer), bufferLen]));

  if not hadBuffer then
    setLength(buffer, bufferLen);
  result := buffer;
end;

{decompress LZ4. you must pass in the maximum size of the output buffer
 and if this is incorrect an error will occur (or potentially memory coruption)}
function lz4Decompress(bytes: tBytes;outputLength: int32):tBytes; overload;
var
  outBuffer: tBytes;
begin
  outBuffer := nil;
  setLength(outBuffer, outputLength);
  result := lz4Decompress(bytes, outBuffer);
end;

{------------------------------------------------}

type
  tLZ4Test = class(tTestSuite)
    procedure run; override;
  end;

procedure tLZ4Test.run();
var
  inBytes: tStream;
  compressedData: tBytes;
  uncompressedData: tBytes;
  MBs: double;
  fileSize: int32;
  i: integer;
  a,b: int32;
  pair, freq: word;
const
  testString = 'There once was a fish, with a family of fish, who liked to play.';
  testData: array[0..18] of byte = (0,3,1,4,1,5,9,2,6,8,3,1,4,1,5,9,3,6,0);
  testCase1: array of byte =
  {this used to fail because we ended on a length literal}
  [152,2,12,3,23,104,38,6,188,34,7,47,30,11,51,68,105,104,2,39,61,0,163,226,5,47,87,
  55,217,170,35,77,97,37,79,119,165,184,62,185,164,38,69,113,129,75,115,155,77,119,
  161,30,1,12,26,17,55,22,19,59,18,23,63,14,27,65,9,51,91,13,57,95,19,59,99,181,168,
  44,45,87,127,49,93,131,53,95,135,202,40,81,182,18,103,146,15,139,108,51,175,93,137,
  175,149,8,12,10,31,71,6,35,75,2,39,79,1,45,83,217,132,8,29,71,111,33,77,115,37,79,
  119,166,4,117,65,109,149,69,111,151,56,103,227,97,139,179,2,159,228,107,149,187,69,
  233,156,35,0,12,5,47,87,11,51,91,13,55,95,17,59,99,41,83,123,47,87,127,49,93,131,53,
  95,135,77,121,159,81,123,163,49,211,176,91,133,171,113,155,195,119,161,199,179,170,
  46,213,134,10,127,205,12,198,34,87,162,0,123,111,151,191,113,157,195,70,91,217,32,
  127,251,145,189,227,37,199,188,34,72,172,93,254,132,131,218,96,167,182,58,64,59,239,
  28,93,212,3,127,176,39,161,144,255,215,12,54,107,231,16,143,244,125,169,207,53,215
  ,172,155,197,237,109,238,116,147,202,80,183,166,42,203,146,24,239,110,11,238,74,49,
  200,38,83,73,195,108,107,231,74,143,248,42,175,212,6,186,235,12,91,253,134,127,222,
  100,161,186,64,147,187,227,217,130,8,175,215,255,220,58,65,184,22,101,164,2,121,211,
  253,220,92,69,191,56,107,229,211,180,25,243,224,184,232,110,95,251,218,176,251,239,
  12,235,114,9,242,78,45,204,42,79,161,205,243,148,15,135,110,49,173,76,87,209,38,121,
  245,20,141,246,15,179,210,222,100,174,188,64,141,164,42,163,250,208,168,177,172,231,
  213,136,12,169,207,12,200,38,85,164,2,121,253,216,178,255,212,172,70,89,215,36,127,
  249,0,163,226,37,197,190,55,219,168,190,148,114,129,220,96,184,142,102,185,164,40,
  154,112,80,152,108,68,218,54,67,131,251,12,56,105,227,20,141,246,15,179,210,53,215,
  174,71,235,152,210,168,130,145,204,80,179,170,46,201,148,26,174,132,92,172,128,90,
  166,124,84,142,102,62,138,96,56,108,51,175,74,87,211,241,186,12,87,251,136,230,188,
  150,159,188,64,197,152,30,217,132,10,194,152,112,222,60,61,186,144,104,166,2,119,
  130,31,153,92,67,191,58,103,227,126,84,46,122,80,40,118,76,36,71,233,156,52,154,12,
  233,116,7,216,172,134,210,168,128,170,8,113,150,11,133,178,136,96,78,83,207,170,128,
  90,146,104,66,142,100,60,51,213,176,87,249,140,110,68,30,143,206,84,104,60,20,98,56,
  16,136,200,12,198,36,89,162,0,123,116,72,32,110,68,28,70,93,215,82,40,10,78,36,3,74,
  32,7,57,219,166,46,4,23,42,0,39,38,5,43,187,162,36,10,31,55,6,37,75,2,39,79,96,18,12,
  106,64,26,102,60,20,98,56,16,55,217,172,70,28,9,66,24,15,147,202,80,58,16,23,34,7,47,
  237,110,13,238,74,49,20,19,59,1,43,83,5,47,87,11,51,91,13,55,95,0,34,12,90,48,8,86,
  44,6,163,186,64,78,36,3,54,12,27,50,8,31,220,58,65,42,0,39,18,23,63,14,27,67,10,31,
  71,6,37,73,17,61,99,21,63,103,25,67,109,29,71,111,66,64,12,76,32,7,242,78,45,66,24,
  15,62,20,17,38,3,43,34,7,45,30,11,51,26,15,55,2,39,79,15,179,210,5,47,87,9,51,91,33,
  75,115,39,81,119,181,168,44,45,87,127];

begin

  assertEqual(MatchLength_REF(testData, 0, 10), 0);
  assertEqual(MatchLength_REF(testData, 1, 10), 6);
  assertEqual(MatchLength_REF(testData, 0, 3), 0);
  assertEqual(MatchLength_REF(testData, 0, 0), 19);

  assertEqual(MatchLength(testData, 0, 10), 0);
  assertEqual(MatchLength(testData, 1, 10), 6);
  assertEqual(MatchLength(testData, 0, 3), 0);
  assertEqual(MatchLength(testData, 0, 0), 19);

  inBytes := tMemoryStream.create();
  for i := 1 to length(testString) do
    inBytes.writeByte(ord(testString[i]));
  compressedData := lz4Compress(inBytes.asBytes);
  uncompressedData := lz4Decompress(compressedData, inBytes.len);
  assertEqual(uncompressedData, inBytes.asBytes);
  inBytes.free();

  inBytes := tMemoryStream.create();
  for i := 0 to 100 do
    inBytes.writeByte(ord('x'));
  compressedData := LZ4Compress(inBytes.asBytes);
  uncompressedData := lz4Decompress(compressedData, inBytes.len);
  assertEqual(uncompressedData, inBytes.asBytes);
  inBytes.free();

  {make sure we don't match on end sequence}
  inBytes := tMemoryStream.create();
  for i := 0 to length(testCase1)-1 do
    inBytes.writeByte(testCase1[i]);
  compressedData := lz4Compress(inBytes.asBytes);
  uncompressedData := lz4Decompress(compressedData, inBytes.len);
  assertEqual(uncompressedData, inBytes.asBytes);
  inBytes.free();

end;

initialization
  tLZ4Test.create('LZ4');
finalization

end.
