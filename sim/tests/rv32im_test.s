# RV32IM CPU Test Program
# Memory operations are LAST (after multiply/divide)

.section .text
.globl _start

_start:
    # ===== Test 1: Basic Arithmetic =====
    addi x1, x0, 5          # x1 = 5
    addi x2, x0, 7          # x2 = 7
    add  x3, x1, x2         # x3 = 12 (expected)
    sub  x4, x2, x1         # x4 = 2 (expected)
    
    # ===== Test 2: Logical Operations =====
    and  x5, x1, x2         # x5 = 5 & 7 = 5
    or   x6, x1, x2         # x6 = 5 | 7 = 7
    xor  x7, x1, x2         # x7 = 5 ^ 7 = 2
    andi x8, x2, 3          # x8 = 7 & 3 = 3
    ori  x9, x1, 8          # x9 = 5 | 8 = 13
    xori x10, x2, 15        # x10 = 7 ^ 15 = 8
    
    # ===== Test 3: Shifts =====
    slli x11, x1, 2         # x11 = 5 << 2 = 20
    srli x12, x2, 1         # x12 = 7 >> 1 = 3
    addi x13, x0, -8        # x13 = -8 (0xFFFFFFF8)
    srai x14, x13, 1        # x14 = -8 >> 1 = -4 (0xFFFFFFFC)
    sll  x15, x1, x2        # x15 = 5 << 7 = 640
    srl  x16, x2, x1        # x16 = 7 >> 5 = 0
    sra  x17, x13, x1       # x17 = -8 >> 5 = -1 (0xFFFFFFFF)
    
    # ===== Test 4: Comparisons =====
    slt  x18, x1, x2        # x18 = (5 < 7) = 1
    slt  x19, x2, x1        # x19 = (7 < 5) = 0
    sltu x20, x13, x1       # x20 = (0xFFFFFFF8 < 5 unsigned) = 0
    slti x21, x1, 10        # x21 = (5 < 10) = 1
    sltiu x22, x1, 3        # x22 = (5 < 3 unsigned) = 0
    
    # ===== Test 5: Upper Immediates =====
    lui  x23, 0x12345       # x23 = 0x12345000
    auipc x24, 0x1000       # x24 = PC + 0x1000000
    
    # ===== Test 6: Branches =====
    beq  x1, x1, branch1    # Should branch (5 == 5)
    addi x25, x0, 99        # Should NOT execute
branch1:
    addi x25, x0, 1         # x25 = 1 (expected)
    
    bne  x1, x2, branch2    # Should branch (5 != 7)
    addi x25, x0, 88        # Should NOT execute
branch2:
    addi x25, x25, 1        # x25 = 2 (expected)
    
    blt  x1, x2, branch3    # Should branch (5 < 7)
    addi x25, x0, 77        # Should NOT execute
branch3:
    addi x25, x25, 1        # x25 = 3 (expected)
    
    bge  x2, x1, branch4    # Should branch (7 >= 5)
    addi x25, x0, 66        # Should NOT execute
branch4:
    addi x25, x25, 1        # x25 = 4 (expected)
    
    # ===== Test 7: JAL/JALR =====
    jal  x26, jump1         # Jump and link
    addi x25, x0, 55        # Should NOT execute
jump1:
    addi x25, x25, 1        # x25 = 5 (expected)
    jalr x27, x26, 0        # Return (jump to x26)
    
    # ===== Test 8: Multiply/Divide (M extension) =====
    addi x1, x0, 6          # x1 = 6
    addi x2, x0, 7          # x2 = 7
    mul  x3, x1, x2         # x3 = 42
    
    # Test with larger numbers
    addi x4, x0, 100        # x4 = 100
    addi x5, x0, 10         # x5 = 10
    mul  x6, x4, x5         # x6 = 1000
    div  x7, x4, x5         # x7 = 10
    rem  x8, x4, x5         # x8 = 0
    
    # Test negative multiply
    addi x9, x0, -3         # x9 = -3
    mul  x10, x1, x9        # x10 = -18 (6 * -3)
    
    # ===== Test 9: Memory Operations =====
    addi x28, x0, 0x100     # x28 = 256 (base address)
    
    # Store operations
    sw   x3, 0(x28)         # Store x3 (42) at mem[0x100]
    sw   x6, 4(x28)         # Store x6 (1000) at mem[0x104]
    sw   x7, 8(x28)         # Store x7 (10) at mem[0x108]
    
    # Load operations
    lw   x11, 0(x28)        # x11 = mem[0x100] = 42
    lw   x12, 4(x28)        # x12 = mem[0x104] = 1000
    lw   x13, 8(x28)        # x13 = mem[0x108] = 10
    
    # Test byte stores/loads
    addi x14, x0, 0xAB      # x14 = 0xAB
    sb   x14, 12(x28)       # Store byte at mem[0x10C]
    lbu  x15, 12(x28)       # x15 = 0xAB (unsigned byte)
    lb   x16, 12(x28)       # x16 = 0xFFFFFFAB (signed byte)
    
    # Test halfword stores/loads
    addi x17, x0, 0x1234    # x17 = 0x1234
    sh   x17, 16(x28)       # Store halfword at mem[0x110]
    lhu  x18, 16(x28)       # x18 = 0x1234 (unsigned halfword)
    lh   x19, 16(x28)       # x19 = 0x1234 (signed halfword)
    
    # ===== COMPLETION MARKER =====
    addi x31, x0, 0xFF      # x31 = 255 (signals done)

# Infinite loop
loop:
    beq x0, x0, loop