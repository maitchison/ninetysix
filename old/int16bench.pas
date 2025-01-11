program int16bench;

{Check if 16bit is really that much slower than 32bit}

uses crt, sysutils;

var
  data8: array[0..1024-1] of uint8;
  data16: array[0..1024-1] of uint16;
  data32: array[0..1024-1] of uint32;


const
  N = 128*1024;

var
  acc32: int32;
  elapsed: double;
  startTime: double;
  mips: double;

procedure bench_default8();
var
  i, j: uint32;
  acc: uint8;
begin
  startTime := Time;
  for j := 0 to N-1 do begin
    for i := 0 to (1024 div 8)-1 do begin
      acc += data8[i];
      acc += data8[i+1];
      acc += data8[i+2];
      acc += data8[i+3];
      acc += data8[i+4];
      acc += data8[i+5];
      acc += data8[i+6];
      acc += data8[i+7];
    end;
  end;
  elapsed := (Time - startTime) * (24*60*60);
  mips := ((N * 1024) / elapsed) / 1000000;
  writeln('D8   Took ', (elapsed*1000*1000/N):0:1, 'us with MIPS ', mips:0:2);
end;

procedure bench_default16();
var
  i, j: uint32;
  acc: uint16;
begin
  startTime := Time;
  for j := 0 to N-1 do begin
    for i := 0 to (1024 div 8)-1 do begin
      acc += data16[i];
      acc += data16[i+1];
      acc += data16[i+2];
      acc += data16[i+3];
      acc += data16[i+4];
      acc += data16[i+5];
      acc += data16[i+6];
      acc += data16[i+7];
    end;
  end;
  elapsed := (Time - startTime) * (24*60*60);
  mips := ((N * 1024) / elapsed) / 1000000;
  writeln('D16  Took ', (elapsed*1000*1000/N):0:1, 'us with MIPS ', mips:0:2);
end;

procedure bench_default32();
var
  i, j: uint32;
  acc: uint32;
begin
  startTime := Time;
  for j := 0 to N-1 do begin
    for i := 0 to (1024 div 8)-1 do begin
      acc += data32[i];
      acc += data32[i+1];
      acc += data32[i+2];
      acc += data32[i+3];
      acc += data32[i+4];
      acc += data32[i+5];
      acc += data32[i+6];
      acc += data32[i+7];
    end;
  end;
  elapsed := (Time - startTime) * (24*60*60);
  mips := ((N * 1024) / elapsed) / 1000000;
  writeln('D32  Took ', (elapsed*1000*1000/N):0:1, 'us with MIPS ', mips:0:2);
end;


procedure bench_asm32();
var
  i, j: uint32;
  acc: uint32;
begin
  startTime := Time;
  for j := 0 to N-1 do begin
    asm
      mov ecx, 1024
      shr ecx, 3
      mov eax, 0
      mov edi, offset data32
    @LOOP:

      add eax, data32[ecx*4]
      mov edx, data32[ecx*4+4]
      add eax, data32[ecx*4+8]
      add edx, data32[ecx*4+12]
      add eax, data32[ecx*4+16]
      add edx, data32[ecx*4+20]
      add eax, data32[ecx*4+24]
      add edx, data32[ecx*4+28]

      add eax, edx

      dec ecx
      jnz @LOOP
    end;
  end;
  elapsed := (Time - startTime) * (24*60*60);
  mips := ((N * 1024) / elapsed) / 1000000;
  writeln('A32  Took ', (elapsed*1000*1000/N):0:1, 'us with MIPS ', mips:0:2);
end;


begin
  bench_default8();
  bench_default16();
  bench_default32();
  bench_asm32();
end.
