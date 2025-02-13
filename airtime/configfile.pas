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
    BPP: byte;
  end;

const
  config: tAirtimeConfig = (
    VSYNC:false;
    XMAS:false;
    DEBUG:false;
    FPS:true;
    HIGHRES: false;
    FORCE_COPY: false;
    BPP: 0; //this denotes max BPP, real might be lower. 0=auto
  );

implementation

uses
  utils;

procedure processArgs();
var
  i: integer;
begin
  {todo: really need a flags system!}
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
    if toLowerCase(paramStr(i)) = '--bpp=8' then
      config.BPP := 8;
    if toLowerCase(paramStr(i)) = '--bpp=16' then
      config.BPP := 16;
    if toLowerCase(paramStr(i)) = '--bpp=24' then
      config.BPP := 24;
    if toLowerCase(paramStr(i)) = '--bpp=32' then
      config.BPP := 32;
  end;
end;

begin
  processArgs();
end.
