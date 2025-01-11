{Scaled integer library

The main advantage here is fast (1-2 cycle) additions, everything
else is about the same speed as floating point operations.

The cases where this helps are mostly where you are adding small increments
to x and y co-ordinates.
}


type ScaledInt = record
    value: int32;

    function GetFloat(): single;
    procedure SetFloat(x: single);

    function GetInt(): integer;
    procedure SetInt(x: integer);

    function Inv(): ScaledInt;
    function FastInv(): ScaledInt;

    class operator Add(a, b: ScaledInt): ScaledInt;
    class operator Multiply(a, b: ScaledInt): ScaledInt;
    class operator Divide(a, b: ScaledInt): ScaledInt;
    class operator Divide(a: ScaledInt; b: integer): ScaledInt;
    property asFloat: single read GetFloat write SetFloat;
    property asInt: integer read GetInt write SetInt;
    end;

class operator ScaledInt.Add(a, b: ScaledInt): ScaledInt; inline;
begin
    result.value := a.value + b.value;
end;

class operator ScaledInt.Multiply(a, b: ScaledInt): ScaledInt; inline;
begin
    result.value := (int64(a.value) * b.value) >> 16;
end;

function ScaledInt.Inv(): ScaledInt; inline;
const
    scale_factor: int64 = $FFFFFFFF;
begin
    {A full precision invert}
    {TODO(MA): might be better to do this on floating point}
    result.value := (scale_factor div value);
end;

function ScaledInt.FastInv(): ScaledInt; inline;
const
    scale_factor: int32 = $FFFF;
begin
    {Gives 8.8 precision instead of 16.16 precision but avoids
    a 64bit integer divide which is very slow.}
    result.value := (scale_factor div (value shr 8)) shl 8;
end;


class operator ScaledInt.Divide(a, b: ScaledInt): ScaledInt; inline;
var inv: ScaledInt;
begin
    inv := b.Inv();
    result := a * inv;
end;

class operator ScaledInt.Divide(a: ScaledInt; b: integer): ScaledInt; inline;
begin
    result.value := a.value div b;
end;


procedure ScaledInt.SetFloat(x: single);
begin
    value := round(x * 65536);
end;

function ScaledInt.GetFloat(): single;
begin
    result := (value / 65536);
end;

procedure ScaledInt.SetInt(x: integer);
begin
    value := x << 16;
end;

function ScaledInt.GetInt(): integer;
begin
    result := value >> 16;
end;


var a, b, c: ScaledInt;

begin
    a.asInt := 2;
    b.asInt := 3;
    writeln((a+b).asFloat);
    writeln((a*b).asFloat);
    writeln((b.Inv()).asFloat);
    writeln((b.FastInv()).asFloat);
    writeln((a/b).asFloat);
    writeln((b/2).asFloat);
end.