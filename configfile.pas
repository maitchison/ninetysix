unit configfile;

interface

type
  tAirtimeConfig = record
    VSYNC: boolean;
    XMAS: boolean;
    DEBUG: boolean;
    FPS: boolean;
    HIGHRES: boolean;
    FORCE_COPY: boolean;
  end;

const
  config: tAirtimeConfig = (
    VSYNC:false;
    XMAS:false;
    DEBUG:false;
    FPS:true;
    HIGHRES: false;
    FORCE_COPY: false;
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
    if toLowerCase(paramStr(i)) = '--highres' then
      config.HIGHRES := true;
    if toLowerCase(paramStr(i)) = '--force_copy' then
      config.FORCE_COPY := true;
  end;
end;

begin
  processArgs();
end.
