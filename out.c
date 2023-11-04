#include "stdio.h"

int main() {
  unsigned char elf[] = {
    // elf header
      // e_ident
      0x7F, 0x45, 0x4c, 0x46, // EI_MAG{0,1,2,3}
      0x02, // IE_CLASS  64bit
      0x01, // EI_DATA  little endian
      0x01, // EI_VERSION  current
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // EI_PAD
    0x02, 0x00, // e_type  executable file
    0x3e, 0x00, // e_machine  AMD x86-64
    0x01, 0x00, 0x00, 0x00, // e_version  current
    0x00, 0x01, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, // e_entry
    0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // e_phoff
    0x78, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // e_shoff
    0x00, 0x00, 0x00, 0x00, // e_flags
    0x40, 0x00, // e_ehsize 64
    0x38, 0x00, // e_phentsize
    0x01, 0x00, // e_phnum
    0x40, 0x00, // e_shentsize
    0x02, 0x00, // e_shnum
    0x01, 0x00, // e_shstrndx
    // program header
    0x01, 0x00, 0x00, 0x00, // p_type PT_LOAD
    0x05, 0x00, 0x00, 0x00, // p_flags
    0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // p_offset
    0x00, 0x01, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, // p_vaddr
    0x00, 0x01, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, // p_paddr
    0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // p_filesz
    0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // p_memsz
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // p_align
    // section header .text
    0x0b, 0x00, 0x00, 0x00, // sh_name .text
    0x01, 0x00, 0x00, 0x00, // sh_type SHT_PROGBITS
    0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // sh_flags
    0x00, 0x01, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, // sh_addr
    0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // sh_offset
    0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // sh_size
    0x00, 0x00, 0x00, 0x00, // sh_link
    0x00, 0x00, 0x00, 0x00, // sh_info
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // sh_addralign
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // sh_entsize
    // section header .shstrtab
    0x01, 0x00, 0x00, 0x00, // sh_name .shstrtab
    0x03, 0x00, 0x00, 0x00, // sh_type SHT_STRTAB
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // sh_flags
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // sh_addr
    0x0A, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // sh_offset
    0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // sh_size
    0x00, 0x00, 0x00, 0x00, // sh_link
    0x00, 0x00, 0x00, 0x00, // sh_info
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // sh_addralign
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // sh_entsize
    0x00, 0x00, 0x00, 0x00, // try pad
    0x00, 0x00, 0x00, 0x00, // try pad
    // .text
    0xB8, 0x3C, 0x00, 0x00, 0x00, // mov eax, 60
    0x48, 0x31, 0xFF, // maybe xor rdi, rdi
    0x0F, 0x05, // syscall
    // .shstrtab
    '\0', '.', 's', 'h', 's', 't', 'r', 't', 'a', 'b',
    '\0', '.', 't', 'e', 'x', 't',
    '\0',
    0x00, 0x00, 0x00, 0x00, 0x00, // try pad
  };

  fwrite(elf, 1, sizeof(elf)/sizeof(char), fopen("ass", "w"));
}
