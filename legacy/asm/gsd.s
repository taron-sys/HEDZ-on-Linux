.intel_syntax noprefix
.text
.globl _start
/* IDirectDrawSurface (v1)::GetSurfaceDesc(this, DDSURFACEDESC*), stdcall 8.
 * Original DirectDraw returned a valid lpSurface (+DDSD_LPSURFACE) for system-memory surfaces; the game (voxel
 * sprite renderer) draws into that pointer without ever calling Lock. Wine only fills lpSurface during Lock,
 * so the game found NULL and skipped drawing -> the hed / held-item sprites stayed empty. */
_start:
  push ebp
  mov ebp, esp
  push ebx
  push esi
  sub esp, 0x80
  push dword ptr [ebp+12]
  push dword ptr [ebp+8]
  call orig_gsd1                /* stdcall: pops its 8 bytes */
  test eax, eax
  jne 9f
  mov esi, [ebp+12]             /* DDSURFACEDESC* */
  test dword ptr [esi+0x68], 0x800      /* ddsCaps.dwCaps & SYSTEMMEMORY */
  je 9f
  test dword ptr [esi+0x68], 0x1000     /* TEXTURE only (sprites); leave plain offscreen surfaces alone */
  je 9f
  mov ebx, [ebp+8]
  sub ebx, 0x10                 /* v1 iface -> IDirectDrawSurface7 */
  lea ecx, [esp]                /* DDSURFACEDESC2 for Lock */
  push edi
  mov edi, ecx
  xor eax, eax
  mov ecx, 0x1f
  rep stosd
  pop edi
  lea edx, [esp]
  mov dword ptr [edx], 0x7c
  push 0
  push 1
  push edx
  push 0
  push ebx
  mov eax, [ebx]
  call [eax+0x64]               /* Lock */
  test eax, eax
  jne 8f
  mov eax, [esp+0x24]           /* desc2.lpSurface */
  mov [esi+0x24], eax
  or dword ptr [esi+4], 0x800   /* DDSD_LPSURFACE */
  push 0
  push ebx
  mov eax, [ebx]
  call [eax+0x80]               /* Unlock */
8:
  xor eax, eax
9:
  add esp, 0x80
  pop esi
  pop ebx
  pop ebp
  ret 8
