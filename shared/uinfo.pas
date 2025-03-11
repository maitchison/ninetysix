{memory and cpu info tools.}
unit uInfo;

interface

uses
  debug;

type
  {I think make this a class?}
  tCPUInfo = record
    mhz: single;
    ram: dword;
    hasMMX: boolean;
    INV_CLOCK_FREQ: double;
    procedure printToLog();
  end;

{cpu stuff}
{todo: move these into a class or record}
function getCPUIDSupport: boolean;
function getMMXSupport: boolean;
function getCPUName(): string;

{memory stuff}
function  getFreeSystemMemory: int64;
function  getFreeMemory: int64;
function  getTotalMemory: int64;
function  getUsedMemory: int64;
procedure logHeapStatus(msg: string='Heap status');
procedure logFullHeapStatus();
procedure logDPMIInfo();

var
  CPUInfo: tCPUInfo;

implementation

uses
  go32,
  utils;

{-------------------------------------------------------------}
{ CPU Stuff }
{-------------------------------------------------------------}

procedure tCPUInfo.printToLog();
var
  mmxString: string;
begin
  if hasMMX then mmxString := '(MMX)' else mmxString := '';
  info(format('System is %.1fMHZ with %.1fMB ram %s',[mhz, ram/1024/1024, mmxString]));
end;

function getRDTSCRate(): double;
var
  tick: int64;
  startTSC, endTSC: uint64;
begin
  result := 166000000; // default to 166MHz}
  tick := getTickCount();
  while getTickCount() = tick do;
  startTSC := getTSC;
  while getTickCount() = tick+1 do;
  endTSC := getTSC;
  if (endTSC = startTSC) then
    warning(format('RDTSC seems to not be working, assuming default of %fMHZ', [(result)/1000/1000]))
  else
    result := (endTSC - startTSC) / (1/18.2065);
end;

function getCPUInfo(): tCPUInfo;
var
  memInfo: tMemInfo;
  totalMem: int64;
  RDTSCrate: double;
begin
  RDTSCRate := getRDTSCRate();
  result.mhz := RDTSCrate / 1000 / 1000;
  result.INV_CLOCK_FREQ := 1/RDTSCRate;
  result.hasMMX := getMMXSupport();
  get_memInfo(memInfo);
  result.ram := memInfo.total_physical_pages * get_page_size;
end;

function getCPUIDSupport: boolean; assembler;
  {copied from from cpu.pp}
  asm
    push  ebx
    pushfd
    pushfd
    pop   eax
    mov   ebx, eax
    xor   eax, $200000
    push  eax
    popfd
    pushfd
    pop   eax
    popfd
    and   eax, $200000
    and   ebx, $200000
    cmp   eax, ebx
    setnz al
    pop   ebx
  end;

function getMMXSupport: boolean; assembler;
  asm
    push  ebx
    push  ecx
    push  edx

    call  getCPUIDSupport
    jz    @NoCPUID

    mov   eax, 1
    cpuid
    test  edx, (1 shl 23)
    jz    @NoMMX

  @HasMMX:
    mov   al, 1
    jmp   @Done

  @NoMMX:
  @NoCPUID:
    mov   al, 0

  @Done:
    pop   edx
    pop   ecx
    pop   ebx
  end;

function getCPUName(): string;
var
  reax: dword;
  cpuName: string;
  family, model, stepping: word;
begin
  if not getCPUIDSUpport then exit('');

  asm
    pushad
    mov eax, 1
    cpuid
    mov [reax], eax
    popad
    end;

  family := (reax shr 8) and $f;
  model := (reax shr 4) and $f;
  stepping :=(reax shr 0) and $f;

  case family of
    3: cpuName := '386';
    4: case model of
      0,1,4: cpuName := '486DX';
      2: cpuName := '486SX';
      3: cpuName := '486DX2';
      5: cpuName := '486SX2';
      7: cpuName := '486DX4';
      else cpuName := '486';
    end;
    5: case model of
      3: cpuName := 'Pentium Overdrive';
      4: cpuName := 'Pentium MMX';
      else cpuName := 'Pentium';
    end;
    6: case model of
      1: cpuName := 'Pentium Pro';
      3: cpuName := 'Pentium II';
      6: cpuName := 'Pentium III';
      else cpuName := 'Pentium Pro/II/III';
    end;
    else cpuName := 'Unknown ('+intToStr(family)+')';
  end;
  result := cpuName;
end;

{-------------------------------------------------------------}


{current free heap memory (assuming heap does not grow anymore)}
function getFreeMemory: int64;
var
  memInfo: tMemInfo;
begin
  result := getFPCHeapStatus().currHeapFree;
end;

{this is basically avalaible memory - current heap size}
function getFreeSystemMemory: int64;
var
  memInfo: tMemInfo;
begin
  get_memInfo(memInfo);
  result := memInfo.available_physical_pages * get_page_size;
end;

{Total memory is the amount of system memory on the machine.}
function getTotalMemory: int64;
var
  memInfo: tMemInfo;
begin
  get_memInfo(memInfo);
  result := memInfo.total_physical_pages * get_page_size;
end;

{Used memory is memory used by our heap.}
function getUsedMemory: int64;
var
  hs: tFPCHeapStatus;
begin
  result := getFPCHeapStatus().currHeapUsed;
end;

procedure logHeapStatus(msg: string='Heap status');
begin
  debug.debug(pad(format('--- %s used:%skb free:%skb ',
    [
      msg,
      // total_physical_pages
      comma(getUsedMemory div 1024),
      comma(getFreeMemory div 1024)
    ]), 60, '-'));
end;

procedure logFullHeapStatus();
var
  fhs: tFPCHeapStatus;
  hs: tHeapStatus;
begin
  fhs := getFPCHeapStatus();
  log('FPC Heap:');
  log(format('MaxHeapSize      %, kb',[fhs.maxHeapSize div 1024]));
  log(format('MaxHeapUsed      %, kb',[fhs.maxHeapUsed div 1024]));
  log(format('CurrHeapSize     %, kb',[fhs.currHeapSize div 1024]));
  log(format('CurrHeapUsed     %, kb',[fhs.currHeapUsed div 1024]));
  log(format('CurrHeapFree     %, kb',[fhs.currHeapFree div 1024]));
  hs := getHeapStatus();
  log('Heap:');
  log(format('TotalAddrSpace   %, kb',[hs.totalAddrSpace div 1024]));
  log(format('TotalUncommitted %, kb',[hs.totalUncommitted div 1024]));
  log(format('TotalCommitted   %, kb',[hs.totalCommitted div 1024]));
  log(format('TotalAllocated   %, kb',[hs.totalAllocated div 1024]));
  log(format('TotalFree        %, kb',[hs.totalFree div 1024]));
  log(format('TotalSmall       %, blocks',[hs.freeSmall]));
  log(format('TotalBig         %, blocks',[hs.freeBig]));
  log(format('Overhead         %, kb',[hs.overhead div 1024]));
  log(format('HeapErrorCode    %d',[hs.heapErrorCode div 1024]));
end;

procedure logDPMIInfo();
var
  ver: tDPMIVersionInfo;
begin
  go32.get_dpmi_version(ver);
  log(format('DPMI Version: %d.%d', [ver.major, ver.minor]));
  note(' - Page size '+comma(get_page_size)+' bytes');
  note(format(' - Memory (used:%,K free:%,K, total:%,K)',[getUsedMemory/1024, getFreeSystemMemory/1024, getTotalMemory/1024]));
  if ver.flags and $1 <> $1 then warning(' - 16-bit');
  if ver.flags and $2 = $2 then warning(' - Real Mode');
  if ver.flags and $4 = $4 then note(' - Virtual Memory Support');
end;

{-------------------------------------------------------------}

initialization
  CPUInfo := getCPUInfo();
end.
