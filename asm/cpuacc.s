.intel_syntax noprefix
.text
.globl _start
/* ddraw_texture_init: entered by jmp from 0x10036da3 (replaces `mov eax,[ebp-0x9c]`), just before the main
 * wined3d texture is created. [ebp-0xa4] = DDSURFACEDESC2* (caps at +0x6c), [ebp-0x50] = wined3d bind
 * flags, [ebp-0x4c] = wined3d resource access.
 *
 * 1. Plain textures (DDSCAPS_TEXTURE, not 3DDEVICE / PRIMARY / BACKBUFFER / ZBUFFER): drop the
 *    RENDER_TARGET bind from the *main* texture (Wine keeps a separate GPU "draw texture" for rendering)
 *    so that CPU access becomes legal, then add CPU access. Lock()/CPU blits into these textures need it;
 *    without it the streamed hed / held-item sprite textures could never be written.
 * 2. Any other surface without RENDER_TARGET / DEPTH_STENCIL bind: add CPU access.
 * Never add GPU access to system-memory surfaces: the game keeps raw pointers into them, and with GPU
 * access wined3d moves fills/blits to the GPU and later Locks download over the game's CPU drawing. */
_start:
  mov eax, [ebp-0xa4]
  mov eax, [eax+0x6c]           /* ddsCaps.dwCaps */
  test eax, 0x1000              /* TEXTURE */
  je 1f
  test eax, 0x22204             /* 3DDEVICE | ZBUFFER | PRIMARYSURFACE | BACKBUFFER */
  jne 1f
  and dword ptr [ebp-0x50], 0xffffffdf   /* bind &= ~RENDER_TARGET */
1:
  mov eax, [ebp-0x50]
  test al, 0x60
  jne 2f
  or dword ptr [ebp-0x4c], 2
2:
  mov eax, [ebp-0x9c]
  jmp back
