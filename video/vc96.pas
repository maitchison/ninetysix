unit vc96;

interface

uses
  debug,
  test,
  utils,
  stream,
  graph32,
  patch;

type
  tVideoFileHeader = packed record
    tag: array[1..4] of char; // VC96
    versionSmall, versionLarge: word;
    format: tPatchColorDepth; {todo: this should be frame level, or maybe patch level}
    width, height: word;
    numFrames: int32;
  end;

  tVideoFrameHeader = packed record
    tag: array[1..4] of char; // FRAM (not really needed...)
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
    procedure writeFrame(page: tPage;refPage: tPage=nil);
    procedure close();

  end;

  tVideoReader = class
  protected
    inStream: tStream;
    frameOn: int32;
    fileHeader: tVideoFileHeader;
  public

    constructor create();
    destructor destroy; override;

    function isOpen: boolean;
    procedure open(aFilename: string);
    procedure readFrame(page: tPage);
    procedure close();

    property width: word read fileHeader.width;
    property height: word read fileHeader.height;

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

{-----}

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
  if aWidth mod 4 <> 0 then fatal('Width must be a multiple of 8');
  if aHeight mod 4 <> 0 then fatal('Height must be a multiple of 8');

  {header}
  fillchar(fileHeader, sizeof(fileHeader), 0);
  fileHeader.tag := 'VC96';
  fileHeader.versionSmall := 1;
  fileHeader.versionLarge := 0;
  fileHeader.format := PCD_24; {todo: move to frame level}
  fileHeader.width := aWidth;
  fileHeader.height := aHeight;
  fileHeader.numFrames := -1;

  outStream := tMemoryStream.create();
  outStream.writeBlock(fileHeader, sizeof(fileHeader));
  for i := 1 to (128-sizeof(fileHeader)) do
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

{write a video frame to file. If refPage is given then all patches on
 this reference frame can be used by the encoder to compress the new page.
 Typically this is the previously decoded frame.
 }
procedure tVideoWriter.writeFrame(page: tPage;refPage: tPage=nil);
var
  x,y: integer;
  patch: tPatch;
  frameHeader: tVideoFrameHeader;
  i: integer;
  weOwnPage: boolean;
begin

  if not assigned(refPage) then begin
    refPage := tPage.create(page.width, page.height);
    weOwnPage := true;
  end;
    weOwnPage := false;

  {todo: we can easily handle pages being different sizes via cropping
   and padding (this happens already). Just need to create an offset
   to center them}

  {checks}
  if not assigned(outStream) then fatal('VideoWriter not open, but writeFrame called.');
  assertEqual(page.width, fileHeader.width);
  assertEqual(page.height, fileHeader.height);

  {header}
  frameHeader.tag := 'FRAM';
  frameHeader.frameID := frameOn;
  frameHeader.format := 1; // I guess this means I-frame?
  outStream.writeBlock(frameHeader, sizeof(frameHeader));
  for i := 1 to (32-sizeof(frameHeader)) do
    outStream.writeByte(0);

  {patches}
  fillchar(patch, sizeof(patch), 0);
  patch.colorDepth := fileHeader.format;
  for y := 0 to (page.height div 4)-1 do begin
    for x := 0 to (page.width div 4)-1 do begin
        patch.readFrom(refPage, x*4, y*4);
        patch.readFrom(refPage, x*4, y*4);
        {todo: make this: readFrom, writeBytes (e.g. frame knows its method)}
        patch.solveMinMax();
        patch.map();
        patch.solveDescent();
        patch.map();
        patch.writeBytes(outStream);
    end;
    write('.');
  end;

  writeln();

  inc(frameOn);

  if weOwnPage then page.free;

  {flush}
  outStream.flush();
end;

{-------------------------------------------------------------}

constructor tVideoReader.create();
begin
  inherited create();
end;

destructor tVideoReader.destroy;
begin
  close();
  inherited destroy()
end;

{-----}

function tVideoReader.isOpen: boolean;
begin
  result := assigned(inStream);
end;

procedure tVideoReader.open(aFilename: string);
var
  i: integer;
begin

  if isOpen then close();

  inStream := tMemoryStream.create();
  inStream.readFromFile(aFilename);

  {header}
  inStream.readBlock(fileHeader, sizeof(fileHeader));

  if fileHeader.tag <> 'VC96' then fatal(format('File header tag incorrect, was %s, but expected VC96', [fileHeader.tag]));
  if fileHeader.width mod 4 <> 0 then fatal(format('Expecting width to be a multiple of 4, but was %d', [fileHeader.width]));
  if fileHeader.height mod 4 <> 0 then fatal(format('Expecting height to be a multiple of 4, but was %d', [fileHeader.height]));

  inStream.seek(128);
end;

procedure tVideoReader.close();
begin
  if assigned(inStream) then begin
    inStream.free;
    inStream := nil;
  end;
end;

procedure tVideoReader.readFrame(page: tPage);
var
  x,y: integer;
  patch: tPatch;
  frameHeader: tVideoFrameHeader;
  i: integer;
begin

  {checks}
  if not assigned(inStream) then fatal('VideoReader not open, but readFrame called.');
  assertEqual(page.width, fileHeader.width);
  assertEqual(page.height, fileHeader.height);

  {header}
  inStream.readBlock(frameHeader, sizeof(frameHeader));
  for i := 1 to 32-sizeof(frameHeader) do
    inStream.readByte();
  assertEqual(frameHeader.tag, 'FRAM');

  {patches}
  fillchar(patch, sizeof(patch), 0);
  patch.colorDepth := fileHeader.format;
  for y := 0 to (page.height div 4)-1 do begin
    for x := 0 to (page.width div 4)-1 do begin
      patch.readBytes(inStream);
      patch.writeTo(page, x*4, y*4);
    end;
    write('.');
  end;

  writeln();

  inc(frameOn);

end;

begin
end.
