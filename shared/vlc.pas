{Variable Length Coding: some simple entropy encoders, works in segments}
unit vlc;

interface

uses
  test,
  debug,
  utils,
  sysTypes,
  myMath,
  bits,
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
  ST_AUTO = 255;  {use rice, pack, or vlc, whichever is best}
  ST_PACK = 254;  {select best pack}
  ST_RICE = 253;  {guess a good rice}
  ST_VLC1 = 0;  {this is the less efficent VLC method} {todo: make this 1, and VLC2 2}
  ST_VLC2 = 1;  {this is the newer VLC method}

  ST_PACK0 = 16; {16..48 = pack}
  ST_PACK1 = 17;
  ST_PACK2 = 18;
  ST_PACK3 = 19;
  ST_PACK4 = 20;
  ST_PACK5 = 21;
  ST_PACK6 = 22;
  ST_PACK7 = 23;
  ST_PACK8 = 24;
  ST_PACK9 = 25;
  {...}
  ST_RICE0 = 48; {48..63 = rice (max code is 15)}
  {...}

var
  RICE_EXCEPTIONS: dword = 0;

function  writeSegment(s: tStream; values: array of dword;segmentType:byte=ST_AUTO): int32;
function  readSegment(s: tStream; n: int32;outBuffer: tDwords=nil): tDWords;
function  readSegment16(s: tStream; n: int32;outBuffer: tWords=nil): tWords;

function  getSegmentTypeName(segmentType: byte): string;

function  VLC2_Bits(value: dword): word; overload;
function  VLC2_Bits(values: array of dword): dword; overload;
procedure VLC2_Write(stream: tStream; values: array of dword);

function  VLC8_Bits(value: dword): word;

procedure RICE_Write(stream: tStream; values: array of dword; k: integer);
function  RICE_Bits(values: array of dword; k: integer): int32;
function  RICE_MaxCodeLength(values: array of dword; k: integer): int32;

implementation

{vlc1 - depricated}
procedure VLC1_Write(stream: tStream; values: array of dword); forward;
function  VLC1_Bits(value: dword): word; forward; overload;
function  VLC1_Bits(values: array of dword): dword; forward; overload;

{packing}
function  packBits(values: array of dword;bits: byte;outStream: tStream=nil): tStream; forward;
procedure unpack32(inBuf: pByte;outBuf: pDWord; n: int32;bitsPerCode: byte); forward;
procedure unpack16(inBuf: pByte;outBuf: pWord; n: int32;bitsPerCode: byte); forward;

var
  packing16_1: array[0..255] of array[0..7] of word;
  packing16_2: array[0..255] of array[0..3] of word;
  packing16_4: array[0..255] of array[0..1] of word;
  packing32_1: array[0..255] of array[0..7] of dword;
  packing32_2: array[0..255] of array[0..3] of dword;
  packing32_4: array[0..255] of array[0..1] of dword;

const
  RICE_TABLE_BITS = 12;
  RICE_MASK = (dword(1) shl RICE_TABLE_BITS)-1;

var
  {used for VLC2 codes. This allows for the 'overlapping' optimization}
  VLC2_OFFSET_TABLE: array[0..8] of dword;

  {
    stores rice decodes for common values of k, given some input byte
    stored as decodedValue + (codeLength * 65536)
    a codelength of 0 indicates input not suffcent for decoding, and we must
    regress to another method
    todo: see if we can make sure in the encoder that this will not happen.
    (one way to do this is to set length for long codes to very high)
  }
  {note: we store EGC codes in this table too, starting at 16}
  RICE_TABLE: array[0..16, 0..(1 shl RICE_TABLE_BITS)-1] of dword;

  { used for segment reading}
  IN_BUFFER: array[0..(128*1024)-1] of byte;
  OUT_BUFFER: array[0..(64*1024)-1] of dword;

{$I vlc_ref.inc}
{$I vlc_asm.inc}

{how many bits required to store an integer [0..maxValue]}
function bitsToStoreMaxValue(maxValue: dWord): integer;
begin
  result := ceil(log2(maxValue+1));
end;

{how many bits required to to encode the given value}
function bitsToStoreValue(value: dWord): integer;
begin
  if value = 0 then exit(1) else exit(bitsToStoreMaxValue(value));
end;

function reverseBits16(x: word): word;
begin
  x := ((x shr 1) and $5555) or (word(x shl 1) and $aaaa);
  x := ((x shr 2) and $3333) or (word(x shl 2) and $cccc);
  x := ((x shr 4) and $0f0f) or (word(x shl 4) and $f0f0);
  x :=  (x shr 8) or word(x shl 8);
  result := x;
end;

function getSegmentTypeName(segmentType: byte): string;
begin
  case segmentType of
    ST_VLC1: result := 'VLC1';
    ST_VLC2: result := 'VLC2';
    ST_PACK0..ST_PACK0+31: result := 'PACK'+intToStr(segmentType - ST_PACK0);
    ST_RICE0..ST_RICE0+15: result := 'RICE'+intToStr(segmentType - ST_RICE0);
    {special codes}
    ST_AUTO: result := 'AUTO';
    ST_PACK: result := 'PACK';
    ST_RICE: result := 'RICE';
    else result := 'INVALID';
  end;
end;

{returns the number of bytes required to encode given values using given
 segment type, without the header.
 Auto is not supported}
function getSegmentLengthWithoutHeader(values: array of dword; segmentType: byte): int32;
begin
  result := 0;
  case segmentType of
    ST_VLC1: result := bytesForBits(VLC1_Bits(values));
    ST_VLC2: result := bytesForBits(VLC2_Bits(values));
    ST_PACK0..ST_PACK0+31: result := bytesForBits((segmentType - ST_PACK0) * length(values));
    ST_RICE0..ST_RICE0+15: result := bytesForBits(RICE_Bits(values, segmentType - ST_RICE0));
    else error('Invalid segment type '+intToStr(segmentType));
  end;
end;

{returns the number of bytes required to encode given values using given
 segment type, including the header (type and length).
 Auto is not supported}
function getSegmentLength(values: array of dword; segmentType: byte): int32;
var
  tagCost, lenCost, segCost: integer;
begin
  tagCost := 1;
  lenCost := bytesForBits(VLC8_Bits(length(values)));
  segCost := getSegmentLengthWithoutHeader(values, segmentType);
  case segmentType of
    ST_PACK0..ST_PACK0+31: result := tagCost + segCost;
    else result := tagCost + lenCost + segCost;
  end;
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
function writeSegment(s: tStream; values: array of dword;segmentType:byte=ST_AUTO): int32;
var
  i: int32;
  valueMax: dword;
  valueSum: double;
  k, baseK, guessK: integer;
  thisBytes, bestBytes: int32;
  pkBits: integer;
  n: int32;
  startPos, postHeaderPos: int32;
  value: dword;
  ricePenality: int32;
  segmentLen: dword;

begin

  result := 0;
  bestBytes := -1;

  if length(values) = 0 then exit;

  if segmentType = ST_AUTO then begin

    valueSum := 0;
    valueMax := 0;
    for value in values do begin
      valueMax := max(valueMax, value);
      valueSum += value;
    end;

    {start with packing}
    pkBits := bitsToStoreMaxValue(valueMax);
    segmentType := ST_PACK0 + pkBits;
    bestBytes := getSegmentLength(values, segmentType);

    {see if RICE is an upgrade}
    guessK := clamp(round(log2(1+(valueSum / length(values)))), 0, 15);
    baseK := guessK;

    for k := (baseK - 1) to (baseK + 1) do begin
      if k < 0 then continue;
      if k > 15 then continue;
      thisBytes := getSegmentLength(values, ST_RICE0 + k);
      if thisBytes < bestBytes then begin
        segmentType := ST_RICE0 + k;
        bestBytes := thisBytes;
      end;
    end;

    {
    note(format(
      'Selecting %s (%d) with scores %d %d (max:%d mean:%f) maxCL:%d',
      [
        getSegmentTypeName(segmentType), deltaK,
        packingBits, riceBits,
        valueMax, valueSum/length(values),
        RICE_MaxCodeLength(values, bestK)
      ]
    ));
    }
  end;

  if segmentType = ST_PACK then begin
    valueMax := 0;
    for value in values do valueMax := max(valueMax, value);
    segmentType := ST_PACK0 + bitsToStoreMaxValue(valueMax);
  end;

  if segmentType = ST_RICE then begin
    valueSum := 0;
    for value in values do valueSum += value;
    segmentType := ST_RICE0+floor(log2(1+(valueSum / length(values))));
  end;

  {calculate the segment bytes without header}
  segmentLen := getSegmentLengthWithoutHeader(values, segmentType);

  {write out the data}
  startPos := s.pos;
  s.writeByte(segmentType);
  if not (segmentType in [ST_PACK0..ST_PACK0+31]) then
    s.writeVLC8(segmentLen);

  postHeaderPos := s.pos;
  case segmentType of
    ST_VLC1: VLC1_Write(s, values);
    ST_VLC2: VLC2_Write(s, values);
    ST_PACK0..ST_PACK0+31: packBits(values, segmentType - ST_PACK0, s);
    ST_RICE0..ST_RICE0+15: RICE_Write(s, values, segmentType - ST_RICE0);
    else error('Invalid segment type '+intToStr(segmentType));
  end;

  result := s.pos-startPos; // includes header

  {$ifdef DEBUG}
  if s.pos-postHeaderPos <> segmentLen then error(format(
    'Segment length error, expecting %d but found %d on type %s (calc=%d)',
    [segmentLen, s.pos-postHeaderPos, getSegmentTypeName(segmentType), getSegmentLength(values, segmentType)]
  ));
  {$endif}

end;

procedure convert32to16(buffer32: array of dword; buffer16: array of word; n: int32);
var
  i: integer;
begin
  if n > length(buffer32) then error('Invalid parameter N');
  for i := 0 to n-1 do begin
    {$ifdef debug}
    if clamp16(int32(buffer32[i])) <> buffer32[i] then error(format('Value %d too large for int16 at position %d/%d', [buffer32[i], i, n-1]));
    {$endif}
    buffer16[i] := buffer32[i];
  end;
end;

procedure readSegmentAndLength(s: tStream; n: int32;out segmentType: byte;out segmentLen: dword);
begin
  segmentType := s.readByte();
  if segmentType in [ST_PACK0..ST_PACK0+31] then
    segmentLen := bytesForBits(n*(segmentType-ST_PACK0))
  else
    segmentLen := s.readVLC8();
end;


function readSegment(s: tStream; n: int32;outBuffer: tDwords=nil): tDWords;
var
  segmentType: byte;
  segmentLen: dword;
begin

  if not assigned(outBuffer) then
    system.setLength(outBuffer, n);

  readSegmentAndLength(s, n, segmentType, segmentLen);

  if segmentLen > length(IN_BUFFER) then error(format('Segment too large (%, > %,)', [segmentLen, length(IN_BUFFER)]));

  {todo: block read here}
  {todo: allow zero copy but looking at bytes ptr then incrementing...
   note: this means setting requiredBytes to segmentLength}
  s.readBlock(IN_BUFFER[0], segmentLen);

  case segmentType of
    ST_VLC1: readVLC1Sequence_ASM(@IN_BUFFER[0], @outBuffer[0], n);
    ST_VLC2: readVLC2Sequence_ASM(@IN_BUFFER[0], @outBuffer[0], n);
    ST_PACK0..ST_PACK0+31: unpack32(@IN_BUFFER[0], @outBuffer[0], n, segmentType-ST_PACK0);
    ST_RICE0..ST_RICE0+15: ReadRice32_ASM(@IN_BUFFER[0], @outBuffer[0], n, segmentType-ST_RICE0);
    else error('Invalid segment type '+intToStr(segmentType));
  end;

  exit(outBuffer);
end;

{16bit word version of read segment. Can be a little faster}
function readSegment16(s: tStream; n: int32;outBuffer: tWords=nil): tWords;
var
  segmentType: byte;
  segmentLen: dword;
begin

  if not assigned(outBuffer) then
    system.setLength(outBuffer, n);

  readSegmentAndLength(s, n, segmentType, segmentLen);

  if segmentLen > length(IN_BUFFER) then error(format('Segment too large (%, > %,)', [segmentLen, length(IN_BUFFER)]));

  {todo: block read here}
  {todo: allow zero copy but looking at bytes ptr then incrementing...
   note: this means setting requiredBytes to segmentLength}
  s.readBlock(IN_BUFFER[0], segmentLen);

  case segmentType of
    ST_VLC1: begin
      {convert for compatability... slower than readSegment32}
      readVLC1Sequence_ASM(@IN_BUFFER[0], @OUT_BUFFER[0], n);
      convert32to16(OUT_BUFFER, outBuffer, n);
    end;
    ST_VLC2: begin
      {convert for compatability... slower than readSegment32}
      readVLC2Sequence_ASM(@IN_BUFFER[0], @OUT_BUFFER[0], n);
      convert32to16(OUT_BUFFER, outBuffer, n);
    end;
    ST_PACK0..ST_PACK0+31:
      unpack16(@IN_BUFFER[0], @outBuffer[0], n, segmentType-ST_PACK0);
    ST_RICE0..ST_RICE0+15: begin
      ReadRice16_ASM(@IN_BUFFER[0], @outBuffer[0], n, segmentType-ST_RICE0);
    end;
    else error('Invalid segment type '+intToStr(segmentType));
  end;

  exit(outBuffer);
end;

{--------------------------------------------------------------}
{ VLCx strategy }
{--------------------------------------------------------------}

{returns size of variable length encoded token}
function VLC1_Bits(value: dword): word;
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

function VLC1_Bits(values: array of dword): dword; overload;
var
  value: dword;
begin
  result := 0;
  for value in values do result += VLC1_Bits(value);
end;

procedure VLC1_Write(stream: tStream; values: array of dword);
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
  buffer := 0;
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

{-------------------------}

{returns number of nibbles required to store given value}
function VLC2_Length(d: dword): byte; inline;
begin
  if d < 8 then exit(1);
  if d < 64+8 then exit(2);
  if d < 512+64+8 then exit(3);
  if d < 4096+512+64+8 then exit(4);
  if d < 32768+4096+512+64+8 then exit(5);
  if d < 262144+32768+4096+512+64+8 then exit(6);
  error('Can not encode VLC value, too large.');
  exit(255);
end;

{returns size of variable length encoded token}
function VLC2_Bits(value: dword): word; overload; inline;
begin
  result := VLC2_Length(value) * 4;
end;

function VLC2_Bits(values: array of dword): dword;
var
  value: dword;
begin
  result := 0;
  for value in values do result += VLC2_Length(value) * 4;
end;

procedure VLC2_Write(stream: tStream; values: array of dword);
var
  value, encode: dword;
  midByte: boolean;
  buffer: byte;
  nibLen: byte;
  i: integer;
  shift: byte;
  nib: byte;
begin
  midByte := false;
  buffer := 0;
  for value in values do begin
    nibLen := VLC2_Length(value);
    encode := value - VLC2_OFFSET_TABLE[nibLen-1];
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

{--------------------------------------}

{returns size of variable length encoded token}
function VLC8_Bits(value: dword): word;
begin
  result := 0;
  {this is the nibble aligned method}
  while True do begin
    if value < 128 then begin
      result += 8;
      exit;
    end else begin
      result += 8;
      value := value shr 7;
    end;
  end;
end;

{--------------------------------------------------------------}
{ RICE strategy }
{--------------------------------------------------------------}

procedure RICE_Write(stream: tStream; values: array of dword; k: integer);
var
  quotient, remainder: dword;
  value: word;
  bs: tBitStream;
  bits: integer;
  i: integer;
begin
  bs.init(stream);
  for value in values do begin
    quotient := value shr k;
    remainder := value - (quotient shl k);
    bits := k+quotient+1;
    if bits > RICE_TABLE_BITS then begin
      inc(RICE_EXCEPTIONS);
      bs.writeBits((1 shl RICE_TABLE_BITS)-1, RICE_TABLE_BITS);
      bs.writeBits(value, 16);
      continue;
    end;
    bs.writeBits((1 shl quotient)-1, quotient+1); {e.g. for (k=2) 12 = 010-0111}
    bs.writeBits(remainder, k);
  end;
  bs.flush();
end;

function RICE_Bits(values: array of dword; k: integer): int32;
var
  quotient, remainder: dword;
  value: dword;
  bitsNeeded: integer;
begin
  result := 0;
  for value in values do begin
    bitsNeeded := (value shr k) + 1 + k;
    {exceptions...}
    if bitsNeeded > RICE_TABLE_BITS then begin
      {encode an exception}
      result += RICE_TABLE_BITS;
      result += 16;
      continue;
    end;
    result += bitsNeeded;
  end;
end;

function RICE_MaxCodeLength(values: array of dword; k: integer): int32;
var
  quotient, remainder: dword;
  value: dword;
  bitsNeeded: integer;
begin
  result := 0;
  for value in values do begin
    bitsNeeded := (value shr k) + 1 + k;
    if bitsNeeded > result then result := bitsNeeded;
  end;
end;

{--------------------------------------------------------------}
{ PACK strategy }
{--------------------------------------------------------------}


function packBits(values: array of dword;bits: byte;outStream: tStream=nil): tStream;
var
  bs: tBitStream;
  value: dword;
  i: integer;
begin

  if not assigned(outStream) then
    outStream := tMemoryStream.create();
  result := outStream;
  bs.init(outStream);

  {$IFDEF Debug}
  for i := 0 to length(values)-1 do
    if values[i] >= (dword(1) shl bits) then
      Error(format('Value %d in segment exceeds expected bound of %d', [values[i], dword(1) shl bits]));
  {$ENDIF}

  if bits = 0 then exit;

  for value in values do
    bs.writeBits(value, bits);

  bs.flush();
end;

procedure unpack32(inBuf: pByte;outBuf: pDWord; n: int32;bitsPerCode: byte);
var
  i: integer;
begin
  case bitsPerCode of
    0: filldword(outBuf^, n, 0);
    1: begin
      for i := 1 to (n shr 3) do begin
        move(packing32_1[inBuf^], outBuf^, 4*8);
        inc(inBuf);
        inc(outBuf, 8);
      end;
      move(packing32_1[inBuf^], outBuf^, 4*(n and $7));
    end;
    2: begin
      for i := 1 to (n shr 2) do begin
        move(packing32_2[inBuf^], outBuf^, 4*4);
        inc(inBuf);
        inc(outBuf, 4);
      end;
      move(packing32_2[inBuf^], outBuf^, 4*(n and $3));
    end;
    4: begin
      for i := 1 to (n shr 1) do begin
        move(packing32_4[inBuf^], outBuf^, 4*2);
        inc(inBuf);
        inc(outBuf, 2);
      end;
      move(packing32_4[inBuf^], outBuf^, 4*(n and $1));
    end;
    8: asm
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
    16: asm
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
    else unpack32_ASM(inBuf, @outBuf[0], n, bitsPerCode);
  end;
end;

procedure unpack16(inBuf: pByte;outBuf: pWord; n: int32;bitsPerCode: byte);
var
  i: integer;
begin
  if bitsPerCode > 16 then error(format('Can not unpack %d bits with unpack16', [bitsPerCode]));
  case bitsPerCode of
    0: fillword(outBuf^, n, 0);
    1: begin
      for i := 1 to (n shr 3) do begin
        move(packing16_1[inBuf^], outBuf^, 2*8);
        inc(inBuf);
        inc(outBuf, 8);
      end;
      move(packing16_1[inBuf^], outBuf^, 2*(n and $7));
    end;
    2: begin
      for i := 1 to (n shr 2) do begin
        move(packing16_2[inBuf^], outBuf^, 2*4);
        inc(inBuf);
        inc(outBuf, 4);
      end;
      move(packing16_2[inBuf^], outBuf^, 2*(n and $3));
    end;
    4: begin
      for i := 1 to (n shr 1) do begin
        move(packing16_4[inBuf^], outBuf^, 2*2);
        inc(inBuf);
        inc(outBuf, 2);
      end;
      move(packing16_4[inBuf^], outBuf^, 2*(n and $1));
    end;
    8: asm
      pushad
      mov ecx, n
      mov esi, inBuf
      mov edi, outBuf
    @PACKLOOP:
      movzx ax, byte ptr [esi]
      inc esi
      mov word ptr [edi], ax
      add edi, 2
      dec ecx
      jnz @PACKLOOP
      popad
    end;
    16: move(inBuf^, outBuf^, n*2);
    else unpack16_ASM(inBuf, @outBuf[0], n, bitsPerCode);
  end;
end;

procedure buildOffsetTable();
var
  i: integer;
  value: dword;
  factor: dword;
begin
  value := 0;
  factor := 1;
  for i := low(VLC2_OFFSET_TABLE) to high(VLC2_OFFSET_TABLE) do begin
    VLC2_OFFSET_TABLE[i] := value;
    factor *= 8;
    value += factor;
  end;
end;

procedure buildRiceTables();
var
  i, j, k: int32;
  fluff: int32;
  fluffBits: int32;
  value: int32;
  copies: int32;
  input, output: int32;
  code, codeLength: int32;
  {rice}
  qCode: int32;
  q, qPart,r: int32;
  {egc}
  valuePlusOne: int32;
  valuePlusOneReversed: int32;
  prefixLength: int32;
  numEntries: int32;

begin
  if RICE_TABLE_BITS > 16 then error('RICE_TABLE_BITS is limited to 16 due to how we read bitStreams');
  fillchar(RICE_TABLE, sizeof(RICE_TABLE), 0);
  numEntries := (1 shl RICE_TABLE_BITS);
  for k := 0 to 15 do begin
    for value := 0 to numEntries-1 do begin
      q := value shr k;
      codeLength := k + q + 1;
      if codeLength > RICE_TABLE_BITS then continue;

      r := value - (q shl k);
      qPart := (1 shl q)-1; //e.g. q=3 -> 0111
      code := qPart or (r shl (q+1));
      fluffBits := RICE_TABLE_BITS-codeLength;
      { write out each byte where this code would appear }
      output := value or (codeLength shl 16);
      for fluff := 0 to (dword(1) shl fluffBits)-1 do begin
        input := code or (fluff shl codeLength);
        if RICE_TABLE[k, input] <> 0 then
          error(format('Overlap at %d %d<-%d', [input, output and $ffff, RICE_TABLE[k, input] and $ffff]));
        RICE_TABLE[k, input] := output;
      end;
    end;
    {add exception}
    {note: there are much shorter exception codes to use..}
    RICE_TABLE[k, numEntries-1] := (1 shl 24) or (RICE_TABLE_BITS shl 16);
    {look for empty slots}
    {
    for value := 0 to numEntries-1 do begin
      if RICE_TABLE[k, value] = 0 then
        note(format('Empty slot on k:%d v:%s',[k, binToStr(value, 16)]));
    end;
    }
  end;

  {for the moment just k=0, i.e. standard EGC}
  for value := 0 to numEntries-1 do begin

    valuePlusOne := value + 1;
    prefixLength := bitsToStoreValue(valuePlusOne)-1;
    codeLength := prefixLength*2+1;
    if codeLength > RICE_TABLE_BITS then continue;

    // this will look like 00000xxxxppp (p is prefix=0, and x is data)
    code := reverseBits16(valuePlusOne) shr (16-codeLength);

    //writeln(value, ' l:' ,codelength,' v:', code);

    fluffBits := RICE_TABLE_BITS-codeLength;
    { write out each byte where this code would appear }
    output := value or (codeLength shl 16);
    for fluff := 0 to (dword(1) shl fluffBits)-1 do begin
      input := code or (fluff shl codeLength);
      if RICE_TABLE[16, input] <> 0 then
        error(format('Overlap at %d: %d->%d', [input, output and $ffff, RICE_TABLE[16, input] and $ffff]));
      RICE_TABLE[16, input] := output;
    end;
  end;

end;

{builds lookup tables used to accelerate unpacking.}
procedure buildUnpackingTables();
var
  packingBits: byte;
  i,j: integer;
begin
  for i := 0 to 255 do begin
    for j := 0 to 7 do begin
      packing16_1[i][j] := (i shr j) and $1;
      packing32_1[i][j] := (i shr j) and $1;
    end;
    for j := 0 to 3 do begin
      packing16_2[i][j] := (i shr (j*2)) and $3;
      packing32_2[i][j] := (i shr (j*2)) and $3;
    end;
    for j := 0 to 1 do begin
      packing16_4[i][j] := (i shr (j*4)) and $f;
      packing32_4[i][j] := (i shr (j*4)) and $f;
    end;
  end;
end;

procedure buildTables();
begin
  buildRiceTables();
  buildOffsetTable();
  buildUnpackingTables();
end;

{----------------------------------------------------}

type
  tVLCTest = class(tTestSuite)
  private
    procedure testUnpack();
    procedure testRice();
  public
    procedure run; override;
  end;

procedure tVLCTest.testUnpack();
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

  unpack32(@inBuffer[0], @ref[0], 10, 1);
  unpack_REF(@inBuffer[0], @outBuffer[0], 10, 1);

  assertEqual(toBytes(outBuffer), toBytes(ref));
end;

procedure tVLCTest.testRice();
const
  testData1: array of dword = [100, 0, 127, 32, 15, 16, 17];
  testData2: array of dword = [1, 2, 65535, 1000, 0];
var
  s: tStream;
  k: integer;
  outData: tDwords;
  outData16: tWords;
begin
  s := tMemoryStream.create();
  {lower values of k will not work due to long code length no longer
   being supported}
  for k := 4 to 8 do begin
    s.reset();
    s.writeSegment(testData1, ST_RICE0+k);

    {32bit}
    s.seek(0);
    setLength(outData, length(testData1));
    s.readSegment(length(testData1), @outData[0]);
    assertEqual(toBytes(outData).toString, toBytes(testData1).toString);

    {16bit}
    s.seek(0);
    setLength(outData16, length(testData1));
    vlc.readSegment16(s, length(testData1), @outData16[0]);
    assertEqual(toBytes(outData16).toString, toBytes(testData1).toString);

    {make sure size is ok}
    {+2 is for header}
    assertEqual(s.pos, 2+bytesForBits(RICE_bits(testData1, k)));
  end;

  {test exceptions}
  s.reset();
  s.writeSegment(testData2, ST_RICE0+8);
  {32bit}
  s.seek(0);
  setLength(outData, length(testData2));
  s.readSegment(length(testData2), @outData[0]);
  assertEqual(outData.toString, toDWords(testData2).toString);
  {16bit}
  s.seek(0);
  setLength(outData16, length(testData2));
  vlc.readSegment16(s, length(testData2), @outData16[0]);
  assertEqual(toDWords(outData16).toString, toDWords(testData2).toString);
  {make sure size is ok}
  {+2 is for header}
  assertEqual(s.pos, 2+bytesForBits(RICE_bits(testData2, k)));
  s.free;
end;

procedure tVLCTest.run();
var
  s: tStream;
  i: integer;
  w: word;
  bs: tStream;
  data: tDWords;
  bits: byte;
  prevMax: dword;
  testSign: array of dword;
const
  testData1: array of dword = [1000, 0, 1000, 32, 15, 16, 17];
  testData2: array of dword = [100, 0, 127, 32, 15, 16, 17];
  {this will get packed}
  testData3: array of dword = [15, 14, 0, 15, 15, 12, 11];
  {this will be packed to 5 bits}
  testData4: array of dword = [31, 31, 31, 31, 31, 31, 31];
  {for VLC testing}
  testData5: array of dword = [14, 12, 1, 2, 100];
  {for exception testing}
begin

  {check pack and unpack}
  for bits := 7 to 15 do begin
    bs := packBits(testData2, bits);
    AssertEqual(bs.len, bytesForBits(bits*length(testData2)));
    bs.seek(0);
    setLength(data, length(testData2));
    unpack32(bs.getCurrentBytesPtr(0), @data[0], length(testData2), bits);
    for i := 0 to length(testData2)-1 do
      AssertEqual(data[i], testData2[i]);
  end;

  testUnpack();
  testRice();

  {check vlcsegment standard}
  s := tMemoryStream.create();
  writeSegment(s, testData1);
  s.seek(0);
  data := readSegment(s, length(testData1));
  s.free;
  for i := 0 to length(testData1)-1 do
    AssertEqual(data[i], testData1[i]);

  {check vlcsegment packed}
  s := tMemoryStream.create;
  writeSegment(s, testData3);
  s.seek(0);
  data := readSegment(s, length(testData3));
  s.free;
  for i := 0 to length(testData3)-1 do
    AssertEqual(data[i], testData3[i]);

  {check odd size packing}
  s := tMemoryStream.create();
  writeSegment(s, testData4);
  s.seek(0);
  data := readSegment(s, length(testData4));
  assertEqual(toBytes(data), toBytes(testData4));
  assertEqual(s.pos, s.len);
  s.free;

  {check VLC2}
  s := tMemoryStream.create(10);
  VLC2_Write(s, testData5);
  setLength(data, length(testData5));
  s.seek(0);
  readVLC2Sequence_ASM(s.getCurrentBytesPtr(0), data, length(testData5));
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

  assertEqual(bitsToStoreValue(0), 1);
  assertEqual(bitsToStoreValue(1), 1);
  assertEqual(bitsToStoreValue(2), 2);
  assertEqual(bitsToStoreValue(3), 2);
  assertEqual(bitsToStoreValue(4), 3);
  assertEqual(bitsToStoreValue(255), 8);
  assertEqual(bitsToStoreValue(256), 9);

  {test reverseBits16(x: word): word;}
  assertEqual(reverseBits16($ffff), $ffff);
  assertEqual(reverseBits16($0000), $0000);
  assertEqual(reverseBits16($0001), $8000);
  assertEqual(reverseBits16($ff00), $00ff);

  {check nibble length}
  assertEqual(VLC2_Length(0), 1);
  assertEqual(VLC2_Length(1), 1);
  assertEqual(VLC2_Length(7), 1);
  assertEqual(VLC2_Length(8), 2);
  assertEqual(VLC2_Length(8+63), 2);
  assertEqual(VLC2_Length(8+64), 3);
  assertEqual(VLC2_Length(8+64+511), 3);
  assertEqual(VLC2_Length(8+64+512), 4);
end;

begin
  buildTables();
  tVLCTest.create('VLC');
end.
