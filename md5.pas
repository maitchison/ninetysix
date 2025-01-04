unit md5;

interface

uses
  test,
  debug,
  types,
  utils;

type
  tDigestData = packed record
    case integer of
      0: (asBytes: array[0..15] of byte);
      1: (asDwords: array[0..3] of dword);
    end;

  tDigest = record
    data: tDigestData;
    function toHex(): string;
  end;

  tChunk = packed record
    case integer of
      0: (bytes: array[0..63] of byte);
      1: (M: array[0..15] of dword);
    end;

function hash(bytes: tBytes): tDigest; overload;
function hash(s: ansistring): tDigest; overload;

implementation

{------------------------------------------------------}

function hexDigit(b: byte): char;
const
  digits = '0123456789abcdef';
begin
  result := digits[(b and $f)+1];
end;

function hexByte(b: byte): string;
begin
  result := hexDigit(b shr 4) + hexDigit(b);
end;

function appendToBytes(data: tBytes;b: byte): tBytes;
begin
  setLength(data, length(data)+1);
  data[length(data)-1] := b;
  result := data;
end;

function leftRotate(value: dword;shifts: byte): dword;
begin
  result := (value shl shifts) or (value shr (32-shifts));
end;

function swapEdian(value: dword): dword;
begin
  {bswap would do this in 1 instruction...}
  result :=
    (((value shr 0) and $ff) shl 24) or
    (((value shr 8) and $ff) shl 16) or
    (((value shr 16) and $ff) shl 8) or
    (((value shr 24) and $ff) shl 0);
end;

{------------------------------------------------------}

function tDigest.toHex(): string;
var
  i: int32;
begin
  result := '';
  for i := 0 to 15 do
    result += hexByte(data.asBytes[i]);
end;

{------------------------------------------------------}

function hash(bytes: tBytes): tDigest; overload;
const
  s: array[0..63] of dword =
  (7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
   5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
   4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
   6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21);
  K: array[0..63] of dword =
 ($d76aa478, $e8c7b756, $242070db, $c1bdceee,
  $f57c0faf, $4787c62a, $a8304613, $fd469501,
  $698098d8, $8b44f7af, $ffff5bb1, $895cd7be,
  $6b901122, $fd987193, $a679438e, $49b40821,
  $f61e2562, $c040b340, $265e5a51, $e9b6c7aa,
  $d62f105d, $02441453, $d8a1e681, $e7d3fbc8,
  $21e1cde6, $c33707d6, $f4d50d87, $455a14ed,
  $a9e3e905, $fcefa3f8, $676f02d9, $8d2a4c8a,
  $fffa3942, $8771f681, $6d9d6122, $fde5380c,
  $a4beea44, $4bdecfa9, $f6bb4b60, $bebfbc70,
  $289b7ec6, $eaa127fa, $d4ef3085, $04881d05,
  $d9d4d039, $e6db99e5, $1fa27cf8, $c4ac5665,
  $f4292244, $432aff97, $ab9423a7, $fc93a039,
  $655b59c3, $8f0ccc92, $ffeff47d, $85845dd1,
  $6fa87e4f, $fe2ce6e0, $a3014314, $4e0811a1,
  $f7537e82, $bd3af235, $2ad7d2bb, $eb86d391);

var
  a0,b0,c0,d0: dword;
  A,B,C,D: dword;
  F,g: dword;
  chunk: tChunk;
  originalLength: dword;
  lengthInBits: qword;
  chunks: dword;
  i, j, z: int32;

begin

  //todo: append to final chunk only

  {$R-,Q-}

  a0 := $67452301;
  b0 := $efcdab89;
  c0 := $98badcfe;
  d0 := $10325476;
  originalLength := length(bytes);
  bytes := appendToBytes(bytes, $80);
  while length(bytes) mod 64 <> 56 do begin
    bytes := appendToBytes(bytes, $00);
  end;

  lengthInBits := 8*originalLength;
  for i := 0 to 7 do
    bytes := appendToBytes(bytes, (lengthInBits shr (i * 8)) and $ff);

  chunks := length(bytes) div 64;
  for j := 0 to chunks-1 do begin

    move(bytes[j*64], chunk.bytes[0], 64);

    A := a0; B := b0; C := c0; D := d0;
    for i := 0 to 63 do begin
      case i div 16 of
        0: begin
          F := (B and C) or ((not B) and D);
          g := i;
        end;
        1: begin
          F := (D and B) or ((not D) and C);
          g := (5*i + 1) mod 16;
        end;
        2: begin
          F := B xor C xor D;
          g := (3*i + 5) mod 16;
        end;
        3: begin
          F := C xor (B or (not D));
          g := (7*i) mod 16;
        end;
      end;
      F := F + A + K[i] + chunk.M[g];
      A := D;
      D := C;
      C := B;
      B := B + leftRotate(F, s[i]);
    end;

    // add this to current counters
    a0 += A;
    b0 += B;
    c0 += C;
    d0 += D;
  end;

  result.data.asDwords[0] := a0;
  result.data.asDwords[1] := b0;
  result.data.asDwords[2] := c0;
  result.data.asDwords[3] := d0;

  {$R+,Q+}

end;

function hash(s: ansistring): tDigest; overload;
var
  bytes: tBytes;
  i: integer;
begin
  bytes := nil;
  setLength(bytes, length(s));
  for i := 0 to length(s)-1 do
    bytes[i] := ord(s[i+1]);
  result := hash(bytes);
end;

{--------------------------------------------------}

type
  tMD5Test = class(tTestSuite)
    procedure run; override;
  end;

procedure tMD5Test.run();
begin

  {helpers}
  assertEqual(hexDigit(7),'7');
  assertEqual(hexDigit(10),'a');
  assertEqual(hexByte(32+10),'2a');
  assertEqual(leftRotate(5, 0), 5);
  assertEqual(leftRotate(5, 1), 10);
  assertEqual(leftRotate(5, 34), 20);

  {md5}
  assertEqual(hash('').toHex, 'd41d8cd98f00b204e9800998ecf8427e');
  assertEqual(hash('a').toHex, '0cc175b9c0f1b6a831c399e269772661');
  assertEqual(hash('The quick brown fox jumps over the lazy dog').toHex, '9e107d9d372bb6826bd81d3542a419d6');

end;

initialization
  tMD5Test.create('MD5');
end.
