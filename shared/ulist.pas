{generics based list}
unit uList;

{
Note: generics seems to make FPC crash... :(
}

interface

type
  tListEnumerator = record
    private
      fIndex: Integer;
      fArray: array of string;
      function getCurrent: string;
    public
      function moveNext: boolean;
      property current: string read getCurrent;
    end;

  tList<T> = record
    fItems: array of T;
    procedure append(x: T);
    function  getItem(index: int32): T; inline;
    procedure setItem(index: int32; value: T); inline;
    property  items[index: int32]: T read getItem write setItem; default;
    function  len: integer;
    function  getEnumerator(): tListEnumerator;
  end;

implementation

procedure tList<T>.append(x: T);
begin
  setLength(fItems, length(fItems)+1);
  items[length(fItems)-1] := x;
end;

function tList<T>.len: integer;
begin
  result := length(fItems);
end;

function tList<T>.getEnumerator(): tListEnumerator;
begin
  result.fArray := fItems;
  result.fIndex := -1;
end;

function  tList<T>.getItem(index: int32): T;
begin
  result := fItems[index];
end;

procedure tList<T>.setItem(index: int32; value: T);
begin
  fItems[index] := value;
end;

{-----------------------------------------------------------}

function tListEnumerator.moveNext: boolean;
begin
  inc(fIndex);
  result := fIndex < length(fArray);
end;

function tListEnumerator.getCurrent: string;
begin
  result := fArray[fIndex];
end;

{-----------------------------------------------------------}

begin
end.
