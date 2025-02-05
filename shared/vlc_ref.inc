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
