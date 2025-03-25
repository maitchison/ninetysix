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
    fMessages: tStrings;
    scrollOffset: integer;
  protected
    procedure  onKeyPress(code: word); override;
    function   rowHeight(): integer;
    function   maxRows(): integer;
  public
    procedure  scroll(offset: integer);
    procedure  addMessage(s: string); overload;
    procedure  addMessage(s: string; args: array of const); overload;
    procedure  doDraw(const dc: tDrawContext); override;
    constructor Create();
  end;

implementation

procedure tGUIListBox.addMessage(s: string); overload;
begin
  fMessages.append(s);
  isDirty := true;
end;

procedure tGUIListBox.addMessage(s: string; args: array of const); overload;
begin
  addMessage(format(s, args));
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
  if scrollOffset > length(fMessages)-maxRows then scrollOffset := length(fMessages)-maxRows;
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
    messageIdx := length(fMessages)-1-row-scrollOffset;
    if messageIdx < 0 then continue;
    if messageIdx >= length(fMessages) then continue;
    font.textOut(dc.asBlendMode(bmBlit), 1+pad, pad+row*rowHeight, fMessages[messageIdx], RGBA.White);
  end;
end;

constructor tGUIListBox.Create();
begin
  inherited Create();
  backgroundCol := RGBA.Clear;
  setBounds(Rect(0, 0, 200, 100));
end;


begin
end.

