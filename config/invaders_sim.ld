OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  ram (wxa!ri): ORIGIN = 0x1000, LENGTH = 32K
}

SECTIONS
{
  .text : {
    *(.text.init) *(.text .text.*)
  } > ram

  .rodata : {
    *(.rodata .rodata.*)
  } > ram

  .data : {
    . = ALIGN(4);
    *(.sdata .sdata.*) *(.data .data.*)
  } > ram

  .bss : {
    . = ALIGN(4);
    *(.sbss .sbss.*) *(.bss .bss.*)
    . = ALIGN(4);
  } > ram

  PROVIDE(_memory_start = ORIGIN(ram));
  PROVIDE(_memory_end   = ORIGIN(ram) + LENGTH(ram));
}
