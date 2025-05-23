{Basic sound blaster driver}
unit uSBDriver;

{$MODE delphi}

{todo: remove references to mixer, and just have a procedure call}

interface

uses
  dos,
  uTest,
  uDebug,
  uUtils,
  go32;

type
  tWords = array of word;

{todo: remove these, and handle through mixer
 (except the direct ones)}
procedure directNoise(s: double);
procedure directPCMData(buffer: tWords);

{-----------------------------------------------------}

{todo: remove most of these public globals}

var
  INTERRUPT_COUNTER: int32 = 0;

  {number of seconds it took to process the last audio chunk}
  lastChunkTime: double = -1;
  maxChunkTime: double = -1;
  currentTC: uint64 = 0;

  backgroundMusicBuffer: pointer = nil;
  backgroundMusicPosition: int32 = 0;
  backgroundMusicLength: int32 = 0;

var
  bufferDirty: boolean = false;
  dosSelector: word = 0;
  currentBuffer: boolean;      // True = BufferA, False = BufferB

const

  {
  Timings for 16bit stereo
  (note: there's a little extra delay due to having to wait one frame,
   this will add around 16ms

  64k = ~200-400 ms     This is way too much latency
  32k = ~100-200 ms      Perhaps a safe trade-off
  16k = ~50-100 ms
  8k  = ~25-50 ms
  4k  = ~12.5-25 ms      This feels about right to me.
  }

  //buffer size in bytes
  BUFFER_SIZE = 4*1024;     //2k is better, but 4k fixes a few glitches on load
  HALF_BUFFER_SIZE = BUFFER_SIZE div 2;


var
  debug_dma_ofs: word;
  debug_dma_page_corrections: int32 = 0;

var
  DEBUG_NOISE_ON_PAGE_CORRETION: boolean = false;

implementation

uses
  uMixer,
  uSound;

procedure speakerOff(); forward;
procedure speakerOn(); forward;

{-----------------------------------------------------}

var
  {during IRQ our segements will sometime be wrong, so we need to
   reference a copy of it}
  backupDS: word = 0;

var
  SB_INT: byte = 0;
  SB_IRQ: byte = 0;

var
  sbGood: boolean = false;
  IS_DMA_ACTIVE: boolean = false;
  DSPVersion: byte = 0;
  dosSegment: word = 0;
  dosOffset: word = 0;


const
  SB_BASE = $220;
  DSP_RESET = SB_BASE + $6;
  DSP_READ_DATA = SB_BASE + $A;
  DSP_WRITE_DATA = SB_BASE + $C;
  DSP_WRITE_STATUS = SB_BASE + $C;
  DSP_DATA_AVAIL = SB_BASE + $E;


{----------------------------------------------------------}
{ DSP stuff}
{----------------------------------------------------------}

function DSPReadyToWrite(): boolean;
begin
  result := (port[DSP_WRITE_STATUS] and $80) = 0;
end;

function DSPDataAvailable(): boolean;
begin
  result := (port[DSP_DATA_AVAIL] and $80) <> 0;
end;

procedure DSPWaitForWrite(timeout: double=1);
var
  timeLimit: double;
begin
  timeLimit := getSec+timeout;
  while not DSPReadyToWrite do
    if (getSec > timeLimit) then fatal('Timeout waiting for DSPWrite');
end;

procedure DSPWrite(command: byte);
var
  timeout: double;
begin
  DSPWaitForWrite();
  port[DSP_WRITE_DATA] := command;
end;

procedure DSPStop();
begin
  DSPWrite($D9);
end;

function DSPRead(): byte;
var
  timeout: double;
begin
  timeout := getSec+1;
  while not DSPDataAvailable do
    if (getSec > timeout) then fatal('Timeout waiting for DSPRead');
  result := port[DSP_READ_DATA];
end;

{Reset DSP, return if successful}
function DSPReset(): boolean;
begin
  port[DSP_RESET] := $1;
  sleep(1);
  port[DSP_RESET] := $0;
  sleep(1);

  {DSP should respond with $AA}
  result := DSPRead = $AA;

  {get version as well}
  DSPWrite($E1);
  dspVersion := DSPRead()
end;


function getDSPIrq(): integer;
var
  value: byte;
begin
  asm
    mov dx, SB_BASE
    add dx, 4
    mov al, $80
    out dx, al
    inc dx

    in  al, dx
    mov [value], al
  end;

  case value of
    1: exit(2);
    2: exit(5);
    4: exit(7);
    8: exit(10);
    else exit(-value);
  end;
end;

{----------------------------------------------------------}
{ DMA Stuff }
{----------------------------------------------------------}

CONST
  {for channel 5}
  {words}
  ISA_StartAddress = $C4;
  ISA_CountRegister = $C6;
  {bytes}
  ISA_STATUS = $D0;
  ISA_COMMAND = $D0;
  ISA_MODE = $D6;
  ISA_FLIP_FLOP = $D8;
  ISA_SINGLE_CHANNEL_MASK = $D4;
  ISA_CH5_PAGE = $8B;

const
  SB_OUTPUT = $41;
  SB_INPUT   = $42;

  SB_OUTPUT_8BIT = $C0;
  SB_OUTPUT_16BIT = $B0;

  SB_MONO_16BIT_SIGNED_PCM = $10;
  SB_STEREO_16BIT_SIGNED_PCM = $30;

{length is samples? or words?}
procedure startPlayback(length: word);
begin
  DSPWrite(SB_OUTPUT);
  DSPWrite($AC);              // 44.1 HZ (according to manual)
  DSPWrite($44);
  DSPWrite(SB_OUTPUT_16BIT);
  DSPWrite(SB_STEREO_16BIT_SIGNED_PCM);
  DSPWrite(lo(word(length-1)));
  DSPWrite(hi(word(length-1)));
end;

{$F+,S-,R-,Q-}
{handle sound buffer refill
ISR mixing mode:
  - music handled in ISR
  - mixing must be performed by main loop outside of ISR
}
procedure soundBlaster_ISR; interrupt;
var
  readAck: byte;
  bufOfs: word;
  startTime: double;
  mixBuffer: pointer;
  newSamples: int32;
  expectedBuffer: boolean;
  requiredCorrection: boolean;

begin

  // todo: check we need to pass IRQ along, i.e. it's not for us.

  asm
    cld
    cli
    push es
    push ds
    push fs
    push gs
    pushad

    mov ax, cs:[backupDS]
    mov ds, ax
    mov es, ax
  end;

  startTime := getSec;
  inc(INTERRUPT_COUNTER);
  currentBuffer := not currentBuffer;

  // acknowledge the DSP
  // $F for 16bit, $E for 8bit
  readAck := port[SB_BASE + $F];

  {get DMA count to see where we should be writing to}
  asm
    pusha

    mov dx, $D8
    mov al, 0
    out dx,al    {reset flip flop}

    mov dx, $C6
    in  al, dx
    mov bl, al
    in  al, dx
    mov bh, al
    mov [debug_dma_ofs], bx
    popa
  end;

  {buf0 should be half_buffer_words, buf1 should be buffer_words}
  {
    If currentBuffer=true, then we are writing to the second block, and DMA offs should be < HALF_BUFFER_SIZE/2
    If currentBuffer=false, then we are writing to the first block, and DMA offs should be > HALF_BUFFER_SIZE/2
    Note: i have no idea why the logic below is reverse to this, but it works?
  }
  requiredCorrection := false;
  if (currentBuffer and (debug_dma_ofs < HALF_BUFFER_SIZE div 2)) then requiredCorrection := true;
  if (not currentBuffer and (debug_dma_ofs > HALF_BUFFER_SIZE div 2)) then requiredCorrection := true;
  if requiredCorrection then begin
    currentBuffer := not currentBuffer;
    inc(debug_dma_page_corrections);
  end;

  if currentBuffer then
    bufOfs := dosOffset + HALF_BUFFER_SIZE
  else
    bufOfs := dosOffset;

  {Initialize the buffer with the music stream.}
  mixBuffer := nil;

  mixBuffer := mixDown(currentTC, HALF_BUFFER_SIZE);

  if (mixBuffer <> nil) then begin
    dosMemPut(dosSegment, bufOfs, mixBuffer^, HALF_BUFFER_SIZE);
  end else begin
    dosMemFillChar(dosSegment, bufOfs, HALF_BUFFER_SIZE, #0);
  end;

  if DEBUG_NOISE_ON_PAGE_CORRETION and requiredCorrection then begin
    {fill the buffer with noise}
    asm
      pushad
      push fs

      mov fs, go32.dosMemSelector
      mov ecx, BUFFER_SIZE

      xor eax, eax
      xor ebx, ebx
      mov ax, dosSegment
      shl eax, 4
      xor ebx, ebx
      mov bx, dosOffset
      add eax, ebx
      mov edx, eax

      mov dl, 7

    @LOOP:

      {this will be loud!}
      rdtsc
      mul ah
      add al, dl
      mov dl, ah

      mov fs:[edi], al
      inc edi

      dec ecx
      jnz @LOOP

      pop fs
      popad
    end;
  end;

  currentTC += HALF_BUFFER_SIZE div 4;

  lastChunkTime := getSec-startTime;
  if lastChunkTime > maxChunkTime then
    maxChunkTime := lastChunkTime;

  // end of interrupt
  // apparently I need to send EOI to slave and master PIC when I'm on IRQ 10
  if SB_IRQ >= 8 then
    port[$A0] := $20;
  port[$20] := $20;

  asm
    popad
    pop gs
    pop fs
    pop ds
    pop es
    // no sti?
    // no push and pop float registers?
  end;

end;
{$F-,S+,R+,Q+}

var
  oldIntVec: tSegInfo;
  newIntVec: tSegInfo;

var
  irqStartMask,
  irqStopMask: byte;

var
  hasInstalledInt: boolean=False;

procedure install_ISR(irq: byte);
begin
  note(' - Installing music interrupt on IRQ'+intToStr(irq));

  case irq of
    0..7: SB_INT := $08+irq;
    8..15: SB_INT := $70+irq-8;
    else fatal('Invalid IRQ for SB');
  end;
  SB_IRQ := irq;

  newIntVec.offset := @soundBlaster_ISR;
  newIntVec.segment := get_cs;

  irqStopMask := 1 shl (SB_IRQ mod 8);
  irqStartMask := not IRQStopMask;

  get_pm_interrupt(SB_INT, oldIntVec);
  set_pm_interrupt(SB_INT, newIntVec);

  if SB_IRQ >= 8 then
    port[$A1] := port[$A1] and IRQStartMask
  else
    port[$21] := port[$21] and IRQStartMask;

  hasInstalledInt := true;

end;

procedure uninstall_ISR;
begin
  if not hasInstalledInt then exit;
  note(' - Removing music interrupt');
  if SB_IRQ >= 8 then
    port[$A1] := port[$A1] or IRQStopMask
  else
    port[$21] := port[$21] or IRQStopMask;
  set_pm_interrupt(SB_INT, oldIntVec);
  hasInstalledInt := false;
end;


procedure startAutoPlayback(length: word);
begin
  DSPWrite(SB_OUTPUT);
  DSPWrite($AC);              // 44.1 HZ (according to manual)
  DSPWrite($44);
  DSPWrite(SB_OUTPUT_16BIT);
  DSPWrite(SB_STEREO_16BIT_SIGNED_PCM);
  DSPWrite(lo(word(length-1)));
  DSPWrite(hi(word(length-1)));
end;

{----------------------------------------------------------}

{play noise directly (blocking) for s seconds.}
procedure directNoise(s: double);
var
  timeLimit: double;
  x: word;
begin
  timeLimit := getSec + s;
  speakerOn();
  while getSec < timeLimit do begin
    DSPWrite($10); // direct 8bit mino 'pc speaker'
    DSPWrite(rnd);
  end;
  speakerOff();
end;

{play PCM audio using direct writes.
Input should be mono, 16-bit, and 44.1khz, however when played
will be converted to 8bit.
This will sound quite bad, a bit like 'pc speaker'.
}
procedure directPCMData(buffer: tWords);
var
  i: int32;
  j: int32;
  startTime: double;
  {used for 16-8bit dithering}
  sample: int32;
  hiSample,loSample: int32;

begin
  startTime := getSec;
  for i := 0 to length(buffer)-1 do begin
    DSPWrite($10); // direct 8bit mono 'pc speaker'}
    sample := int16(buffer[i]);
    //write(sample, ' ');
    sample := sample + (32*1024);
    hiSample := sample shr 8;
    loSample := sample and $ff;

    if loSample > rnd then inc(hiSample);

    if hiSample > 255 then hiSample := 255;
    if hiSample < 0 then hiSample := 0;

    DSPWrite(hiSample);

    while getSec < startTime + (i / 44100) do;
  end;
end;

{Start IRQ and DMA to handle audio in background.}
procedure initiateDMAPlayback();
var
  bytestoCopy: dword;
  samples: dword;
  len: word;
  addr: dword;
  words: word;
  halfWords: word;
  blockSize: word;

  tmp: byte;

begin

  if IS_DMA_ACTIVE then
    fatal('DMA transfer is already active');

  note(' - Setting up DMA transfer.');
  if not assigned(mixer) then
    fatal('A mixer has not yet been assigned.');

  DSPReset();

  {start with an empty buffer}
  dosMemFillChar(dosSegment, dosOffset, BUFFER_SIZE , #0);

  currentBuffer := True;

  {this took a long time to get right...

  DMA should the setup to transfer the entire buffer.
  SB should be told to use half the buffer as the blocksize, this way
  we get an interrupt halfway through the block}

  words := BUFFER_SIZE div 2;           // number of words in buffer.
  halfWords := HALF_BUFFER_SIZE div 2;  // number of words in halfbuffer.
  addr := (dosSegment shl 4) + dosOffset;

  {check address does not span 64K}
  if (addr shr 16) <> ((addr + words*2) shr 16) then
    fatal('DMA destination buffer spans 64k boundary');

  {1. reset}
  DSPReset();
  port[$D4] := $05; // mask DMA channel
  port[$D8] := $01;  // any value
  port[$D6] := $59; // single mode, auto-initialize, write
  port[$8B] := byte(addr shr 16);  // page address, high bits of address, probably 0
  port[$C4] := lo(word(addr shr 1));
  port[$C4] := hi(word(addr shr 1));
  port[$C6] := lo(word(words-1));  // length is words -1
  port[$C6] := hi(word(words-1));
  port[$D4] := $01;    // unmask DMA channel 5}
  {6. time constant}
  DSPWrite($41);
  DSPWrite(hi(44100));              // 44.1 HZ (according to manual)
  DSPWrite(lo(44100));

  DSPWrite($B6);  // 16-bit output mode.
  DSPWrite($30);  // 16-bit stereo signed PCM input.
  // according to manual, this must be half the DMA size.
  // since we using 16-bit audio, these are words

  DSPWrite(lo(word(halfWords-1)));
  DSPWrite(hi(word(halfWords-1)));

  IS_DMA_ACTIVE := true;

end;

procedure stopDMAPlayback();
begin
  {does this actually stop playback?}
  DSPStop();
  IS_DMA_ACTIVE := false;
end;

{----------------------------------------------------------}

function getPage(addr: dword): word;
begin
  result := (addr shr 16);
end;

procedure initSound();
var
  res: longint;
  addr: dword;
  irq: integer;
begin
  note('[init] Sound');
  sbGood := DSPReset();

  irq := getDSPIrq();

  if sbGood then
    info(format(' - detected SoundBlaster16 at %hh (V%d.0) IRQ:%d', [SB_BASE, DSPVersion, irq]))
  else
    warning('No SoundBlaster detected');

  if irq < 0 then begin
    warning(format('Could not detect IRQ for SB16, guessing 5... (mask was %d)', [-irq]));
    irq := 5;
  end;

  if BUFFER_SIZE > 32*1024 then
    fatal('Invalid BUFFER_SIZE, must be <= 32k');
  if (BUFFER_SIZE and $f) <> 0 then
    fatal('Invalid BUFFER_SIZE, must be a multiple of 16');

  {allocate twice the memory, this way atleast one half will not be split across segment boundaries}
  res := Global_Dos_Alloc(BUFFER_SIZE*2);
  dosSelector := word(res);
  dosSegment := word(res shr 16);
  if dossegment = 0 then
    fatal('Failed to allocate dos memory');

  addr := (dosSegment shl 4);
  if getPage(addr) <> getPage(addr + BUFFER_SIZE) then begin
    warning(' - SB Buffer allocation spanned a page, so I moved it.');
    dosOffset := BUFFER_SIZE;
  end else
    dosOffset := 0;

  note(format(' - successfully allocated dos memory for DMA (%d|%d)', [dosSelector, dosSegment]));

  install_ISR(irq);
  initiateDMAPlayback();
  speakerOn();
end;

procedure freeBuffer();
begin
  global_dos_free(dosSelector);
  dosSegment := 0;
  dosOffset := 0;
  dosSelector := 0;
end;

procedure speakerOff();
begin
  DSPWrite($D3);
end;

procedure speakerOn();
begin
  DSPWrite($D1);
end;

procedure closeSound();
begin
  note('[done] sound');
  note(' - IRQ was triggered '+intToStr(INTERRUPT_COUNTER)+' times.');
  if debug_dma_page_corrections > 0 then
    warning('Required '+intToStr(debug_dma_page_corrections)+' page corrections');
  DSPWrite($D3); // mute the speaker so we don't get crackle.
  stopDMAPlayback();
  uninstall_ISR();
  freeBuffer();
end;

{----------------------------------------------------------}

procedure runTests();
begin
end;

{----------------------------------------------------------}

begin
  // mute the speaker so we don't get crackle.
  speakerOn();
  backupDS := get_ds();
  runTests();
  initSound();
  addExitProc(closeSound);
end.
