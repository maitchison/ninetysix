program Main;

{todo:

mordor level loading
defered renderer :)
voxel engine :)

}


uses
    crt, dos, keyboard,
    sysutils,
    screen,
    graph3d, vertex;

type
    THitRecord = record
        id: integer;
        distance: single;
    end;

var
    vseg: word;
    vofs: dword;

var rdtscFrequency: double;

var
    defaultTexture: Texture;


var
    x,y: integer;
    i: integer;
    hits: int32;

    startTime, endTime, fps: double;

    video_mps: single;

    BUFFER: array[0..240-1, 0..320-1] of RGBA;
    {VIDEO: array[0..199, 0..319] of byte absolute $A000:0;}

const
    DEG_TO_RAD = 3.1415926 / 180;


procedure putPixel(x, y: int32; col:rgba);
var
    address: int32;
    ofs: int32;
begin

if (x < 0) or (x >= 320) then exit;
if (y < 0) or (y >= 200) then exit;

ofs := x + (y * 320);

asm
    mov edi, ofs
    mov eax, col
    mov ds:[BUFFER + edi*4], eax
    end
end;

function ReadTimer: word; assembler;
asm
    cli
    mov al, $00
    out $43, al
    in  al, $40
    mov ah, al
    in al, $40
    xchg ah, al
    sti
end;


{note: seems to crash, but I think thats because i'm under windows}
function ReadTime: double;
var
    b,a: word;
    bb: double;
    li: longint absolute a;
begin
asm
    cmp vseg, 0
    jz @NoWindows
    mov ax, $100
    call [vofs]
    push eax
    pop ax
    pop dx
    jmp @Exit

@NoWindows:
    push ds
    mov dx, $40
    mov ds, dx

    cli
    in  al, dx
    mov ah, al
    in  al, $40
    sti

    mov cx, ax

    cli
    in  al, dx
    mov ah, al
    in  al, $40
    mov bx, ds:$6C
    sti

    cmp cl, al
    je  @NotChanged

    //in  al, dx
    //mov ah, al
    //in  al, $40
    //mov bx, ds:$6C
    //sti

@NotChanged:
    xchg ah, al
    mov dx, bx
    pop ds
    neg ax
@Exit:
    mov a, ax
    mov b, dx
    end;

    bb := b;
    result := (longint(a)+((bb)*65536))/1192500;

end;


type
    TTick = packed record
        lo, hi: cardinal;
    end;

function getRDTSC(): uint64;
var
    tick: TTick;
    ticks: uint64 absolute tick;
begin
    asm
        rdtsc
        mov tick.lo, eax
        mov tick.hi, edx
    end;
    result := ticks;
end;


function getSec(): double;
var
    h, m, s, hsec: word;
const
    pitFrequency: double = 1193180;
begin
    {50ms}
    //GetTime(h, m, s, hsec);
    //result := h * 3600 + m * 60 + s + hsec / 100;

    {50ms}
    //result := double(getTickCount) / 1000.0;

    {50ms}
    //result := double(getTickCount64) / 1000.0;


    {<1ms, but crashes}
    //result := ReadTime();


    {cycle accurate}
    {assuming here 166 MHz}
    result := getRDTSC() / (166*1000*1000);


end;

{
procedure test_windows();
begin
asm
    push es
    push edi

    xor eax, eax
    xor edi, edi
    mov es, di
    mov bx, 5
    mov ax, $1684
    int $2f
    mov vseg, es
    mov vofs, edi

    pop edi
    pop es
end;
end;
}


procedure bench_ram();
var
    col: integer;
    startTime: double;
    elapsed: double;
    writtenMb: double;
    p: Pointer;
begin
    startTime := getSec();

    GetMem(p, 64000);


    {
    start: 74.1
    }

    for col := 0 to 255 do begin
    asm
        mov edi, p
        mov bx, col
        mov ah, bl
        shl eax, 16
        mov al, bl
        mov ah, bl
        mov ecx, 64000/4
        push es
        mov bx, fs
        mov es, bx
    @loop:
        add edi, 4
        mov es:[edi], eax
        dec ecx
        jnz @loop
        pop es
        end;
    end;

    elapsed := getSec() - startTime;
    writtenMb := 320 * 200 * 255 / (1000*1000);
    video_mps := writtenMb / elapsed;

end;

procedure bench_video();
var
    col: integer;
    startTime: double;
    elapsed: double;
    writtenMb: double;
begin
    writeln('Read speed mb/s');

    startTime := getSec();

    {
    10.26 - start
    29.67 - from byte to 32bit word (30mbs is what I remember from before)
    33.33 - use rep stosd
    33.31 - use mmx
    33.31 - loop unrole (2x)
    }

    for col := 0 to 255 do begin
    asm
        mov edi, $A0000
        mov bx, col
        mov ah, bl
        shl eax, 16
        mov al, bl
        mov ah, bl
        mov ecx, 64000/4
        push es
        mov bx, fs
        mov es, bx
        shr ecx, 1
    @loop:
        add edi, 4
        mov fs:[edi], eax
        add edi, 4
        mov fs:[edi], eax
        dec ecx
        jnz @loop
{        cld
        rep stosd}

{        shr ecx, 1
        movd mm0, eax
        punpckldq mm0, mm0

    @loop:
        movq es:[edi], mm0
        add edi, 8
        loop @loop}


        pop es
        end;
    end;

    elapsed := getSec() - startTime;

    writtenMb := 320 * 200 * 255 / (1000*1000);

    video_mps := writtenMb / elapsed;


    {
    writeln('S3 transfer speed mbs/s');
    writeln('S3 clear speed mb/s');}
end;

procedure bench_disk();
begin
    writeln('Write speed mb/s');
    writeln('Read speed mb/s');
end;

procedure bench_memory();
begin
    writeln('Read speed mb/s');
    writeln('Write speed mb/s');
end;

procedure bench_cpu();
begin
    writeln('Integer Addition (MIPS)');
    writeln('Integer Multiplication (MIPS)');
    writeln('Float Addition (MIPS)');
    writeln('Float Multiplication (MIPS)');
end;

procedure init_320x200();
begin
asm
    mov ax,13h
    int 10h
    end;
end;



var
    maze: array[0..15, 0..15] of Byte;


function trace_mmx(x, y, dir: single): THitRecord;
{trace through the maze, return how many steps until we
collide with an object, or -1 if we do not hit anything}
var
    dx, dy: single;
    mx, my: integer;
    i: integer;

    _dx, _dy: int32;
    _x, _y: int32;

    steps: integer;
    id: byte;
    distance: integer;

const
    STEP_SIZE = 0.1;

begin
    id:=0;

    trace_mmx.id := -1;
    trace_mmx.distance := 0;

    dx := sin(dir*DEG_TO_RAD) * STEP_SIZE;
    dy := -cos(dir*DEG_TO_RAD) * STEP_SIZE;

    _dx := trunc(dx * 65536);
    _dy := trunc(dy * 65536);
    _x := trunc(x * 65536);
    _y := trunc(y * 65536);


    steps := round(16.0 / STEP_SIZE);


    {rewrite with MMX}

    asm
        pusha
        xor ecx, ecx
        mov cx, steps

        mov eax, _x
        mov ebx, _y

    @Loop:

        {check}
        mov edx, eax
        shr edx, 16
        mov edi, edx
        mov edx, ebx
        shr edx, 16
        shl edx, 4
        add edi, edx
        mov dl, [maze+edi]
        cmp dl, 0
        jne @Hit

        {move}
        add eax, _dx
        add ebx, _dy

        dec ecx
        jnz @Loop

        jmp @Miss

    @Hit:

        xor eax, eax
        mov ax, steps
        sub eax, ecx

        mov id, dl
        mov distance, ax

        jmp @Exit

    @Miss:

    @Exit:

        popa
        end;

    if id > 0 then begin
        trace_mmx.id := id;
        trace_mmx .distance := distance * STEP_SIZE;
        hits := hits + 1;
    end;
end;


function trace(x, y, dir: single): THitRecord;
{trace through the maze, return how many steps until we
collide with an object, or -1 if we do not hit anything}
var
    dx, dy: single;
    mx, my: integer;
    i: integer;

    _dx, _dy: int32;
    _x, _y: int32;

    steps: integer;
    id: byte;
    distance: integer;

const
    STEP_SIZE = 0.1;

begin
    id:=0;

    trace.id := -1;
    trace.distance := 0;

    dx := sin(dir*DEG_TO_RAD) * STEP_SIZE;
    dy := -cos(dir*DEG_TO_RAD) * STEP_SIZE;

    _dx := trunc(dx * 65536);
    _dy := trunc(dy * 65536);
    _x := trunc(x * 65536);
    _y := trunc(y * 65536);


    steps := round(16.0 / STEP_SIZE);


    {rewrite with MMX}

    asm
        pusha
        xor ecx, ecx
        mov cx, steps

        mov eax, _x
        mov ebx, _y

    @Loop:

        {check}
        mov edx, eax
        shr edx, 16
        mov edi, edx
        mov edx, ebx
        shr edx, 16
        shl edx, 4
        add edi, edx
        mov dl, [maze+edi]
        cmp dl, 0
        jne @Hit

        {move}
        add eax, _dx
        add ebx, _dy

        dec ecx
        jnz @Loop

        jmp @Miss

    @Hit:

        xor eax, eax
        mov ax, steps
        sub eax, ecx

        mov id, dl
        mov distance, ax

        jmp @Exit

    @Miss:

    @Exit:

        popa
        end;

    if id > 0 then begin
        trace.id := id;
        trace.distance := distance * STEP_SIZE;
        hits := hits + 1;
    end;
    (*


    for i := 0 to steps do begin
        _x  := _x + _dx;
        _y := _y + _dy;
        mx := _x div  65536;
        my := _y div 65536;
        if (word(mx) and word(my)) >= 16 then
            exit;
        {if (mx < 0) or (my < 0) then
            exit;
        if (mx > 15) or (my > 15) then
            exit; }
        if maze[mx, my] > 0 then begin
            trace.distance := i * STEP_SIZE;
            trace.id := maze[mx, my];
            hits := hits + 1;
            exit;
        end;
    end;
    *)
end;

procedure vline(x, y1, y2 : integer; col:byte);
var
    y: integer;
    ofs: int32;
    h: integer;
begin

    if (x < 0) or (x > 320) then
        exit;

    if y1 >= y2 then
        exit;

    ofs := x + (y1 * 320);
    h := y2-y1+1;

asm
    pusha
    mov edi, $A0000
    add edi, ofs
    mov al, col
    xor ecx, ecx
    mov cx, h
    mov ebx, 320
@loop:
    mov fs:[edi], al
    add edi, ebx
    loop @loop
    popa
    end;
end;

procedure cls(col: RGBA);
begin
  filldword(BUFFER, 320*200, 0);
end;


procedure flip();
begin
asm
    push es

    mov ecx, 320*240
    lea edi, BUFFER

    mov es, LFB
    xor esi, esi

    mov ebx, 0

@LOOP:
    mov eax, ds:[edi+ebx*4]
    mov es:[esi+ebx*4], eax

    inc ebx

    dec ecx
    jnz @LOOP

    pop es

    end;
end;


procedure textMode();
begin
asm
    mov ax, 3h
    int 10h
    end;
end;


procedure render(x, y, angle: single);
{render the viewport}
var
    angleOffset: single;
    dist: single;
    hit: THitRecord;
    i: integer;
    height: integer;
const
    DOF: single = 90;
begin
{cls(3);}
for i := 0 to 320 do begin
    angleOffset := (DOF * (i / 320)) - (DOF/2);
    hit := trace_mmx(x, y, angle +  angleOffset);
    if hit.id > 0 then begin
        height := round(200 / Cos(angleOffset*DEG_TO_RAD) / (hit.distance+0.1));
        if height > 99 then
            height := 99;
        vline(i, 0, 100-height, 3);
        vline(i, 100-height, 100+height, 10+hit.id);
        vline(i, 100+height, 199, 3);
    end else
        vline(i, 0, 199, 3);
    end;
end;

function clip(x, corner, max: integer): integer;
var rep: integer;
begin

    rep := max - corner*2;

    if x < corner then
        result := x
    else if x < corner + rep then
        result := corner
    else
        result := (corner*2) + (x-max)
end;

       {
procedure nineSlice(drawX, drawY: integer; width, height: integer; corner: integer);
var
    px: integer;
    py: integer;
    col: byte;
begin
  for x := 0 to width do begin
    for y := 0 to height do begin
      px := clip(x, 8, width);
      py := clip(y, 8, height);
      col := getPixel(px, py);
      putPixel(drawX+x, drawY+y, col);
      end;
  end;
end;  }


procedure line(x1, y1, x2, y2: integer; col: RGBA);
{draw a line from p1 to p2

implementation from wikipedia Bresenham's line algorithm.

}
var
    x,y: integer;
    dx, dy: integer;
    sx, sy: integer;
    error, e2: integer;
    counter: integer;
begin
    dx := abs(x2 - x1);
    if x1 < x2 then sx := 1 else sx := -1;
    dy := -abs(y2 - y1);
    if y1 < y2 then sy := 1 else sy := -1;
    error := dx + dy;
    x := x1;
    y := y1;
    counter := 100;

    while counter > 0 do begin
        putPixel(x, y, col);
        if (x = x2) and (y = y2) then break;
        e2 := 2 * error;
        if e2 >= dy then begin
            if x = x2 then break;
            error := error + dy;
            x := x + sx;
        end;
        if e2 <= dx then begin
            if y = y2 then break;
            error := error + dx;
            y := y + sy;
        end;
        counter := counter - 1;
    end;

end;

(*
procedure vline2(x1, y1, height: integer; tx, ty1, ty2: integer);
{draw a vertial line}
var
    x,y, i: integer;
    sty: int32;
    dty: int32;
    col: byte;
begin
    x := x1;
    y := y1;

    dty := round((1<<16) * ((ty2 - ty1)+1) / (height));
    sty := ty1 << 16;

    if height <= 0 then exit;
    for i := 0 to height-1 do begin
        col := getPixel(tx , sty >> 16);
        putPixel(x, y, col);
        y := y + 1;
        sty := sty + dty;
    end;
end;
  *)

procedure vline3(x1, y1, y2: int32; u, v1, v2: single);
{draw a vertial line}
var
    height: integer;
    ru, sv, sdv: int32;
    dty: dword;
    col: byte;
    screenAddr, textureAddr: dword;
    t: single;
begin

    {clipping}
    if (y2 < y1) then exit();
    if (x1 < 0) or (x1 >= 320) then exit();
    if (y1 < 0) then begin
        t := (0 - y1) / ((y2 - y1) + 1);
        y1 := 0;
        v1 := v1 + (v2 - v1) * t;
    end;
    if (y2 > 199) then begin
        t := (199 - y1) / ((y2 - y1) + 1);
        y2 := 199;
        v2 := v1 + (v2 - v1) * t;
    end;

    height := (y2 - y1)+1;

    // nothing to draw.
    if (height <= 0) then exit;


    {work out our texture coords}
    ru := trunc(u * 64) and $3F;
    sv := trunc(64 * v1 * 65536);
    sdv := trunc((64 * (v2 - v1) / height) * 65536);

    screenAddr := x1 + (y1*320);
    textureAddr := ru * 64;

    asm

        mov cx, height

        // buffer address
        mov edi, screenAddr

        //texture
        mov esi, textureaddr
        shl esi, 2

        mov edx, sv

    @Loop:

        mov ebx, edx
        shr ebx, 16
        and bx,  $3F  {modulate by texture width of 64}
        mov eax, defaultTexture.texels[esi + ebx * 4]
        mov BUFFER[edi * 4], eax

        add edi, 320
        add edx, sdv

        dec cx
        jnz @Loop

        end;
end;


procedure vline4(x1, y1, y2: int32; col: RGBA);
{draw a vertial line of solid color}
var
    height: integer;
    screenAddr: dword;
begin

    {clipping}
    if (y2 < y1) then exit();
    if (x < 0) or (x >= 320) then exit();
    if (y1 < 0) then y1 := 0;
    if (y2 > 199) then y2 := 199;

    height := (y2 - y1)+1;

    // nothing to draw.
    if (height <= 0) then exit;

    screenAddr := x1 + (y1*320);

    asm
        mov cx, height
        mov eax, col
        mov edi, screenAddr
    @Loop:
        mov BUFFER[edi*4], eax
        add edi, 320
        dec cx
        jnz @Loop
        end;
end;


type Pnt2D = record
    x, y: integer
    end;


function worldToScreen(w: V3D): Pnt2D;
var
    z: single;
begin
    z := w.z;
    if (z < 1) then z := 1;
    {1.2 due to non-square pixels}
    result.x := round((200/1.2)*((w.x / z)) + (320/2));
    result.y := round(200*((w.y / z)) + (200/2));
end;

function lerp(a, b, factor: single): single;
begin
    if factor < 0 then factor := 0;
    if factor > 1 then factor := 1;
    result := (a * (1-factor)) + (b * factor);
end;

var
    zbuffer: array[0..319] of single;

procedure wallPoly(w1, w2: V3D);
{draws a wall aligned polgyon in world space}
var
    p1, p2, tmp: Pnt2D;
    tmpw: V3D;

    t: single;
    uz1, uz2, invz1, invz2: single;
    x, height: int32;
    z: single;
    hh: single;
    h2: int32;
    u: single;
    f: Frustrum;
    y1, y2: int32;

    uv1, uv2: V2D;
    tuv: V2D;

    clipResult: integer;
begin

    {frustrum clipping}

    f := Frustrum.Create(80, 10, 500);
    uv1 := V2D.create(0.0, 0.0);
    uv2 := V2D.create(1.0, 1.0);
    clipResult := f.clip2d(w1, w2, uv1, uv2);
    if clipResult < 0 then exit();

    {map from world to screen}
    p1 := worldToScreen(w1);
    p2 := worldToScreen(w2);

    if p1.x > p2.x then begin
        tmpw := w1;
        w1 := w2;
        w2 := tmpw;
        tmp := p1;
        p1 := p2;
        p2 := tmp;
        tuv := uv1;
        uv1 := uv2;
        uv2 := tuv;
    end;



    uz1 := uv1.x/w1.z;
    uz2 := uv2.x/w2.z;
    invz1 := 1/w1.z;
    invz2 := 1/w2.z;

    {scan x}
    for x := p1.x to p2.x do begin
        if (x < 0) or (x > 319) then continue;
        t := (x - p1.x) / ((p2.x - p1.x)+1);

        height := 100 - round(lerp(p1.y, p2.y, t));

        y1 := trunc(100 - height);
        y2 := trunc(100 + height);
        z := trunc(1/lerp(invz1, invz2, t));
        if z >= zbuffer[x] then continue;
        zbuffer[x] := z;
        u := lerp(uz1, uz2, t) / lerp(invz1, invz2, t);
        vline3(x, y1, y2, u, 0.0, 1.0);
        // show z depth
        //vline4(x, y1, y2, RGBA.Create(byte(trunc(z)), 0, 0, 0));
    end;

    {debug}
    {
    line(p1.x, p1.y, p2.x, p2.y, 11);
    line(p2.x, p2.y, p2.x, 200-p2.y, 11);
    line(p2.x, 200-p2.y, p1.x, 200-p1.y, 11);
    line(p1.x, 200-p1.y, p1.x, p1.y, 11);
    }


end;


function transformWorld(p, ofs: V3D; theta: single): V3D;
var
    q: V3D;
begin
    {todo: implement V3D maths}
    q.x := p.x - ofs.x;
    q.y := p.y - ofs.y;
    q.z := p.z - ofs.z;

    result.x := q.x * cos(theta) - q.z * sin(theta);
    result.y := q.y;
    result.z := q.x * sin(theta) + q.z * cos(theta);

    //result.z := result.z + 200;
end;


type tWall = record
    p1, p2: V3D;
end;

var key: char;


function check_key(): char;
var output: word;
begin
    asm
        mov ah, 1
        int 16h
        jz @Nokey
    @Key:
        mov ah, 0
        int 16h
        mov output, ax
        jmp @Exit
    @Nokey:
        mov output, 0
    @Exit:
    end;

    result := char(output and $FF);
end;

type SpriteArray = array[0..6, 0..6] of byte;

procedure drawSprite(x,y: integer; arr: SpriteArray);
var
  i,j: integer;
  col: RGBA;
begin
  col.r := 255;
  for i := 0 to 6 do begin
    for j := 0 to 6 do begin
      if (arr[j, i] <> 0) then
        putpixel(x+i, y+j, col);
      end;
  end;
end;

procedure displayNumber(r: single);
{A very crude way to display a number on screen}
var
    s: string;
    c: char;

const
    NUMBERS: array[0..10, 0..6, 0..6] of byte = (
    (
    (0,1,1,0,0,0,0),
    (1,0,0,1,0,0,0),
    (1,0,0,1,0,0,0),
    (1,0,0,1,0,0,0),
    (1,0,0,1,0,0,0),
    (1,0,0,1,0,0,0),
    (0,1,1,0,0,0,0)
    ),
    (
    (0,1,1,0,0,0,0),
    (1,1,1,0,0,0,0),
    (0,0,1,0,0,0,0),
    (0,0,1,0,0,0,0),
    (0,0,1,0,0,0,0),
    (0,0,1,0,0,0,0),
    (1,1,1,1,0,0,0)
    ),
    (
    (1,1,1,1,0,0,0),
    (0,0,0,1,0,0,0),
    (0,0,0,1,0,0,0),
    (0,0,1,0,0,0,0),
    (0,1,0,0,0,0,0),
    (1,0,0,0,0,0,0),
    (1,1,1,1,0,0,0)
    ),
    (
    (1,1,1,0,0,0,0),
    (0,0,0,1,0,0,0),
    (0,0,0,1,0,0,0),
    (0,1,1,1,0,0,0),
    (0,0,0,1,0,0,0),
    (0,0,0,1,0,0,0),
    (1,1,1,0,0,0,0)
    ),
    (
    (1,0,0,0,0,0,0),
    (1,0,0,0,0,0,0),
    (1,0,0,0,0,0,0),
    (1,0,1,0,0,0,0),
    (1,1,1,1,0,0,0),
    (0,0,1,0,0,0,0),
    (0,0,1,0,0,0,0)
    ),
    (
    (1,1,1,1,0,0,0),
    (1,0,0,0,0,0,0),
    (1,0,0,0,0,0,0),
    (1,1,1,1,0,0,0),
    (0,0,0,1,0,0,0),
    (0,0,0,1,0,0,0),
    (1,1,1,0,0,0,0)
    ),
    (
    (0,1,1,1,0,0,0),
    (1,0,0,0,0,0,0),
    (1,0,0,0,0,0,0),
    (1,1,1,0,0,0,0),
    (1,0,0,1,0,0,0),
    (1,0,0,1,0,0,0),
    (0,1,1,0,0,0,0)
    ),
    (
    (1,1,1,1,0,0,0),
    (0,0,0,1,0,0,0),
    (0,0,1,0,0,0,0),
    (0,0,1,0,0,0,0),
    (0,1,0,0,0,0,0),
    (0,1,0,0,0,0,0),
    (1,0,0,0,0,0,0)
    ),
    (
    (0,1,1,0,0,0,0),
    (1,0,0,1,0,0,0),
    (1,0,0,1,0,0,0),
    (0,1,1,0,0,0,0),
    (1,0,0,1,0,0,0),
    (1,0,0,1,0,0,0),
    (0,1,1,0,0,0,0)
    ),
    (
    (0,1,1,0,0,0,0),
    (1,0,0,1,0,0,0),
    (1,0,0,1,0,0,0),
    (0,1,1,1,0,0,0),
    (0,0,0,1,0,0,0),
    (0,0,0,1,0,0,0),
    (0,0,0,1,0,0,0)
    ),
    (
    (0,0,0,0,0,0,0),
    (0,0,0,0,0,0,0),
    (0,0,0,0,0,0,0),
    (0,0,0,0,0,0,0),
    (0,0,0,0,0,0,0),
    (0,0,0,0,0,0,0),
    (0,0,1,0,0,0,0)
    )
    );

begin
    x := 0;
    y := 0;
    s := Format('%6.1f' ,[r]);
    for i := 0 to length(s) do begin
        c := s[i];
        if (ord(c) >= ord('0')) and (ord(c) <= ord('9')) then
            drawSprite(x, y, NUMBERS[ord(c) - ord('0')]);
        if c = '.' then
            drawSprite(x, y, NUMBERS[10]);
        x := x + 5;

    end;
end;


var
    wall: array[0..15] of tWall;
    p1, p2: V3D;
    pos: V3D;
    angle: single;
    SCALE: single;
    counter: integer;

    { time keeping }
    elapsed: double;
    lastTime: double;
    thisTime: double;

    elapsedEMA: single;

const
    SPEED = 100.0;

var
    startTS, endTS: qword;
    startTick, endTick: qword;

begin

// get freq
startTick := getTickCount64();
while getTickCount64() = startTick do;

startTick := getTickCount64();
startTS := getRDTSC();
while getTickCount64() < startTick + 200 do;
endTick := getTickCount64();
endTS := getRDTSC();

rdtscFrequency := (endTS - startTS) / ((endTick - startTick) / 1000);


//test_windows();

initkeyboard();


SCALE := 300;

Randomize;

for i := 0 to 15 do begin
    wall[i].p1.x := (Random - 0.5) * SCALE;
    wall[i].p1.y := -25;
    wall[i].p1.z := (Random - 0.5) * SCALE;

    wall[i].p2.x := wall[i].p1.x + ((Random - 0.5) * 100);
    wall[i].p2.y := -25;
    wall[i].p2.z := wall[i].p1.z + ((Random - 0.5) * 100);
end;


init_320x240x32();

{
for i := 0 to 15 do begin
    maze[i,0] := 1;
    maze[0,i] := 1;
    maze[15,i] := 1;
    maze[i,15] := 1;
end;

maze[9,9] := 2;
 }
{fps?}
{startTime := getSec();}

// for i := 0 to 20 do begin
//     render(8.5, 8.5, i);
// end;

{
nineSlice(10, 10, 100, 100, 8);
nineSlice(50, 50, 100, 10, 8);
nineSlice(20, 120, 100, 20, 8);

line(10, 10, 30, 50, 1);
}

pos.x := 0;
pos.y := 0;
pos.z := -100;


wall[0].p1.x := -50;
wall[0].p1.z := -50;
wall[0].p2.x := +50;
wall[0].p2.z := -50;

wall[1].p1.x := +50;
wall[1].p1.z := -50;
wall[1].p2.x := +50;
wall[1].p2.z := +50;

wall[2].p1.x := +50;
wall[2].p1.z := +50;
wall[2].p2.x := -50;
wall[2].p2.z := +50;


{repeat high, very low wait}
{
asm
    mov ah,03h
    mov al,05h
    mov bh,00h
    mov bl,00h
    int 16h
end;
}

defaultTexture := Texture.Create('c:\src\gfx\wall1.bmp');

lastTime := getSec();
elapsedEMA := 1/100;


repeat
    thisTime := getSec();
    elapsed := thisTime - lastTime;
    lastTime := thisTime;

    elapsedEMA := 0.95 * elapsedEMA + 0.05 * elapsed;

    key := check_key();

    cls(RGBA.Create(0,0,0,0));
    for i := 0 to 319 do begin
        zbuffer[i] := 999;
    end;
    for i := 0 to 2 do begin
        p1 := transformWorld(wall[i].p1, pos, angle);
        p2 := transformWorld(wall[i].p2, pos, angle);
        wallPoly(p1, p2);
    end;


    if KeyPress[key_q] then angle := angle - 2.5 * elapsed;
    if keyPress[key_e] then angle := angle + 2.5 * elapsed;

    if KeyPress[key_w] then begin
        pos.x := pos.x + sin(angle) * SPEED * elapsed;
        pos.z := pos.z + cos(angle) * SPEED * elapsed;
    end;

    if KeyPress[key_s] then begin
        pos.x := pos.x - sin(angle) * SPEED * elapsed;
        pos.z := pos.z - cos(angle) * SPEED * elapsed;
    end;

    if KeyPress[key_a] then begin
        pos.x := pos.x - cos(angle) * SPEED * elapsed;
        pos.z := pos.z + sin(angle) * SPEED * elapsed;
    end;

    if KeyPress[key_d] then begin
        pos.x := pos.x + cos(angle) * SPEED * elapsed;
        pos.z := pos.z - sin(angle) * SPEED * elapsed;
    end;

    fps := 1 / (elapsedEMA + 0.0001);

    displayNumber(fps);

    flip();

    counter := counter + 1;

{endTime := getSec();}

{fps := 200 / (endTime-startTime);}

until KeyPress[key_esc];


textMode();


writeln(trunc(pos.x), trunc(pos.y), trunc(pos.z));

{
writeln(fps:0:2);

repeat
until KeyPressed;
}

{ writeln('hits ', hits);}


writeln(trunc(rdtscFrequency));

end.


