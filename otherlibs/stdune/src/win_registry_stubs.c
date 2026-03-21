#include <caml/memory.h>
#include <caml/mlvalues.h>

#ifdef _WIN32
#include <windows.h>
#endif

CAMLprim value stdune_long_paths_enabled(value v_unit)
{
  CAMLparam1(v_unit);
#ifdef _WIN32
  HKEY key;
  DWORD value_data = 0;
  DWORD size = sizeof(DWORD);
  LONG result = RegOpenKeyExA(
    HKEY_LOCAL_MACHINE,
    "SYSTEM\\CurrentControlSet\\Control\\FileSystem",
    0, KEY_READ, &key);
  if (result == ERROR_SUCCESS) {
    RegQueryValueExA(
      key, "LongPathsEnabled", NULL, NULL,
      (LPBYTE)&value_data, &size);
    RegCloseKey(key);
  }
  CAMLreturn(Val_bool(value_data != 0));
#else
  CAMLreturn(Val_false);
#endif
}
