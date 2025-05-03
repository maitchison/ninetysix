{check text mode}
program texttest;

{under dosbox-x, when using 80x50, the text is corrupted between runs.
 this tool helps diagnose that}

uses
  crt,
  vga,
  utils;

var
  i: integer;
  mode, cols, page: byte;
  screenSize: word;
  screenCols: word;
  screenCharRows: byte;

begin

  videoDriver.setText();

  textAttr := White;
  clrscr;

  writeln('Video mode        ', Mem[Seg0040:$49]);
  writeln('Character columns ', MemW[Seg0040:$4A]);
  writeln('DisplayPageLength ', MemW[Seg0040:$4C]);
  writeln('Offset            ', MemW[Seg0040:$4E]);
  writeln('Character Rows    ', Mem[Seg0040:$84]+1);


  asm
    mov ah, $0f
    int $10
    mov mode, al
    mov cols, ah
    mov page, bh
  end;


  for i := 1 to 10 do begin
    writeln(i,' -----------------------');
  end;

end.
