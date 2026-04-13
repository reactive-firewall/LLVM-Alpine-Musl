SECTIONS
{
  .eh_frame :
  {
    __eh_frame_start = .;
    KEEP(*(.eh_frame))
    __eh_frame_end = .;
  }

  .eh_frame_hdr :
  {
    KEEP(*(.eh_frame_hdr))
  }

  __eh_frame_hdr_start = SIZEOF(.eh_frame_hdr) > 0 ? ADDR(.eh_frame_hdr) : 0;
  __eh_frame_hdr_end   = SIZEOF(.eh_frame_hdr) > 0 ? . : 0;
}
