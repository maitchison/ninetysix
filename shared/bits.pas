{write to stream bit at a time}
unit bits;

interface

uses
  test,
  debug,
  stream,
  sysTypes,
  utils;

{object so that we can create without mem alloc}
type tBitStream = object
  stream: tStream;
  buffer: dword;
  pos: integer;
  constructor init(aStream: tStream);
  procedure writeBits(value: word; bits: byte);
  function readBits(bits: byte): word;
  procedure flush();
  procedure clear();
end;

implementation

constructor tBitStream.init(aStream: tStream);
begin
  stream := aStream;
  clear();
end;

{max supported is 16bits}
procedure tBitStream.writeBits(value: word; bits: byte);
begin
  {$IFDEF debug}
  if value >= (1 shl bits) then
    error(format('Value %d in segment exceeds expected bound of %d', [value, 1 shl bits]));
  {$ENDIF}
  buffer := buffer or (dword(value) shl pos);
  pos += bits;
  while pos >= 16 do begin
    stream.writeWord(buffer and $ffff);
    buffer := buffer shr 16;
    pos -= 16;
  end;
end;

{shared buffer with writeBits...}
function tBitStream.readBits(bits: byte): word;
begin
  {pos here means number of valid bits}
  {note: we read a byte at a time so as to not read too many bytes}
  while pos < bits do begin
    buffer := buffer or (dword(stream.readByte) shl pos);
    pos += 8;
  end;
  result := buffer and ((1 shl bits)-1);
  buffer := buffer shr bits;
  pos -= bits;
end;

procedure tBitStream.flush();
begin
  while (pos > 0) do begin
    stream.writeByte(buffer and $ff);
    buffer := buffer shr 8;
    pos -= 8;
  end;
  clear();
end;

procedure tBitStream.clear();
begin
  buffer := 0;
  pos := 0;
end;

{-------------------------------------------}

type
  tBitsTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tBitsTest.run();
var
  s: tStream;
  bs: tBitStream;
begin

  s := tStream.create();
  bs.init(s);
  bs.writeBits(7, 4);
  bs.writeBits(6, 11);
  bs.writeBits(1, 3); // 19 bits = 3 bytes
  bs.flush();
  writeln(s.asBytes.toString);
  assertEqual(s.pos, 3);
  s.seek(0);
  assertEqual(bs.readBits(4), 7);
  assertEqual(bs.readBits(11), 6);
  assertEqual(bs.readBits(3), 1);
  s.free;
end;

{--------------------------------------------------}

initialization
  tBitsTest.create('Bits');
end.
