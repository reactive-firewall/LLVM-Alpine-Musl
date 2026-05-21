/* PIC-friendly. Works when linking relocatable objects (-r) and final links.
 * Uses section-local '.'-based symbols so the linker emits relocations
 * rather than fixed absolute addresses. PROVIDE used so user code can
 * override symbols if needed.
 */

SECTIONS
{
  /* .eh_frame: keep CFI entries and expose start/end within the section */
  .eh_frame :
  {
    PROVIDE(__eh_frame_start = .);
    KEEP(*(.eh_frame))
    PROVIDE(__eh_frame_end = .);
  }

  /* .eh_frame_hdr: keep header entries and expose start/end within the section.
   * Note: for -r there is no final ADDR() meaning; defining start/end here
   * produces relocatable symbols. For final link, these symbols will be
   * resolved to runtime addresses by the linker as usual.
   */
  .eh_frame_hdr :
  {
    PROVIDE(__eh_frame_hdr_start = .);
    KEEP(*(.eh_frame_hdr))
    PROVIDE(__eh_frame_hdr_end = .);
  }

  /* Optional: provide fallback zero values if section absent after a final link.
   * These PROVIDE()s will be ignored if symbols above were defined; they exist
   * to make intent explicit in case some tool queries them before relocation.
   */
  /* (Commented out because for -r these would be inappropriate;
     leave them commented or remove.) */
  /* PROVIDE(__eh_frame_hdr_start_addr = 0); */
  /* PROVIDE(__eh_frame_hdr_end_addr   = 0); */
}
