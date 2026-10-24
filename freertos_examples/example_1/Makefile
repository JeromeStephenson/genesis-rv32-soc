#==============================================================================
#  Makefile - minimal FreeRTOS boot image for the RV32I SoC
#             (uses the OFFICIAL FreeRTOS RISC-V port from the kernel tree)
#  Produces: app.elf, app.map, imem.hex, dmem.hex
#==============================================================================

CROSS_COMPILE ?= riscv-none-elf-
CC      := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
SIZE    := $(CROSS_COMPILE)size
PYTHON  ?= python3

# Memory depths in WORDS - must match riscv_soc / tb_soc parameters
IMEM_WORDS := 32768
DMEM_WORDS := 32768

KERNEL := FreeRTOS-Kernel
PORT   := $(KERNEL)/portable/GCC/RISC-V
CHIP   := $(PORT)/chip_specific_extensions/RV32I_CLINT_no_extensions
BUILD  := build
TARGET := app.elf

#------------------------------------------------------------------------------
# Sources
#------------------------------------------------------------------------------
C_SRCS := \
    main.c \
    $(KERNEL)/tasks.c \
    $(KERNEL)/list.c \
    $(KERNEL)/queue.c \
    $(PORT)/port.c

S_SRCS := \
    startup.S \
    $(PORT)/portASM.S

OBJS := $(addprefix $(BUILD)/,$(C_SRCS:.c=.o) $(S_SRCS:.S=.o))

#------------------------------------------------------------------------------
# Flags
#   rv32i_zicsr_zifencei : your binutils gates CSR ops behind Zicsr
#   -mno-relax / medany  : no linker relaxation, PC-relative anywhere
#   (no -G0: your gcc does not implement it)
#------------------------------------------------------------------------------
CPUFLAGS := -march=rv32i_zicsr_zifencei -mabi=ilp32 -mcmodel=medany -mno-relax
INCLUDES := -I. -I$(KERNEL)/include -I$(PORT) -I$(CHIP)

CFLAGS  := $(CPUFLAGS) $(INCLUDES) \
           -ffreestanding -nostdlib -fno-builtin \
           -fdata-sections -ffunction-sections \
           -O2 -g3 -Wall -Wextra

ASFLAGS := $(CPUFLAGS) $(INCLUDES) -x assembler-with-cpp -g3

LDFLAGS := $(CPUFLAGS) -T linker.ld -nostartfiles \
           -Wl,-Map=$(TARGET:.elf=.map),--gc-sections

LIBS    := -lgcc

.PHONY: all hex hex-objcopy clean disasm info

all: hex

#------------------------------------------------------------------------------
# Compile
#------------------------------------------------------------------------------
$(BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/%.o: %.S
	@mkdir -p $(dir $@)
	$(CC) $(ASFLAGS) -c $< -o $@

$(TARGET): $(OBJS) linker.ld
	$(CC) $(LDFLAGS) $(OBJS) $(LIBS) -o $@
	$(SIZE) $@

#------------------------------------------------------------------------------
# Hex generation (region-aware: IMEM = load image, DMEM = .data init values)
#------------------------------------------------------------------------------
hex: imem.hex dmem.hex

imem.hex dmem.hex: $(TARGET) elf2hex.py
	$(PYTHON) elf2hex.py $(TARGET) imem.hex dmem.hex $(IMEM_WORDS) $(DMEM_WORDS)
	@echo "--- first words of imem.hex:"; head -n 4 imem.hex
	@echo "--- first words of dmem.hex:"; head -n 4 dmem.hex

# Fallback if python3 is unavailable
hex-objcopy: $(TARGET)
	$(OBJCOPY) -O binary -j .text -j .data $(TARGET) imem.bin
	$(OBJCOPY) -O binary -j .data          $(TARGET) dmem.bin
	od -An -v -tx4 --endian=little imem.bin | tr -s ' \n' '\n' | grep -v '^$$' > imem.hex
	od -An -v -tx4 --endian=little dmem.bin | tr -s ' \n' '\n' | grep -v '^$$' > dmem.hex
	rm -f imem.bin dmem.bin

#------------------------------------------------------------------------------
# Helpers
#------------------------------------------------------------------------------
disasm: $(TARGET)
	$(OBJDUMP) -d -S $(TARGET) > app.dis

info: $(TARGET)
	$(OBJDUMP) -h $(TARGET)

clean:
	rm -rf $(BUILD) $(TARGET) $(TARGET:.elf=.map) app.dis imem.hex dmem.hex
