function readVLC1Sequence_REF(stream: tStream; n: int32;outBuffer: tDwords): tDWords;
var
  i: integer;
begin
  error('VLC1 is no longer supported');
end;

{General unpacking routine. Works on any number of bits, but is a bit slow.}
procedure unpack_REF(inBuffer: pByte;outBuffer: pDWord; n: word;bitsPerCode: byte);
var
  i, j: int32;
  bitBuffer: dword;         { buffer for our bits }
  bitsRemaining: int32;     { number of bits left in the buffer }
  value: dword;             { current value being unpacked}
  mask: dword;              { mask for extracting bits}

begin
  bitBuffer := 0;
  bitsRemaining := 0;
  mask := (1 shl bitsPerCode) - 1;

  for i := 0 to n-1 do begin
    {make sure we have enough bits to perform the read}
    while bitsRemaining < bitsPerCode do begin
      bitBuffer := bitBuffer or (inBuffer^ shl bitsRemaining);
      inc(inBuffer);
      inc(bitsRemaining, 8);
    end;

    {extract the next code}
    value := bitBuffer and mask;
    outBuffer^ := value;
    inc(outBuffer);

    {remove extracted code from the bit buffer}
    bitBuffer := bitBuffer shr bitsPerCode;
    dec(bitsRemaining, bitsPerCode);
  end;
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
