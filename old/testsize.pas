program test_size;

uses myutils, crt, go32;

{
empty = 59k

[59k] switch to release (hmm no better?)
[34k] no debug info
[84k] sysutils
[88k] +crt
[88k] +go32v2

For test.exe

Release + myutils = 97k
Debug + myutils = 177k (this is same as before)
Ok removed the sysutils now

52k / 115k

}


begin
end.