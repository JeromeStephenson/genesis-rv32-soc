OUTPUT_ARCH("riscv")
ENTRY(_reset)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 128K
    DMEM (rwx) : ORIGIN = 0x80000000, LENGTH = 128K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text.reset))
        *(.text*)
        *(.rodata*)
        *(.srodata*)
        . = ALIGN(4);
    } > IMEM

    .data :
    {
        . = ALIGN(4);
        _sdata = .;
        PROVIDE(_gp = _sdata + 0x800);
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
        _edata = .;
    } > DMEM AT > IMEM

    _sidata = LOADADDR(.data);

    .bss (NOLOAD) :
    {
        . = ALIGN(16);
        _sbss = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(16);
        _ebss = .;
    } > DMEM

    /* --- FreeRTOS ISR / first-task stack, used by portASM.S -----------
       Reserved block of its own so it can NEVER overlap main()'s stack. */
    . = ALIGN(16);
    . += 2048;                        /* 2 KiB */
    __freertos_irq_stack_top = .;     /* grows down from here */

    /* --- main() / pre-scheduler stack: strictly INSIDE DMEM ---------- */
    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM) - 16;   /* 0x8001FFF0, not 0x80020000 */

    _heap_start = _ebss;
}
