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
  lz4;


const
  TEST_FILE = 'data/higraph.pas';
  //TEST_FILE = 'data/img.dat';

  MAX_BPE_TOKENS = 256;

Type

  TOldTokens = array of Word;
  TCompressionFunction = function(data: TBytes): TBytes;


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

procedure test(method: string; proc: TCompressionFunction);
var
  inStream: tStream;
  outBytes: tBytes;
  startTime, elapsed: double;
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
  outBytes := proc(inStream.asBytes);
  elapsed := getSec-startTime;

  {start:
  full is 12.0 seconds, 2.14x... this is very bad}

  writeln('Compression       ', inStream.len/length(outBytes):6:2,'x');
{  writeln('Compressed Size   ', length(OutputBuffer):4);}

  writeln('Compression took  ', (elapsed):6:2, 's')

  ;
{  writeln('Compression speed ', (length(InputBuffer)/elapsed/1024/1024):6:2, ' MB/s');}

end;


procedure testCompression();
const
  testString = 'There once was a fish, with a family of fish, who liked to play.';
var
  inBytes: tStream;
  compressedData: tBytes;
  uncompressedData: tBytes;
  MBs: double;
  fileSize: int32;
  i: integer;
  startTime, elapsed: double;
begin

  {a small simple test}

  writeln();

  inBytes := tMemoryStream.create();
  for i := 1 to length(testString) do
    inBytes.writeByte(ord(testString[i]));

  writeln(testString);
  writeln(length(testString), ',', inBytes.len);

  compressedData := LZ4Compress(inBytes.asBytes);

  writeln(length(compressedData));
  writeln(bytesToStr(compressedData));

  uncompressedData := LZ4Decompress(compressedData);

  writeln(length(uncompressedData));
  writeln(bytesToStr(uncompressedData));

  AssertEqual(uncompressedData, inBytes.asBytes);

  {test on much larger text}
  startTime := getSec;
  inBytes := tStream.FromFile(TEST_FILE);
  elapsed := getSec()-startTime;
  fileSize := inBytes.len;
  MBs := fileSize/1024/1024/elapsed;
  writeln(Format('Read at %f MB/s', [MBs]));

  startTime := getSec;
  compressedData := LZ4Compress(inBytes.asBytes);
  elapsed := getSec()-startTime;
  MBs := fileSize/1024/1024/elapsed;
  writeln(Format('Compressed at %f MB/s', [MBs]));


  uncompressedData := nil;
  setLength(uncompressedData, filesize);

  startTime := getSec;
  for i := 0 to 100-1 do
    uncompressedData := lz4Decompress(compressedData, uncompressedData);
  elapsed := getSec()-startTime;
  MBs := 100*fileSize/1024/1024/elapsed;
  writeln(Format('Decompressed at %f MB/s', [MBs]));

  {verify we have a match}
  AssertEqualLarge(uncompressedData, inBytes.asBytes);

  writeln('Compression looks good to me!');

end;

begin
  testCompression();
end.
