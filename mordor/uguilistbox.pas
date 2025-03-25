{messages window for MDR}
unit uGUIListBox;

interface

uses
  uTest,
  uDebug,
  uUtils,
  uGui,
  uRect,
  uGraph32,
  uSprite,
  uScreen,
  uColor,
  uKeyboard,
  uTypes,
  uList,
  uMath,
  uFont;

type
  tGUIListBox = class(tGuiComponent)
  const
    pad = 3;
  protected
    fMessages: pStringList;
    scrollOffset: integer;
    prevSourceLength: int32;
  protected
    procedure  onKeyPress(code: word); override;
    procedure  doUpdate(elapsed: single); override;
    function   rowHeight(): integer;
    function   maxRows(): integer;
  public
    procedure  scroll(offset: integer);
    procedure  doDraw(const dc: tDrawContext); override;
    constructor Create();
    property   source: pStringList read fMessages write fMessages;
  end;

implementation

procedure tGUIListBox.doUpdate(elapsed: single);
begin
  inherited doUpdate(elapsed);
  {for the moment just trigger on length change, which will work for
   append only message logs. In the future have a 'onListChanged' for
   a tStringList}
  if assigned(fMessages) and (fMessages^.len <> prevSourceLength) then begin
    isDirty := true;
    prevSourceLength := fMessages^.len;
  end;
end;

procedure tGUIListBox.onKeyPress(code: word);
begin
  case code of
    key_openSquareBracket: scroll(-1);
    key_closeSquareBracket: scroll(+1);
  end;
end;

function tGuiListBox.rowHeight(): integer;
begin
  result := font.height+1;
end;

function tGuiListBox.maxRows(): integer;
begin
  maxRows := floor((bounds.height-2*pad)/rowHeight);
end;

procedure tGUIListBox.scroll(offset: integer);
begin
  scrollOffset += offset;
  if scrollOffset > fMessages^.len-maxRows then scrollOffset := fMessages^.len-maxRows;
  if scrollOffset < 0 then scrollOffset := 0;
  isDirty := true;
end;

procedure tGUIListBox.doDraw(const dc: tDrawContext);
var
  messageIdx: integer;
  row: integer;
  fontHeight: integer;
begin
  dc.asBlendMode(bmBlit).fillRect(bounds, RGBA.Clear);
  {display messages}
  for row := 0 to maxRows-1 do begin
    messageIdx := fMessages^.len-1-row-scrollOffset;
    if messageIdx < 0 then continue;
    if messageIdx >= fMessages^.len then continue;
    font.textOut(dc.asBlendMode(bmBlit), 1+pad, pad+row*rowHeight, fMessages^[messageIdx], RGBA.White);
  end;
end;

constructor tGUIListBox.Create();
begin
  inherited Create();
  backgroundCol := RGBA.Clear;
  setBounds(Rect(0, 0, 200, 100));
  prevSourceLength := -1;
end;


begin
end.

