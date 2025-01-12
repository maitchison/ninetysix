{really just an example to test out new framework}
unit fileref_test;

interface

uses
  test,
  fileref;

implementation

type
  tFileRefTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tFileRefTest.run();
var
  frl: tFileRefList;
begin
  frl := nil;
  assertEqual(length(frl), 0);
  frl.append(tFileRef.create());
  assertEqual(length(frl), 1);
  {note: there's a memory leak here, but leave it in so we can detect it}
end;

begin
  tFileRefTest.create('FileRef');
end.