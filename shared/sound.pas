{Unit for saving and loading sound files.}
unit sound;

{$MODE delphi}

{todo:
  support load load of wave files (via getsample)
  support pitch and volume (via get sample)
  support fade and and fade out (via get sample)

  todo: split mixer and sound
}


interface

uses
  test,
  debug,
  resource,
  utils,
  dos,
  sbDriver;

type

  tAudioFormat = (
    AF_INVALID,
    AF_16_STEREO,
    AF_8_STEREO,
    AF_16_MONO,
    AF_8_MONO
  );

const
  AF_SIZE: array[tAudioFormat] of integer = (
    0,
    4,
    2,
    2,
    1
  );

type
  tAudioSample16S = packed record
    left, right: int16;
    class operator subtract(a,b: tAudioSample16S): tAudioSample16S;
    function toMid: int16; inline;
    function toDif: int16; inline;
    function toString: string;
    property a: int16 read left write left;
    property b: int16 read right write right;
  end;
  tAudioSample8S = packed record
    left, right: uint8;
  end;
  tAudioSample16M = packed record
  case byte of
    0: (value: int16);
    1: (left: int16);
    2: (right: int16);
  end;
  tAudioSample8M = packed record
  case byte of
    0: (value: byte);
    1: (left: byte);
    2: (right: byte);
  end;

  pAudioSample16S = ^tAudioSample16S;
  pAudioSample8S = ^tAudioSample8S;
  pAudioSample16M = ^tAudioSample16M;
  pAudioSample8M = ^tAudioSample8M;

  tAudioSampleF32 = packed record
  {32 bit stereo sample, used for mixing}
    left,right: single;
    class operator implicit(a: tAudioSampleF32): tAudioSample16S;
    class operator implicit(a: tAudioSample16S): tAudioSampleF32;
    class operator add(a,b: tAudioSampleF32): tAudioSampleF32;
    class operator subtract(a,b: tAudioSampleF32): tAudioSampleF32;
    class operator multiply(a: tAudioSampleF32;b: single): tAudioSampleF32;
    class operator multiply(b: single; a: tAudioSampleF32): tAudioSampleF32;
    class operator multiply(b: single; a: tAudioSample16S): tAudioSampleF32;
  end;
  tAudioSampleI32 = packed record
  {32 bit stereo sample, used for mixing}
    left,right: int32;
  end;

  tAudioSample = tAudioSample16S;
  pAudioSample = ^tAudioSample;

  tSoundEffect = class(tResource)

    tag: string;
    data: pointer;
    length: int32;        // number of samples
    format: tAudioFormat;

    constructor create(aFormat: tAudioFormat=AF_16_STEREO; aLength: int32=0; aTag: string='');
    destructor destroy(); override;

    function toString(): string; override;

    function bytesPerSample: int32; inline;
    function calculateRMS: double;
    function duration: double;

    function asFormat(af: tAudioFormat): tSoundEffect;
    function clone(): tSoundEffect;
    function getSample(pos: int32): tAudioSample;
    procedure setSample(pos: int32;sample: tAudioSample);

    class function createNoise(duration: single): tSoundEffect;
    class function Load(filename: string): tSoundEffect;

    property items[index: int32]: tAudioSample read getSample write setSample; default;

  end;

type
  tSFXLibrary = class(tResourceLibrary)
  protected
    function getSFXByTag(aTag: string): tSoundEffect;
  public
    function addResource(filename: string): tResource; override;
    property items[tag: string]: tSoundEffect read getSFXByTag; default;
  end;


function getAudioFormat(bitsPerChannel: integer; numChannels: integer): tAudioFormat;

implementation

uses
  mixLib,
  wave,
  la96;

{--------------------------------------------------------}

function tSFXLibrary.getSFXByTag(aTag: string): tSoundEffect;
var
  res: tResource;
begin
  res := getByTag(aTag);
  assert(res is tSoundEffect);
  result := tSoundEffect(res);
end;

function tSFXLibrary.addResource(filename: string): tResource;
var
  res: tResource;
begin
  res := inherited addResource(filename);
  assert((res is tSoundEffect) or (res is tLazyResource));
  result := res;
end;

{--------------------------------------------------------}

function getAudioFormat(bitsPerChannel: integer; numChannels: integer): tAudioFormat;
begin
  case numChannels of
    1: case bitsPerChannel of
      8: exit(AF_8_MONO);
      16: exit(AF_16_MONO);
    end;
    2: case bitsPerChannel of
      8: exit(AF_8_STEREO);
      16: exit(AF_16_STEREO);
    end;
  end;
  exit(AF_INVALID);
end;

{--------------------------------------------------------}

class operator tAudioSample16S.subtract(a,b: tAudioSample16S): tAudioSample16S;
begin
  result.left  := clamp16(a.left  - b.left);
  result.right := clamp16(a.right - b.right);
end;

function tAudioSample16S.toMid: int16; inline;
begin
  result := (int32(left)+int32(right)) div 2;
end;

function tAudioSample16S.toDif: int16; inline;
begin
  result := (int32(left)-int32(right)) div 2;
end;

function tAudioSample16S.toString: string;
begin
  result := '('+intToStr(left)+','+intToStr(right)+')';
end;

class operator tAudioSampleF32.implicit(a: tAudioSample16S): tAudioSampleF32;
begin
  result.left  := a.left;
  result.right := a.right;
end;

class operator tAudioSampleF32.implicit(a: tAudioSampleF32): tAudioSample16S;
begin
  result.left  := clamp16(a.left);
  result.right := clamp16(a.right);
end;

class operator tAudioSampleF32.add(a,b: tAudioSampleF32): tAudioSampleF32;
begin
  result.left  := a.left  + b.left;
  result.right := a.right + b.right;
end;

class operator tAudioSampleF32.subtract(a,b: tAudioSampleF32): tAudioSampleF32;
begin
  result.left  := a.left  - b.left;
  result.right := a.right - b.right;
end;

class operator tAudioSampleF32.multiply(a: tAudioSampleF32;b: single): tAudioSampleF32;
begin
  result.left  := a.left  * b;
  result.right := a.right * b;
end;

class operator tAudioSampleF32.multiply(b: single; a: tAudioSampleF32): tAudioSampleF32;
begin
  result.left  := a.left  * b;
  result.right := a.right * b;
end;

class operator tAudioSampleF32.multiply(b: single; a: tAudioSample16S): tAudioSampleF32;
begin
  result.left  := a.left  * b;
  result.right := a.right * b;
end;

{--------------------------------------------------------}

constructor tSoundEffect.create(aFormat: tAudioFormat; aLength: int32; aTag: string='');
begin
  inherited create();
  length := aLength;
  format := aFormat;
  tag := aTag;
  getMem(data, length * AF_SIZE[format]);
  fillchar(data^, length * AF_SIZE[format], 0);
end;

destructor tSoundEffect.destroy();
begin
  if assigned(data) then
    freeMem(data);
  length := 0;
  data := nil;
  tag := '';
  inherited destroy();
end;

function tSoundEffect.toString(): string;
begin
  exit(tag);
end;

{returns copy of sound in 16bit-stereo format.}
function tSoundEffect.asFormat(af: tAudioFormat): tSoundEffect;
var
  i: int32;
begin
  result := tSoundEffect.create(af, self.length, self.tag);
  for i := 0 to self.length-1 do
    result.setSample(i, self.getSample(i));
end;

{create a copy}
function tSoundEffect.clone(): tSoundEffect;
begin
  result := self.asFormat(self.format);
end;

function tSoundEffect.getSample(pos: int32): tAudioSample;
begin
  if (pos < 0) or (pos >= length) then begin
    fillchar(result, sizeof(result), 0);
    exit;
  end;
  case format of
    AF_16_STEREO: result := pAudioSample16S(data + (pos * 4))^;
    AF_16_MONO: begin
      result.left := pAudioSample16M(data + (pos * 2))^.value;
      result.right := pAudioSample16M(data + (pos * 2))^.value;
    end;
    AF_8_STEREO: begin
      result.left := int32(pAudioSample8S(data + (pos * 2))^.left) * 256 - 32768;
      result.right := int32(pAudioSample8S(data + (pos * 2))^.right) * 256 - 32768;
    end;
    AF_8_MONO: begin
      result.left := int32(pAudioSample8M(data + (pos * 1))^.value) * 256 - 32768;
      result.right := int32(pAudioSample8M(data + (pos * 1))^.value) * 256 - 32768;
    end;
    else fatal('Invalid format');
  end;
end;

{bytes per sample}
function tSoundEffect.bytesPerSample: int32; inline;
begin
  result := AF_SIZE[format];
end;

{returns the RMS of the sample}
function tSoundEffect.calculateRMS: double;
var
  i: int32;
  ll, rr: int32;
  sample: tAudioSample16S;
begin
  result := 0;
  for i := 0 to length-1 do begin
    sample := self[i];
    ll := sample.left*sample.left;
    rr := sample.right*sample.right;
    result += ll;
    result += rr;
  end;
  result /= length;
  result := sqrt(result);
end;

{returns duration in seconds}
function tSoundEffect.duration: double;
begin
  result := length / 44100;
end;

procedure tSoundEffect.setSample(pos: int32; sample: tAudioSample);
begin
  if (pos < 0) or (pos >= length) then begin
    exit;
  end;
  case format of
    AF_16_STEREO: pAudioSample16S(data + (pos * bytesPerSample))^ := sample;
    AF_8_STEREO: begin
      pAudioSample8S(data + (pos * bytesPerSample))^.left := (sample.left div 256) + 128;
      pAudioSample8S(data + (pos * bytesPerSample))^.right := (sample.right div 256) + 128;
    end;
    else fatal('Invalid format');
  end;
end;

class function tSoundEffect.createNoise(duration: single): tSoundEffect;
var
  i: int32;
  numSamples: dWord;
  sample: tAudioSample;
begin
  numSamples := trunc(44100 * duration);
  result := tSoundEffect.create(AF_16_STEREO, numSamples);
  for i := 0 to numSamples-1 do begin
    sample.left := random(65536)-32768;
    sample.right := random(65536)-32768;
    result.setSample(i, sample);
  end;
  result.tag := 'noise';
end;

class function tSoundEffect.Load(filename: string): tSoundEffect;
var
  proc: tResourceLoaderProc;
  res: tResource;
  startTime: double;
begin
  proc := getResourceLoader(extractExtension(filename));
  if assigned(proc) then begin
    startTime := getSec;
    res := proc(filename);
    if not (res is tSoundEffect) then fatal('Resources is of invalid type');
    result := tSoundEffect(proc(filename));
    note(' - loaded %s (%fs) in %.2fs', [filename, result.length/44100, getSec-startTime]);
  end else
    debug.fatal('No sound loader for file "'+filename+'"');
end;


{----------------------------------------------------------}

begin
end.
