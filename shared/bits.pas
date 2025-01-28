{write to stream bit at a time}
unit bits;

interface

uses
  test,
  debug,
  stream,
  utils;

{object so that we can create without mem alloc}
type tBitStream = object
  stream: tStream;
  buffer: dword;
  pos: integer;
  constructor init(aStream: tStream);
  procedure writeBits(value: word; bits: byte);
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
    error(format('Value %d in segment exceeds expected bound of %d', [values[i], 1 shl bits]));
  {$ENDIF}
  buffer := buffer or (dword(value) shl pos);
  pos += bits;
  while pos >= 16 do begin
    stream.writeWord(buffer and $ffff);
    buffer := buffer shr 16;
    pos -= 16;
  end;
end;

procedure tBitStream.flush();
begin
  while (pos > 0) do begin
    stream.writeByte(buffer and $ff);
    buffer := buffer shr 8;
    pos -= 8;
  end;
  pos := 0;
  buffer := 0;
end;

procedure tBitStream.clear();
begin
  buffer := 0;
  pos := 0;
end;

begin
end.
