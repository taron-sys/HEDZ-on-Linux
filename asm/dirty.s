.intel_syntax noprefix
.text
.globl _start
_start:
/* hook_texhandle: entered by jmp from 0x1000d0c5, eax = surface base */
hook_texhandle:
  mov edx, 0x1800          /* SYSTEMMEMORY | TEXTURE: refresh any texture when bound */
  call dirty7
  mov edx, [esi]
  add eax, 0x18
  jmp tex_back
/* hook_blt: vtable slot IDirectDrawSurface::Blt (this, dst_rect, src, src_rect, flags, fx) */
hook_blt:
  /* COLORFILL (0x400) or DEPTHFILL (0x02000000) into a system-memory surface: do it on the CPU (see cpufill).
   * DEPTHFILL matters for the hed / equipment voxel renderer: the game clears its software z-buffer (a
   * system-memory DDSCAPS_ZBUFFER surface) with Blt(DEPTHFILL, 0xffff) and only falls back to clearing the
   * memory itself if that call FAILS. Wine succeeds but clears a GPU-side buffer, so the memory the game's
   * z-test reads stayed 0 and every voxel was rejected. */
  test dword ptr [esp+20], 0x02000400
  je 5f
  mov edx, [esp+24]
  test edx, edx
  je 5f
  mov edx, [edx+0x50]       /* DDBLTFX.dwFillColor */
  mov ecx, [esp+8]          /* dst rect or NULL */
  mov eax, [esp+4]
  sub eax, 0x10             /* v1 iface -> IDirectDrawSurface7 */
  call cpufill
  test eax, eax
  jne 5f
  ret 0x18                  /* handled, eax = DD_OK */
5:
  mov eax, [esp+12]
  test eax, eax
  je 1f
  sub eax, 0x10
  mov edx, 0x800           /* blit sources: system memory only */
  call dirty7
1:
  jmp orig_blt
/* hook_bltfast: IDirectDrawSurface::BltFast (this, x, y, src, rect, flags) */
hook_bltfast:
  /* sysmem 16bpp source -> texture destination: copy on the CPU (see cpubltfast) */
  test dword ptr [esp+24], 0xffffffee   /* only DDBLTFAST_SRCCOLORKEY (1) / WAIT (0x10) handled */
  jne 6f
  cmp dword ptr [esp+16], 0
  je 6f
  lea ecx, [esp+4]
  call cpubltfast
  test eax, eax
  jne 6f
  ret 0x18
6:
  mov eax, [esp+16]
  test eax, eax
  je 2f
  sub eax, 0x10
  mov edx, 0x800
  call dirty7
2:
  jmp orig_bltfast
/* dirty7: eax = IDirectDrawSurface7*, edx = caps mask; if (caps & mask), Lock+Unlock so wined3d re-uploads. preserves regs */
dirty7:
  pushad
  mov ebx, eax
  sub esp, 0x90
  mov edi, esp
  push edi
  push ebx
  mov eax, [ebx]
  call [eax+0x38]
  test eax, eax
  jne 9f
  test dword ptr [edi], edx
  je 9f
  lea esi, [edi+0x10]
  mov dword ptr [esi], 0x7c
  push 0
  push 1
  push esi
  push 0
  push ebx
  mov eax, [ebx]
  call [eax+0x64]
  test eax, eax
  jne 9f
  push 0
  push ebx
  mov eax, [ebx]
  call [eax+0x80]
9:
  add esp, 0x90
  popad
  ret

/* cpufill: eax = IDirectDrawSurface7*, ecx = RECT* or NULL, edx = fill colour.
 * If the surface is in system memory and 16 bpp: Lock, fill the rect with the colour, Unlock, return 0.
 * Otherwise return 1 (caller falls back to Wine's Blt).
 * Why: the game clears a sysmem surface with Blt(COLORFILL), then draws into it through a pointer it
 * kept from an earlier Lock. If wined3d does the fill on the GPU, the next Lock downloads the cleared GPU
 * copy over the game's drawing. Filling on the CPU keeps system memory authoritative. */
cpufill:
  pushad                    /* saved: edi+0 esi+4 ebp+8 esp+12 ebx+16 edx+20 ecx+24 eax+28 */
  mov ebx, eax
  sub esp, 0x90
  mov edi, esp              /* [edi] DDSCAPS2, [edi+0x10] DDSURFACEDESC2 */
  mov dword ptr [esp+0x90+28], 1
  push edi
  push ebx
  mov eax, [ebx]
  call [eax+0x38]           /* GetCaps */
  test eax, eax
  jne 8f
  test dword ptr [edi], 0x800
  je 8f
  lea esi, [edi+0x10]
  mov dword ptr [esi], 0x7c
  push 0
  push 1
  push esi
  push 0
  push ebx
  mov eax, [ebx]
  call [eax+0x64]           /* Lock */
  test eax, eax
  jne 8f
  cmp dword ptr [esi+0x54], 16
  jne 7f                    /* not 16 bpp: unlock and let Wine do it */
  /* rect -> left/top/right/bottom in [edi+0x00..0x0c] (caps no longer needed) */
  mov ecx, [esp+0x90+24]
  test ecx, ecx
  je 1f
  mov eax, [ecx]
  mov [edi], eax
  mov eax, [ecx+4]
  mov [edi+4], eax
  mov eax, [ecx+8]
  mov [edi+8], eax
  mov eax, [ecx+12]
  mov [edi+12], eax
  jmp 2f
1:
  mov dword ptr [edi], 0
  mov dword ptr [edi+4], 0
  mov eax, [esi+0xc]        /* dwWidth */
  mov [edi+8], eax
  mov eax, [esi+8]          /* dwHeight */
  mov [edi+12], eax
2:
  mov eax, [esi+0xc]        /* clamp right/bottom */
  cmp [edi+8], eax
  jle 3f
  mov [edi+8], eax
3:
  mov eax, [esi+8]
  cmp [edi+12], eax
  jle 3f
  mov [edi+12], eax
3:
  mov edx, [esp+0x90+20]    /* colour */
  mov ecx, [edi+4]          /* y = top */
4:
  cmp ecx, [edi+12]
  jge 6f
  mov eax, ecx
  imul eax, [esi+0x10]      /* y * lPitch */
  add eax, [esi+0x24]       /* + lpSurface */
  mov ebp, [edi]            /* x = left */
  lea eax, [eax+ebp*2]
  push ecx
  mov ecx, [edi+8]
  sub ecx, ebp              /* width */
  jle 9f
10:
  mov [eax], dx
  add eax, 2
  dec ecx
  jne 10b
9:
  pop ecx
  inc ecx
  jmp 4b
6:
  mov dword ptr [esp+0x90+28], 0
7:
  push 0
  push ebx
  mov eax, [ebx]
  call [eax+0x80]           /* Unlock */
8:
  add esp, 0x90
  popad
  ret

/* cpubltfast: ecx -> BltFast args {this(v1), x, y, src(v1), RECT*, flags}.
 * If src is a 16 bpp SYSTEMMEMORY surface and dst a 16 bpp TEXTURE (not sysmem): Lock both, copy the rect
 * (skipping src colour-key pixels if DDBLTFAST_SRCCOLORKEY), Unlock, return 0. Otherwise return 1.
 * Why: wined3d has no usable blitter for CPU-only source -> GPU-only (draw) texture and drops the copy
 * ("Operation requires 0x2 access"); this left the hed / held-item sprites (streamed 64x64 voxel
 * renders) empty. Locals at [ebp]: 0 capsS, 0x10 capsD, 0x20 descS, 0xa0 descD, 0x120 key, 0x128 args. */
cpubltfast:
  pushad
  sub esp, 0x140
  mov ebp, esp
  mov dword ptr [esp+0x140+28], 1
  mov [ebp+0x128], ecx
  mov eax, [ecx+12]
  sub eax, 0x10
  mov esi, eax                  /* src7 */
  mov eax, [ecx]
  sub eax, 0x10
  mov edi, eax                  /* dst7 */
  /* caps */
  push ebp
  push esi
  mov eax, [esi]
  call [eax+0x38]
  test eax, eax
  jne 99f
  lea eax, [ebp+0x10]
  push eax
  push edi
  mov eax, [edi]
  call [eax+0x38]
  test eax, eax
  jne 99f
  test dword ptr [ebp], 0x800   /* src SYSTEMMEMORY */
  je 99f
  mov eax, [ebp+0x10]
  test eax, 0x1000              /* dst TEXTURE */
  je 99f
  test eax, 0x800               /* dst not sysmem */
  jne 99f
  /* colour key */
  mov dword ptr [ebp+0x120], 0xffffffff
  mov ecx, [ebp+0x128]
  test dword ptr [ecx+20], 1
  je 1f
  lea eax, [ebp+0x120]
  push eax
  push 8                        /* DDCKEY_SRCBLT */
  push esi
  mov eax, [esi]
  call [eax+0x40]               /* GetColorKey */
  test eax, eax
  jne 99f
  and dword ptr [ebp+0x120], 0xffff
1:
  /* lock src (read-only) */
  mov dword ptr [ebp+0x20], 0x7c
  lea eax, [ebp+0x20]
  push 0
  push 0x11                     /* WAIT | READONLY */
  push eax
  push 0
  push esi
  mov eax, [esi]
  call [eax+0x64]
  test eax, eax
  jne 99f
  mov dword ptr [ebp+0xa0], 0x7c
  lea eax, [ebp+0xa0]
  push 0
  push 1
  push eax
  push 0
  push edi
  mov eax, [edi]
  call [eax+0x64]
  test eax, eax
  jne 97f
  cmp dword ptr [ebp+0x20+0x54], 16
  jne 96f
  cmp dword ptr [ebp+0xa0+0x54], 16
  jne 96f
  /* rect: [ebp+0x00..0x0c] reuse capsS area: l t r b */
  mov ecx, [ebp+0x128]
  mov eax, [ecx+16]
  test eax, eax
  je 2f
  mov edx, [eax]
  mov [ebp], edx
  mov edx, [eax+4]
  mov [ebp+4], edx
  mov edx, [eax+8]
  mov [ebp+8], edx
  mov edx, [eax+12]
  mov [ebp+12], edx
  jmp 3f
2:
  mov dword ptr [ebp], 0
  mov dword ptr [ebp+4], 0
  mov edx, [ebp+0x20+0xc]
  mov [ebp+8], edx
  mov edx, [ebp+0x20+8]
  mov [ebp+12], edx
3:
  /* clamp src rect to src size */
  mov edx, [ebp+0x20+0xc]
  cmp [ebp+8], edx
  jle 4f
  mov [ebp+8], edx
4:
  mov edx, [ebp+0x20+8]
  cmp [ebp+12], edx
  jle 4f
  mov [ebp+12], edx
4:
  /* width/height, clamped to dst size from (x,y) */
  mov eax, [ebp+8]
  sub eax, [ebp]                /* w */
  mov edx, [ebp+12]
  sub edx, [ebp+4]              /* h */
  mov ecx, [ebp+0x128]
  mov ebx, [ebp+0xa0+0xc]
  sub ebx, [ecx+4]              /* dstW - x */
  cmp eax, ebx
  jle 4f
  mov eax, ebx
4:
  mov ebx, [ebp+0xa0+8]
  sub ebx, [ecx+8]              /* dstH - y */
  cmp edx, ebx
  jle 4f
  mov edx, ebx
4:
  test eax, eax
  jle 95f
  test edx, edx
  jle 95f
  mov [ebp+0x10], eax           /* w (capsD area reused) */
  mov [ebp+0x14], edx           /* h */
  mov dword ptr [ebp+0x18], 0   /* row */
5:
  mov eax, [ebp+0x18]
  cmp eax, [ebp+0x14]
  jge 95f
  /* src row ptr */
  mov ecx, [ebp+4]
  add ecx, eax
  imul ecx, [ebp+0x20+0x10]
  add ecx, [ebp+0x20+0x24]
  mov edx, [ebp]
  lea esi, [ecx+edx*2]
  /* dst row ptr */
  mov ecx, [ebp+0x128]
  mov edx, [ecx+8]
  add edx, eax
  imul edx, [ebp+0xa0+0x10]
  add edx, [ebp+0xa0+0x24]
  mov ecx, [ecx+4]
  lea edi, [edx+ecx*2]
  mov ecx, [ebp+0x10]
  mov ebx, [ebp+0x120]
6:
  movzx eax, word ptr [esi]
  cmp eax, ebx
  je 7f
  mov [edi], ax
7:
  add esi, 2
  add edi, 2
  dec ecx
  jne 6b
  inc dword ptr [ebp+0x18]
  jmp 5b
95:
  mov dword ptr [esp+0x140+28], 0
96:
  /* unlock dst */
  mov ecx, [ebp+0x128]
  mov eax, [ecx]
  sub eax, 0x10
  push 0
  push eax
  mov eax, [eax]
  call [eax+0x80]
97:
  mov ecx, [ebp+0x128]
  mov eax, [ecx+12]
  sub eax, 0x10
  push 0
  push eax
  mov eax, [eax]
  call [eax+0x80]
99:
  add esp, 0x140
  popad
  ret
