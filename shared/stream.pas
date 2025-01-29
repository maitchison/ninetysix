{A very simple stream class}
unit stream;

{$MODE Delphi}

{todo: borrow most of LZBlock}

interface

uses
  utils,
  debug,
  myMath,
  sysTypes,
  test;

type

  tStream = class

    {
    note on position
    fPos is our current position within the buffer.
    valid bytes are considered to be [0..bytesUsed-1]

    capacity (bytesAllocated) is always >= fPos
    using seek(fPos) is a 'soft clear', as in does not change the capacitiy.
    }

  protected
    bytes: pByte;
    bytesAllocated: int32;   {capacity is how much memory we allocated}
    bytesUsed: int32;   {bytesUsed is the number of actual bytes used}
    fPos: int32;        {current position in stream}
    midByte: boolean;

  private
    procedure makeCapacity(n: dword);
    procedure setCapacity(newSize: dword);
    procedure setLength(n: dword);

    function getByte(index: dword): byte; inline;
    procedure setByte(index: dword; value: byte); inline;

  public

    constructor Create(aInitialCapacity: dword=0);
    destructor Destroy(); override;
    class function FromFile(filename: string): tStream; static;

    property items[index: dword]: byte read getByte write setByte; default;

    procedure writeNibble(b: byte); inline;
    procedure writeByte(b: byte); inline;
    procedure writeWord(w: word); inline;
    procedure writeDWord(d: dword); inline;
    procedure writeVLC(value: dword); inline;
    function  writeVLCSegment(values: array of dword;segmentType:byte=255): int32;

    procedure setSize(newSize: int32);

    procedure writeChars(s: string);
    procedure writeBytes(aBytes: tBytes;aLen:int32=-1);
    procedure writeBlock(var x;numBytes: int32);

    function  peekByte: byte; inline;
    function  peekWord: word; inline;
    function  peekDWord: dword; inline;

    function  readByte: byte; inline;
    function  readNibble: byte; inline;
    function  readWord: word; inline;
    function  readDWord: dword; inline;
    function  readVLC: dword; inline;
    function  readVLCSegment(n: int32;outBuffer: tDwords=nil): tDWords;
    function  readBytes(n: int32): tBytes;
    procedure readBlock(var x;numBytes: int32);

    procedure byteAlign(); inline;
    procedure seek(aPos: dword; aMidByte: boolean=False);
    procedure advance(numBytes: integer);

    procedure writeToFile(fileName: string);
    procedure readFromFile(fileName: string; blockSize: int32=4096);

    procedure flush();
    procedure reset();
    procedure softReset();

    property  capacity: int32 read bytesAllocated;
    property  len: int32 read bytesUsed;
    property  pos: int32 read fPos;

    function  asBytes: tBytes;
    function  getCurrentBytesPtr: pointer;

  end;

implementation

uses
  vlc;

{------------------------------------------------------}

constructor tStream.Create(aInitialCapacity: dword=0);
begin
  inherited Create();
  bytes := nil;
  bytesAllocated := 0;
  midByte := False;
  if aInitialCapacity > 0 then
    makeCapacity(aInitialCapacity)
end;

destructor tStream.Destroy();
begin
  freeMem(bytes); bytes := nil;
  inherited destroy;
end;

class function tStream.FromFile(filename: string): tStream; static;
begin
  result := tStream.Create();
  result.readFromFile(filename);
end;

{------------------------------------------------------}

function tStream.getByte(index: dword): byte; inline;
begin
  result := bytes[index];
end;

procedure tStream.setByte(index: dword; value: byte); inline;
begin
  bytes[index] := value;
end;

{updates stream so that it has this much capacity.
Will truncate down if needed.
What get's modified
 - Pos: no change
 - ByteSize: >= newSize
 - ByteUsed: truncated down to newSize
}
procedure tStream.setCapacity(newSize: dword);
var
  blocks: int32;
begin

  //if newSize > 64*1024 then
  //  log(format('Allocating large block of size %,->%,', [bytesAllocated, newSize]));

  blocks := (newSize+1023) div 1024;

  {quick check to make sure everythings ok}
  if assigned(bytes) <> (bytesAllocated > 0) then
    error('Looks like stream was not initialized.');

  if blocks=0 then begin
    freeMem(bytes);
  end else begin
    reallocMem(bytes, blocks*1024);
    if bytes = nil then error('Could not allocate memory block');
  end;

  bytesAllocated := blocks*1024;

  {bytesUsed can not be more than actual buffer size}
  if bytesUsed > newSize then
    bytesUsed := newSize;
end;

{makes sure the stream has capacity for *atleast* n bytes}
procedure tStream.makeCapacity(n: dword);
begin
  if bytesAllocated < n then
    {resize might require a copy, so always increase size by atleast 5%}
    setCapacity(max(n, dword(int64(bytesAllocated)*105 div 100)));
end;

{expand (or contract) the length this many bytes}
{note: we never shrink the capacity here.}
procedure tStream.setLength(n: dword);
begin
  makeCapacity(n);
  bytesUsed := n;
end;

{------------------------------------------------------}

procedure tStream.writeNibble(b: byte); inline;
begin
  if midByte then begin
    bytes[fPos] := bytes[fPos] or (b shl 4);
    midByte := false;
    inc(fPos);
  end else begin
    setLength(fPos+1);
    bytes[fPos] := b;
    midByte := true;
  end;
end;

procedure tStream.writeByte(b: byte); inline;
begin
  if midByte then begin
    writeNibble((b shr 0) and $f);
    writeNibble((b shr 4) and $f);
    exit;
  end;
  setLength(fPos+1);
  bytes[fPos] := b;
  inc(fPos);
end;

procedure tStream.writeWord(w: word); inline;
begin
  if midByte then begin
    writeNibble((w shr 0) and $f);
    writeByte((w shr 4) and $ff);
    writeNibble((w shr 12) and $f);
    exit;
  end;
  setLength(fPos+2);
  {little edian}
  bytes[fPos] := w and $FF;
  bytes[fPos+1] := w shr 8;
  inc(fPos,2);
end;

procedure tStream.writeDWord(d: dword); inline;
begin
  if midByte then begin
    writeNibble((d shr 0) and $f);
    writeByte((d shr 4) and $ff);
    writeByte((d shr 12) and $ff);
    writeByte((d shr 20) and $ff);
    writeNibble((d shr 28) and $f);
    exit;
  end;
  setLength(fPos+4);
  {little edian}
  bytes[fPos] := d and $ff;
  bytes[fPos+1] := (d shr 8) and $ff;
  bytes[fPos+2] := (d shr 16) and $ff;
  bytes[fPos+3] := (d shr 24) and $ff;
  inc(fPos,4);
end;

procedure tStream.writeChars(s: string);
var
  i: integer;
begin
  for i := 1 to length(s) do
    writeByte(ord(s[i]));
end;

{expands stream to given new size (or truncates if needed)}
procedure tStream.setSize(newSize: int32);
begin
  setLength(newSize);
  bytesUsed := newSize
end;

procedure tStream.writeBytes(aBytes: tBytes;aLen:int32=-1);
begin
  if aLen < 0 then aLen := length(aBytes);
  if aLen = 0 then exit;
  if midByte then error('unaligned write bytes');
  if aLen > length(aBytes) then error('tried writing too many bytes');
  setLength(fPos + aLen);
  move(aBytes[0], self.bytes[fPos], aLen);
  inc(fPos, aLen);
end;

function tStream.readNibble: byte; inline;
begin
  if midByte then begin
    result := bytes[fPos] shr 4;
    midByte := false;
    inc(fPos);
  end else begin
    result := bytes[fPos] and $f;
    midByte := true;
  end;
end;

function tStream.readByte: byte; inline;
begin
  {todo: support halfbyte}
  if midByte then
    Error('Reading missaligned bytes not yet supported');
  result := bytes[fPos];
  inc(fPos);
end;

function tStream.readWord: word; inline;
begin
  if midByte then
    Error('Reading missaligned words not yet supported');
  result := bytes[fPos] + (bytes[fPos+1] shl 8);
  inc(fPos,2);
end;

function tStream.readDWord: dword; inline;
begin
  if midByte then
    Error('Reading missaligned dwords not yet supported');
  result := bytes[fPos] + (bytes[fPos+1] shl 8) + (bytes[fPos+2] shl 16) + (bytes[fPos+3] shl 24);
  inc(fPos,4);
end;

function tStream.peekByte: byte; inline;
begin
  {todo: support halfbyte}
  if midByte then
    Error('Reading missaligned bytes not yet supported');
  result := bytes[fPos];
end;

function tStream.peekWord: word; inline;
begin
  if midByte then
    Error('Reading missaligned bytes not yet supported');
  result := bytes[fPos] + (bytes[fPos+1] shl 8);
end;

function tStream.peekDWord: dword; inline;
begin
  if midByte then
    Error('Reading missaligned dwords not yet supported');
  result := bytes[fPos] + (bytes[fPos+1] shl 8) + (bytes[fPos+2] shl 16) + (bytes[fPos+3] shl 24);
end;

function tStream.readVLC: dword; inline;
var
  value: dword;
  b: byte;
  shift: byte;
begin
  value := 0;
  shift := 0;
  while True do begin
    b := readNibble;
    value += (b and $7) shl shift;
    if b < $8 then begin
      exit(value);
    end else begin
      inc(shift, 3);
    end;
  end;
end;

function tStream.readBytes(n: int32): tBytes;
begin
  result := nil;
  if n = 0 then exit;
  if midByte then
    error('Unaligned readBytes');
  if n > (len-fPos) then
    error(Format('Read over end of stream, requested, %d bytes but only %d remain.', [n,  (len - fpos)]));

  system.setLength(result, n);
  move(bytes[fPos], result[0], n);
  fPos += n;
end;

{read a block from stream into variable}
procedure tStream.readBlock(var x;numBytes: int32);
begin
  if numBytes = 0 then exit;
  if midByte then error('Unaligned readBlock');
  if numBytes > (len-fPos) then
    error(Format('Read over end of stream, requested, %d bytes but only %d remain.', [numBytes,  (fPos + numBytes)]));
  move(bytes[fPos], x, numBytes);
  fPos += numBytes;
end;

{write a block from stream into variable}
procedure tStream.writeBlock(var x;numBytes: int32);
begin
  if numBytes = 0 then exit;
  if midByte then error('unaligned writeBlock');
  setLength(fPos + numBytes);
  move(x, self.bytes[fPos], numBytes);
  inc(fPos, numBytes);
end;

{writes memory stream to file}
procedure tStream.writeToFile(fileName: string);
var
  f: file;
  bytesWritten: dword;
  ioError: word;
begin
  {$i-}
  assignFile(f, fileName);
  rewrite(f,1);
  ioError := IORESULT; if ioError <> 0 then error(format('Could not open file for writing "%s", Error:%s', [filename, getIOErrorString(ioError)]));
  blockwrite(f, bytes[0], bytesUsed, bytesWritten);
  ioError := IORESULT; if ioError <> 0 then error(format('Could not write to file "%s", Error:%s', [filename, getIOErrorString(ioError)]));
  close(f);
  {$i+}
end;

{loads memory stream from file, and resets position to start of stream.}
procedure tStream.readFromFile(fileName: string; blockSize: int32=4096);
var
  f: file;
  bytesRead: dword;
  bytesRemaining: dword;
  bytesToRead: dword;
  ioError: word;
begin

  {$i-}
  assignFile(f, fileName);
  system.reset(f,1);
  ioError := IOResult; if ioError <> 0 then error(format('Could not open file "%s" for reading, Error:%s', [filename, getIOErrorString(ioError)]));
  {$i+}

  setCapacity(fileSize(f));
  bytesRemaining := filesize(f);
  bytesUsed := fileSize(f);
  fPos := 0;
  while bytesRemaining > 0 do begin
    bytesToRead := min(blockSize, bytesRemaining);
    blockread(f, bytes[fPos], bytesToRead, bytesRead);
    if bytesRead <> bytesToRead then
      error(format('Error reading from file "%s", expected to read %d bytes but read %d', [bytesToRead, bytesRead]));
    bytesRemaining -= bytesRead;
    fPos += bytesRead;
  end;
  close(f);
  seek(0);
  midByte := False;
end;

procedure tStream.byteAlign(); inline;
{writes a nibble if we are halfway though a nibble}
begin
  if midByte then writeNibble(0);
end;

procedure tStream.seek(aPos: dword; aMidByte: boolean=False);
begin
  fPos := aPos;
  midByte := aMidByte;
  {note: we'll get an error if we seek beyond capacity}
  if bytesUsed < fPos then bytesUsed := fPos;
end;

{advance the current position this many bytes}
procedure tStream.advance(numBytes: integer);
begin
  fPos += numBytes;
end;

{write a variable length encoded token

Encoding is as follows

with most signficant nibbles on the right.

(todo: check this is still right)

xxx0               (0-7)
xxx1xxx0           (8-63)
xxx1xxx1xxx0       (64-511)
xxx1xxx1xxx1xxx0   (512-4095)

Note: codes in the form

0000xxx1
...

are out of band, and used for control codes

}
{todo: remove this from stream... we will no longer support it or
 nibble writing}
procedure tStream.writeVLC(value: dword);
begin
  {this is the nibble aligned method}
  while true do begin
    if value < 8 then begin
      writeNibble(value);
      exit;
    end else begin
      writeNibble($8+(value and $7));
      value := value shr 3;
    end;
  end;
end;

function tStream.readVLCSegment(n: int32;outBuffer: tDwords=nil): tDWords;
begin
  result := vlc.readSegment(self, n, outBuffer);
end;

function tStream.writeVLCSegment(values: array of dword;segmentType:byte=255): int32;
begin
  result := vlc.writeSegment(self, values, segmentType);
end;

procedure tStream.flush();
begin
  {not used for memory stream}
end;

procedure tStream.reset();
begin
  freeMem(bytes); bytes := nil;
  bytesUsed := 0;
  bytesAllocated := 0;
  fPos := 0;
  midByte := false;
end;

{Reset stream, but keep previous capcity}
procedure tStream.softReset();
begin
  bytesUsed := 0;
  fPos := 0;
  midByte := false;
end;

function tStream.asBytes(): tBytes;
begin
  result := nil;
  if bytesUsed = 0 then exit;
  system.setLength(result, bytesUsed);
  move(bytes^, result[0], bytesUsed);
end;

{returns pointer to current byte... use with caution.}
function tStream.getCurrentBytesPtr: pointer;
begin
  result := @bytes[fPos];
end;

{---------------------------------------------------------------}

procedure runBenchmark();
var
  s: tStream;
  i: int32;
  startTime, endTime: double;
begin
  startTime := getSec;
  s := tStream.Create();
  for i := 1 to 1024 do
    s.writeByte(255);
  endTime := getSec;
  writeln('Wrote 1kb at ',1024/(endTime-startTime)/1024/1024:3:3,' MB/s');
  s.free;

  startTime := getSec;
  s := tStream.Create();
  for i := 1 to 64*1024 do
    s.writeByte(255);
  endTime := getSec;
  writeln('Wrote 64kb at ',64*1024/(endTime-startTime)/1024/1024:3:3,' MB/s');
  s.free;
end;

{-------------------------------------------}

type
  tStreamTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tStreamTest.run();
var
  s: tStream;
  i: integer;
  w: word;
  bitsStream: tStream;
  data: tDWords;
  bits: byte;
const
  testData1: array of dword = [1000, 0, 1000, 32, 15, 16, 17];
  testData2: array of dword = [100, 0, 127, 32, 15, 16, 17];
  {this will get packed}
  testData3: array of dword = [15, 14, 0, 15, 15, 12, 11];
  {this will be packed to 5 bits}
  testData4: array of dword = [31, 31, 31, 31, 31, 31, 31];
begin

  {check nibble}
  s := tStream.Create();
  for i := 0 to 15 do
    s.writeNibble(i);
  assertEqual(s.len, 8);
  s.writeToFile('tmp.dat');
  s.free;

  s := tStream.Create();
  s.readFromFile('tmp.dat');
  assertEqual(s.len, 8);
  for i := 0 to 15 do
    assertEqual(s.readNibble, i);
  s.free;

  {check bytes}
  s := tStream.Create();
  for i := 1 to 16 do
    s.writeByte(i);
  assertEqual(s.len, 16);
  s.writeToFile('tmp.dat');
  s.free;

  s := tStream.Create();
  s.readFromFile('tmp.dat');
  assertEqual(s.len, 16);
  for i := 1 to 16 do
    assertEqual(s.readByte, i);
  s.free;

  {check words}
  s := tStream.Create();
  for i := 1 to 16 do
    s.writeWord(256+i);
  assertEqual(s.len, 32);
  s.writeToFile('tmp.dat');
  s.free;

  s := tStream.Create();
  s.readFromFile('tmp.dat');
  assertEqual(s.len, 32);
  for i := 1 to 16 do
    assertEqual(s.readWord, 256+i);
  s.free;

  {check as bytes}
  s := tStream.Create();
  s.writeByte(5);
  s.writeByte(9);
  s.writeByte(2);
  assertEqual(s.asBytes, [5,9,2]);
  s.free;

  {check writeBytes}
  s := tStream.Create();
  s.writeByte(1);
  s.writeBytes([2,3,4]);
  s.writeByte(5);
  assertEqual(s.asBytes, [1,2,3,4,5]);
  s.free;

end;

{--------------------------------------------------}

initialization
  tStreamTest.create('Stream');
end.
