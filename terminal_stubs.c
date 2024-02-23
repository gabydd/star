#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <sys/ioctl.h>

CAMLprim value terminal_size(value fd) {
  CAMLparam1(fd);
  CAMLlocal1(result);
  struct winsize size;
  ioctl(Int_val(fd), TIOCGWINSZ, &size);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, Val_int(size.ws_col));
  Store_field(result, 1, Val_int(size.ws_row));
  CAMLreturn(result);
}
