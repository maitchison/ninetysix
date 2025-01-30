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
  ST_RICE_SLOW = 252; {select best rice}
  ST_VLC1 = 0;  {this is the less efficent VLC method} {todo: make this 1, and VLC2 2}
  ST_VLC2 = 1;  {this is the newer VLC method}
  ST_SIGN = 8;  {special encoding for sign bits}

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

  ST_RICE0 = 48; {48..64 = rice}

function  writeSegment(stream: tStream; values: array of dword;segmentType:byte=ST_AUTO): int32;
function  readSegment(stream: tStream; n: int32;outBuffer: tDwords=nil): tDWords;

function  VLC2_Bits(value: dword): word; overload;
function  VLC2_Bits(values: array of dword): dword; overload;
procedure VLC2_Write(stream: tStream; values: array of dword);

procedure SIGN_Write(stream: tStream; values: array of dword); overload;
procedure SIGN_Write(stream: tStream; values: array of int8); overload;
function  SIGN_Bits(values: array of dword): int32; overload;
function  SIGN_Bits(values: array of int8): int32; overload;
procedure SIGN_ReadMasked(stream: tStream; n: int32; outBuffer: pDword);
procedure SIGN_Read(stream: tStream; n: int32; outBuffer: pDword);

procedure RICE_Write(stream: tStream; values: array of dword; k: integer);
procedure RICE_Read(stream: tStream; n: int32; outBuffer: pDword; k: integer);
function  RICE_Bits(values: array of dword; k: integer): int32;

implementation

{vlc1 - depricated}
procedure VLC1_Write(stream: tStream; values: array of dword); forward;
function  VLC1_Bits(value: dword): word; forward;

{packing}
function  packBits(values: array of dword;bits: byte;outStream: tStream=nil): tStream; forward;
procedure unpack(inBuffer: pByte;outBuffer: pDWord; n: word;bitsPerCode: byte); forward;
procedure unpackBits(s: tStream;nCodes: integer;outBuffer: tDWords;bitsPerCode: byte); forward;

var
  packing1: array[0..255] of array[0..7] of dword;
  packing2: array[0..255] of array[0..3] of dword;
  packing4: array[0..255] of array[0..1] of dword;

const
  RICE_TABLE_BITS = 16;

var
  {used for VLC2 codes. This allows for the 'overlapping' optimization}
  VLC2_OFFSET_TABLE: array[0..8] of dword;

  {
    stores rice decodes for common values of k, given some input byte
    stored as decodedValue + (codeLength * 256)
    a codelenght of 0 indicates input not suffcent for decoding, and we must
    regress to another method
    todo: see if we can make sure in the encoder that this will not happen.
    (one way to do this is to set length for long codes to very high)
  }
  RICE_TABLE: array[0..15, 0..(1 shl RICE_TABLE_BITS)-1] of dword;

{$I vlc_ref.inc}
{$I vlc_asm.inc}

function bitsToStoreMaxValue(maxValue: dWord): integer;
begin
  result := ceil(log2(maxValue+1));
end;

function getSegmentTypeName(segmentType: byte): string;
begin
  case segmentType of
    ST_VLC1: result := 'VLC1';
    ST_VLC2: result := 'VLC2';
    ST_SIGN: result := 'SIGN';
    ST_PACK0..ST_PACK0+31: result := 'PACK'+intToStr(segmentType - ST_PACK0);
    ST_RICE0..ST_RICE0+15: result := 'RICE'+intToStr(segmentType - ST_RICE0);
    else result := 'INVALID';
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
function writeSegment(stream: tStream; values: array of dword;segmentType:byte=ST_AUTO): int32;
var
  i: int32;
  valueMax: dword;
  valueSum: double;
  packingBits, riceBits: int32;
  k, bestK, guessK, deltaK: integer;
  thisBits, bestBits: int32;
  n: int32;
  startPos: int32;
  value: dword;
begin

  startPos := stream.pos;

  if length(values) = 0 then exit;

  if segmentType = ST_AUTO then begin
    valueSum := 0;
    valueMax := 0;
    for value in values do begin
      valueMax := max(valueMax, value);
      valueSum += value;
    end;

    {start with packing}
    packingBits := bitsToStoreMaxValue(valueMax) * length(values);
    segmentType := ST_PACK0 + bitsToStoreMaxValue(valueMax);
    bestBits := packingBits;

    {see if RICE is an upgrade}
    deltaK := 0;
    guessK := clamp(floor(log2(1+(valueSum / length(values)))), 0, 15);
    for k := (guessK - 1) to (guessK + 1) do begin
      if k < 0 then continue;
      if k > 15 then continue;
      riceBits := RICE_Bits(values, k);
      if riceBits < bestBits then begin
        segmentType := ST_RICE0 + k;
        bestBits := riceBits;
        bestK := k;
        deltaK := bestK - guessK;
      end;
    end;

    {
    note(format(
      'Selecting %s (%d) with scores %d %d (max:%d mean:%f)',
      [
        getSegmentTypeName(segmentType), deltaK,
        packingBits, riceBits,
        valueMax, valueSum/length(values)
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

  if segmentType = ST_RICE_SLOW then begin
    for i := 0 to 15 do begin
      thisBits := RICE_Bits(values, i);
      if (i = 0) or (thisBits < riceBits) then begin
        riceBits := thisBits;
        segmentType := ST_RICE0+i;
      end;
    end;
  end;

  {write out the data}
  stream.writeByte(segmentType);
  case segmentType of
    ST_VLC1: VLC1_Write(stream, values);
    ST_VLC2: VLC2_Write(stream, values);
    ST_SIGN: SIGN_Write(stream, values);
    ST_PACK0..ST_PACK0+31: packBits(values, segmentType - ST_PACK0, stream);
    ST_RICE0..ST_RICE0+15: RICE_Write(stream, values, segmentType - ST_RICE0);
    else error('Invalid segment type '+intToStr(segmentType));
  end;

  result := stream.pos-startPos;

end;

function readSegment(stream: tStream; n: int32;outBuffer: tDwords=nil): tDWords;
var
  segmentType: byte;
begin

  if not assigned(outBuffer) then
    system.setLength(outBuffer, n);

  segmentType := stream.readByte();

  case segmentType of
    ST_VLC1: readVLC1Sequence_ASM(stream, n, outBuffer);
    ST_VLC2: readVLC2Sequence_ASM(stream, n, outBuffer);
    ST_SIGN: SIGN_Read(stream, n, @outBuffer[0]);
    ST_PACK0..ST_PACK0+31: unpackBits(stream, n, outBuffer, segmentType-ST_PACK0);
    ST_RICE0..ST_RICE0+15: RICE_Read(stream, n, @outBuffer[0], segmentType-ST_RICE0);
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
end;

{returns size of variable length encoded token}
function VLC2_Bits(value: dword): word; overload; inline;
begin
  result := VLC2_Length(value) * 4;
end;

function  VLC2_Bits(values: array of dword): dword; overload;
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

{--------------------------------------------------------------}
{ SIGN strategy }
{--------------------------------------------------------------}

procedure SIGN_Write(stream: tStream; values: array of dword); overload;
var
  i: int32;
  value, prevValue: dword;
  counter: integer;
begin
  prevValue := 0;
  counter := 0;
  for i := 0 to length(values)-1 do begin
    value := values[i];
    if prevValue = value then
      inc(counter)
    else begin
      stream.writeVLC(counter);
      counter := 1;
      prevValue := value;
    end;
  end;
  stream.writeVLC(counter);
  stream.byteAlign();
end;

{special version for signs, i.e. -1, 0, and 1. We store the sign bit
 for 0 as what ever compresses the best}
procedure SIGN_Write(stream: tStream; values: array of int8); overload;
var
  i: int32;
  value, prevValue: int8;
  counter: integer;
begin
  prevValue := 1;
  counter := 0;
  for i := 0 to length(values)-1 do begin
    value := values[i];
    if prevValue * value < 0 then begin
      {change of sign}
      stream.writeVLC(counter);
      counter := 1;
      prevValue *= -1;
    end else
      inc(counter)
  end;
  stream.writeVLC(counter);
  stream.byteAlign();
end;

function SIGN_Bits(values: array of dword): int32; overload;
var
  i: int32;
  value, prevValue: dword;
  counter: integer;
begin
  prevValue := 0;
  counter := 0;

  result := 0;

  for i := 0 to length(values)-1 do begin
    value := values[i];
    if prevValue = value then
      inc(counter)
    else begin
      result += VLC1_Bits(counter);
      counter := 1;
      prevValue := value;
    end;
  end;
  result += VLC1_Bits(counter);
end;

{special version for signs, i.e. -1, 0, and 1. We store the sign bit
 for 0 as what ever compresses the best}
function SIGN_Bits(values: array of int8): int32; overload;
var
  i: int32;
  value, prevValue: int8;
  counter: integer;
begin
  prevValue := 1;
  counter := 0;
  result := 0;
  for i := 0 to length(values)-1 do begin
    value := values[i];
    if prevValue * value < 0 then begin
      {change of sign}
      result += VLC1_Bits(counter);
      counter := 1;
      prevValue *= -1;
    end else
      inc(counter)
  end;
  result += VLC1_Bits(counter);
end;


procedure SIGN_Read(stream: tStream; n: int32; outBuffer: pDword);
var
  i: int32;
  value: dword;
  counter: integer;
begin
  value := 0;
  repeat
    counter := stream.readVLC();
    for i := 0 to counter-1 do begin
      outBuffer^ := value;
      inc(outBuffer);
    end;
    n -= counter;
    value := 1-value;
  until n <= 0;
  stream.byteAlign();
end;

{outputs 0 for non-signed, and -1 ($ffff...) for signed}
procedure SIGN_ReadMasked(stream: tStream; n: int32; outBuffer: pDword);
var
  i: int32;
  mask: int32;
  counter: integer;
begin
  mask := 0;
  repeat
    counter := stream.readVLC();
    if counter > 0 then
      filldword(outBuffer^, counter, dword(mask));
    outBuffer += counter;
    n -= counter;
    if mask = 0 then dec(mask) else inc(mask);
  until n <= 0;
  stream.byteAlign();
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
    if bits > 16 then error(format('Fault when writing RICE code, we do not support rice codes longer than 16 bits (value=%d, k=%d, bits=%d)', [value, k, bits]));

    {the slower method that supports long quotients}
    {todo: remove this and do the fast method, which I think should work now}
    for i := 1 to quotient do bs.writeBits(1, 1);
    bs.writeBits(0, 1);
    {this is faster, but does not work with quotents with > 16 bits}
    //oh... this is wrong, the zero should be a the other end...
    //bs.writeBits((1 shl (quotient+1)) - 2, quotient+1); {e.g. 4 = 11110}
    bs.writeBits(remainder, k);
  end;
  bs.flush();
end;

{fast inline asm rice code reader.
This function can only use the lookup table, which is 16bit, which means
 rice codes longer than this can not be used. For data where that matters
 we'd need to either use VLC2, or to (more likely) just pack the bits.
 the k divisor 15 = 32k, so max code representable would be 32k.
 Reading > 16bits is non-trival as it requires shifting a 64bit integer
 (so we can load 32bits at a time). Although maybe there would be a 20-bit
 hack I could do.
 I think for my case I'm fine as I'm really just using 8-but ulaw anyway.

 Hmm... maybe I should just implement the falt adjustment in asm...
 it's not that hard.
}
procedure ReadRice_ASM(stream: tStream; n: int32; outBuffer: pDword; k: integer);
var
  tablePtr, outPtr, streamPtr: pointer;
  bufferValue: dword;
  bufferPos: byte;
  bytesRead: integer;
begin
  tablePtr := @RICE_TABLE[k, 0];
  outPtr := outBuffer;
  // I think I need to store the length and load it here all at once.
  streamPtr := stream.getCurrentBytesPtr(); // dodgy...
  asm

    pushad

    {
      eax   tmp
      ebx   bufferValue
      ecx   0  || tmp | bufferPos
      edx   loop

      esi   streamPtr
      edi   outPtr
      ebp   tablePtr
    }

    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx

    mov edx, N

    mov esi, STREAMPTR
    mov edi, OUTPTR

    push ebp
    mov ebp, TABLEPTR

  @Loop:

    {read word}
    cmp cl, 16
    jge @SkipRead
  @Read:
    {this is the correct way to do it...}
    // todo: change to ebp
    //mov eax, STREAM
    // note: could make this faster if we could somehow read all the bytes in first...
    //call tStream.readWord     // eax = readword
    {this is the dodgy way}
    movzx eax, word ptr [esi]
    add esi, 2

    shl eax, cl
    or  ebx, eax
    add cl, 16

  @SkipRead:
    movzx eax, bx                  // eax = 0  || next 16 buffer bits
    mov eax, dword ptr [ebp+eax*4] // eax = 0 | len || value

    {consume bits}
    mov ch, cl                  // ch = old buf len
    ror eax, 16                 // eax = value || 0 | len
    mov cl, al                  // cl = bits to burn
    shr ebx, cl                 // burn bits from buffer
    neg cl
    add cl, ch                  // ch = pos - bitsRead

    {write value}
    shr eax, 16                 // eax = 0 || value
    mov dword ptr [edi], eax    // outBuffer^ = code

    {end loop}
    add edi, 4
    dec edx
    jnz @Loop

    pop ebp

    {
      calculate how many bytes we just read, which is
      bytes read - bytes remaining in buffer
    }
    mov eax, esi
    sub eax, STREAMPTR
    and ecx, $ff
    shr cl, 3
    sub eax, ecx
    mov BYTESREAD, eax

    popad

  end;
  stream.seek(stream.pos+bytesRead);
end;

procedure ReadRice_REF(stream: tStream; n: int32; outBuffer: pDword; k: integer);
var
  quotient, remainder: dword;
  value: word;
  bs: tBitStream;
  i: integer;
  decoded: dword;
  mask: word;
begin
  {table lookup method}
  bs.init(stream);
  mask := (1 shl RICE_TABLE_BITS)-1;
  for i := 0 to n-1 do begin
    decoded := RICE_TABLE[k, bs.peekWord and mask];
    bs.consumeBits(decoded shr 16);
    outBuffer^ := decoded and $ffff;
    inc(outBuffer);
  end;
  bs.giveBack();
end;

{todo: we need this to be super fast asm}
procedure RICE_Read(stream: tStream; n: int32; outBuffer: pDword; k: integer);
begin
  //ReadRice_REF(stream, n, outBUffer, k);
  ReadRice_ASM(stream, n, outBUffer, k);
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
    { this is just a method of discouraging the use of long rice codes }
    if bitsNeeded > 16 then exit(high(int32));
    result += bitsNeeded;
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
    outStream := tStream.create();
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

procedure unpackBits(s: tStream;nCodes: integer;outBuffer: tDWords;bitsPerCode: byte);
var
  bytesRequired: int32;
  bytesPtr: pointer;
begin

  if nCodes = 0 then exit;

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
  qCode, code: int32;
  codeLength: int32;
  q, qPart,r: int32;
  copies: int32;
  input, output: int32;
begin
  if RICE_TABLE_BITS > 16 then error('RICE_TABLE_BITS is limited to 16 due to how we read bitStreams');
  fillchar(RICE_TABLE, sizeof(RICE_TABLE), 0);
  for k := 0 to high(RICE_TABLE) do begin
    for value := 0 to (1 shl RICE_TABLE_BITS)-1 do begin
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
          error(format('Overlap at %d %d->%d', [input, output and $ffff, RICE_TABLE[k, input] and $ffff]));
        RICE_TABLE[k, input] := output;
      end;
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
    for j := 0 to 7 do
      packing1[i][j] := (i shr j) and $1;
    for j := 0 to 3 do
      packing2[i][j] := (i shr (j*2)) and $3;
    for j := 0 to 1 do
      packing4[i][j] := (i shr (j*4)) and $f;
  end;
end;

procedure buildTables();
begin
  buildRiceTables();
  buildOffsetTable();
  buildUnpackingTables();
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
  for segmentType in [
    ST_VLC1, ST_VLC2,
    ST_PACK7, ST_PACK8, ST_PACK9,
    ST_RICE0+6,
    ST_AUTO, ST_PACK, ST_RICE
  ] do begin
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

  unpack(@inBuffer[0], @ref[0], 10, 1);
  unpack1(@inBuffer[0], @outBuffer[0], 10);

  assertEqual(toBytes(outBuffer), toBytes(ref));
end;

procedure tVLCTest.testRice();
const
  testData: array of dword = [100, 0, 127, 32, 15, 16, 17];
var
  s: tStream;
  k: integer;
  outData: tDwords;
begin
  s := tStream.create();
  {lower values of k will not work due to long code length no longer
   being supported}
  for k := 4 to 8 do begin
    s.reset();
    RICE_Write(s, testData, k);
    s.seek(0);
    setLength(outData, length(testData));
    RICE_Read(s, length(testData), @outData[0], k);
    assertEqual(toBytes(outData).toString, toBytes(testData).toString);
    assertEqual(s.pos, bytesForBits(RICE_bits(testData, k)));
  end;
  s.free;
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
  {for sign testing}
  testSign1: array of dword = [1,1,1,0,1,1,1];
  testSign2: array of dword = [0,0,0];
  testSign3: array of dword = [1,1,1];
  testSign4: array of dword = [1,1,0];
begin

  {test sign}
  for testSign in [testSign1, testSign2, testSign3, testSign4] do begin
    s := tStream.create();
    s.writeVLCSegment(testSign, ST_SIGN);
    s.seek(0);
    setLength(data, length(testSign));
    data := s.readVLCSegment(length(testSign), data);
    s.free;
    for i := 0 to length(testSign)-1 do
      assertEqual(data[i], testSign[i]);
  end;

  for testSign in [testSign1, testSign2, testSign3, testSign4] do begin
    s := tStream.create();
    SIGN_Write(s, testSign);
    s.seek(0);
    setLength(data, length(testSign));
    SIGN_ReadMasked(s, length(testSign), @data[0]);
    s.free;
    for i := 0 to length(testSign)-1 do
      assertEqual(int32(data[i]), -testSign[i]);
  end;

  {check pack and unpack}
  for bits := 7 to 15 do begin
    bitsStream := packBits(testData2, bits);
    AssertEqual(bitsStream.len, bytesForBits(bits*length(testData2)));
    bitsStream.seek(0);
    setLength(data, length(testData2));
    unpackBits(bitsStream, length(testData2), data, bits);
    for i := 0 to length(testData2)-1 do
      AssertEqual(data[i], testData2[i]);
  end;

  testUnpack();
  testRice();

  {check vlcsegment standard}
  s := tStream.create();
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
  VLC2_Write(s, testData5);
  setLength(data, length(testData5));
  s.seek(0);
  readVLC2Sequence_ASM(s, length(testData5), data);
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
