program testfp;

uses
  uDebug,
  uUtils,
  uMath,
  uTimer;

var
  x: single;
  i: integer;
  z: integer;

var
  bias: single;

begin
  x := 1.23;
  startTimer('loop');
  for i := 0 to 1000000-1 do;
  stopTimer('loop');
  bias := getTimer('loop').elapsed;

  startTimer('round');
  for i := 0 to 1000000-1 do z := round(x);
  stopTimer('round');
  writeln(format('%.3f', [getTimer('round').elapsed - bias]));

  startTimer('trunc-');
  for i := 0 to 1000000-1 do z := round(x-0.5);
  stopTimer('trunc-');
  writeln(format('%.3f', [getTimer('trunc-').elapsed - bias]));

  startTimer('trunc');
  for i := 0 to 1000000-1 do z := trunc(x);
  stopTimer('trunc');
  writeln(format('%.3f', [getTimer('trunc').elapsed - bias]));

  startTimer('floor');
  for i := 0 to 1000000-1 do z := floor(x);
  stopTimer('floor');
  writeln(format('%.3f', [getTimer('floor').elapsed - bias]));

  startTimer('ceil');
  for i := 0 to 1000000-1 do z := ceil(x);
  stopTimer('ceil');
  writeln(format('%.3f', [getTimer('ceil').elapsed - bias]));


end.