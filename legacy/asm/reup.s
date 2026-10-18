.intel_syntax noprefix
.text
.globl _start
_start:
  mov eax, [esp+4]
  lea ecx, [eax+0x24]
  push ecx
  push eax
  call setexec
  jmp execute
