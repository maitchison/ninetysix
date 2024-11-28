program lz96;
{testing an extremly simple LZ77 compressor}

{
	Uncompressed: 3659
  Zstream: 1446
  LZ4: 1978 (best compression)
  LZ96 2026
  LZ96 1989 (2 step lookahead)
  LZ96 1987 (remove offset from end block)
  LZ96 1989 (switch to block size heurisitic - maybe go back later?)
  LZ96 1975 (add min match_size... wow, we seem to be better than LZ4?)

  Ok, I'm 3 bytes ahead, but I tihnk that's because I don't respect the
  	'last 5 bytes are literals' rule.

  (rate is 0.02 MB/s ... lets get that up)


  Note: Lookahead 1 gives 1%, Lookahead 2 gives 2% (negative gain after that)


  LZ4+ENT0 = 1854 (small again)

  Rought gains

  	LZ4 (1.85x)
    ENT0 (



}

{$MODE DELPHI}

uses
	test,
  debug,
	utils,
  hashmap,
  stream,
	lzblock;


const
	TEST_FILE = 'data/higraph.pas';
	//TEST_FILE = 'data/img.dat';

	MAX_BPE_TOKENS = 256;


Type

	TOldTokens = array of Word;
	TIntegers = array of Integer;

  TCompressionFunction = function(data: TBytes): TBytes;
	
  TStringMap = record
  	matches: array[0..65535] of TIntegers;
    procedure addReference(key: word; pos: word);
  end;


var
	map: TStringMap;

type
	TMatchRecord = record
  	gain: int32;
    length: int32;
    pos: int32;
  end;


{---------------------------------------------------------------}


var
	{
  number of bytes to lookahead when checking for matches
  }

	LOOKAHEAD: byte = 2;


{-----------------------------------------------------}
{ From UTILS }
{-----------------------------------------------------}

const
	CLOCK_FREQ = 166*1000*1000;	
  INV_CLOCK_FREQ: double = 1.0 / CLOCK_FREQ;

function GetRDTSC(): uint64; assembler; register;
asm
	rdtsc
	{result will already be in EAX:EDX, so nothing to do}
  end;

{Get seconds since power on.
Can be used for very accurate timing measurement}
function GetSec(): double; inline;
begin
    result := getRDTSC() * INV_CLOCK_FREQ;
end;

function sanitize(w: word): string;
begin
	if (w < 32) or (w >= 128) then
  	result := '#'+IntToStr(w)
  else	
	  result := char(w);
end;

function max(a,b: int32): int32;
begin
	if a > b then exit(a);
  exit(b);
end;


{-----------------------------------------------------}
{buffer helpers}
{todo: move to a class, and make fast}

function Append(x: TBytes;b: byte): TBytes;
begin
	SetLength(x, Length(x)+1);
  x[Length(x)-1] := b;
  result := x;
end;

{Returns the number of bytes that match at given positions}
function MatchLength(data: TBytes; a,b: word): word;
var
	l,s: word;
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

procedure TStringMap.addReference(key: word; pos: word);
begin
	SetLength(Matches[key], Length(Matches[Key])+1);
  Matches[key][Length(Matches[Key])-1] := pos;
end;


{---------------------------------------------------------------}
{ EntropyEncoder}
{---------------------------------------------------------------}

{Apply bytepair encoding to input}
function bytePairEncode(bytes:tBytes;useByte: byte; out a,b: int32;minFreq:integer=3): tBytes;
var
	outStream: tStream;
  {allPairsFreq: array[0..255,0..255] of word;}
  bestFreq: word;
  i, bestI: int32;
  pair: word;
  value: word;
  map: tSparseMap;
begin
	{todo: this would be much more efficent with a simple hash map}

  (*
  fillword(allPairsFreq, sizeof(allPairsFreq) div 2, 0);

  {find the most common pair}
  bestFreq := 0;
  for i := 0 to length(bytes)-2 do begin
    inc(allPairsFreq[bytes[i], bytes[i+1]]);
    thisFreq := allPairsFreq[bytes[i], bytes[i+1]];
    if thisFreq > bestFreq then begin
    	bestFreq := thisFreq;
      bestI := i;
  	end;  	
  end;
  *)

  {find the most common pair}
  map := tSparseMap.Create();
  bestFreq := 0;
  for i := 0 to length(bytes)-2 do begin
  	pair := bytes[i] + (bytes[i+1] shl 8);
    value := map.getValue(pair)+1;
    map.setValue(pair, value);
    if value > bestFreq then begin
    	bestFreq := value;
      bestI := i;
  	end;  	
  end;
  {stub:}
  write(map.largestBin, '/', map.usedBins);
  map.free;

  pair := pword(@bytes[bestI])^;

  if bestFreq < minFreq then begin
  	{it costs ~2 tokens to output the BPE code, so if we get 2 or fewer
     matches, then this conversion is not worthwhile}
    a := -1;
    b := -1;
    exit(bytes);
  end else begin
  	a := bytes[bestI];
  	b := bytes[bestI+1];
  end;


  {perform replacement}
  outStream := tStream.create();
  i := 0;
  while i < length(bytes) do begin
  	if (i+1 < length(bytes)) and (pword(@bytes[i])^ = pair) then begin
    	outStream.writeByte(useByte);
      inc(i,2);
    end else begin
    	outStream.writeByte(bytes[i]);
      inc(i);
    end;
  end;


  result := outStream.bytes;
  	
end;

{finds some minumum x not contained within data, or -1 if all
 256 codewords have been used.}
function firstFreeByte(data: tBytes): integer;
var
	i: int32;
	used: array[0..255] of boolean;
begin
  {todo: switch to working on tbytes ... need a byte based BPE}
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
	i, prevI: int32;
  numReplacements: integer;
  a,b: int32;
  outStream: tStream;
begin

  outStream := tStream.create()

  prevI := 0;useByte := firstFreeByte(bytes);
  ifree codespace for BPE}  = nil;
  numReplacements := 0;
  setLength(freq, 256*256);
  bestFreq := 0;                                                 ------------------------------------------------------------}
                                            ion doLZ4(data: tBytes): tBytes;
var
  buffer: TBytes;
  pos: word;
  code: word;
  bytesMatched: word;
  srcLen: word;
  matches: TIntegers;
  i,j,k: word;

  bestMatch: array[0..31] of TMatchRecord;
  thisMatch: TMatchRecord;
  goodMatch: TMatchRecord;

  doMatch: boolean;
  copyBytes: word;

  a,b: int32;

  block: tLZBlock;


begin

	{note: assume 5 <= blocksize <= 64k}

	{todo: special case for short TBytes (i.e length <= 5)}

  fillchar(map, sizeof(map), 0);
  srcLen := length(data);

	{greedy approach}

  {push first character}
  setLength(buffer, 0);
  pos := 0;
	buffer := Append(buffer, data[pos]);
  pos += 1;

  block := tLZBlock.Create();

  {todo: build all references at the start... although them
   I'm not streaming, but I think that's ok}

  while True do begin

    if pos >= srcLen-1 then begin
    	{We reached the end, just dump the buffer}
			block.writeEndSequence(buffer);
      setLength(buffer, 0);
      exit;
    end;

    fillchar(thisMatch, sizeof(thisMatch), 0);
    fillchar(bestMatch, sizeof(bestMatch), 0);

    for i := 0 to LOOKAHEAD do begin
    	{we're going to do a lookahead, to see if we get a better match
       if we delay a short amount}

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


      {note: we need a special case to check previous byte matches,
       i.e. for RLE. Currently matches does not cover this}
      	
      {See if we can get a match from here...}
      {note: we can not do matching when near end as
       matches must be atleast 4 bytes}
      if pos+i < srcLen-4 then begin
      	code := word(data[pos+i]) + (word(data[pos+i+1]) shl 8);

        {todo: as soon as we find a better match after i=1 we can stop}

        fillchar(thisMatch, sizeof(thisMatch), 0);

        matches := map.matches[code];
        if assigned(matches) then begin
          for j := 0 to length(matches)-1 do begin
        		thisMatch.length := MatchLength(data, pos+i, matches[j]);
            thisMatch.pos := matches[j];
            if thisMatch.length < 2 then begin
            	writeln('invalid reference!');
              halt;
            end;

            if thisMatch.length < 4 then continue;

            {proper gain formula}
            {1.80x}

          	{ignore cost of offset + token (i.e. just want to know cost of encoding the length + buffer really}
            a := tLZBlock.getSequenceSize(0, length(buffer)+i+thisMatch.length) - 3 - tLZBlock.getSequenceSize(thisMatch.length, length(buffer) + i);
            {simplified gain formula}
            {1.81}
            {we count a match of any length with a cost of 3 bytes (token+offset), even though this
            is not true for long matches}
            b := int32(thisMatch.length) - 3;

            {heristic works just as well, maybe the times this is off do not matter?}
            thisMatch.gain := b;

            if thisMatch.gain > bestMatch[i].gain then
            	bestMatch[i] := thisMatch;
          end;
        end;
      end;
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
      if LOOKAHEAD > 0 then begin
      	{calculte oportunity cost... which is quite complicated for long
         lookahead}
        {ok, just ignore if there's a better one}
	      for i := 1 to LOOKAHEAD do begin
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
      block.writeSequence(bestMatch[0].length, int32(pos) - bestMatch[0].pos, buffer);
      SetLength(buffer, 0);
      {add references for the copied bytes we just output}
      copyBytes := bestMatch[0].length;
      while copyBytes > 0 do begin
				map.AddReference(data[pos-1]+(word(data[pos]) shl 8), pos-1);
	      inc(pos);
        dec(copyBytes);
      end;
    end else begin    	
	    {... If not, add a literal and keep going}
  	  buffer := Append(buffer, data[pos]);
      {add a reference for this byte}
      map.AddReference(data[pos-1]+(word(data[pos]) shl 8), pos-1);
      inc(pos);
    end;
  end;

  result := block.toBytes;
end;


function lz4Compress(bytes: tBytes): tBytes;
var	
  block: tLZBlock;
begin
	writeln(length(bytes));
	bytes := doBPE(bytes);
{  writeln(length(bytes));
  bytes := doLZ4(bytes);}
  result := bytes;
end;

var
	startTime, elapsed: double;

{Used for reference}
function memCopyCompress(data: TBytes): TBytes;
var	
	output: Tbytes;
begin
	output := nil;
  setLength(output, length(data));
  move(data[0], output[0], length(data));
  result := output;	
end;

(*
function zCompress(data: TBytes): TBytes;
var
  output: TMemoryStream;
  compressor: TCompressionStream;
  outputBytes: TBytes;
begin

	outputBytes := nil;

	{do the compression}
  output := TMemoryStream.Create();
	compressor := TCompressionStream.Create(clDefault, output);
  compressor.WriteBuffer(data[0], length(data));
  compressor.Free; {required to flush the compressor}

  {read back into tBytes}
  setLength(outputBytes, output.size);
  output.position := 0;
  output.ReadBuffer(outputBytes[0], output.size);

  {clean up}
  output.free;

  result := outputBytes;
end; *)

procedure test(method: string; proc: TCompressionFunction);
var
	inStream: tStream;
  outBytes: tBytes;
begin


  writeln(method,':');

	{read input}
  startTime := getSec;
  inStream := tStream.FromFile(TEST_FILE);
  elapsed := getSec()-startTime;
  {writeln('Read took         ', (1000*elapsed):6:2, ' ms');}
  {writeln('Incompressed Size ', Length(InputBuffer));}

  {run compression}
  startTime := getSec;
  outBytes := proc(inStream.bytes);
  elapsed := getSec-startTime;


  {start:
  full is 12.0 seconds, 2.14x... this is very bad}

	writeln('Compression       ', inStream.len/length(outBytes):6:2,'x');
{	writeln('Compressed Size   ', length(OutputBuffer):4);}
	
  writeln('Compression took  ', (elapsed):6:2, 's')

  ;
{  writeln('Compression speed ', (length(InputBuffer)/elapsed/1024/1024):6:2, ' MB/s');}

end;

var
	i: integer;
  a,b,c: integer;

const
	MAX_I: byte = 10;


procedure runTests();
var
	i: integer;
	inBytes,outBytes: tBytes;
const
	TEST_X: array[0..7] of byte = (0,1,2,3,3,5,3,3);
	TEST_Y: array[0..5] of byte = (0,1,2,255,5,255);
begin
	inBytes := nil;
  outBytes := nil;
	setLength(inBytes, length(TEST_X));
  move(TEST_X, inBytes[0], length(TEST_X));
	outBytes := bytePairEncode(inBytes, 255, a,b, 1);
  assertEqual(length(outBytes), length(TEST_Y));
  for i := 0 to length(TEST_Y)-1 do
  	assertEqual(outBytes[i], TEST_Y[i]);
end;

begin

	runTests();

	{Set text mode}
  (*
	asm
  	mov ax, $0003;
	  int $10
    mov ax, $1112;
    mov bl, 0;
    int $10;
	end; *)


	writeln();
	writeln('==============================');
	writeln();
	Test('MemCopy', @memCopyCompress);
  writeln();

  test('LZ4',@lz4Compress);

  writeln('done.');


end.
