{A very simple stream class}
unit stream;

{$MODE Delphi}

interface

uses
  utils,
  debug,
  myMath,
  sysTypes,
  filesystem,
  test;

const
  FS_READBUFFER_SIZE = 16*1024;

type
  tStream = class

  protected
    fPos: int32;        {current position in stream}
    fLen: int32;        {length of stream}

    procedure setLen(newLen: int32); virtual;
    procedure expandLen(n: int32);

  public

    constructor create();
    destructor destroy(); override;

    {derived}
    function  peekByte: byte; inline;
    function  peekWord: word; inline;
    function  peekDWord: dword; inline;
    function  readVLC8: dword; inline;
    function  readByte: byte; virtual;
    function  readWord: word; virtual;
    function  readDWord: dword; virtual;
    procedure writeByte(b: byte); virtual;
    procedure writeWord(w: word); virtual;
    procedure writeDWord(d: dword); virtual;
    function  asBytes(): tBytes;
    procedure writeChars(s: string);
    procedure writeVLC8(value: dword);
    function  readBytes(n: int32): tBytes;
    procedure writeBytes(aBytes: tBytes;aLen:int32=-1);
    function  readSegment(n: int32;outBuffer: tDwords=nil): tDWords;
    function  writeSegment(values: array of dword;segmentType:byte=255): int32;

    procedure advance(numBytes: integer);

    {base functions for other classes to implement}
    procedure seek(aPos: int32); virtual;
    procedure flush(); virtual;
    procedure reset(); virtual;
    procedure readBlock(out x;numBytes: int32); virtual; abstract;
    procedure writeBlock(var x;numBytes: int32); virtual; abstract;

    {for direct access}
    function  getCurrentBytesPtr(requestedBytes: int32=0): pointer; virtual;

    {properties}
    property  len: int32 read fLen write setLen;
    property  pos: int32 read fPos write seek;
  end;

  {implements stream with an in-memory buffer

  tMemoryStream makes use of a 'capacity' which are the number of bytes
  allocated in the bytesBuffer. This will always be >= len.
  Bytes at address >= len have undefined value.
  }
  tMemoryStream = class(tStream)
  protected
    bytes: pByte;
    fCapacity: int32;   {capacity is how much memory we allocated}

  protected
    procedure makeCapacity(n: int32);
    procedure setCapacity(newSize: dword);
    procedure setLen(n: int32); override;
  public
    constructor create(aInitialCapacity: dword=0);
    destructor destroy(); override;

    {our core overrides}
    procedure seek(aPos: int32); override;
    procedure flush(); override;
    procedure reset(); override;
    function  getCurrentBytesPtr(requestedBytes: int32=0): pointer; override;

    {soft reset does not freem memory and maintains capacity}
    procedure softReset();

    {helpers}
    class function fromFile(filename: string): tMemoryStream; static;
    procedure writeToFile(fileName: string);
    procedure readFromFile(fileName: string; blockSize: int32=4096;maxSize: int32=-1);

    {our r/w override}
    function  readByte: byte; override;
    function  readWord: word; override;
    function  readDWord: dword; override;
    procedure readBlock(out x;numBytes: int32); override;
    procedure writeByte(b: byte); override;
    procedure writeWord(w: word); override;
    procedure writeDWord(d: dword); override;
    procedure writeBlock(var x;numBytes: int32); override;

    {properties}
    property  capacity: int32 read fCapacity;

  end;

  {Unbuffered filestream}
  tFileStream = class(tStream)
  protected
    f: file;
    // Just a read buffer for the moment... write buffer to come later.
    bufferPos: int32; // index of first byte in buffer.
    bufferLen: int32; // number of valid bytes in buffer.
    buffer: array[0..FS_READBUFFER_SIZE-1] of byte;
    procedure moveBuffer(aPos: int32);
    procedure requestBufferBytes(aPos, numBytes: int32);
  public

    constructor create(aFilename: string; fileMode: tFileMode=FM_READ);
    destructor destroy(); override;

    {our core overrides}
    procedure seek(aPos: int32); override;
    procedure flush(); override;
    procedure reset(); override;

    {our r/w override}
    procedure readBlock(out x;numBytes: int32); override;
    procedure writeBlock(var x;numBytes: int32); override;

  end;


implementation

uses
  vlc;

{------------------------------------------------------}
{ tStream }
{------------------------------------------------------}

constructor tStream.create();
begin
  inherited create();
  if self.classType = tStream then
    error('Attempted to instantiate an abstract class: tStream');
  fPos := 0;
  fLen := 0;
end;

destructor tStream.destroy();
begin
  inherited destroy;
end;

procedure tStream.setLen(newLen: int32);
begin
  fLen := newLen;
end;

procedure tStream.seek(aPos: int32);
begin
  fPos := aPos;
end;

procedure tStream.flush();
begin
  // nop
end;

procedure tStream.reset();
begin
  fPos := 0;
  fLen := 0;
end;

{expand the length this many bytes, will not contract length}
procedure tStream.expandLen(n: int32);
begin
  if fLen < n then setLen(n);
end;

function tStream.peekByte: byte; inline;
begin
  result := readByte;
  advance(-1);
end;

function tStream.peekWord: word; inline;
begin
  result := readWord;
  advance(-2);
end;

function tStream.peekDWord: dword; inline;
begin
  result := readDWord;
  advance(-4);
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

function tStream.readVLC8: dword; inline;
var
  b: byte;
  shift: byte;
begin
  result := 0;
  shift := 0;
  repeat
    b := readByte();
    if b < 128 then begin
      result := result or (b shl shift);
      exit;
    end else begin
      result := result or (dword(b-128) shl shift);
      shift += 7;
    end;
  until false;
end;

function tStream.readBytes(n: int32): tBytes;
begin
  result := nil;
  if n = 0 then exit;
  if n > (len-fPos) then
    error(Format('Read over end of stream, requested, %d bytes but %d remain.', [n,  len - fpos]));
  setLength(result, n);
  readBlock(result[0], n);
end;

procedure tStream.writeBytes(aBytes: tBytes;aLen:int32=-1);
begin
  if aLen < 0 then aLen := length(aBytes);
  if aLen = 0 then exit;
  if aLen > length(aBytes) then error('tried writing too many bytes');
  expandLen(fPos + aLen);
  writeBlock(aBytes[0], aLen);
end;

procedure tStream.writeByte(b: byte);
begin
  writeBlock(b, 1)
end;

procedure tStream.writeWord(w: word);
begin
  writeBlock(w, 2)
end;

procedure tStream.writeDWord(d: dword);
begin
  writeBlock(d, 4)
end;

function tStream.readByte: byte;
var
  b: byte;
begin
  readBlock(b, 1); result := b;
end;

function tStream.readWord: word;
var
  w: word;
begin
  readBlock(w, 2); result := w;
end;

function tStream.readDWord: dword;
var
  d: dword;
begin
  readBlock(d, 4); result := d;
end;

function tStream.readSegment(n: int32;outBuffer: tDwords=nil): tDWords;
begin
  result := vlc.readSegment(self, n, outBuffer);
end;

function tStream.writeSegment(values: array of dword;segmentType:byte=255): int32;
begin
  result := vlc.writeSegment(self, values, segmentType);
end;


{this is very slow. Make a copy of the entire stream from start to end
 as a tBytes}
function tStream.asBytes(): tBytes;
begin
  result := nil;
  if flen = 0 then exit;
  seek(0);
  setLength(result, fLen);
  readBlock(result[0], fLen);
end;

{advance the current position this many bytes}
procedure tStream.advance(numBytes: integer);
begin
  seek(fpos + numBytes);
end;

{returns a pointer to a buffer containing (atleast) the next
 'requestedBytes' bytes. Not all streams will implement this
 method, in which case they will return nil. Writing this this
 buffer is strongly discouraged.}
function tStream.getCurrentBytesPtr(requestedBytes: int32): pointer;
begin
  result := nil;
end;

{-------------------------------------------}
{ tMemoryStream }
{-------------------------------------------}

constructor tMemoryStream.create(aInitialCapacity: dword=0);
begin
  inherited create();
  bytes := nil;
  fCapacity := 0;
  if aInitialCapacity > 0 then
    makeCapacity(aInitialCapacity)
end;

destructor tMemoryStream.destroy();
begin
  freeMem(bytes); bytes := nil;
  inherited destroy;
end;

class function tMemoryStream.FromFile(filename: string): tMemoryStream; static;
begin
  result := tMemoryStream.Create();
  result.readFromFile(filename);
end;

{-------------------------------------------}

{process all pending writes}
procedure tMemoryStream.flush();
begin
  {not used for memory stream}
end;

{resets stream, freeing all memory.}
procedure tMemoryStream.reset();
begin
  freeMem(bytes); bytes := nil;
  fPos := 0;
  fLen := 0;
  fCapacity := 0;
end;

{reset stream, but keep memory allocation}
procedure tMemoryStream.softReset();
begin
  fLen := 0;
  fPos := 0;
end;

function tMemoryStream.getCurrentBytesPtr(requestedBytes: int32=0): pointer;
begin
  result := @bytes[fPos];
end;

{-------------------------------------------}

{updates stream so that it has this much capacity.
Will truncate down if needed.
What get's modified
 - Pos: no change
 - ByteSize: >= newSize
 - ByteUsed: truncated down to newSize
}
procedure tMemoryStream.setCapacity(newSize: dword);
var
  blocks: int32;
begin

  blocks := (newSize+1023) div 1024;

  {quick check to make sure everythings ok}
  if assigned(bytes) <> (fCapacity > 0) then
    error('Looks like stream was not initialized.');

  if blocks=0 then begin
    freeMem(bytes);
  end else begin
    reallocMem(bytes, blocks*1024);
    if bytes = nil then error('Could not allocate memory block');
  end;

  fCapacity := blocks*1024;

  {truncate if needed}
  if fLen > newSize then
    fLen := newSize;
end;

procedure tMemoryStream.seek(aPos: int32);
begin
  if aPos > fLen then error(format('Seek past end of file (seek to %,/%,).', [aPos, fLen]));
  fPos := aPos;
end;

{makes sure the stream has capacity for *atleast* n bytes}
procedure tMemoryStream.makeCapacity(n: int32);
begin
  if fCapacity < n then
    {resize might require a copy, so always increase size by atleast 5%}
    setCapacity(max(dword(n), dword(int64(fCapacity)*105 div 100)));
end;

{expand (or contract) the length this many bytes}
{note: we never shrink the capacity here.}
procedure tMemoryStream.setLen(n: int32);
begin
  makeCapacity(n);
  flen := n;
end;

{------------------------------------------------------}

procedure tMemoryStream.writeByte(b: byte);
begin
  expandLen(fPos+1);
  bytes[fPos] := b;
  inc(fPos);
end;

procedure tMemoryStream.writeWord(w: word);
begin
  expandLen(fPos+2);
  pWord(bytes + fPos)^ := w;
  inc(fPos, 2);
end;

procedure tMemoryStream.writeDWord(d: dword);
begin
  expandLen(fPos+4);
  pDWord(bytes + fPos)^ := d;
  inc(fPos, 4);
end;

function tMemoryStream.readByte: byte;
begin
  result := bytes[fPos];
  inc(fPos);
end;

function tMemoryStream.readWord: word;
begin
  result := pWord(bytes + fPos)^;
  inc(fPos,2);
end;

function tMemoryStream.readDWord: dword;
begin
  result := pDWord(bytes + fPos)^;
  inc(fPos,4);
end;

{read a block from stream into variable}
procedure tMemoryStream.readBlock(out x;numBytes: int32);
begin
  if numBytes = 0 then exit;
  if numBytes > (len-fPos) then
    error(Format('Read over end of stream, requested, %d bytes but %d remain.', [numBytes,  len-fPos]));
  move(bytes[fPos], x, numBytes);
  fPos += numBytes;
end;

{write a block from stream into variable}
procedure tMemoryStream.writeBlock(var x; numBytes: int32);
begin
  if numBytes = 0 then exit;
  expandLen(fPos + numBytes);
  move(x, self.bytes[fPos], numBytes);
  inc(fPos, numBytes);
end;

{loads memory stream from file, and resets position to start of stream.}
procedure tMemoryStream.readFromFile(fileName: string; blockSize: int32=4096; maxSize: int32=-1);
var
  f: file;
  bytesRead: dword;
  bytesRemaining: dword;
  bytesToRead: dword;
  ioError: word;
begin

  fs.openFile(filename, f, FM_READ);

  try
    {work out how much to read}
    if maxSize > 0 then
      bytesToRead := min(maxSize, filesize(f))
    else
      bytesToRead := filesize(f);
    bytesRemaining := bytesToRead;
    setCapacity(bytesToRead);
    flen := bytesToRead;

    fPos := 0;
    while bytesRemaining > 0 do begin
      bytesToRead := min(blockSize, bytesRemaining);
      blockread(f, bytes[fPos], bytesToRead, bytesRead);
      if bytesRead <> bytesToRead then
        error(format('Error reading from file "%s", expected to read %d bytes but read %d', [bytesToRead, bytesRead]));
      bytesRemaining -= bytesRead;
      fPos += bytesRead;
    end;
    seek(0);
  finally
    close(f);
  end;
end;

{writes memory stream to file}
procedure tMemoryStream.writeToFile(fileName: string);
var
  f: file;
  bytesWritten: dword;
  ioError: word;
begin
  {$i-}
  assignFile(f, fileName);
  rewrite(f,1);
  ioError := IORESULT; if ioError <> 0 then error(format('Could not open file for writing "%s", Error:%s', [filename, getIOErrorString(ioError)]));
  bytesWritten := 0;
  blockWrite(f, bytes[0], len, bytesWritten);
  ioError := IORESULT; if ioError <> 0 then error(format('Could not write to file "%s", Error:%s', [filename, getIOErrorString(ioError)]));
  close(f);
  {$i+}
end;

{---------------------------------------------}

constructor tFileStream.create(aFilename: string; fileMode: tFileMode=FM_READ);
var
  oldFileMode: word;
begin

  reset();

  oldFileMode := system.fileMode;
  system.fileMode := byte(fileMode);

  {todo: use filesystem for this...}
  case fileMode of
    FM_READ: begin
      {open file for read only}
      if not fs.exists(aFilename) then error('Could not open "'+aFilename+'" for reading');
      system.assign(f, aFilename);
      system.reset(f,1);
      fLen := filesize(f);
    end;
    FM_WRITE: begin
      {creates a new file, or overwrites it if it exists}
      system.assign(f, aFilename);
      system.rewrite(f,1);
      fLen := 0;
    end;
    FM_READWRITE: begin
      {if file exists it is opened, with pos at the start of the file,
       and the ability to both read and write to it}
      if fs.exists(aFilename) then begin
        system.assign(f, aFilename);
        system.rewrite(f,1);
        system.reset(f,1);
        fLen := filesize(f);
      end else begin
        system.assign(f, aFilename);
        system.rewrite(f,1);
        fLen := 0;
      end;
    end;
    else error(format('Invalid fileMode %d', [fileMode]));
  end;

  system.fileMode := oldFileMode;

end;

destructor tFileStream.destroy();
begin
  flush();
  close(f);
  inherited destroy();
end;

procedure tFileStream.seek(aPos: int32);
begin
  fPos := aPos;
end;

procedure tFileStream.flush();
begin
  // when we use buffering we'll have to write out our buffer here.
end;

procedure tFileStream.reset();
begin
  fPos := 0;
  fLen := 0;
  fillchar(buffer, sizeof(buffer), 0);
  bufferPos := 0;
  bufferLen := 0;
end;

procedure tFileStream.readBlock(out x;numBytes: int32);
begin
  {direct read for large blocks}
  if (numBytes > FS_READBUFFER_SIZE div 2) then begin
    system.seek(f, fPos);
    blockRead(f, x, numBytes)
  end else begin
    requestBufferBytes(fPos, numBytes);
    move(buffer[fPos - bufferPos], x, numBytes);
  end;
  fPos += numBytes;
end;

procedure tFileStream.writeBlock(var x;numBytes: int32);
begin
  system.seek(f, pos);
  blockWrite(f, x, numBytes);
  fPos += numBytes;
  if fPos > fLen then fLen := fPos;
end;

{-------------------------------------------}

{move the buffer such that the bytes [fpos..fpos+numBytes) are contained somewhere within it}
procedure tFileStream.requestBufferBytes(aPos, numBytes: int32);
var
  delta: int32;
begin
  {
  note: this isn't very efficent, especially for rewinding
  we could improve this by moving with 4k alignment, and copying
  the parts of the buffer that remain the same.
  however for sequential reading, this is ok for the moment
  although reading, say 33k at a time would be bad
  }
  delta := aPos - bufferPos;
  if delta < 0 then begin
    {requested before the buffer so move it}
    moveBuffer(aPos);
  end else begin
    {requested after the buffer so move it}
    if delta + numBytes > bufferLen then begin
      moveBuffer(aPos);
    end;
  end;
end;

procedure tFilestream.moveBuffer(aPos: int32);
begin
  bufferPos := aPos;
  bufferLen := min(FS_READBUFFER_SIZE, len - aPos);
  if bufferLen > 0 then begin
    system.seek(f, bufferPos);
    system.blockRead(f, buffer[0], bufferLen);
  end;
end;

{-------------------------------------------}

type
  tStreamTest = class(tTestSuite)
    procedure run; override;
    procedure testFileStream();
    procedure testMemoryStream();
  end;

procedure tStreamTest.run();
begin
  testMemoryStream();
  testFileStream();
end;

procedure tStreamTest.testFileStream();
var
  fs: tFileStream;
  i: integer;
begin
  fs := tFileStream.create('tmp.dat', FM_WRITE);
  for i := 1 to 100 do
    fs.writeByte(i);
  fs.free;

  assertEqual(filesystem.fs.getFilesize('tmp.dat'), 100);

  fs := tFileStream.create('tmp.dat');
  for i := 1 to 100 do
    assertEqual(fs.readByte, i);
  fs.free;

  filesystem.fs.delFile('tmp.dat');
end;

procedure tStreamTest.testMemoryStream();
var
  s: tMemoryStream;
  i: integer;
const
  testData1: array of dword = [1000, 0, 1000, 32, 15, 16, 17];
begin

  {check bytes}
  s := tMemoryStream.create();
  for i := 1 to 16 do
    s.writeByte(i);
  assertEqual(s.len, 16);
  s.writeToFile('tmp.dat');
  s.free;

  s := tMemoryStream.create();
  s.readFromFile('tmp.dat');
  assertEqual(s.len, 16);
  for i := 1 to 16 do
    assertEqual(s.readByte, i);
  s.free;

  {check words}
  s := tMemoryStream.create();
  for i := 1 to 16 do
    s.writeWord(256+i);
  assertEqual(s.len, 32);
  s.writeToFile('tmp.dat');
  s.free;

  s := tMemoryStream.create();
  s.readFromFile('tmp.dat');
  assertEqual(s.len, 32);
  for i := 1 to 16 do
    assertEqual(s.readWord, 256+i);
  s.free;

  {check as bytes}
  s := tMemoryStream.create();
  s.writeByte(5);
  s.writeByte(9);
  s.writeByte(2);
  assertEqual(s.asBytes, [5,9,2]);
  s.free;

  {check writeBytes}
  s := tMemoryStream.create();
  s.writeByte(1);
  s.writeBytes([2,3,4]);
  s.writeByte(5);
  assertEqual(s.asBytes, [1,2,3,4,5]);
  s.free;

  {check vlc}
  s := tMemoryStream.create();
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
