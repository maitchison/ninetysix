unit LZ4;

{todo:
	Clean this unit up
}

{$MODE Delphi}

{$DEFINE debug}

interface

uses
	test,
  debug,
	hashmap,
	stream,
	utils;

type
	tCompressionProfile = record
  	lookahead: byte; {2 for best quality, 0 for fastest}
    maxBinSize: integer; {-1 for unlimited}
  end;

const
  LZ96_FAST: tCompressionProfile = (
  	lookahead:	0;
    maxBinSize:	1;
  	);
	LZ96_STANDARD: tCompressionProfile = (
  	lookahead:	0;
    maxBinSize:	32;
  	);
	LZ96_HIGH: tCompressionProfile = (
  	lookahead:	1;
    maxBinSize:	128;
  	);
	LZ96_VERYHIGH: tCompressionProfile = (
  	lookahead:	2;
    maxBinSize:	1024;
  	);
  LZ96_MAXIMUM: tCompressionProfile = (
  	lookahead:	2;
    maxBinSize:	0;
	  );

type

  tLZ4Stream = class(tStream)
	
	private
  	procedure writeVLC(value: int32);
  public
  	class function getSequenceSize(matchLength: integer;numLiterals: word): word;
    procedure writeSequence(matchLength: integer;offset: word;const literals: array of byte);
    procedure writeEndSequence(const literals: array of byte);
  end;

function LZ4Compress(data: tBytes): tBytes; overload;
function LZ4Compress(data: tBytes;level: tCompressionProfile): tBytes; overload;
function LZ4Decompress(bytes: tBytes;buffer: tBytes=nil):tBytes;
function LZ4Debug(bytes: tBytes;ref: tBytes=nil;print:boolean=False): tBytes;

implementation

{---------------------------------------------------------------}

const
	MIN_MATCH_LENGTH = 4;
  MAX_BLOCK_SIZE = 256*1024;

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

procedure tLZ4Stream.writeVLC(value: int32);
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
	a := length(literals);
  WriteByte(min(a, 15));
  if a >= 15 then
  	writeVLC(a-15);
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

	startSize := pos;

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
  if a >= 15 then writeVLC(a-15);

  if length(literals) > 0 then
		for i := 0 to length(literals)-1 do
  		writeByte(literals[i]);

  writeWord(offset);

  if b >= 15 then writeVLC(b-15);

  {make sure this worked}
	{$IFDEF debug}
  if (pos - startSize) <> getSequenceSize(matchLength, length(literals)) then
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
{ EntropyEncoder}
{---------------------------------------------------------------}

function findMostFrequentPair_REF(bytes:tBytes;out freq:word): word;
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

function findMostFrequentPair(bytes:tBytes;out freq:word): word;
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

  	mov bx, [edi]				//bx <- pair
    mov dx, [esi+ebx*2]		//dx <- count(pair)	
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

function replacePair(bytes: tBytes;pair:word;useByte:byte): tBytes;
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

{Apply bytepair encoding to input}
function bytePairEncode(bytes:tBytes;useByte: byte; out a,b: int32;minFreq:integer=3): tBytes;
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

function firstFreeByte(data: tBytes): int16; pascal;
var
	used: array[0..255] of byte;
  dataPtr: pointer;
  usedPtr: pointer;
  value: int16;
  i: integer;
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
		mov	byte ptr [edi+eax], 1   	
  	
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
function firstFreeByte_REF(data: tBytes): integer;
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

{Perform byte pair encoding.}
function doBPE(bytes: tBytes; maxReplacements: integer=256): tBytes;
var

	i: int32;
  numReplacements: integer;
  useByte: int32;

  a,b: int32;
  outStream: tStream;

  {freq: array of word;}
  pair, value, freq : word;

begin

	if maxReplacements <= 0 then exit(bytes);

  {initialization}
	outStream := tStream.Create();
  numReplacements := 0;

	{work out which byte to use in substitutions}
	useByte := firstFreeByte(bytes);

  {no free codespace for BPE}
	if useByte < 0 then begin
		findMostFrequentPair(bytes, freq);
    writeln('No codespace for BPE, but if we had space first substitution would have saved ~',freq, ' bytes');
	  exit(bytes);
  end;

	while (numReplacements < maxReplacements) do begin
  	
		bytes := bytePairEncode(bytes, useByte, a, b);
    if a < 0 then
    	{no more good pairs}
    	break;

    {write out the substitution we just performed}
    outStream.writeByte(useByte);
    outStream.writeByte(a);
    outStream.writeByte(b);

	  useByte := firstFreeByte(bytes);

    if useByte < 0 then break;

    inc(numReplacements);	
  end;

  writeln('Added ', numReplacements, ' new tokens');

  outStream.writeBytes(bytes);
  result := outStream.asBytes;
  outStream.free;	
end;

{---------------------------------------------------------------}

function LZ4Compress(data: tBytes): tBytes;
begin
	result := LZ4Compress(data, LZ96_HIGH);
end;

function LZ4Compress(data: tBytes;level: tCompressionProfile): tBytes;
var
  literalBuffer: tStream;
  pos, lastClean: int32;
  code: dword;
  bytesMatched: dword;
  srcLen: int32;
  matches: array of dword;
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

  map := tHashMap.create(level.maxBinSize);
  srcLen := length(data);

	{greedy approach}

  {push first character}
  pos := 0;
  literalBuffer := tStream.create(128);
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
    if pos >= srcLen-1 then begin
    	{we reached the end, just dump the buffer}
      while pos < srcLen do begin
	    	literalBuffer.writeByte(data[pos]);
        inc(pos);
      end;
	 		block.writeEndSequence(literalBuffer.asBytes);
      literalBuffer.free;
	    exit(block.asBytes);
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

        {fast path}
        (*
        if map.match[code] > 0 then begin
	        thisMatch.pos := map.match[code];
        	thisMatch.length := matchLength(data, pos+i, thisMatch.pos);
          thisMatch.gain := int32(thisMatch.length) - 3;
          if thisMatch.gain > 0 then
          	bestMatch[i] := thisMatch;
        end;*)

        fillchar(thisMatch, sizeof(thisMatch), 0);

        matches := map.matches[code];
        if assigned(matches) then begin
          for j := 0 to length(matches)-1 do begin

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
	    while (literalBuffer.len + bestMatch[i].pos + bestMatch[i].length) >= srcLen-1 do begin
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
        error('ops');
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

function readVLC: dword; inline; register;
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
    	numLiterals += readVLC;

    {copy literals}
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
    	matchLength += readVLC;
    	
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


function lz4Decompress(bytes: tBytes;buffer: tBytes=nil):tBytes;
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
  if not hadBuffer then
	  setLength(buffer, MAX_BLOCK_SIZE);
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
    mov dl, al 		// remember for later

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

  	add ecx, 4	 	// a match_length of 4 is recorded as 0
  	
    // copy matches
    push esi

    mov esi, edi
    sub esi, ebx
    rep movsb

    pop esi

		jmp @DECODE_LOOP

    (*

    {this is not used anymore}
  @MOVE:

  	{fast move function, can be used instead of rep movsb
     looks like it's a bit slower though due to the call overhead
     and checks at the beginning

  	{
     ecx=len
     esi=source
     edi=dest
    }

    {short if <4 remain}
    cmp ecx, 4
    jb @MOVE_SHORT

    {short if close overlap}
    mov eax, edi
    sub eax, esi
    cmp eax, 4
    jb @MOVE_SHORT


  @MOVE_LONG:
  	{copy 4 bytes at a time}
  	
    push ecx
    shr ecx, 2
    rep movsd
    pop ecx
    and ecx, $3

  @MOVE_SHORT:

    rep movsb
    ret *)

  @DONE:

  	mov eax, edi
    sub eax, bufferPtr
    mov [bufferLen], eax  	

    popad

  end;

  if bufferLen > length(buffer) then
  	Error(Format('Supplied buffer did not have enough bytes, wanted %d but only had %d', [bufferLen, length(buffer)]));
  if hadBuffer and (bufferLen < length(buffer)) then
    Error(Format('Supplied buffer did not match decode length, expected %d but only had %d', [length(buffer), bufferLen]));

  if not hadBuffer then
	  setLength(buffer, bufferLen);
  result := buffer;
end;

{------------------------------------------------}

procedure runTests_BPE();
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
  pair := findMostFrequentPair_REF(inBytes, freq);
  assertEqual(pair, 3+5*256);
  assertEqual(freq, 2);
  pair := findMostFrequentPair(inBytes, freq);
  assertEqual(pair, 3+5*256);
  assertEqual(freq, 2);

  {FindFirstByte}
  assertEqual(firstFreeByte_REF(inBytes), 4);
  assertEqual(firstFreeByte(inBytes), 4);

  {BPE}
	outBytes := bytePairEncode(inBytes, 255, a, b, 1);
  assertEqual(outBytes, slnBytes);
  assertEqual(a, 3);
  assertEqual(b, 5);

end;

procedure runTests_LZ4();
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
begin

  assertEqual(MatchLength_REF(testData, 0, 10), 0);
	assertEqual(MatchLength_REF(testData, 1, 10), 6);
	assertEqual(MatchLength_REF(testData, 0, 3), 0);
	assertEqual(MatchLength_REF(testData, 0, 0), 19);

  assertEqual(MatchLength(testData, 0, 10), 0);
	assertEqual(MatchLength(testData, 1, 10), 6);
	assertEqual(MatchLength(testData, 0, 3), 0);
	assertEqual(MatchLength(testData, 0, 0), 19);

	inBytes := tStream.create();
  for i := 1 to length(testString) do
  	inBytes.writeByte(ord(testString[i]));
  compressedData := lz4Compress(inBytes.asBytes);
  uncompressedData := lz4Decompress(compressedData);
	AssertEqual(uncompressedData, inBytes.asBytes);
  inBytes.free;

  inBytes := tStream.create();
  for i := 0 to 100 do
  	inBytes.writeByte(ord('x'));
	compressedData := LZ4Compress(inBytes.asBytes);
  uncompressedData := lz4Decompress(compressedData);
  AssertEqual(uncompressedData, inBytes.asBytes);

  inBytes.free;

end;


procedure runTests();
begin
	runTests_BPE();
  runTests_LZ4();
end;


begin
	runTests();
end.
