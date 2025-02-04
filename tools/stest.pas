{test performance of my IO stream, as well as some of the encoders}
program sTest;

uses
  debug,
  test,
  crt,
  vlc,
  sysTypes,
  utils,
  fileSystem,
  stream;

var
  testGroup: string;
  testName: string;
  testStartTime: double;
  testEndTime: double;
  testBytes: integer;

procedure setTestGroup(aGroup: string);
begin
  testGroup := aGroup;
  writeln();
  info(testGroup);
  writeln();
end;

procedure startTest(atestName: string);
begin
  testName := aTestName;
  testStartTime := getSec();
end;

procedure stopTest(aBytes: int32);
begin
  testEndTime := getSec();
  testBytes := aBytes;
end;

function testMBPS(): single;
begin
  result := testBytes / 1024 / 1024 / (testEndTime-testStartTime);
end;

procedure displayTestResults();
begin
  note(format('%s %sMB/s', [pad(testName, 40), fltToStr(testMBPS, 2, 8)]));
end;

procedure benchmarkStream(s: tStream; title:string);
const
  numTestBytes = 64*1024;
var
  i: int32;
  startTime, endTime: double;
  buffer: array[0..numTestBytes-1] of byte;

begin

  setTestGroup(title);

  {---------------------------------}
  {read}

  s.reset();
  for i := 1 to numTestBytes do s.writeByte(255);

  s.seek(0);
  startTest('Read BYTE');
  for i := 1 to numTestBytes do s.readByte();
  stopTest(numTestBytes); displayTestResults();

  s.seek(0);
  startTest('Read WORD');
  for i := 1 to numTestBytes div 2 do s.readWord();
  stopTest(numTestBytes); displayTestResults();

  s.seek(0);
  startTest('Read DWORD');
  for i := 1 to numTestBytes div 4 do s.readDword();
  stopTest(numTestBytes); displayTestResults();

  s.seek(0);
  startTest('Read BLOCK');
  s.readBlock(buffer, numTestBytes);
  stopTest(numTestBytes); displayTestResults();

  {---------------------------------}
  {write}

  s.seek(0);
  startTest('Write BYTE');
  for i := 1 to numTestBytes do s.writeByte(255);
  stopTest(numTestBytes); displayTestResults();

  s.seek(0);
  startTest('Write WORD');
  for i := 1 to (numTestBytes div 2) do s.writeWord(255);
  stopTest(numTestBytes); displayTestResults();

  s.seek(0);
  startTest('Write DWORD');
  for i := 1 to (numTestBytes div 4) do s.writeDWord(255);
  stopTest(numTestBytes); displayTestResults();

  s.seek(0);
  startTest('Write BLOCK');
  s.writeBlock(buffer, numTestBytes);
  stopTest(numTestBytes); displayTestResults();

end;

procedure benchmarkVLC();
var
  inData, outData: tDwords;
  i: integer;
  s: tStream;
  startTime, encodeElapsed, decodeElapsed: double;
  segmentType: byte;
  bytes: int32;
  readMBPS, writeMBPS: single;
begin
  setLength(inData, 64000);
  setLength(outData, 64000);
  for i := 0 to length(inData)-1 do
    inData[i] := rnd div 2;

  setTestGroup('Segment R/W');

  {run a bit of a benchmark on random bytes (0..127)}
  s := tMemoryStream.create(2*64*1024);
  note(format('%s     %s    %s (MB/s)', [pad('Segment Type',40), 'Read', 'Write']));
  writeln('-----------------------------------------------------------------');
  for segmentType in [
    ST_VLC1, ST_VLC2, ST_VLC8,
    ST_PACK7, ST_PACK8, ST_PACK9,
    ST_RICE0+6,
    ST_FAST0+6,
    ST_AUTO, ST_PACK, ST_RICE, ST_FAST
  ] do begin

    s.seek(0);
    startTest(getSegmentTypeName(segmentType)+' write');
    bytes := writeSegment(s, inData, segmentType);
    stopTest(2*60*1024); writeMBPS := testMBPS();

    s.seek(0);
    startTest(getSegmentTypeName(segmentType)+ ' read');
    readSegment(s, length(inData), outData);
    stopTest(2*60*1024); readMBPS := testMBPS();

    note(format('%s %s %s', [pad(getSegmentTypeName(segmentType), 40), fltToStr(readMBPS, 2, 8), fltToStr(writeMBPS, 2, 8)]));
  end;

end;

begin
  textAttr := White;
  debug.VERBOSE_SCREEN := llNote;
  benchmarkStream(tMemoryStream.create(), 'MemoryStream R/W');
  benchmarkStream(tFileStream.create('stream.tmp'), 'FileStream R/W');
  benchmarkVLC();
  textAttr := White;
end.
