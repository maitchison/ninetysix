unit vc96;

interface

uses
  debug,
  test,
  stream,
  graph32,
  patch;

type
  tVideoFileHeader = packed record
    tag: array[1..4] of char; // VC96
    versionSmall, versionLarge: word;
    format: byte;
    width, height: word;
    numFrames: int32;
  end;

  tVideoFrameHeader = packed record
    frameID: dword;
    format: byte;
  end;

  tVideoWriter = class
  protected
    outFilename: string; // todo: make this part of outstream?
    outStream: tStream;
    frameOn: int32;
    fileHeader: tVideoFileHeader;
  public

    constructor create();
    destructor destroy; override;

    function isOpen: boolean;
    procedure open(aFilename: string;aWidth,aHeight: word);
    procedure writeFrame(page: tPage);
    procedure close();

  end;

implementation

{-------------------------------------------------------------}

constructor tVideoWriter.create();
begin
  inherited create();
end;

destructor tVideoWriter.destroy;
begin
  close();
  inherited destroy()
end;

{-------------------------------------------------------------}

function tVideoWriter.isOpen: boolean;
begin
  result := assigned(outStream);
end;

procedure tVideoWriter.open(aFilename: string;aWidth,aHeight: word);
var
  i: integer;
begin

  if isOpen then close();
  outFilename := aFilename;

  {checks}
  if isOpen then close();
  if aWidth mod 4 <> 0 then error('Width must be a multiple of 8');
  if aHeight mod 4 <> 0 then error('Height must be a multiple of 8');

  {header}
  fillchar(fileHeader, sizeof(fileHeader), 0);
  fileHeader.tag := 'VC96';
  fileHeader.versionSmall := 1;
  fileHeader.versionLarge := 0;
  fileHeader.format := 1; {not really used}
  fileHeader.width := aWidth;
  fileHeader.height := aHeight;
  fileHeader.numFrames := -1;

  outStream := tStream.create();
  outStream.writeBlock(fileHeader, sizeof(fileHeader));
  for i := 0 to 128-sizeof(fileHeader) do
    outStream.writeByte(0);

  {flush}
  outStream.flush()
end;

procedure tVideoWriter.close();
begin
  if isOpen then
    outStream.writeToFile(outFilename);
  if assigned(outStream) then begin
    outStream.free;
    outStream := nil;
  end;
  outFilename := '';
end;

procedure tVideoWriter.writeFrame(page: tPage);
var
  x,y: integer;
  patch: tPatch;
  frameHeader: tVideoFrameHeader;
  i: integer;
begin

  {todo: we can easily handle pages being different sizes via cropping
   and padding (this happens already). Just need to create an offset
   to center them}

  {checks}
  if not assigned(outStream) then error('VideoWriter not open, but writeFrame called.');
  assertEqual(page.width, fileHeader.width);
  assertEqual(page.height, fileHeader.height);

  {header}
  frameHeader.frameID := frameOn;
  frameHeader.format := 1; // I guess this means I-frame?
  outStream.writeBlock(frameHeader, sizeof(frameHeader));
  for i := 0 to 32-sizeof(frameHeader) do
    outStream.writeByte(0);

  {patches}
  patch.colorDepth := PCD_24;
  for y := 0 to (page.height div 4)-1 do begin
    for x := 0 to (page.width div 4)-1 do begin
        patch.readFrom(page, x*4, y*4);
        {todo: make this: readFrom, writeBytes (e.g. frame knows its method)}
        patch.solveDescent();
        patch.map();
        patch.writeBytes(outStream);
    end;
    write('.');
  end;

  writeln();

  inc(frameOn);

  {flush}
  outStream.flush();
end;

begin
end.
