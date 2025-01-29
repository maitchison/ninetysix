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
  function peekByte(): byte; inline;
  function peekWord(): word; inline;
  procedure consumeBits(bits: byte); inline;
  procedure writeBits(value: word; bits: byte); inline;
  function readBits(bits: byte): word; inline;
  procedure giveBack();
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
procedure tBitStream.writeBits(value: word; bits: byte); inline;
begin
  {$IFDEF debug}
  if value >= (dword(1) shl bits) then
    error(format('Value %d in segment exceeds expected bound of %d', [value, dword(1) shl bits]));
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
function tBitStream.readBits(bits: byte): word; inline;
begin
  {pos here means number of valid bits}
  {note: we read a byte at a time so as to not read too many bytes}
  if pos < bits then begin
    buffer := buffer or (dword(stream.readWord) shl pos);
    pos += 16;
  end;
  result := buffer and ((1 shl bits)-1);
  buffer := buffer shr bits;
  pos -= bits;
end;

{consumes this many bits}
procedure tBitStream.consumeBits(bits: byte); inline;
begin
  {pos here means number of valid bits}
  if pos < bits then begin
    buffer := buffer or (dword(stream.readWord) shl pos);
    pos += 16;
  end;
  buffer := buffer shr bits;
  pos -= bits;
end;

{peak at the next 8 bits}
function tBitStream.peekByte(): byte; inline;
begin
  {pos here means number of valid bits}
  if pos < 16 then begin
    buffer := buffer or (dword(stream.readWord) shl pos);
    pos += 16;
  end;
  result := byte(buffer);
end;

function tBitStream.peekWord(): word; inline;
begin
  {pos here means number of valid bits}
  if pos < 16 then begin
    buffer := buffer or (dword(stream.readWord) shl pos);
    pos += 16;
  end;
  result := word(buffer);
end;

{we read ahead a bit, this function will give back the bytes already
 loaded into buffer, and clear the buffer}
procedure tBitStream.giveBack();
var
  bytesAhead: integer;
begin
  bytesAhead := pos div 8;
  if bytesAhead > 0 then
    stream.seek(stream.pos-bytesAhead);
  clear();
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
