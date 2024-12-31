unit configfile;

interface

type
  tAirtimeConfig = record
    VSYNC: boolean;
    XMAS: boolean;
    DEBUG: boolean;
    FPS: boolean;
  end;

const
  config: tAirtimeConfig = (
    VSYNC:false;
    XMAS:false;
    DEBUG:false;
    FPS:true;
  );

implementation

uses
  utils;

procedure processArgs();
var
  i: integer;
begin
  for i := 1 to ParamCount do begin
    if toLowerCase(paramStr(i)) = '--xmas' then
      config.XMAS := true;
    if toLowerCase(paramStr(i)) = '--vsync' then
      config.VSYNC := true;
    if toLowerCase(paramStr(i)) = '--debug' then
      config.DEBUG := true;
    if toLowerCase(paramStr(i)) = '--fps' then
      config.FPS := true;
  end;
end;

begin
  processArgs();
end.
