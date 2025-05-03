program maketile;

{
Script to convert XCOM tile based graphics into VOX files for touch up
and editing in magica voxel.

Some important ideas

color = material type... this kind of sucks, but not sure how else to do it
limite to 256 colors, and they're xcom colors
all lighting must be removed.

input sprites are 32x40
output voxels are 16x16x24

projections:

	cubiod: -> convert as if every voxel is solid of certian height
  full: -> just cuboid with max height
  floor: -> converts a floor tile (just cubiod with low height)
  los: -> use los volume to reproject

The process is

[maketile] -vox file-> [magicaVoxel] -slices-> [game]
[maketile] -slices-> [game]

The game automatically converts the sprite sheets into voxels as needed.

}

uses
	uP96,
  uRect,
  uSprite,
  uColor,
  uVoxel,
  uGraph32,
	uTest,
  uDebug,
  uKeyboard,
	uUtils,
  uMouse,
  uScreen,
  uVESADriver,
  uVGADriver;


type
	tP3D = record
  	x,y,z,w: integer;
  end;

type
  tTile3D = class
  	vox: array[0..23, 0..15, 0..15] of RGBA;
    procedure setSolid(height: integer);
    function reproject(dx,dy: integer): tP3D;
    function getVox(x,y,z: integer): RGBA;
    procedure setVox(x,y,z: integer;v: RGBA);
    procedure paint(s: tSprite);
  end;


var
	screen: tScreen;

{------------------------------------------------}

procedure tTile3D.setSolid(height: integer);
var
	x,y,z: integer;
  col: RGBA;
begin
	for z := 0 to 23 do begin
  	for x := 0 to 15 do begin
    	for y := 0 to 15 do begin
      	if z < height then col := RGB(0,0,0,255) else col := RGB(0,0,0,0);
        setVox(x,y,z,col);
      end;
    end;
  end;
end;

function tTile3D.getVox(x,y,z: integer): RGBA;
begin
	result := RGB(0,0,0,0);
  if dword(x) >= 16 then exit;
  if dword(y) >= 16 then exit;
  if dword(z) >= 24 then exit;
  result := vox[z,y,x];
end;

procedure tTile3D.setVox(x,y,z: integer;v: RGBA);
begin
  if dword(x) >= 16 then exit;
  if dword(y) >= 16 then exit;
  if dword(z) >= 24 then exit;
  vox[z,y,x] := v;
end;

function tTile3D.reproject(dx,dy: integer): tP3D;
var
	dz: integer;
  p: tP3D;
begin
	for dz := 0 to 32 do begin
  	p.x := (dz + dx) div 2;
    p.y := (dz - dx) div 2;
    p.z := dy + (dz div 2);
    if getVox(p.x,p.y,p.z).a <> 0 then exit(p);
  end;
  result.x := -1;
end;

procedure tTile3D.paint(s: tSprite);
var
	x,y: integer;
  col: RGBA;
  p: tP3D;
begin
	for x := 0 to 31 do begin
  	for y := 0 to 39 do begin
    	col := s.getPixel(x,y);
      if col = RGB(255,0,255) then continue;
      p := reproject(x,y);
      if p.x >= 0 then setVox(p.x, p.y, p.z, col);
    end;
  end;
end;

var
	page: tPage;
  tile: tTile3D;
  sprite: tSprite;

begin
  {set video}
  enableVideoDriver(tVesaDriver.create());
  if (tVesaDriver(videoDriver).vesaVersion) < 2.0 then
    fatal('Requires VESA 2.0 or greater.');
  if (tVesaDriver(videoDriver).videoMemory) < 1*1024*1024 then
    fatal('Requires 1MB video card.');
  videoDriver.setTrueColor(320, 240);
  initMouse();
  initKeyboard();
  screen := tScreen.create();
  screen.scrollMode := SSM_COPY;

  {convert sprite}

  page := tPage.Load('res\cultivate.p96');

  tile := tTile3D.Create();
  sprite := tSprite.Create(page, Rect(0, 464, 32, 40));
  tile.setSolid(1);
  tile.paint(sprite);

  {show it}
  repeat
  	sprite.draw(screen.canvas.getDC, 10, 10);

    screen.pageFlip();


  until keyDown(key_esc);

  {shut down}
  videoDriver.setText();

end.
