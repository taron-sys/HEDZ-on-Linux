.intel_syntax noprefix
.text
.globl _start
/* ddraw_texture_init, entered by jmp from 0x10036c1e (replaces `movzx ecx,byte [ebp+0xc]; mov edi,[ebp+0x10]`).
 * eax = struct ddraw_texture*; its surface_desc starts at +4 (flags +8, height +0xc, width +0x10, pitch +0x14,
 * mip count +0x1c, lpSurface +0x28, RGB bit count +0x58, ddsCaps.dwCaps +0x6c).
 *
 * The game Locks each video-memory texture ONCE at creation and from then on keeps writing into that pointer
 * (hed / equipment voxel sprites), expecting it to stay valid. Wine's map pointer for such GPU-resident
 * textures does not stay valid, so the writes were lost. Give plain 16 bpp video-memory textures caller-owned
 * memory (DDSD_LPSURFACE): Wine then always hands out exactly that pointer, and uploads from it. */
_start:
  pushad
  mov ebx, eax
  mov ecx, [ebx+0x6c]
  test ecx, 0x1000              /* DDSCAPS_TEXTURE */
  je 9f
  test ecx, 0x22224             /* BACKBUFFER|FRONTBUFFER|PRIMARY|3DDEVICE|ZBUFFER */
  jne 9f
  test ecx, 0x4000              /* DDSCAPS_VIDEOMEMORY */
  je 9f
  test dword ptr [ebx+8], 0x800 /* already has lpSurface */
  jne 9f
  cmp dword ptr [ebx+0x58], 16
  jne 9f
  test dword ptr [ebx+8], 0x20000   /* DDSD_MIPMAPCOUNT */
  je 1f
  cmp dword ptr [ebx+0x1c], 1
  ja 9f
1:
  mov eax, [ebx+0x10]
  lea eax, [eax*2+3]
  and eax, 0xfffffffc
  mov edx, eax                  /* pitch */
  imul eax, [ebx+0xc]
  add eax, 64
  push edx
  push eax
  push 1
  call 2f
2:
  pop eax                       /* position-independent: IAT slot = runtime(2b) + (calloc_iat - 2b) */
  add eax, calloc_iat - 2b
  call dword ptr [eax]
  add esp, 8
  pop edx
  test eax, eax
  je 9f
  mov [ebx+0x28], eax
  mov [ebx+0x14], edx
  or dword ptr [ebx+8], 0x808   /* DDSD_LPSURFACE | DDSD_PITCH */
9:
  popad
  movzx ecx, byte ptr [ebp+0xc]
  mov edi, [ebp+0x10]
  jmp back
