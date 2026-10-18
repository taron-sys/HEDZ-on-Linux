.intel_syntax noprefix
.text
.globl _start
/* MATRIXLOAD handler (jump table opcode 4). edi=count, [ebp-0xc4]=data, [ebp-0xc0]=size(byte), [ebp+0xc]=device */
_start:
  mov esi, [ebp-0xc4]
  mov ebx, edi
  test ebx, ebx
  je 9f
1:
  mov eax, [esi+4]
  dec eax
  mov dword ptr [esp], 0
  mov [esp+4], eax
  mov dword ptr [esp+8], 2
  call get_obj
  test eax, eax
  je 2f
  push eax              /* matrix */
  push dword ptr [esi]  /* dest handle */
  mov ecx, [ebp+0xc]
  add ecx, 0xc
  push ecx              /* IDirect3DDevice* */
  mov edx, [ecx]
  call [edx+0x40]       /* SetMatrix */
2:
  movzx ecx, byte ptr [ebp-0xc0]
  add esi, ecx
  dec ebx
  jne 1b
9:
  jmp mload_cont
/* MATRIXMULTIPLY per-entry hook at 0x10015ba7; ebx = current D3DMATRIXMULTIPLY* */
mmul_hook:
  pushad
  mov eax, [ebx]
  dec eax

  sub esp, 12
  mov dword ptr [esp], 0
  mov [esp+4], eax
  mov dword ptr [esp+8], 2
  call get_obj
  add esp, 12
  test eax, eax
  je 3f
  push eax
  push dword ptr [ebx]
  mov ecx, [ebp+0xc]
  add ecx, 0xc
  push ecx
  mov edx, [ecx]
  call [edx+0x40]
3:
  popad
  add ebx, dword ptr [ebp-0xcc]
  jmp mmul_back
