{
Sand simulation

Purpose: test how fast we can do cellura automa based
simulations on a p166


[*] get basics working
[*] colors
[*] pushing physics
[*] explosions
[*] scaled int
[ ] impact map
[ ] move one pixel at a time
[ ] chunks?
[ ] pixels can sleep (and then move)
[ ] interaction via mouse clicks.
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

{todo: switch to scaled integer and update in one go, maybe with MMX?}
{for MMX we want 16.16 I guess, so two 32bit if that can be done, otherwise 8.8 and update two cells at once}
{also, use seperate array for typeid and for speed (and then do attributes elsewhere}
type tCell = packed record
	typeId: byte;
  col: byte;
  lastUpdated: word;
	end; {32 bits}

type tCellPos = packed record
  x,y: int32;
  vx,vy: int32;
  ix,iy: int32; {impact}
  end;

type tSlot = packed record
	didUpdate: boolean;
	end;

var
	grid: array[0..GRID_HEIGHT-1, 0..GRID_WIDTH-1] of tCell;
	gridPos: array[0..GRID_HEIGHT-1, 0..GRID_WIDTH-1] of tCellPos;
  impact: array[0..GRID_HEIGHT-1, 0..GRID_WIDTH-1] of single;
  impactTMP: array[0..GRID_HEIGHT-1, 0..GRID_WIDTH-1] of single;
  step: word;


  stats: tStats;


{propigate impact force}
{I think I can do this via a buffer... the seperatable thing
 works for diffusion, but not streaming... maybe we have two steps?
 also, pushing works better than receiving, as it's easier to make sure
 density is consistant.


 rule1: we conserve presure. (except on boundaries)
 rule2: presure may only move from high to low.
}
function updateImpact():single;
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

{0 = black, 1=white}
procedure putScala(x,y: integer; value: single);
var
	c: integer;
begin
	if value < 0 then value := 0;
  if value > 1 then value := 1;
  putPixel(x,y,16 + trunc(value*15.999));
end;

procedure drawGrid();
var
	x,y: int32;
  ofs: int32;
  id: byte;
  col: byte;
  upspeed: single;
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
      {
      if grid[y,x].typeid = 0 then begin
	      putPixel(x, y, 0);
        continue;
      end;
       }
      col := grid[y,x].col;

      //col := col + grid[y, x].typeid;
      //col := col + chunkStatus[y shr CHUNK_SHIFT, x shr CHUNK_SHIFT] * 4;


      {show impact}
      {if (abs(gridPos[y,x].ix) > 0.5) or (abs(gridPos[y,x].iy) > 0.5) then
      	col := 5;}

      {show new impact}
      putScala(x,y,impact[y,x] / 15);


      {putPixel(x,y,byte(trunc(impact[y,x]))); }

      {putPixel(x, y, col);}


      {putScala(x,y,gridPos[y,x].vx);}
    end;

  end;
end;

procedure placeWall(y,x: integer);
begin
	grid[y,x].typeid := 1;
  impact[y,x] := 9999;
end;


procedure initGrid();
var
	x,y: integer;
  i,j: integer;
  id: byte;
begin
	for y := 0 to GRID_HEIGHT-1 do begin
  	for x := 0 to GRID_WIDTH-1 do begin
    	if x < 90 then continue;
    	id := trunc(Random * 1.5);
      grid[y,x].typeid := id;
      grid[y,x].col := 128+trunc(Random * 8);
      grid[y,x].lastUpdated := 0;
      gridPos[y,x].x := x shl 8;
      gridPos[y,x].y := y shl 8;
      gridPos[y,x].vx := trunc(Random-0.5) * 256;
    	{impact[y,x] := trunc(Random*255);}
    end;
  end;


  for i := 30 to 100 do begin
		placeWall(64-1,i);
		placeWall(64+1,i);
		placeWall(74-3,i);
		placeWall(74+3,i);

  end;


  impact[64,64] := 32*256;
  impact[74,64] := 32*256;

  {
  impact[65,64] := 4*256;
  impact[65,65] := 4*256;
  impact[64,65] := 4*256;
   }

end;

{Very slow version
Speed:
}
procedure updateGrid();
var
	cx,cy: int32;
  nx,ny: int32;
  cell: tCell;
  pos: tCellPos;
  steps: int32;


procedure updateCell(cy,cx: int32); inline;
var
	nSteps: int32;
  n: int32;
  ox,oy: int32;
begin

  	grid[cy,cx].typeId := 0;

	  {move}
	  pos.x += pos.vx;
	  pos.y += pos.vy;

	  {bounds}
    if pos.x < 0 then begin
    	pos.x := 0;
      pos.vx := -pos.vx;
    end;
    if pos.y < 0 then pos.y := 0;
    if pos.x > 255*256 then pos.x := 255*256;
    if pos.y > (GRID_HEIGHT-1)*256 then pos.y := (GRID_HEIGHT-1)*256;

    nx := (pos.x shr 8);
    ny := (pos.y shr 8);

    if grid[ny,nx].typeId = 0 then begin
    	{move into new cell}
      gridPos[cy, cx].vy := 0;
      gridPos[cy, cx].vx := 0;
      gridPos[cy, cx].ix := 0;
      gridPos[cy, cx].iy := 0;
      grid[ny, nx] := cell;
      grid[ny, nx].lastUpdated := step;
      gridPos[ny, nx] := pos;
      gridPos[ny, nx].vy += 25;
      if gridPos[ny,nx].vy > 1000 then gridPos[ny,nx].vy := 1000;
    end else begin
	    {we collided}
      gridPos[cy,cx].vx := pos.vx div 2;
      gridPos[cy,cx].vy := pos.vy div 2;
      gridPos[ny, nx].ix += pos.vx div 2;
      gridPos[ny, nx].iy += pos.vy div 2;
      {apply some jitter}
      gridPos[cy, cx].vx += trunc((random - 0.5)*256);

      {this isn't needed, but do it anyway for book keeping}
      grid[cy,cx].lastUpdated := step;

      grid[cy,cx].typeId := 2;
    	grid[cy,cx].col += 1;
    end;


end;

begin
	step += 1;


  for cy := 0 to GRID_HEIGHT-1 do begin
  	for cx := 0 to 255 do begin
      {update our impact}
      {todo: turn unused impact into heat}
	    gridPos[cy,cx].vx += gridPos[cy,cx].ix div 2;
	    gridPos[cy,cx].vy += gridPos[cy,cx].iy div 2;
	    gridPos[cy,cx].ix := gridPos[cy,cx].ix div 2;
	    gridPos[cy,cx].iy := gridPos[cy,cx].iy div 2;
    end;
  end;

	for cy := 0 to GRID_HEIGHT-1 do begin
  	for cx := 0 to 255 do begin
    	cell := grid[cy,cx];
      pos := gridPos[cy, cx];
      {Don't update cells twice, even if they've moved}
      if cell.lastUpdated >= step then continue;
		
    	if cell.typeid = 2 then begin
      	if (cy < GRID_HEIGHT-1) and (grid[cy+1,cx].typeid=0) then begin
        	cell.typeid := 1;
          grid[cy,cx].typeid := 1;
        end;
      end;

     	if cell.typeId = 1 then begin
      	updateCell(cy, cx);
      end;
	  end;
  end;
end;


procedure explosion(ox,oy: integer; radius: single; strength: single);
var
	dst: single;
  dx,dy: single;
  normx,normy: single;
  power: single;
  x,y: integer;

begin
	for y := 0 to GRID_HEIGHT-1 do begin
		for x := 0 to GRID_WIDTH-1 do begin
    	if grid[y,x].typeid=0 then continue;
	  	dx := ox-x;
	    dy := oy-y;
	  	dst := sqrt((dx*dx) + (dy*dy));
	    normx := dx / (dst+0.001);
	    normy := dy / (dst+0.001);
	    if dst > radius then continue;
	    power := strength / dst;
      if power > 5 then power := 5;
	    gridPos[y,x].ix := trunc((-normx * power)*256);
	    gridPos[y,x].iy := trunc((-normy * power)*256);
      grid[y,x].typeid := 1;

	    {show explosion}
	    {grid[y,x].col := 1;}
  	end;
	end;
end;

var
	i: integer;
  dx, dy: integer;
  msPerUpdate: double;
  den1,den2: single;

begin

	randomize();
	init_320x200x8();

  initGrid();

	drawGrid();


  stats.startTime := getSec();

  step := 0;

  den1 := 256;

  for i := 0 to 50 do begin

  	{updateGrid();}
    den2 := updateImpact();
	  drawGrid();
		stats.updates := stats.updates + 1;
    if i >= 200 then begin
	  	{if readkey = 'q' then break;}
    end;
    if i = 100 then begin
    	explosion(128, 158, 40, 100);
      drawGrid();
      {if readkey = 'q' then break;}
    end;


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
  writeln(den1:0:2);
  writeln(den2:0:2);
  	 	
end.
