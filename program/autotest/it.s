# TAG = IT
    .text

    # Setup interrupt vector to point to interrupt handler
    la x1, interrupt_handler
    csrrw x0, mtvec, x1         # Set mtvec to interrupt handler address

    # Enable global interrupts (MIE bit in mstatus)
    addi x1, x0, 8              # MIE = bit 3
    csrrw x0, mstatus, x1       # Set MIE bit in mstatus (use csrrw, not csrrs)

    # Enable external interrupts in mie register (bit 11 = MEIP)
    addi x1, x0, 0x7ff          # 2047
    addi x1, x1, 1              # 2048 = 0x800 (bit 11)
    csrrs x0, mie, x1           # Enable MEIP in mie

    # Enable interrupt source 2 (push button) in PLIC enable register
    lui x2, 0x0c002             # 0x0C002000 = PLIC enable register
    addi x1, x0, 4              # Bit 2 = push button IRQ source
    sw x1, 0(x2)                # Set PLIC enable(2) = 1

    # Output initial value (before interrupt)
    lui x31, 0xBEF00            # pout: 0xBEF00000

    # Wait for interrupt from testbench push signal
    addi x3, x0, 0
wait_loop:
    beq x3, x0, wait_loop

    # After interrupt handled, output success value
    lui x31, 0x600D0            # pout: 0x600D0000

    ebreak                      # End test

interrupt_handler:
    # Mark that interrupt was taken
    addi x3, x0, 1              # Set flag to exit wait loop

    # Output value from interrupt handler
    lui x31, 0x15170            # pout: 0x15170000

    # Acknowledge interrupt: read claim then write to complete
    lui x5, 0x0c200             # PLIC claim/complete base
    addi x5, x5, 4              # 0x0C200004 = claim/complete register
    lw x6, 0(x5)                # Read claim (gets IRQ ID, clears pending)
    sw x6, 0(x5)                # Write to complete the interrupt

    # Return from interrupt
    mret

    # max_cycle 10000
    # irq_start
    # 100
    # irq_end
    # pout_start
    # BEF00000
    # 15170000
    # 600D0000
    # pout_end
