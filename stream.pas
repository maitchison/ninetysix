{A very simple stream class}
unit stream;

{$MODE Delphi}

{todo: borrow most of LZBlock}

interface

uses
	utils,
  debug,
	test;

type
	tStream = class

  	{
    note on position
    pos is our current position within the buffer.
    valid bytes are considred to be [0..pos-1]

    capacity length(bytes) is always >= pos
    setting pos := 0 is a 'soft clear', as in does not change the capacitiy.
    }

  protected
  	bytes: tBytes;   {length(bytes) is the capcity}
    bytesLen: dword; {bytesLen is the number of actual bytes used}
    pos: int32;
    midByte: boolean;

  private
  	procedure makeCapacity(n: dword); inline;
  	procedure setCapacity(n: dword); inline;
		procedure setLength(n: dword); inline;

    function getByte(index: dword): byte; inline;
    procedure setByte(index: dword; value: byte); inline;

  public

    constructor Create(aInitialCapacity: dword=0);
    class function FromFile(filename: string): tStream; static;

  	property items[index: dword]: byte read getByte write setByte; default;

    procedure writeNibble(b: byte); inline;
    procedure writeByte(b: byte); inline;
    procedure writeWord(w: word); inline;
    procedure writeVLC(value: dword); inline;
    function VLCbits(value: dword): word; inline;

    procedure writeBytes(aBytes: tBytes);

    function  readByte: byte; inline;
    function  readWord: word; inline;

    procedure byteAlign(); inline;

		procedure writeToDisk(fileName: string);
    procedure readFromDisk(fileName: string);

    function  capacity: int32; inline;
    function  len: int32; inline;

    procedure reset();
		procedure softReset();

    function  asBytes: tBytes;

  end;


implementation

{------------------------------------------------------}

constructor tStream.Create(aInitialCapacity: dword=0);
begin
	bytes := nil;
  pos := 0;
  bytesLen := 0;
  midByte := False;
  if aInitialCapacity > 0 then
  	makeCapacity(aInitialCapacity);
end;

class function tStream.FromFile(filename: string): tStream; static;
begin
	result := tStream.Create();
  result.readFromDisk(filename);
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

procedure tStream.setCapacity(n: dword); inline;
begin
	system.setLength(bytes, n);
  if bytesLen > length(bytes) then
  	bytesLen := length(bytes); {byteslen can not be more than actaul buffer size}	
end;

procedure tStream.makeCapacity(n: dword); inline;
begin
	if length(bytes) < n then
		setCapacity(n);
end;

{expand (or contract) the length this many bytes}
{note: we never shrink the capacity here.}
procedure tStream.setLength(n: dword); inline;
begin
	makeCapacity(n);
	bytesLen := n;
end;


{------------------------------------------------------}

procedure tStream.writeNibble(b: byte); inline;
begin
	{$IFDEF debug}
	if (b and $f) <> b then
  	Error('Invalid nibble value '+intToStr(b));
	{$ENDIF}

	if midByte then begin
		bytes[pos] := bytes[pos] or (b shl 4);  	
  	midByte := false;
    inc(pos);
  end else begin
    setLength(pos+1);
	  bytes[pos] := b;
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
  setLength(pos+1);
  bytes[pos] := b;
  inc(pos);
end;

procedure tStream.writeWord(w: word); inline;
begin
	if midByte then begin
  	writeNibble((w shr 0) and $f);
  	writeByte((w shr 4) and $ff);
  	writeNibble((w shr 12) and $f);
    exit;
  end;
  setLength(pos+2);
  {little edian}
  bytes[pos] := w and $FF;
  bytes[pos+1] := w shr 8;
  inc(pos,2);
end;

procedure tStream.writeBytes(aBytes: tBytes);
var
	i: dword;
begin
	byteAlign();
  setLength(pos + length(bytes));
  move(aBytes[0], self.bytes[pos], length(aBytes));
end;

function tStream.readByte: byte; inline;
begin
  result := bytes[pos];
  inc(pos);
end;

function tStream.readWord: word; inline;
begin
  result := bytes[pos] + (bytes[pos+1] shl 8);
  inc(pos,2);
end;

{writes memory stream to disk}
procedure tStream.writeToDisk(fileName: string);
var
	f: file;
  bytesWritten: dword;
begin
	assignFile(f, fileName);
  rewrite(f,1);
  blockwrite(f, bytes[0], bytesLen, bytesWritten);
  close(f);
end;

{loads memory stream from disk, and resets position to start of stream.}
procedure tStream.readFromDisk(fileName: string);
var
	f: file;
  bytesRead: dword;
begin
	assignFile(f, fileName);
  system.reset(f,1);
  system.setLength(bytes, fileSize(f));
  bytesLen := length(bytes);
  blockread(f, bytes[0], length(bytes), bytesRead);
  close(f);
  pos := 0;
end;

function tStream.len(): int32; inline;
begin
	result := bytesLen;
end;

function tStream.capacity(): int32; inline;
begin
	result := length(bytes);
end;

procedure tStream.byteAlign(); inline;
{writes a nibble if we are halfway though a nibble}
begin
	if midByte then writeNibble(0);
end;

{write a variable length encoded token}
procedure tStream.writeVLC(value: dword);
begin
	{this is the nibble aligned method}
  while True do begin
    if value <= 7 then begin
    	writeNibble(value);
      exit;
    end else begin
    	writeNibble($8+(value and $7));
      value := value shr 3;
    end;	
  end;
end;

{returns size of variable length encoded token}
function tStream.VLCbits(value: dword): word;
begin
	result := 0;
	{this is the nibble aligned method}
  while True do begin
    if value <= 7 then begin
    	result += 4;
      exit;
    end else begin
    	result += 4;
      value := value shr 3;
    end;	
  end;
end;

procedure tStream.reset();
begin
	system.setLength(bytes, 0);
  bytesLen := 0;
  pos := 0;
end;

{Reset stream, but keep previous capcity}
procedure tStream.softReset();
begin
  bytesLen := 0;
  pos := 0;
end;

function tStream.asBytes(): tBytes;
begin
	if bytesLen = 0 then
  	exit(nil);

	if bytesLen = length(self.bytes) then
  	{just output a reference}
		exit(self.bytes);

  {
  ok, so we have a size missmatch, passing bytes would have the wrong
  length.
	We have two options
  	1. Create a fake tBytes with the correct length
    2. Create a new tBytes and copy accross the data.
  Option 2 is safest, as I don't know if the runtime will change how
  dynamic arrays work. Also, option 1 might not work if the object tries
  to free it's memory.
  }
  result := nil;
  system.setLength(result, bytesLen);
  move(bytes[0], result[0], bytesLen);
end;

{---------------------------------------------------------------}

procedure runTests();
var	
	s: tStream;
  i: integer;
begin

	{check bytes}
  s := tStream.Create();
	for i := 1 to 16 do
  	s.writeByte(i);
  assertEqual(s.len, 16);
  s.writeToDisk('tmp.dat');
  s.free;

  s := tStream.Create();
  s.readFromDisk('tmp.dat');
  assertEqual(s.len, 16);
	for i := 1 to 16 do
  	assertEqual(s.readByte, i);
  s.free;

	{check words}
  s := tStream.Create();
	for i := 1 to 16 do
  	s.writeWord(256+i);
  assertEqual(s.len, 32);
  s.writeToDisk('tmp.dat');
  s.free;

  s := tStream.Create();
  s.readFromDisk('tmp.dat');
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

end;

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


begin	
	runTests();
end.
