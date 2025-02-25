unit engine;

{$MODE FPC}

interface

const
  GRID_WIDTH = 256;
  GRID_HEIGHT = 192;

var
  impact: array[0..GRID_HEIGHT-1, 0..GRID_WIDTH-1] of single;
  impactTMP: array[0..GRID_HEIGHT-1, 0..GRID_WIDTH-1] of single;
  iImpact: array[0..GRID_HEIGHT-1, 0..GRID_WIDTH-1] of int16;
  iImpactTMP: array[0..GRID_HEIGHT-1, 0..GRID_WIDTH-1] of int16;


procedure UpdateImpact_Method1_Reference;
procedure UpdateImpact_Method1_Fast;
procedure UpdateImpact_Method1_MMX;


implementation

{fabric method using gausian blur}

procedure UpdateImpact_Method1_Reference();
{Update impact using method 1:
Reference implementation...
211ms
}
var
  x,y: integer;
  dx,dy: integer;
const
  kernel: array[-1..1, -1..1] of single = (
    (1/16, 1/8, 1/16),
    (1/8,  1/4, 1/8),
    (1/16, 1/8, 1/16)
  );
begin
  impactTMP := impact;

  for y := 1 to GRID_HEIGHT-2 do begin
    for x := 1 to GRID_WIDTH-2 do begin
      impact[y,x] := 0;
      for dy := -1 to 1 do
        for dx := -1 to 1 do
          impact[y,x] += impactTMP[y+dy,x+dx] * kernel[dy,dx];
    end;
  end;
end;


procedure UpdateImpact_Method1_Fast();
{Update impact using method 1:
Faster implementation...
28ms
- No copy, with two passes.
}
var
  x,y: integer;
  dx,dy: integer;
  prev, this, next: single;
begin
  prev := 0;
  for y := 1 to GRID_HEIGHT-2 do begin
    for x := 1 to GRID_WIDTH-2 do begin
      this := impact[y,x];
      next := impact[y,x+1];
      impact[y,x] := (prev / 2) + (this / 4) + (next / 2);
      prev := this;
    end;
  end;
  prev := 0;
  for x := 1 to GRID_WIDTH-2 do begin
    for y := 1 to GRID_HEIGHT-2 do begin
      this := impact[y,x];
      next := impact[y+1,x];
      impact[y,x] := (prev / 2) + (this / 4) + (next / 2);
      prev := this;
    end;
  end;
end;


procedure UpdateImpact_Method1_ASM();
{Update impact using method 1:
ASM Integer version
17.5 ms
Not tested!
}
var
  x,y: integer;
begin

  for y := 1 to GRID_HEIGHT-2 do begin
    asm

      xor eax, eax
      mov ah, byte ptr y
      mov al, 1
      shl eax, 1
      mov edi, eax

      mov cx, GRID_WIDTH-2
      mov ax, iImpact[edi-2]    {prev}
      mov bx, iImpact[edi]      {this}
      mov dx, iImpact[edi+2]    {next}

    @LOOP:

      shl bx, 1
      add ax, bx
      add ax, dx
      shr ax, 2
      mov iImpact[edi], ax

      mov ax, bx
      mov bx, dx
      add edi, 2
      mov dx, iImpact[edi]

      dec cx
      jnz @LOOP
    end;

  end;

  for x := 1 to GRID_WIDTH-2 do begin
    asm

      xor eax, eax
      mov ah, 1
      mov al, byte ptr x
      shl eax, 1
      mov edi, eax

      mov cx, GRID_HEIGHT-2
      mov ax, iImpact[edi-(256*2)]    {prev}
      mov bx, iImpact[edi]        {this}
      mov dx, iImpact[edi+(256*2)]    {next}

    @LOOP:

      shl bx, 1
      add ax, bx
      add ax, dx
      shr ax, 2
      mov iImpact[edi], ax

      mov ax, bx
      mov bx, dx
      add edi, 2*256
      mov dx, iImpact[edi]

      dec cx
      jnz @LOOP
    end;

  end;


end;


procedure UpdateImpact_Method1_MMX();
{Update impact using method 1:
MMX Integer version
3.6 ms (but some bugs...)
}
var
  x,y: integer;
begin

  for y := 1 to GRID_HEIGHT-2 do begin
    asm

      xor eax, eax
      mov ah, y
      mov al, 1
      shl eax, 1
      mov edi, eax

      {we process 4 pixels at a time using MMX.
       note: we ignore 2 pixels, which isn't great...}
      mov cx, GRID_WIDTH-2
      shr cx, 2

    @LOOP:

      movq mm0, iImpact[edi-2]    {prev}
      movq mm1, iImpact[edi]      {this}
      movq mm2, iImpact[edi+2]    {next}

      psllw mm1, 0   {this *= 2}
      paddw mm0, mm1
      paddw mm0, mm2
      psrlw mm0, 2

      {there's a bug here, we overwrite this value, but then read
       it back in. We need to save the old MM1 somewhere and reuse it
       }
      movq iImpact[edi], mm0

      add edi, 2*4

      dec cx
      jnz @LOOP
    end;

  end;

  for x := 1 to GRID_WIDTH-2 do begin
    asm

      xor eax, eax
      mov ah, 1
      mov al, x
      shl eax, 1
      mov edi, eax

      {we process 4 pixels at a time using MMX.
       note: we ignore 2 pixels, which isn't great...}
      mov cx, GRID_HEIGHT-2
      shr cx, 2

    @LOOP:

      movq mm0, iImpact[edi-(2*256)]    {prev}
      movq mm1, iImpact[edi]      {this}
      movq mm2, iImpact[edi+(2*256)]    {next}

      psllw mm1, 0   {this *= 2}
      paddw mm0, mm1
      paddw mm0, mm2
      psrlw mm0, 2

      movq iImpact[edi], mm0

      add edi, (2*256)*4

      dec cx
      jnz @LOOP
    end;

  end;


end;


(*
function UpdateImpact_Method2_Reference();
{Update impact using method 2:
Reference implementation...
Not fast....
}
var
  x,y: integer;
  prev,this,next: single;
  w1,w2,w3,w4,w0,wt: single;
  value: single;
  give: single;
  total: single;
begin
  total := 0;
  impactTMP := impact;
  for y := 1 to GRID_HEIGHT-1 do begin
    for x := 1 to GRID_WIDTH-1 do begin

      if grid[y,x].typeid = 1 then continue;

      value := impactTMP[y,x];
      total += value;

      w1 := 0;
      w2 := 0;
      w3 := 0;
      w4 := 0;
      if impactTMP[y,x-1] < value then w1 := 1;
      if impactTMP[y,x+1] < value then w2 := 1;
      if impactTMP[y-1,x] < value then w3 := 1;
      if impactTMP[y+1,x] < value then w4 := 1;


      wt := w1+w2+w3+w4;

      if wt = 0 then continue;

      give := value * 0.2;

      impact[y,x] -= give;
      impact[y,x-1] += give * (w1/wt);
      impact[y,x+1] += give * (w2/wt);
      impact[y-1,x] += give * (w3/wt);
      impact[y+1,x] += give * (w4/wt);

    end;
  end;

  exit(total);

end;
  *)

begin
end.
