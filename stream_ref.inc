function readVLCSequence_REF(stream: tStream; n: int32;outBuffer: tDwords): tDWords;
var
  i: integer;
begin
  for i := 0 to n-1 do
    outBuffer[i] := stream.readVLC;
  stream.byteAlign();
end;
