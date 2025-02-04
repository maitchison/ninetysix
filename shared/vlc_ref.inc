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

(*
{updating this to no longer use stream is difficult as we are using
 bitStream...}
procedure ReadRice_REF(inPtr, outPtr: pointer; n: int32; k: integer);
var
  quotient, remainder: dword;
  value: word;
  bs: tBitStream;
  i: integer;
  decoded: dword;
  mask: word;
  streamPtr: pWord;
begin
  streamPtr := inPtr;
  {table lookup method}
  bs.init(stream);
  mask := (1 shl RICE_TABLE_BITS)-1;
  for i := 0 to n-1 do begin
    decoded := RICE_TABLE[k, bs.peekWord and mask];
    bs.consumeBits(decoded shr 16);
    pDWord(outBuffer)^ := decoded and $ffff;
    inc(outBuffer);
  end;
  bs.giveBack();
end;
*)