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
    using seek(pos) is a 'soft clear', as in does not change the capacitiy.
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
    procedure writeVLCControlCode(value: dword); inline;
    procedure writeVLCSegment(values: array of dword); inline;
    function  VLCbits(value: dword): word; inline;

		procedure writeChars(s: string);
    procedure writeBytes(aBytes: tBytes);

    function  peekByte: byte; inline;
    function  peekWord: word; inline;

    function  readByte: byte; inline;
		function  readNibble: byte; inline;
    function  readWord: word; inline;
    function  readVLC: dword;
		function  readVLCSegment(n: int32): tDWords;
    function  readBytes(n: int32): tBytes;

    procedure byteAlign(); inline;
    procedure seek(aPos: dword; aMidByte: boolean=False);

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

procedure tStream.writeChars(s: string);
var
	i: integer;
begin
	for i := 1 to length(s) do
  	writeByte(ord(s[i]));	
end;

procedure tStream.writeBytes(aBytes: tBytes);
begin
	if length(aBytes) = 0 then exit;
	byteAlign();
  setLength(pos + length(aBytes));
  move(aBytes[0], self.bytes[pos], length(aBytes));
  inc(pos, length(aBytes));
end;

function tStream.readNibble: byte; inline;
begin
	if midByte then begin
  	result := bytes[pos] shr 4;
  	midByte := false;
    inc(pos);
  end else begin
	  result := bytes[pos] and $f;
  	midByte := true;
  end;	
end;

function tStream.readByte: byte; inline;
begin
	{todo: support halfbyte}
  if midByte then
  	Error('Reading missaligned bytes not yet supported');
  result := bytes[pos];
  inc(pos);
end;

function tStream.readWord: word; inline;
begin
  if midByte then
  	Error('Reading missaligned bytes not yet supported');
  result := bytes[pos] + (bytes[pos+1] shl 8);
  inc(pos,2);
end;

function tStream.peekByte: byte; inline;
begin
	{todo: support halfbyte}
  if midByte then
  	Error('Reading missaligned bytes not yet supported');
  result := bytes[pos];
end;

function tStream.peekWord: word; inline;
begin
  if midByte then
  	Error('Reading missaligned bytes not yet supported');
  result := bytes[pos] + (bytes[pos+1] shl 8);
end;

function tStream.readVLC: dword;
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
    	{todo: support control codes}
    	exit(value);
    end else begin
    	inc(shift, 3);
    end;
  end;	
end;

function tStream.readBytes(n: int32): tBytes;
var
	i: integer;
begin
	if midByte then
  	Error('Misaligned readBytes');
	result := nil;
  system.setLength(result, n);
  move(bytes[pos], result[0], n);
  pos += n;
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
  seek(0);
  midByte := False;
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

procedure tStream.seek(aPos: dword; aMidByte: boolean=False);
begin
	pos := aPos;
  midByte := aMidByte;
end;

{write a variable length encoded token}
procedure tStream.writeVLC(value: dword);
begin
	{stub: logging}
	{this is the nibble aligned method}
  while True do begin
    if value < 8 then begin
    	writeNibble(value);
      exit;
    end else begin
    	writeNibble($8+(value and $7));
      value := value shr 3;
    end;	
  end;
end;

{write a special out-of-band control code.}
procedure tStream.writeVLCControlCode(value: dword);
begin
	{these codes will never appear in normal VLC encoding as they
   would always be encoded using the smaller length.}
  if value < 8 then
	  writeByte($80+value)
  else if value < 512 then
  	writeWord($8000+value)
  else
  	Error('Invalid control code');

end;

function packBits(values: array of dword;bits: byte;outStream: tStream=nil): tStream;
var
	bitBuffer: dword;
  bitPos: integer;
  s: tStream;
  i,j: int32;

procedure writeBit(b: byte);
begin
	bitBuffer += b shl bitPos;
  inc(bitPos);
  if bitPos = 8 then begin
  	s.writeByte(bitBuffer);
    bitBuffer := 0;
  	bitPos := 0;
  end;
end;

begin
  s := outStream;
  if not assigned(s) then
		s := tStream.create();
  result := s;

  {$IFDEF Debug}
	for i := 0 to length(values)-1 do
		if values[i] >= (1 shl bits) then
	  	Error('Value too high');
  {$ENDIF}

  {special cases}
  case bits of
  	0: begin
      {do nothing}
	  	exit;
    end;
    else begin
    	{generic bit packing}
    	bitBuffer := 0;
      bitPos := 0;

      for i := 0 to length(values)-1 do
        for j := 0 to bits-1 do
        	writeBit((values[i] shr j) and $1);

      if bitPos > 0 then
      	s.writeByte(bitBuffer);
    end;
  end;

end;

function unpackBits(s: tStream;bits: byte;n: integer): tDWords;
var
	bitBuffer: byte;
  bitsRemaining: integer;
  i,j: int32;
  value: dword;

function nextBit: byte;
begin
	if bitsRemaining = 0 then begin
  	bitBuffer := s.readByte;
    bitsRemaining := 8;
  end;
  result := bitBuffer and $1;
  bitBuffer := bitBuffer shr 1;
  dec(bitsRemaining);
end;

begin

	result := nil;
  setLength(result, n);
	
  case bits of
  	0: begin
	  	filldword(result[0], n, 0);
  		exit;
	  end;
    else begin
			bitBuffer := s.readByte;
		  bitsRemaining := 8;
		  for i := 0 to n-1 do begin
  			{this could be a lot faster, but atleast is supports bits > 8}
		    value := 0;
		    for j := 0 to bits-1 do
	  			value += nextBit shl j;
		    result[i] := value;
      end;
    end;
  end;
end;

function tStream.readVLCSegment(n: int32): tDWords;
var
	ctrlCode: word;
  b: byte;
  w: word;
  i: int32;
  bytes: tBytes;
begin

	result := nil;
  system.setLength(result, n);
	
  b := peekByte;
  if (b and $80 = $80) and ((b and $7f) < 8) then begin
  	{this is a control code}
    readByte;
  	result := unpackBits(self, 1+(b and $7), n);
    exit;
  end;

  for i := 0 to n-1 do
  	result[i] := readVLC;	

end;

{
Writes a series of variable length codes, with optional packing.
Generaly this just writes out a list of VLC codes.
However, if the codes would benefit from fixed-length packing then
a special control character is sent, and the values are packed.

Note: It is the callers resposability to note how many values were
written, i.e. by first encoding a VLC length code

This function can be useful to minimize the worst case, as we can
make use of 8bit packing with very little loss in efficency.
}
procedure tStream.writeVLCSegment(values: array of dword);
var
	i: int32;
  maxValue: int32;
  unpackedBits: int32;
  packingCost: int32;
  n: integer;
begin
	maxValue := 0;
  unpackedBits := 0;
	for i := 0 to length(values)-1 do begin
  	maxValue := max(maxValue, values[i]);
  	unpackedBits += VLCBits(values[i]);
  end;

  {special case for all zeroes}
  (*
  if maxValue = 0 then begin
		writeVLCControlCode(256);
    exit;	
  end;
  *)

  for n := 1 to 8 do begin
  	if maxValue < (1 shl n) then begin
	    packingCost := (length(values) * n)+16;
	    if packingCost < unpackedBits then begin
        {control-code}
    		writeVLCControlCode(n-1);
        packBits(values, n, self);
	    	exit;
      end;
    end;
  end;
	{just write out the data}
	for i := 0 to length(values)-1 do
  	writeVLC(values[i]);
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
  seek(0);
end;

{Reset stream, but keep previous capcity}
procedure tStream.softReset();
begin
  bytesLen := 0;
  seek(0);
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
  w: word;
  bitsStream: tStream;
  data: tDWords;
  bits: byte;
const
	testData1: array of dword = [1000, 0, 1000, 32, 15, 16, 17];
	testData2: array of dword = [100, 0, 127, 32, 15, 16, 17];
  {this will get packed}
  testData3: array of dword = [15, 14, 0, 15, 15, 12, 11];
begin

	{check pack and unpack}
  for bits := 7 to 15 do begin
	  bitsStream := packBits(testData2, bits);
	  AssertEqual(bitsStream.len, bytesForBits(bits*length(testData2)));
	  bitsStream.seek(0);
	  data := unpackBits(bitsStream, bits, length(testData2));
	  for i := 0 to length(testData2)-1 do
  	  AssertEqual(data[i], testData2[i]);
  end;

  {check vlcsegment standard}
  s := tStream.create;
  s.writeVLCSegment(testData1);
  s.seek(0);
	data := s.readVLCSegment(length(testData1));
  s.free;
  for i := 0 to length(testData1)-1 do
  	AssertEqual(data[i], testData1[i]);

  {check vlcsegment packed}
  s := tStream.create;
  s.writeVLCSegment(testData3);
  s.seek(0);
	data := s.readVLCSegment(length(testData3));
  for i := 0 to length(testData3)-1 do begin
  	writeln(testData3[i],' >> ', data[i]);
  end;

  s.free;
  for i := 0 to length(testData3)-1 do
  	AssertEqual(data[i], testData3[i]);

	{check nibble}
  s := tStream.Create();
	for i := 0 to 15 do
  	s.writeNibble(i);
  assertEqual(s.len, 8);
  s.writeToDisk('tmp.dat');
  s.free;

  s := tStream.Create();
  s.readFromDisk('tmp.dat');
  assertEqual(s.len, 8);
	for i := 0 to 15 do
  	assertEqual(s.readNibble, i);
  s.free;

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
	  s.writeVLC(testData1[i]);
  s.seek(0);
  for i := 0 to length(testData1)-1 do
  	assertEqual(s.readVLC, testData1[i]);
  s.free;

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
