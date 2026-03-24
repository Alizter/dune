
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>

#include <errno.h>

#ifndef _WIN32

#include <caml/signals.h>

#include <errno.h>
#include <sys/types.h>
#include <dirent.h>
typedef struct dirent directory_entry;

value val_file_type(int typ) {
  switch(typ)
    {
#ifndef __HAIKU__     
   case DT_REG:
      return Val_int(0);
    case DT_DIR:
      return Val_int(1);
    case DT_CHR:
      return Val_int(2);
    case DT_BLK:
      return Val_int(3);
    case DT_LNK:
      return Val_int(4);
    case DT_FIFO:
      return Val_int(5);
    case DT_SOCK:
      return Val_int(6);
    case DT_UNKNOWN:
      return Val_int(7);
#endif
    default:
      return Val_int(7);
    }
}

CAMLprim value caml__dune_filesystem_stubs__readdir(value vd)
{
  CAMLparam1(vd);
  CAMLlocal2(v_filename, v_tuple);

  DIR * d;
  directory_entry * e;
  d = DIR_Val(vd);
  if (d == (DIR *) NULL) unix_error(EBADF, "readdir", Nothing);
  caml_enter_blocking_section();
  errno = 0;
  e = readdir((DIR *) d);
  caml_leave_blocking_section();
  if (e == (directory_entry *) NULL) {
    if(errno == 0) {
      CAMLreturn(Val_int(0));
    } else {
      uerror("readdir", Nothing);
    }
  }
  v_filename = caml_copy_string(e->d_name);
  v_tuple = caml_alloc_small(2, 0);
  Field(v_tuple, 0) = v_filename;
#ifndef __HAIKU__
  Field(v_tuple, 1) = val_file_type(e->d_type);
#else
  Field(v_tuple, 1) = Val_int(7);
#endif
  CAMLreturn(v_tuple);
}

#else

#include <windows.h>

CAMLprim value caml__dune_filesystem_stubs__readdir(value vd)
{
  unix_error(ENOSYS, "readdir", Nothing);
}

/* Map Windows file attributes to Unix file_kind values:
   S_REG=0, S_DIR=1, S_LNK=4 */
static int file_kind_of_attrs(DWORD attrs)
{
  if (attrs & FILE_ATTRIBUTE_REPARSE_POINT)
    return 4; /* S_LNK - junctions, symlinks, WSL symlinks */
  if (attrs & FILE_ATTRIBUTE_DIRECTORY)
    return 1; /* S_DIR */
  return 0; /* S_REG */
}

/* Read a directory using FindFirstFileW/FindNextFileW, returning
   (string * Unix.file_kind) list with UTF-8 filenames and correct
   file kinds for reparse points. */
CAMLprim value caml__dune_filesystem_stubs__read_dir_with_kinds_win32(value v_path)
{
  CAMLparam1(v_path);
  CAMLlocal4(v_list, v_pair, v_name, v_cons);

  HANDLE hFind;
  WIN32_FIND_DATAW findData;
  const char *path;
  int pathlen;
  char *pattern;
  int wide_len;
  wchar_t *wide_pattern;
  char utf8_buf[MAX_PATH * 3];
  int utf8_len;

  path = String_val(v_path);
  pathlen = caml_string_length(v_path);

  /* Build the search pattern: path\* */
  pattern = (char *)malloc(pathlen + 3);
  if (!pattern) unix_error(ENOMEM, "read_dir", v_path);
  memcpy(pattern, path, pathlen);
  pattern[pathlen] = '\\';
  pattern[pathlen + 1] = '*';
  pattern[pathlen + 2] = '\0';

  /* Convert to UTF-16 */
  wide_len = MultiByteToWideChar(CP_UTF8, 0, pattern, -1, NULL, 0);
  if (wide_len == 0) {
    free(pattern);
    win32_maperr(GetLastError());
    uerror("read_dir", v_path);
  }
  wide_pattern = (wchar_t *)malloc(wide_len * sizeof(wchar_t));
  if (!wide_pattern) {
    free(pattern);
    unix_error(ENOMEM, "read_dir", v_path);
  }
  MultiByteToWideChar(CP_UTF8, 0, pattern, -1, wide_pattern, wide_len);
  free(pattern);

  hFind = FindFirstFileW(wide_pattern, &findData);
  free(wide_pattern);

  if (hFind == INVALID_HANDLE_VALUE) {
    win32_maperr(GetLastError());
    uerror("read_dir", v_path);
  }

  v_list = Val_emptylist;

  do {
    /* Skip . and .. */
    if (findData.cFileName[0] == L'.' &&
        (findData.cFileName[1] == L'\0' ||
         (findData.cFileName[1] == L'.' && findData.cFileName[2] == L'\0')))
      continue;

    /* Convert filename from UTF-16 to UTF-8 */
    utf8_len = WideCharToMultiByte(CP_UTF8, 0, findData.cFileName, -1,
                                   utf8_buf, sizeof(utf8_buf), NULL, NULL);
    if (utf8_len == 0) continue;

    v_name = caml_copy_string(utf8_buf);

    /* Create pair (name, kind) — kind is a Unix.file_kind value */
    v_pair = caml_alloc(2, 0);
    Store_field(v_pair, 0, v_name);
    Store_field(v_pair, 1, Val_int(file_kind_of_attrs(findData.dwFileAttributes)));

    /* Cons onto list */
    v_cons = caml_alloc(2, 0);
    Store_field(v_cons, 0, v_pair);
    Store_field(v_cons, 1, v_list);
    v_list = v_cons;
  } while (FindNextFileW(hFind, &findData));

  FindClose(hFind);
  CAMLreturn(v_list);
}

/* Delete a file given a UTF-8 path, using the wide Windows API. */
CAMLprim value caml__dune_filesystem_stubs__win32_unlink(value v_path)
{
  CAMLparam1(v_path);
  wchar_t wide_buf[MAX_PATH];
  int len;

  len = MultiByteToWideChar(CP_UTF8, 0, String_val(v_path), -1,
                            wide_buf, MAX_PATH);
  if (len == 0) {
    win32_maperr(GetLastError());
    uerror("unlink", v_path);
  }
  if (!DeleteFileW(wide_buf)) {
    win32_maperr(GetLastError());
    uerror("unlink", v_path);
  }
  CAMLreturn(Val_unit);
}

/* Remove a directory given a UTF-8 path, using the wide Windows API.
   Also works for removing junction/symlink reparse points. */
CAMLprim value caml__dune_filesystem_stubs__win32_rmdir(value v_path)
{
  CAMLparam1(v_path);
  wchar_t wide_buf[MAX_PATH];
  int len;

  len = MultiByteToWideChar(CP_UTF8, 0, String_val(v_path), -1,
                            wide_buf, MAX_PATH);
  if (len == 0) {
    win32_maperr(GetLastError());
    uerror("rmdir", v_path);
  }
  if (!RemoveDirectoryW(wide_buf)) {
    win32_maperr(GetLastError());
    uerror("rmdir", v_path);
  }
  CAMLreturn(Val_unit);
}

#endif
