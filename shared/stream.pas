{A very simple stream class}
unit stream;

{$MODE Delphi}

{todo: borrow most of LZBlock}

interface

uses
  utils,
  debug,
  types,
  test;

type

  tPackingMethod = (
    PACK_OFF,
    PACK_FAST,
    PACK_ALL
  );

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
    procedure writeVLCControlCode(value: dword); inline;
    procedure writeVLCSegment(values: array of dword;packing:tPackingMethod=PACK_FAST);
    function  VLCbits(value: dword): word; inline;

    procedure setSize(newSize: int32);

    procedure writeChars(s: string);
    procedure writeBytes(aBytes: tBytes;aLen:int32=-1);

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

    procedure byteAlign(); inline;
    procedure seek(aPos: dword; aMidByte: boolean=False);

    procedure writeToDisk(fileName: string);
    procedure readFromDisk(fileName: string);

    procedure reset();
    procedure softReset();

    property  capacity: int32 read bytesAllocated;
    property  len: int32 read bytesUsed;
    property  pos: int32 read fPos;

    function  asBytes: tBytes;
    {todo: support weak pointers on locked streams}
    //function  getBuffer: tBytes;

  end;

implementation

{$I stream_ref.inc}
{$I stream_asm.inc}

{------------------------------------------------------}

{Returns the packing code for given number of bits}
function encodePackingCode(nBits: byte): int32;
begin
  case nBits of
    0: exit(0);
    1: exit(1);
    2: exit(2);
    4: exit(3);
    8: exit(4);
    {extra ones}
    3: exit(5);
    5: exit(6);
    6: exit(7);
  end;
  exit(100+nBits); {stub: support all codes}
end;

{Returns the packing code for given number of bits}
function decodePackingCode(value: byte): int32;
begin
  case value of
    0: exit(0);
    1: exit(1);
    2: exit(2);
    3: exit(4);
    4: exit(8);
    {extra codes}
    5: exit(3);
    6: exit(5);
    7: exit(5);
  end;
  exit(-1);
end;

var
  packing1: array[0..255] of array[0..7] of dword;
  packing2: array[0..255] of array[0..3] of dword;
  packing4: array[0..255] of array[0..1] of dword;
  packing8: array[0..255] of array[0..0] of dword;

{builds lookup tables used to accelerate unpacking.}
procedure buildUnpackingTables();
var
  packingBits: byte;
  i,j: integer;
begin
  for i := 0 to 255 do begin
    for j := 0 to 7 do
      packing1[i][j] := (i shr j) and $1;
    for j := 0 to 3 do
      packing2[i][j] := (i shr (j*2)) and $3;
    for j := 0 to 1 do
      packing4[i][j] := (i shr (j*4)) and $f;
    packing8[i][0] := i;
  end;
end;

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

  blocks := (newSize+1023) div 1024;

  reallocMem(bytes, blocks*1024);

  bytesAllocated := blocks*1024;

  {bytesUsed can not be more than actual buffer size}
  if bytesUsed > newSize then
    bytesUsed := newSize;
end;

{makes sure the stream has capacity for *atleast* n bytes}
procedure tStream.makeCapacity(n: dword);
begin
  if bytesAllocated < n then
    {resize requires a copy, so always increase size by atleast 5%}
    //stub:
    //setCapacity(max(n, int64(bytesAllocated)*105 div 100));
    setCapacity(n);
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
  {$IFDEF debug}
  if (b and $f) <> b then
    Error('Invalid nibble value '+intToStr(b));
  {$ENDIF}

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
var
  i: integer;
begin
  if midByte then
    error('Unaligned readBytes');
  if n > (len-fPos) then
    error(Format('Read over end of stream, requested, %d bytes but only %d remain.', [n,  (fPos + n)]));
  result := nil;
  if n = 0 then
    exit;
  system.setLength(result, n);
  move(bytes[fPos], result[0], n);
  fPos += n;
end;

{writes memory stream to disk}
procedure tStream.writeToDisk(fileName: string);
var
  f: file;
  bytesWritten: dword;
begin
  assignFile(f, fileName);
  rewrite(f,1);
  blockwrite(f, bytes[0], bytesUsed, bytesWritten);
  close(f);
end;

{loads memory stream from disk, and resets position to start of stream.}
procedure tStream.readFromDisk(fileName: string);
var
  f: file;
  bytesRead: dword;
  ioError: word;
begin

  {$I-}
  assignFile(f, fileName);
  system.reset(f,1);
  {$I+}

  IOError := IOResult;
  if IOError <> 0 then
    Error('Could not open file "'+FileName+'" '+GetIOError(IOError));

  setCapacity(fileSize(f));
  bytesUsed := fileSize(f);
  blockread(f, bytes^, bytesUsed, bytesRead);
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
end;

{write a variable length encoded token

Encoding is as follows

with most signficant nibbles on the right.

(todo: check this is still right)

xxx0               (0-7)
xxx1xxx0           (8-63)
xxx1xxx1xxx0       (64-511)
xxx1xxx1xxx1xxx0  (512-4095)

Note: codes in the form

0000xxx1
...

are out of band, and used for control codes

}
procedure tStream.writeVLC(value: dword);
begin
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
  while True do begin
    if value < 8 then begin
      writeNibble($8+value);
      writeNibble(0);
      exit;
    end else begin
      writeNibble($8+(value and $7));
      value := value shr 3;
    end;
  end;
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

      {pad with 0s to write final byte}
      while bitPos <> 0 do
        writeBit(0);
    end;
  end;
end;


procedure unpack0(inBuf: pByte; outBuf: pDWord;n: dWord);
begin
  filldword(outBuf^, n, 0);
end;

procedure unpack1(inBuf: pByte; outBuf: pDWord;n: dWord);
var
  i: integer;
begin
  for i := 1 to (n shr 3) do begin
    move(packing1[inBuf^], outBuf^, 4*8);
    inc(inBuf);
    inc(outBuf, 8); // inc is dwords...
  end;
  move(packing1[inBuf^], outBuf^, 4*(n and $7));
end;

procedure unpack2(inBuf: pByte; outBuf: pDWord;n: dWord);
var
  i: integer;
begin
  for i := 1 to (n shr 2) do begin
    move(packing2[inBuf^], outBuf^, 4*4);
    inc(inBuf);
    inc(outBuf, 4);
  end;
  move(packing2[inBuf^], outBuf^, 4*(n and $3));
end;

procedure unpack4(inBuf: pByte; outBuf: pDWord;n: dWord);
var
  i: integer;
begin
  for i := 1 to (n shr 1) do begin
    move(packing4[inBuf^], outBuf^, 4*2);
    inc(inBuf);
    inc(outBuf, 2);
  end;
  move(packing4[inBuf^], outBuf^, 4*(n and $1));
end;

procedure unpack8(inBuf: pByte; outBuf: pDWord;n: dWord);
var
  i: integer;
  inPtr, outPtr: pointer;
begin
  asm
    pushad
    mov ecx, n
    mov esi, inBuf
    mov edi, outBuf
  @PACKLOOP:

    movzx eax, byte ptr [esi]
    inc esi
    mov dword ptr [edi], eax
    add edi, 4

    dec ecx
    jnz @PACKLOOP
    popad
  end;
  {
  for i := 1 to n do begin
    move(packing8[inBuf^], outBuf^, 4);
    inc(inBuf);
    inc(outBuf);
  end;
  }
end;

{General unpacking routine.
 Works on any number of bits, but is a bit slow.}
procedure unpack(inBuffer: pByte;outBuffer: pDWord; n: word;bitsPerCode: byte);
var
  i,j: int32;
  bitBuffer: byte;
  bitsRemaining: integer;
  value: dword;
  bytePos: int32;

function nextBit: byte; inline;
begin
  if bitsRemaining = 0 then begin
    inc(inBuffer);
    bitBuffer := inBuffer^;
    bitsRemaining := 8;
  end;
  result := bitBuffer and $1;
  bitBuffer := bitBuffer shr 1;
  dec(bitsRemaining);
end;

begin
  bitBuffer := inBuffer^;
  bitsRemaining := 8;
  for i := 0 to n-1 do begin
    value := 0;
    for j := 0 to bitsPerCode-1 do
      value += nextBit shl j;
    outBuffer^ := value;
    inc(outBuffer);
  end;
end;

{Unpack bits
  s             the stream to read from
  bitsPerCode   the number of packed bits per symbol
  nCodes         the number of symbols

  output         array of 32bit dwords
}

function unpackBits(s: tStream;bitsPerCode: byte;nCodes: integer;outBuffer: tDWords=nil): tDWords;
var
  bytesRequired: int32;
  bytes: tBytes;
begin

  if not assigned(outBuffer) then
    setLength(outBuffer, nCodes);

  if nCodes = 0 then exit(outBuffer);

  bytesRequired := bytesForBits(bitsPerCode * nCodes);
  bytes := s.readBytes(bytesRequired);

  case bitsPerCode of
    0: unpack0(nil, @outBuffer[0], nCodes);
    1: unpack1(@bytes[0], @outBuffer[0], nCodes);
    2: unpack2(@bytes[0], @outBuffer[0], nCodes);
    4: unpack4(@bytes[0], @outBuffer[0], nCodes);
    8: unpack8(@bytes[0], @outBuffer[0], nCodes);
    else unpack(@bytes[0], @outBuffer[0], nCodes, bitsPerCode);
  end;

  exit(outBuffer);
end;

function isControlCode(b: byte): boolean;
begin
  result := (b >= 8) and (b < 16);
end;

function tStream.readVLCSegment(n: int32;outBuffer: tDwords=nil): tDWords;
var
  ctrlCode: word;
  b: byte;
  packingBits: int32;
begin

  if not assigned(outBuffer) then
    system.setLength(outBuffer, n);

  self.byteAlign();

  b := peekByte;
  if isControlCode(b) then begin
    {this is a control code}
    packingBits := decodePackingCode(readByte-8);
    if packingBits < 0 then
      Error('Invalid packing code');
    unpackBits(self, packingBits, n, outBuffer);
    exit(outBuffer);
  end;

  readVLCSequence_ASM(self, n, outBuffer);

  exit(outBuffer);
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
procedure tStream.writeVLCSegment(values: array of dword;packing:tPackingMethod=PACK_FAST);
var
  i: int32;
  maxValue: int32;
  unpackedBits: int32;
  packingCost: int32;
  packingOptions: set of byte;
  n: integer;
const
  FAST_OPTIONS = [0,1,2,4,8];
  ALL_OPTIONS = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24];
begin
  maxValue := 0;
  unpackedBits := 0;
  for i := 0 to length(values)-1 do begin
    maxValue := max(maxValue, values[i]);
    unpackedBits += VLCBits(values[i]);
  end;

  self.byteAlign();

  if packing <> PACK_OFF then begin
    if packing = PACK_FAST then
      packingOptions := FAST_OPTIONS
    else
      packingOptions := ALL_OPTIONS;
    for n in packingOptions do begin
      if maxValue < (1 shl n) then begin
        packingCost := (length(values) * n)+8;
        if packingCost < unpackedBits then begin
          {control-code}
          writeVLCControlCode(encodePackingCode(n));
          packBits(values, n, self);
          exit;
        end;
      end;
    end;
  end;

  {just write out the data}
  for i := 0 to length(values)-1 do
    writeVLC(values[i]);

  self.byteAlign();
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
  freeMem(bytes); bytes := nil;
  bytesUsed := 0;
  seek(0);
end;

{Reset stream, but keep previous capcity}
procedure tStream.softReset();
begin
  bytesUsed := 0;
  seek(0);
end;

function tStream.asBytes(): tBytes;
begin
  result := nil;
  if bytesUsed = 0 then exit;
  system.setLength(result, bytesUsed);
  move(bytes^, result[0], bytesUsed);
end;

{---------------------------------------------------------------}

procedure testUnpack();

var
  outBuffer: array[0..9] of dword;
  inBuffer: array[0..1] of byte;
  ref: array[0..9] of dword;
  i: integer;
begin

  inBuffer[0] := 53;
  inBuffer[1] := 11;

  for i := 0 to 9 do
    {to check if we are overwriting values or not}
    outBuffer[i] := i;

  unpack(@inBuffer[0], @ref[0], 10, 1);
  unpack1(@inBuffer[0], @outBuffer[0], 10);

  assertEqual(toBytes(outBuffer), toBytes(ref));

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
  testUnpack();

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

{--------------------------------------------------}

initialization
  buildUnpackingTables();
  tStreamTest.create('Stream');
end.
