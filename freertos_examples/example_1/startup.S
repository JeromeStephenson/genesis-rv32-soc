#=============================================================================
#  startup.S  -  RV32I SoC boot code (FreeRTOS bring-up, debug-enabled)
#=============================================================================
    .section .text.reset, "ax"
    .global _reset

_reset:
    .option push
    .option norelax
    la      gp, _gp
    .option pop

    la      sp, _stack_top

    /* Early trap handler: no FreeRTOS context yet */
    la      t0, boot_trap_handler
    csrw    mtvec, t0

    /* Make sure interrupts are disabled before C runtime */
    csrc    mstatus, 8
    csrw    mie, zero

    /*---------------------------------------------------------------
     * Copy .data from IMEM load address (LMA) to DMEM runtime (VMA)
     *-------------------------------------------------------------*/
    la      a0, _sdata
    la      a1, _edata
    la      a2, _sidata

.Lcopy_data:
    bgeu    a0, a1, .Lcopy_done
    lw      t0, 0(a2)
    sw      t0, 0(a0)
    addi    a0, a0, 4
    addi    a2, a2, 4
    j       .Lcopy_data

.Lcopy_done:
    /*---------------------------------------------------------------
     * Clear .bss
     *-------------------------------------------------------------*/
    la      a0, _sbss
    la      a1, _ebss

.Lclear_bss:
    bgeu    a0, a1, .Lbss_done
    sw      zero, 0(a0)
    addi    a0, a0, 4
    j       .Lclear_bss

.Lbss_done:
    /*---------------------------------------------------------------
     * MRET SMOKE TEST
     *-------------------------------------------------------------*/
    la      t0, .Lmret_ok
    csrw    mepc, t0
    li      t1, 0x00001880
    csrw    mstatus, t1
    mret

.Lmret_ok:
    la      a0, .Lmsg_mret
    jal     ra, .Lputstr

    /*---------------------------------------------------------------
     * MSCRATCH SMOKE TEST
     * This is the exact CSR FreeRTOS uses for context switching!
     *-------------------------------------------------------------*/
    li      t0, 0xDEADBEEF
    csrw    mscratch, t0       /* Write to mscratch */
    csrr    t1, mscratch       /* Read from mscratch */
    
    bne     t0, t1, .Lmscratch_fail /* If they don't match, it failed */
    
    la      a0, .Lmsg_mscratch_ok
    jal     ra, .Lputstr
    j       .Lcall_main

.Lmscratch_fail:
    la      a0, .Lmsg_mscratch_fail
    jal     ra, .Lputstr
    /* Hang */
9:  j       9b

.Lcall_main:
    call    main

.Lhalt:
    j       .Lhalt

#=============================================================================
#  Early-boot trap handler
#=============================================================================
    .align 2
    .global boot_trap_handler
boot_trap_handler:
    csrc    mstatus, 8
    csrr    s0, mcause
    csrr    s1, mepc
    csrr    s2, mtval

    li      t0, 0x80010000
    sw      s0, 0(t0)
    sw      s1, 4(t0)
    sw      s2, 8(t0)

    li      t0, 0x10001004
    sw      s0, 0(t0)

    la      a0, .Lmsg_c
    jal     ra, .Lputstr
    mv      a0, s0
    jal     ra, .Lputhex
    la      a0, .Lmsg_epc
    jal     ra, .Lputstr
    mv      a0, s1
    jal     ra, .Lputhex
    la      a0, .Lmsg_val
    jal     ra, .Lputstr
    mv      a0, s2
    jal     ra, .Lputhex
    la      a0, .Lmsg_crlf
    jal     ra, .Lputstr

9:  j       9b

#=============================================================================
#  Tiny UART helpers
#=============================================================================
    .section .text.bootdbg, "ax"

.Lputstr:
    mv      t2, a0
1:  lb      a0, 0(t2)
    beqz    a0, 2f
    li      t0, 0x10000004
3:  lw      t1, 0(t0)
    andi    t1, t1, 1
    beqz    t1, 3b
    li      t0, 0x10000000
    sw      a0, 0(t0)
    addi    t2, t2, 1
    j       1b
2:  ret

.Lputhex:
    mv      t2, a0
    li      t4, 28
1:  srl     a0, t2, t4
    andi    a0, a0, 0xF
    li      t0, 10
    blt     a0, t0, 2f
    addi    a0, a0, 0x57
    j       3f
2:  addi    a0, a0, 0x30
3:  li      t0, 0x10000004
4:  lw      t1, 0(t0)
    andi    t1, t1, 1
    beqz    t1, 4b
    li      t0, 0x10000000
    sw      a0, 0(t0)
    addi    t4, t4, -4
    bgez    t4, 1b
    ret

    .section .rodata
.Lmsg_c:    .asciz "\r\nTRAP mcause=0x"
.Lmsg_epc:  .asciz "  mepc=0x"
.Lmsg_val:  .asciz "  mtval=0x"
.Lmsg_crlf: .asciz "\r\n"
.Lmsg_mret: .asciz "MRET OK\r\n"
.Lmsg_mscratch_ok: .asciz "MSCRATCH OK\r\n"
.Lmsg_mscratch_fail: .asciz "ERR: MSCRATCH FAILED!\r\n"
