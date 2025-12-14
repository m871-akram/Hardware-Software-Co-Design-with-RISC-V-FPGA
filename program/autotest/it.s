# TAG = IT
    .text
    
    # Initialize test value
    lui x31, 0x0
    
    # Setup interrupt vector to point to interrupt handler
    la x1, interrupt_handler
    csrrw x0, mtvec, x1         # Set mtvec to interrupt handler address
    
    # Enable global interrupts (MIE bit in mstatus)
    addi x1, x0, 1 << 3         # MIE = bit 3
    csrrs x0, mstatus, x1       # Set MIE bit in mstatus
    
    # Enable external interrupts in mie register
    addi x1, x0, 0x7ff          # Enable bits 0-10
    addi x1, x1, 1              # Result: 0x800 (bit 11)
    csrrs x0, mie, x1           # Enable external interrupts in mie
    
    # Trigger interrupt via PLIC (write to interrupt pending register)
    lui x2, 0x0c002             # PLIC base address for interrupt pending
    addi x1, x0, 1 << 2         # Interrupt ID 2
    sw x1, 0(x2)                # Trigger the interrupt
    
    # Output initial value before interrupt
    lui x31, 0xBEF0             # Before interrupt: 0xBEF00000
    
    # Initialize counter
    addi x3, x0, 0
    
wait_loop:
    # Wait for interrupt to be handled (x3 will be set by handler)
    beq x3, x0, wait_loop
    
    # After interrupt handled, output success value
    lui x31, 0x600D             # Success: 0x600D0000
    
    ebreak                      # End test
    
interrupt_handler:
    # Save context (simplified - just using x4)
    addi x4, x31, 0             # Save x31
    
    # Mark that interrupt was taken
    addi x3, x0, 1              # Set flag to exit wait loop
    
    # Output value from interrupt handler
    lui x31, 0x1517             # In interrupt: 0x15170000
    
    # Acknowledge interrupt in PLIC
    lui x5, 0x0c200             # PLIC claim/complete base
    addi x5, x5, 4              # Claim/complete register
    lw x6, 0(x5)                # Read claim (get interrupt ID)
    sw x6, 0(x5)                # Write to complete the interrupt
    
    # Restore context
    addi x31, x4, 0             # Restore x31
    
    # Return from interrupt
    mret

    # max_cycle 10000
    # pout_start
    # BEF00000
    # 15170000
    # 600D0000
    # pout_end
