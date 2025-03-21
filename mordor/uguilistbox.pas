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
  protected
    fMessages: tStrings;
  public
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

procedure tGUIListBox.doDraw(const dc: tDrawContext);
var
  messageIdx: integer;
  row: integer;
  rowHeight: integer;
  maxRows: integer;
  fontHeight: integer;
const
  pad: integer = 3;
begin
  inherited doDraw(dc);

  dc.fillRect(bounds, RGBA.Black);
  dc.drawRect(bounds, RGB(rnd,rnd,rnd));


  rowHeight := font.height+1;
  maxRows := floor((bounds.height-2*pad)/rowHeight);

  {display messages}
  for row := 0 to maxRows-1 do begin
    messageIdx := length(fMessages)-1-row;
    if messageIdx < 0 then break;
    font.textOut(dc, 1+pad, pad+row*rowHeight, fMessages[messageIdx], RGBA.White);

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

