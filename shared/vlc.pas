{Variable Length Coding: some simple entropy encoders, works in segments}
unit vlc;

interface

uses
  test,
  debug,
  utils,
  sysTypes,
  myMath,
  stream;

{
  Supports the following encodings

  PACK - pack source into n bits
  VLC1 - the old VLC system, that stores 4 bits per 3 bits required.
  VLC2 - newer, slightly more efficent system (prob 4% better)
  RICE - rice codes :)
  SIGN - used to store sign bits, records distance between switches

  todo: see if LZ4 is worth while?
}

const
  {segment types}
  ST_AUTO = 255;
  ST_PACK = 254;
  ST_VLC1 = 0;  {this is the less efficent VLC method} {todo: make this 1, and VLC2 2}
  ST_VLC2 = 1;  {this is the newer VLC method}
  ST_PACK0 = 16;
  ST_PACK1 = 17;
  ST_PACK2 = 18;
  ST_PACK3 = 19;
  ST_PACK4 = 20;
  ST_PACK5 = 21;
  ST_PACK6 = 22;
  ST_PACK7 = 23;
  ST_PACK8 = 24;
  ST_PACK9 = 25;

function writeSegment(stream: tStream; values: array of dword;segmentType:byte=ST_AUTO): int32;
function readSegment(stream: tStream; n: int32;outBuffer: tDwords=nil): tDWords;


implementation

{vlc}
procedure writeVLC1(stream: tStream; values: array of dword); forward;
procedure writeVLC2(stream: tStream; values: array of dword); forward;

{packing}
function  packBits(values: array of dword;bits: byte;outStream: tStream=nil): tStream; forward;
procedure unpack(inBuffer: pByte;outBuffer: pDWord; n: word;bitsPerCode: byte); forward;
function  unpackBits(s: tStream;bitsPerCode: byte;nCodes: integer;outBuffer: tDWords=nil): tDWords; forward;

var
  packing1: array[0..255] of array[0..7] of dword;
  packing2: array[0..255] of array[0..3] of dword;
  packing4: array[0..255] of array[0..1] of dword;

{$I vlc_ref.inc}
{$I vlc_asm.inc}

function bitsToStoreMaxValue(maxValue: dWord): integer;
begin
  result := ceil(log2(maxValue+1));
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

returns the number of bytes used
}
function writeSegment(stream: tStream; values: array of dword;segmentType:byte=ST_AUTO): int32;
var
  i: int32;
  maxValue: int32;
  //unpackedBytes, unpackedBits: int32;
  packBitsRequired: byte;
  packingBytes: int32;
  n: int32;
  startPos: int32;
  value: dword;
begin

  startPos := stream.pos;

  maxValue := 0;
  //unpackedBits := 0;
  for i := 0 to length(values)-1 do begin
    maxValue := max(maxValue, values[i]);
  end;
  //unpackedBytes := bytesForBits(unpackedBits);

  //stream.byteAlign();

  (*
  if packing <> PACK_OFF then begin
    {support up to 32 bits with packing}
    packBitsRequired := ceil(log2(maxValue+1));
    packingBytes := bytesForBits(length(values) * packBitsRequired)+1;
    if (packingBytes <= unpackedBytes) or (packing = PACK_ALWAYS) then begin
      stream.writeByte(ST_PACK+packBitsRequired);
      packBits(values, packBitsRequired, stream);
      result := stream.pos-startPos;
      exit;
    end;
  end;*)

  if segmentType = ST_AUTO then
    segmentType := ST_VLC2;

  if segmentType = ST_PACK then begin
    segmentType := ST_PACK0 + bitsToStoreMaxValue(maxValue);
  end;

  {write out the data}
  stream.writeByte(segmentType);
  case segmentType of
    ST_VLC1: writeVLC1(stream, values);
    ST_VLC2: writeVLC2(stream, values);
    ST_PACK0..ST_PACK0+32: packBits(values, segmentType - ST_PACK0, stream);
    else error('Invalid segment type '+intToStr(segmentType));
  end;

  result := stream.pos-startPos;

  //stream.byteAlign();
end;

function readSegment(stream: tStream; n: int32;outBuffer: tDwords=nil): tDWords;
var
  segmentType: byte;
begin

  if not assigned(outBuffer) then
    system.setLength(outBuffer, n);

  stream.byteAlign();

  segmentType := stream.readByte();

  case segmentType of
    ST_VLC1: readVLC1Sequence_ASM(stream, n, outBuffer);
    ST_VLC2: readVLC2Sequence_ASM(stream, n, outBuffer);
    ST_PACK0..ST_PACK0+32: unpackBits(stream, segmentType-ST_PACK0, n, outBuffer);
    else error('Invalid segment type '+intToStr(segmentType));
  end;

  stream.byteAlign();
  exit(outBuffer);
end;

{--------------------------------------------------------------}
{ VLCx strategy }
{--------------------------------------------------------------}

procedure writeVLC1(stream: tStream; values: array of dword);
var
  x, value: dword;
  midByte: boolean;
  buffer: byte;

  procedure writeNibble(b: byte); inline;
  begin
    if midByte then begin
      buffer := buffer or (b shl 4);
      midByte := false;
      stream.writeByte(buffer);
    end else begin
      buffer := b;
      midByte := true;
    end;
  end;


begin
  midByte := false;
  for x in values do begin
    value := x;
    {write this value}
    while true do begin
      if value < 8 then begin
        writeNibble(value);
        break;
      end else begin
        writeNibble($8+(value and $7));
        value := value shr 3;
      end;
    end;
  end;
  if midByte then writeNibble(0);
end;

{returns number of nibbles required to store given value}
{todo: make faster}
function VLC2Length(d: dword; out prevMax: dword): byte;
var
  maxStore: dword;
  i: integer;
begin
  prevMax := 0;
  maxStore := 8;
  for i := 1 to 12 do begin
    if d < maxStore then exit(i);
    prevMax := maxStore;
    maxStore += (8 shl (i*3));
  end;
end;

procedure writeVLC2(stream: tStream; values: array of dword);
var
  value, encode: dword;
  midByte: boolean;
  buffer: byte;
  nibLen: byte;
  nibSub: dword;
  i: integer;
  shift: byte;
  nib: byte;

begin
  midByte := false;
  for value in values do begin
    nibLen := VLC2Length(value, nibSub);
    encode := value - nibSub;
    shift := nibLen*3;
    for i := 1 to nibLen do begin
      shift -= 3;
      nib := (encode shr shift) and $7;
      if i = nibLen then nib += $8;
      if midByte then begin
        buffer := buffer or nib;
        midByte := false;
        stream.writeByte(buffer);
      end else begin
        buffer := nib shl 4;
        midByte := true;
      end;
    end;
  end;
  if midByte then stream.writeByte(buffer);
end;

{--------------------------------------------------------------}
{ PACK strategy }
{--------------------------------------------------------------}

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
      Error(format('Value %d in segment exceeds expected bound of %d', [values[i], 1 shl bits]));
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
end;

procedure unpack16(inBuf: pByte; outBuf: pDWord;n: dWord);
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

    movzx eax, word ptr [esi]
    add esi, 2
    mov dword ptr [edi], eax
    add edi, 4

    dec ecx
    jnz @PACKLOOP
    popad
  end;
end;

{General unpacking routine. Works on any number of bits, but is a bit slow.}
procedure unpack(inBuffer: pByte;outBuffer: pDWord; n: word;bitsPerCode: byte);
begin
  unpack_ASM(inBuffer, outBuffer, n, bitsPerCode)
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
  bytesPtr: pointer;
begin

  if not assigned(outBuffer) then
    setLength(outBuffer, nCodes);

  if nCodes = 0 then exit(outBuffer);

  bytesRequired := bytesForBits(bitsPerCode * nCodes);

  bytesPtr := s.getCurrentBytesPtr();

  case bitsPerCode of
    0: unpack0(bytesPtr, @outBuffer[0], nCodes);
    1: unpack1(bytesPtr, @outBuffer[0], nCodes);
    2: unpack2(bytesPtr, @outBuffer[0], nCodes);
    4: unpack4(bytesPtr, @outBuffer[0], nCodes);
    8: unpack8(bytesPtr, @outBuffer[0], nCodes);
    16: unpack16(bytesPtr, @outBuffer[0], nCodes);
    else unpack(bytesPtr, @outBuffer[0], nCodes, bitsPerCode);
  end;

  s.advance(bytesRequired);

  exit(outBuffer);
end;

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
  end;
end;

{----------------------------------------------------}

procedure benchmark();
var
  inData, outData: tDwords;
  i: integer;
  s: tStream;
  startTime, encodeElapsed, decodeElapsed: double;
  segmentType: byte;
  bytes: int32;
begin
  setLength(inData, 64000);
  setLength(outData, 64000);
  for i := 0 to length(inData)-1 do
    inData[i] := rnd div 2;

  {run a bit of a benchmark on random bytes (0..127)}
  s := tStream.create(2*64*1024);
  for segmentType in [ST_VLC1, ST_VLC2, ST_PACK7, ST_PACK8, ST_PACK9, ST_AUTO] do begin
    s.seek(0);
    startTime := getSec();
    bytes := writeSegment(s, inData, segmentType);
    encodeElapsed := getSec() - startTime;

    s.seek(0);
    startTime := getSec();
    readSegment(s, length(inData), outData);
    decodeElapsed := getSec() - startTime;

    info(format('mode:%d - %d bytes (encode:%fms decode:%fms)', [segmentType, bytes, 1000*encodeElapsed, 1000*decodeElapsed]));
  end;

end;

{----------------------------------------------------}

type
  tVLCTest = class(tTestSuite)
    procedure run; override;
  end;

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

procedure tVLCTest.run();
var
  s: tStream;
  i: integer;
  w: word;
  bitsStream: tStream;
  data: tDWords;
  bits: byte;
  prevMax: dword;
const
  testData1: array of dword = [1000, 0, 1000, 32, 15, 16, 17];
  testData2: array of dword = [100, 0, 127, 32, 15, 16, 17];
  {this will get packed}
  testData3: array of dword = [15, 14, 0, 15, 15, 12, 11];
  {this will be packed to 5 bits}
  testData4: array of dword = [31, 31, 31, 31, 31, 31, 31];
  {for VLC testing}
  testData5: array of dword = [14, 12, 1, 2, 100];
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

  {check vlc}
  s := tStream.Create();
  for i := 0 to length(testData1)-1 do
    s.writeVLC(testData1[i]);
  s.seek(0);
  for i := 0 to length(testData1)-1 do
    assertEqual(s.readVLC, testData1[i]);
  s.free;

  {check odd size packing}
  s := tStream.Create();
  s.writeVLCSegment(testData4);
  s.seek(0);
  data := s.readVLCSegment(length(testData4));
  assertEqual(toBytes(data), toBytes(testData4));
  assertEqual(s.pos, s.len);
  s.free;

  {check VLC2}
  s := tStream.create(10);
  writeVLC2(s, testData5);
  setLength(data, length(testData5));
  s.seek(0);
  readVLC2Sequence_ASM(s, length(testData5), data);
  //stub:
  writeln(data.toString);
  writeln(s.asBytes.toString);
  for i := 0 to length(testData5)-1 do
    assertEqual(data[i], testData5[i]);
  s.free;

  {check bitsToStore}
  assertEqual(bitsToStoreMaxValue(0), 0);
  assertEqual(bitsToStoreMaxValue(1), 1);
  assertEqual(bitsToStoreMaxValue(2), 2);
  assertEqual(bitsToStoreMaxValue(3), 2);
  assertEqual(bitsToStoreMaxValue(4), 3);
  assertEqual(bitsToStoreMaxValue(255), 8);
  assertEqual(bitsToStoreMaxValue(256), 9);

  {check nibble length}
  assertEqual(VLC2Length(0, prevMax), 1);
  assertEqual(VLC2Length(1, prevMax), 1);
  assertEqual(VLC2Length(7, prevMax), 1);
  assertEqual(VLC2Length(8, prevMax), 2);
  assertEqual(VLC2Length(8+63, prevMax), 2);
  assertEqual(VLC2Length(8+64, prevMax), 3);
  assertEqual(VLC2Length(8+64+511, prevMax), 3);
  assertEqual(VLC2Length(8+64+512, prevMax), 4);
end;

begin
  buildUnpackingTables();
  tVLCTest.create('VLC');
  benchmark();
end.
