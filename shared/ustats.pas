{helper for stats}
unit uStats;

interface

uses
  uTest;

type
  tStats = record
    alpha: single;
    m1, m2: double;
    n: int32;
    minValue, maxValue: int64;
    ema: double;
    procedure addValue(x: int32);
    procedure init(clearEMA: boolean=true);
    function  mean: double;
    function  variance: double;
  end;

implementation

procedure tStats.init(clearEMA: boolean=true);
begin
  m1 := 0; m2 := 0; n := 0; alpha := 0.985;
  minValue := high(int64); maxValue := low(int64);
  if clearEMA then
    ema := 0;
end;

procedure tStats.addValue(x: int32);
begin
  m1 += x;
  m2 += ((x*1.0)*x);
  if x < minValue then minValue := x;
  if x > maxValue then maxValue := x;
  ema := (alpha * ema) + (1-alpha) * x;
  inc(n);
end;

function tStats.mean: double;
begin
  result := m1 / n;
end;

function tStats.variance: double;
begin
  result := (m2/n) - (mean*mean);
end;

{--------------------------------------------------------}

type
  tStatsTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tStatsTest.run();
var
  st: tStats;
begin
  st.init();
  st.addValue(-5);
  st.addValue(5);
  assertEqual(st.mean, 0);
  assertEqual(st.variance, 25);
  st.addValue(9);
  assertEqual(st.mean, 3);
  assertClose(st.variance, 34.66666667);
end;

{--------------------------------------------------------}

initialization
  tStatsTest.create('Stats');
finalization

end.
