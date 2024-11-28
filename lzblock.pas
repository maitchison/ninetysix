unit LZBlock;

{$MODE Delphi}

{$DEFINE debug}

interface

uses
	sysutils; {change to utils}

type
	{todo: fix this}
  tLZBlockData = array[0..65535] of byte;

  tTokenData = array[0..65535] of word;

  tTokens = class
  	data: TTokenData;
    pos: dWord;

    constructor Create();
    function toBytes(): TBytes;
    class function fromBytes(bytes: TBytes): tTokens; static;
    procedure writeToken(w:word); register; inline;
    function len: word;
  end;

	tLZBlock = class
    data: tLZBlockData;
    pos: dWord;
    halfByte: boolean;

    constructor Create();
    procedure align(); register; inline;
    procedure writeNibble(n:byte); register; inline;
    procedure writeByte(b:byte); register; inline;
    procedure writeWord(w:word); register; inline;

    {todo: move these?}
    procedure writeToken(token:dword; rle: byte=0);
		procedure writeTokenPair(token1, token2:dword);
		procedure writeTokenVar(token: dword);

    function toBytes(): TBytes;
    class function fromBytes(bytes: TBytes): tLZBlock; static;

    class function getSequenceSize(matchLength: integer;numLiterals: word): word;
    procedure writeSequence(matchLength: integer;offset: word;literals: TBytes);
    procedure writeEndSequence(literals: TBytes);
  end;


implementation

const
	MIN_MATCH_LENGTH = 4;

{---------------------------------------------------------------}
{TODO: use utils instead}

function max(a,b: integer): integer;
begin
	if a > b then exit(a);
  exit(b);
end;

function min(a,b: integer): integer;
begin
	if a < b then exit(a);
  exit(b);
end;


{---------------------------------------------------------------}
{ tTokens}
{---------------------------------------------------------------}

constructor tTokens.Create();
begin
	pos := 0;
end;

function tTokens.toBytes(): TBytes;
var
	i: integer;
  block: tLZBlock;
begin
	block := tLZBlock.Create();
	for i := 0 to pos-1 do begin
  	block.writeTokenVar(self.data[i]);
  end;
  result := block.toBytes();
end;

class function tTokens.fromBytes(bytes: TBytes): tTokens; static;
var
	i: integer;
begin
	result := tTokens.Create();
	for i := 0 to length(bytes)-1 do begin
  	result.data[i] := bytes[i];
  end;
  result.pos := length(bytes);
end;

procedure tTokens.writeToken(w:word); register; inline;
begin
	self.data[self.pos] := w;
	inc(self.pos);
end;

function tTokens.len: word;
begin
	result := pos;
end;


{---------------------------------------------------------------}
{ tLZBlock}
{---------------------------------------------------------------}

constructor tLZBlock.Create();
begin
  pos := 0;
  halfByte := False;
end;

procedure tLZBlock.align(); register; inline;
{writes a nibble if we are halfway though a nibble}
begin
	if halfByte then writeNibble(0);
end;

procedure tLZBlock.writeNibble(n: byte); register; inline;
begin
	{$IFDEF debug}
	if (n and $F) <> n then RunError(201);
	{$ENDIF}

	if halfByte then begin
		data[pos] := data[pos] or (n shl 4);  	
  	halfByte := False;
    inc(pos);
  end else begin
  	data[pos] := n;
  	halfByte := True;
  end;
end;

procedure tLZBlock.writeByte(b: byte); register; inline;
begin
	data[pos] := b;
  inc(pos); 	
end;

procedure tLZBlock.writeWord(w: word); register; inline;
begin
	pWord(@data[pos])^ := w;
  inc(pos, 2);
end;

{write a variable length encoded token}
procedure tLZBlock.writeToken(token:dword; rle: byte=0);
begin
	{this is the simpler byte aligned method}

  {$IFDEF Debug}
  if (rle > 7) then RunError(201);
  if (rle > 0) and (token > 7) then RunError(201);
  {$ENDIF}

  if token < 8 then
    {single token, with optional RLE}
    writeByte($8 and token + (rle shl 4))
  else if token < 64 then
  	writeByte(token)
  else if token < 512 then
  	writeWord($4000 + token)
  else
  	RunError(201);	
end;

procedure tLZBlock.writeTokenPair(token1, token2:dword);
begin
  {$IFDEF Debug}
  if (token1 > 7) or (token2 > 7) then RunError(201);
  {$ENDIF}
  writeByte(8+token1 + (8+token2) shl 4);
end;


{write a variable length encoded token}
procedure tLZBlock.writeTokenVar(token: dword);
var
	nibble: byte;
begin

	{this is the nibble aligned method}
  while token > 0 do begin
  	nibble := token and $7;
    token := token shr 3;
    if token = 0 then
    	writeNibble(nibble)
    else
    	writeNibble($8+nibble);  	
  end;
end;

{returns the number of bytes required to encode block}
class function tLZBlock.GetSequenceSize(matchLength: integer;numLiterals: word): word;
var
	a,b: int32;
  bytesRequired: word;
begin
	bytesRequired := 1; {for token}
  a := numLiterals;
  b := matchLength - MIN_MATCH_LENGTH;
  a -= 15;
  while a > 0 do begin
  	inc(bytesRequired);
    a -= 255;
  end;
  b -= 15;
  while b > 0 do begin
  	inc(bytesRequired);
    b -= 255;
  end;

  bytesRequired += numLiterals;
  bytesRequired += 2; {offset}
  result := bytesRequired;	
end;

procedure tLZBlock.writeEndSequence(literals: TBytes);
var
	i: int32;
	a: int32;
begin
	a := length(literals);
  WriteByte(min(a, 15));
  a -= 15;
  while a > 0 do begin
  	writeByte(min(a, 255));
    a -= 255;
  end;
  if length(literals) > 0 then
	  for i := 0 to length(literals)-1 do
  		writeByte(literals[i]);
end;

procedure tLZBlock.writeSequence(matchLength: integer;offset: word;literals: TBytes);
var
	numLiterals: word;
  a,b: int32;
  i: word;
  startSize: int32;
begin

	startSize := pos;

	{note: literals may be empty, but match and offset may not}

	{
	write('Block: ');
  if length(literals) > 0 then
	  for i := 0 to length(literals)-1 do
	  	write(sanitize(literals[i]))
  else
  	write(' <empty>');
  write(' + copy ', matchLength, ' bytes from ', offset);
  writeln();
  }

	numLiterals := Length(literals);

  if matchLength < 4 then begin
  	writeln('Invalid match length!');  	
  	halt;
  end;


  a := numLiterals;
  b := matchLength-MIN_MATCH_LENGTH;
		
  WriteByte(min(a, 15) + min(b,15) * 16);
  a -= 15;
  while a > 0 do begin
  	writeByte(min(a, 255));
    a -= 255;
  end;

  if length(literals) > 0 then
	  for i := 0 to length(literals)-1 do
  		writeByte(literals[i]);

  writeWord(offset);

  b -= 15;
  while b > 0 do begin
  	writeByte(min(b, 255));
    b -= 255;
  end;

  {make sure this worked}
	{$IFDEF debug}
  if (pos - startSize) <> getSequenceSize(matchLength, length(literals)) then
  	writeln('Invalid block length!');
  {$ENDIF}
end;


function tLZBLock.toBytes(): TBytes;
begin
	result := nil;
  setLength(result, pos);
  move(data[0], result[0], pos);
end;

class function tLZBlock.fromBytes(bytes: TBytes): tLZBlock; static;
begin
	result := tLZBlock.Create();
  move(bytes[0], result.data[0], length(bytes));
  result.pos := length(bytes);	
end;

begin
end.
