 {
Sand simulation

Purpose: test how fast we can do cellura automa based
simulations on a p166
}


uses
	crt,
	graph32,
  screen,
  time,
  graph3d;


const
	GRID_WIDTH = 256;
	GRID_HEIGHT = 192;
	CHUNK_SIZE = 16;
	CHUNK_SHIFT = 4;
  CHUNKS_WIDTH = GRID_WIDTH div CHUNK_SIZE;
  CHUNKS_HEIGHT = GRID_HEIGHT div CHUNK_SIZE;


type TStats = record
	updates: int32;
  startTime: double;
  endTime: Double;
  chunksUpdated: int32;
  chunksSkipped: int32;
end;

var
	grid: array[0..GRID_HEIGHT-1, 0..GRID_WIDTH-1] of byte;
	timer: array[0..GRID_HEIGHT-1, 0..GRID_WIDTH-1] of int32; {used for movement speed}
  speed: array[0..GRID_HEIGHT-1, 0..GRID_WIDTH-1] of int32; {used for movement speed}


  chunk: array[0..CHUNKS_HEIGHT-1, 0..CHUNKS_WIDTH-1] of int32; {number of non-empty cells}
  chunkStatus: array[0..CHUNKS_HEIGHT-1, 0..CHUNKS_WIDTH-1] of byte; {0=empty, 1=active, 2=locked}

  stats: tStats;


procedure putPixel(x, y: int32; col:rgba);
var
    address: int32;
    ofs: int32;
begin

	if (x < 0) or (x >= 320) then exit;
	if (y < 0) or (y >= 200) then exit;

	ofs := x + (y * 320);

	asm
		push es
    mov edi, ofs
    mov ax, LFB
    mov es, ax

    xor eax, eax
    mov al, col.r
    shl eax, 8
    mov al, col.g
    shl eax, 8
    mov al, col.b

    mov es:[edi*1], eax
    pop es
  	end
end;

procedure putPixel(x, y: int32; col:byte);
var
    address: int32;
    ofs: int32;
begin

	if (x < 0) or (x >= 320) then exit;
	if (y < 0) or (y >= 200) then exit;

	ofs := x + (y * 320);

  Mem[$A000:ofs] := col

end;

procedure drawGrid();
var
	x,y: int32;
  ofs: int32;
  id: byte;
  col: byte;
begin
	for y := 0 to GRID_HEIGHT-1 do begin
{  	ofs := $A0000 + y * 320;
  	asm
      mov esi, ofs
      mov ecx, 255
      mov edi, y
      shl edi, 8

    @LOOP:
    	mov al, es:[grid + edi]
    	mov fs:[esi], al
      inc esi
      inc edi
    	dec ecx
      jnz @LOOP

    end;}

  	for x := 0 to GRID_WIDTH-1 do begin
    	col := 0;
      col := col + grid[y, x];
      //col := col + chunkStatus[y shr CHUNK_SHIFT, x shr CHUNK_SHIFT] * 4;
    	
      putPixel(x, y, col );
    end;

  end;
end;


procedure initGrid();
var
	x,y: integer;
  id: byte;
begin
	fillchar(chunk, sizeof(chunk), 0);
	for y := 0 to GRID_HEIGHT-1 do begin
  	for x := 0 to GRID_WIDTH-1 do begin
    	id := byte(round(int(Random * 1.5)));
      grid[y,x] := id;
      if (id > 0) then inc(chunk[y shr CHUNK_SHIFT, x shr CHUNK_SHIFT]);
    end;
  end;
end;

{Speeds:

(Draw is 6ms)
Asm version 2ms
Pascal (without checks) 4.3ms... ok this is fast enough nice.
Also, jump table might be faster.
I think this means I can implement speed as delay... With a max speed of like 4 tiles per update.

If I run at quarter resolution, then 120 updates per second can be done I think.
This means I need update to be around 0.5ms, which means assembler I guess... hmm
Ok, do this in pascal, and just run at half speed for a while.
Goal is 30fps with 120 ups. But might do soid and gas simulation.


What about with chunks?


}
procedure updateGrid_BASE();
var
	x,y: int32;
  id: byte;
begin
	for y := 126 downto 0 do begin
  	for x := 0 to 255 do begin
  		id := grid[y,x];
		  if id = 0 then continue;
		  if id = 1 then begin      	
				if grid[y+1, x] = 0 then begin
		  		grid[y+1, x] := grid[y, x];
					grid[y, x] := 0;
		    end else if (x > 0) and (grid[y+1, x-1] = 0) then begin
		  		grid[y+1, x-1] := grid[y, x];
					grid[y, x] := 0;
		    end else if (x < 255) and (grid[y+1, x+1] = 0) then begin
		  		grid[y+1, x+1] := grid[y, x];
					grid[y, x] := 0;
		    end;
      end;
	  end;
  end;
end;

{Simple implementation...
5.9ms... why slow?
5.0ms, don't update empty chunks
3.2ms, don't update locked chunks
3.0ms, use cx and cy instead of shifting x and y
0.4ms if we don't update any chunks
4.4ms, function call for update cell.
2.4ms, switched to in32 for arguments (why does this make such a difference?)
2.5ms, switch to exit instead of if else

2.0ms, internal asm fast path
2.4ms, switch to generic chunk size... why is this slower?
2.0ms, ok it was sensitive to chunkstatus, I had width instead of width-1 for the array size... hmm
1.6ms, switched to 16x16... interesting..
1.56ms, some more changes...

also... try doing this upside down? if that's going to be our update order...

rules:

1) if we are empty, don't update.
2) if we are full and blocked in U shape, then don't update.

idea: update inner 6x6 within a chunk super fast, use pascal for outter edge,
it's much simpler to update when we stay within a chunk. Also, make chunks 16x16?

}
procedure updateGrid_CHUNKS();
var
	cx, cy, dx, dy, x, y: int32;
  i: int32;
  id: byte;


	function isLocked(cy, cx: int32): boolean; inline;
  begin
  	if cx < 0 then exit(true);
    if cy < 0 then exit(true);
    if cx >= CHUNKS_WIDTH then exit(true);
    if cy >= CHUNKS_HEIGHT then exit(true);
    exit(chunkStatus[cy, cx] = 2);
  end;

  function isFull(cy, cx: int32): boolean; inline;
  begin
  	if cx < 0 then exit(true);
    if cy < 0 then exit(true);
    if cx >= CHUNKS_WIDTH then exit(true);
    if cy >= CHUNKS_HEIGHT then exit(true);
    exit(chunk[cy, cx] = CHUNK_SIZE*CHUNK_SIZE);
  end;


  {Fast path for interal cells, chunk count will not change.}
  procedure processInternalRow(y, x : int32); assembler; inline;
  asm

    	mov edi, y
      shl edi, 8
      add edi, x
      inc edi {start at x+1}
      mov ecx, CHUNK_SIZE-2

    @Loop:

    	mov al, grid[edi]

      cmp al, 0
      je @Done


    //TYPE_1 (assume for the moment...)
    //cmp al, 1
    //jne @Skip1

      { check byte order is correct..}

      mov ax, word ptr grid[edi+256]
      cmp al, 0
      jne @SKIP_T1_DOWN
    	mov grid[edi], 0
      mov grid[edi+256], 1

      jmp @Done

    @SKIP_T1_DOWN:

      mov al, grid[edi+256-1]
      cmp al, 0
      jne @SKIP_T1_LEFT
    	mov grid[edi], 0
      mov grid[edi+256-1], 1

      jmp @Done

    @SKIP_T1_LEFT:

      cmp ah, 0
      jne @SKIP_T1_RIGHT
    	mov grid[edi], 0
      mov grid[edi+256+1], 1

      jmp @Done

    @SKIP_T1_RIGHT:

			jmp @Done


    @Skip1:

    @Done:
      inc edi    	
    	dec ecx
      jnz @Loop


  end;

  {note: expects cx, cy to be set correctly}
  procedure processCell(y, x: int32); inline;
  begin	
		if grid[y,x] = 1 then begin
    	{decrement timer}
    	timer[y,x] -= speed[y,x];
      {increment speed}
      speed[y,x] += 25;
      if (timer[y,x] > 0) then exit;	
		
	    if grid[y+1, x] = 0 then begin
				grid[y, x] := 0;
		  	grid[y+1, x] := 1;
        timer[y+1, x] := timer[y,x] + 1000;

        dec(chunk[cy, cx]);
        inc(chunk[(y+1) shr CHUNK_SHIFT, cx]);
        exit;
      end;

	    if (grid[y+1, x-1] = 0) and (x > 0) then begin
		  	grid[y+1, x-1] := 1;
				grid[y, x] := 0;
        timer[y+1, x-1] := timer[y,x] + 1000;
      	dec(chunk[cy, cx]);
        inc(chunk[(y+1) shr CHUNK_SHIFT, (x-1) shr CHUNK_SHIFT]);
        exit;
	    end;
      	
  	  if (grid[y+1, x+1] = 0) and (x < GRID_WIDTH-1) then begin
		  	grid[y+1, x+1] := 1;
				grid[y, x] := 0;
        timer[y+1, x+1] := timer[y, x] + 1000;
        dec(chunk[cy, cx]);
        inc(chunk[(y+1) shr CHUNK_SHIFT, (x+1) shr CHUNK_SHIFT]);
        exit;
			end;

	    {sitting on something, so stop us and push other down..}
	    speed[y+1,x] += speed[y,x];
  	  speed[y,x] := 0;
		
    end;

  end;


begin


	{calculate chunk status}
  {0.02ms}
  for cy := CHUNKS_HEIGHT-1 downto 0 do begin
    for cx := 0 to CHUNKS_WIDTH-1 do begin
    	if chunk[cy, cx] = 0 then begin
      	chunkStatus[cy, cx] := 0;
        continue;
      end;

      // assume active
      chunkStatus[cy, cx] := 1;

      if chunk[cy, cx] = CHUNK_SIZE*CHUNK_SIZE then begin

        // the cx+1 ones are wrong... as we have not checked them yet.		
        {These chunks update before us, so check if they are blocked}
        if not isLocked(cy, cx-1) then continue;
        if not isLocked(cy+1, cx-1) then continue;
        if not isLocked(cy+1, cx) then continue;
        if not isLocked(cy+1, cx+1) then continue;
				{this chunk updates after us, so just need to know if it is full}
        {note: technically just the right needs to be full...}
        if not isFull(cy, cx+1) then continue;

      	chunkStatus[cy, cx] := 2;      		
        continue;
      end;

    end;
  end;

	for y := GRID_HEIGHT-2 downto 0 do begin
	  cy := y shr CHUNK_SHIFT;
    for cx := 0 to CHUNKS_WIDTH-1 do begin
    	if chunkStatus[cy, cx] <> 1 then begin
      	inc(stats.chunksSkipped);
      	continue;
      end;
      inc(stats.chunksUpdated);
      x := cx shl CHUNK_SHIFT;

      for i := 0 to CHUNK_SIZE-1 do
	  		processCell(y, x+i);

			{
      if (y and (CHUNK_SIZE-1)) = (CHUNK_SIZE-1) then begin
      	for i := 0 to CHUNK_SIZE-1 do
	  			processCell(y, x+i);
      end else begin
				processCell(y, x);
        processInternalRow(y, x);
				processCell(y, x+CHUNK_SIZE-1);
      end;}	
      	
	  end;
  end;
end;



var
	i: integer;
  msPerUpdate: double;

begin

	randomize();
	init_320x200x8();

  initGrid();

	drawGrid();


  stats.startTime := getSec();

  for i := 0 to 400 do begin
  	updateGrid_CHUNKS();
	  {drawGrid(); }
		stats.updates := stats.updates + 1;
  end; 	

  stats.endTime := getSec();

  drawGrid();

  readkey();


  msPerUpdate := (stats.endTime - stats.startTime) * 1000 / stats.updates;
	
  asm
  	mov ax,03
    int $10
    end;
  writeln('MS per update ', msPerUpdate:0:2);
  writeln('Chunks skipped ', (stats.chunksSkipped/(stats.chunksUpdated+stats.chunksSkipped)):0:2);

  	 	
end.
