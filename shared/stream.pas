{A very simple stream class}
unit stream;

{$MODE Delphi}

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

    procedure writeByte(b: byte); inline;
    procedure writeWord(w: word); inline;
    procedure writeDWord(d: dword); inline;
    procedure writeVLC8(value: dword); inline;
    function  writeSegment(values: array of dword;segmentType:byte=255): int32;

    procedure setSize(newSize: int32);

    procedure writeChars(s: string);
    procedure writeBytes(aBytes: tBytes;aLen:int32=-1);
    procedure writeBlock(var x;numBytes: int32);

    function  peekByte: byte; inline;
    function  peekWord: word; inline;
    function  peekDWord: dword; inline;

    function  readByte: byte; inline;
    function  readWord: word; inline;
    function  readDWord: dword; inline;
    function  readVLC8: dword; inline;
    function  readSegment(n: int32;outBuffer: tDwords=nil): tDWords;
    function  readBytes(n: int32): tBytes;
    procedure readBlock(var x;numBytes: int32);

    procedure seek(aPos: dword);
    procedure advance(numBytes: integer);

    procedure writeToFile(fileName: string);
    procedure readFromFile(fileName: string; blockSize: int32=4096;maxSize: int32=-1);

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
  filesystem,
  vlc;

{------------------------------------------------------}

constructor tStream.Create(aInitialCapacity: dword=0);
begin
  inherited Create();
  bytes := nil;
  bytesAllocated := 0;
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

procedure tStream.writeByte(b: byte); inline;
begin
  setLength(fPos+1);
  bytes[fPos] := b;
  inc(fPos);
end;

procedure tStream.writeWord(w: word); inline;
begin
  setLength(fPos+2);
  {little edian}
  bytes[fPos] := w and $FF;
  bytes[fPos+1] := w shr 8;
  inc(fPos,2);
end;

procedure tStream.writeDWord(d: dword); inline;
begin
  setLength(fPos+4);
  {little edian}
  bytes[fPos] := d and $ff;
  bytes[fPos+1] := (d shr 8) and $ff;
  bytes[fPos+2] := (d shr 16) and $ff;
  bytes[fPos+3] := (d shr 24) and $ff;
  inc(fPos,4);
end;

procedure tStream.writeVLC8(value: dword); inline;
begin
  while value >= 128 do begin
    writeByte($80 + value and $7f);
    value := value shr 7;
  end;
  writeByte($00 + value);
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
  if aLen > length(aBytes) then error('tried writing too many bytes');
  setLength(fPos + aLen);
  move(aBytes[0], self.bytes[fPos], aLen);
  inc(fPos, aLen);
end;

function tStream.readByte: byte; inline;
begin
  result := bytes[fPos];
  inc(fPos);
end;

function tStream.readWord: word; inline;
begin
  result := pWord(bytes + fPos)^;
  inc(fPos,2);
end;

function tStream.readDWord: dword; inline;
begin
  result := pDWord(bytes + fPos)^;
  inc(fPos,4);
end;

function tStream.readVLC8: dword; inline;
var b: byte;
begin
  result := 0;
  repeat
    b := readByte();
    if b < 128 then begin
      result := result or b;
      exit;
    end else begin
      result := result or (b-128);
      result := result shl 7;
    end;
  until false;
end;

function tStream.peekByte: byte; inline;
begin
  result := bytes[fPos];
end;

function tStream.peekWord: word; inline;
begin
  result := pWord(bytes + fPos)^;
end;

function tStream.peekDWord: dword; inline;
begin
  result := pDWord(bytes + fPos)^;
end;

function tStream.readBytes(n: int32): tBytes;
begin
  result := nil;
  if n = 0 then exit;
  if n > (len-fPos) then
    error(Format('Read over end of stream, requested, %d bytes but %d remain.', [n,  len - fpos]));
  system.setLength(result, n);
  move(bytes[fPos], result[0], n);
  fPos += n;
end;

{read a block from stream into variable}
procedure tStream.readBlock(var x;numBytes: int32);
begin
  if numBytes = 0 then exit;
  if numBytes > (len-fPos) then
    error(Format('Read over end of stream, requested, %d bytes but %d remain.', [numBytes,  len-fPos]));
  move(bytes[fPos], x, numBytes);
  fPos += numBytes;
end;

{write a block from stream into variable}
procedure tStream.writeBlock(var x; numBytes: int32);
begin
  if numBytes = 0 then exit;
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
procedure tStream.readFromFile(fileName: string; blockSize: int32=4096; maxSize: int32=-1);
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

  {work out how much to read}
  if maxSize > 0 then
    bytesToRead := min(maxSize, filesize(f))
  else
    bytesToRead := filesize(f);
  bytesRemaining := bytesToRead;
  setCapacity(bytesToRead);
  bytesUsed := bytesToRead;

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
end;

procedure tStream.seek(aPos: dword);
begin
  fPos := aPos;
  if bytesUsed < fPos then bytesUsed := fPos;
end;

{advance the current position this many bytes}
procedure tStream.advance(numBytes: integer);
begin
  fPos += numBytes;
end;

function tStream.readSegment(n: int32;outBuffer: tDwords=nil): tDWords;
begin
  result := vlc.readSegment(self, n, outBuffer);
end;

function tStream.writeSegment(values: array of dword;segmentType:byte=255): int32;
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
end;

{Reset stream, but keep previous capcity}
procedure tStream.softReset();
begin
  bytesUsed := 0;
  fPos := 0;
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

  {check vlc}
  s := tStream.Create();
  for i := 0 to length(testData1)-1 do
    s.writeVLC8(testData1[i]);
  s.seek(0);
  for i := 0 to length(testData1)-1 do
    assertEqual(s.readVLC8, testData1[i]);
  s.free;

  filesystem.fs.delFile('tmp.dat');

end;

{--------------------------------------------------}

initialization
  tStreamTest.create('Stream');
end.
