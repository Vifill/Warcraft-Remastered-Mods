# Hook handlers jumped to from patched sites in Warcraft.exe, plus VERSION.dll forwarders.
# Game addresses come from globals in w1r_mods.c, set from the game's real base address.
    .intel_syntax noprefix
    .text

# ghost_fix: replaces "movzx ecx,[edx+1Eh]; cmp byte [ecx+eax],0" at 0x508C8B.
# edx = unit on the neighbouring tile (NULL for a stale "unit here" flag), ecx = tile index.
    .globl _ghost_handler
_ghost_handler:
    test edx, edx
    jnz 1f
    mov eax, dword ptr [_g_tile_flags_pp]
    mov eax, dword ptr [eax]
    and word ptr [eax + ecx*2], 0xFEFF       # clear the stale flag for good
    jmp dword ptr [_g_ghost_free]            # treat the tile as free
1:  movzx ecx, byte ptr [edx + 0x1E]
    cmp byte ptr [ecx + eax], 0
    jmp dword ptr [_g_ghost_ret]

# middle_mouse_pan, shared part: returns this tick's pan delta in ecx (x) / edx (y), zero while
# the middle button is up. Clobbers eax.
pan_delta:
    push 4                                   # VK_MBUTTON
    call dword ptr [_g_GetAsyncKeyState]
    test ax, 0x8000
    jz 3f
    mov ecx, dword ptr [_g_mouse_x]
    movsx eax, word ptr [ecx]
    mov ecx, dword ptr [_g_mouse_y]
    movsx edx, word ptr [ecx]
    xor ecx, ecx
    cmp byte ptr [_g_pan_held], 0
    je 2f
    push esi
    mov esi, dword ptr [_g_pan_last_x]
    sub esi, eax
    imul esi, dword ptr [_g_pan_scale]
    sar esi, 8
    mov ecx, esi
    mov esi, dword ptr [_g_pan_last_y]
    sub esi, edx
    imul esi, dword ptr [_g_pan_scale]
    sar esi, 8
    mov dword ptr [_g_pan_last_y], edx
    mov edx, esi
    pop esi
    mov dword ptr [_g_pan_last_x], eax
    ret
2:  mov dword ptr [_g_pan_last_x], eax
    mov dword ptr [_g_pan_last_y], edx
    mov byte ptr [_g_pan_held], 1
    xor edx, edx
    ret
3:  mov byte ptr [_g_pan_held], 0
    xor ecx, ecx
    xor edx, edx
    ret

# middle_mouse_pan (W1): replaces "movsx ecx,si; add [cam_x],ecx" at 0x4F2474 in the scroll
# routine. esi/edi hold this tick's camera delta; while the middle button is held add the mouse
# movement.
    .globl _pan_handler
_pan_handler:
    pushad                                   # [esp+0]=edi [esp+4]=esi
    call pan_delta
    add word ptr [esp + 4], cx
    add word ptr [esp], dx
    popad
    movsx ecx, si                            # replayed original instructions
    push eax
    mov eax, dword ptr [_g_cam_x]
    add dword ptr [eax], ecx
    pop eax
    jmp dword ptr [_g_pan_ret]

# middle_mouse_pan (W2): replaces "cwde; add [cam_x],eax; movsx eax,cx" at 0x4DF656 in the
# scroll routine. ax/cx hold this tick's camera delta.
    .globl _pan2_handler
_pan2_handler:
    pushad                                   # [esp+24]=ecx [esp+28]=eax
    call pan_delta
    add word ptr [esp + 28], cx
    add word ptr [esp + 24], dx
    popad
    cwde                                     # replayed original instructions
    push ecx
    mov ecx, dword ptr [_g_cam_x]
    add dword ptr [ecx], eax
    pop ecx
    movsx eax, cx
    jmp dword ptr [_g_pan_ret]

# pathfinding_astar: replaces "lea eax,[ebp+8]; push 0FFFFh" at 0x508972 in findPath, after
# the goal area is marked. edi = unit. On success skip to findPath's cleanup.
    .globl _astar_handler
_astar_handler:
    pushad
    push edi
    call _w1r_astar
    add esp, 4
    test eax, eax
    popad                                    # flags preserved
    jz 5f
    add esp, 8                               # args of the earlier goal-marking call
    jmp dword ptr [_g_astar_cleanup]
5:  lea eax, [ebp + 8]
    push 0xFFFF
    jmp dword ptr [_g_astar_resume]

# VERSION.dll exports forwarded to the real system DLL.
    .macro fwd name
    .globl _fwd_\name
_fwd_\name:
    jmp dword ptr [_p_\name]
    .endm
    fwd GetFileVersionInfoA
    fwd GetFileVersionInfoByHandle
    fwd GetFileVersionInfoExA
    fwd GetFileVersionInfoExW
    fwd GetFileVersionInfoSizeA
    fwd GetFileVersionInfoSizeExA
    fwd GetFileVersionInfoSizeExW
    fwd GetFileVersionInfoSizeW
    fwd GetFileVersionInfoW
    fwd VerFindFileA
    fwd VerFindFileW
    fwd VerInstallFileA
    fwd VerInstallFileW
    fwd VerLanguageNameA
    fwd VerLanguageNameW
    fwd VerQueryValueA
    fwd VerQueryValueW
