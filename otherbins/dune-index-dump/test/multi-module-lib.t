Test dune-index-dump on a multi-module wrapped library index.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name mylib)
  >  (modules mylib helper dead))
  > EOF

  $ cat > mylib.ml <<EOF
  > let result = Helper.used_fn 42
  > EOF

  $ cat > mylib.mli <<EOF
  > val result : int
  > EOF

  $ cat > helper.ml <<EOF
  > let used_fn x = x + 1
  > let unused_fn x = x * 2
  > EOF

  $ cat > helper.mli <<EOF
  > val used_fn : int -> int
  > val unused_fn : int -> int
  > EOF

  $ cat > dead.ml <<EOF
  > let dead_fn x = x - 1
  > EOF

  $ cat > dead.mli <<EOF
  > val dead_fn : int -> int
  > EOF

  $ dune build @ocaml-index

  $ dune-index-dump --sexp _build/default/.mylib.objs/cctx.ocaml-index
  (((kind impl)
    (comp_unit Stdlib)
    (id 55)
    (locs
     ((name *)
      (file helper.ml)
      (line 2)
      (start_bol 22)
      (start_cnum 42)
      (end_bol 22)
      (end_cnum 43)))
    (related_group_size 0))
   ((kind impl)
    (comp_unit Stdlib)
    (id 54)
    (locs
     ((name -)
      (file dead.ml)
      (line 1)
      (start_bol 0)
      (start_cnum 18)
      (end_bol 0)
      (end_cnum 19)))
    (related_group_size 0))
   ((kind impl)
    (comp_unit Stdlib)
    (id 53)
    (locs
     ((name +)
      (file helper.ml)
      (line 1)
      (start_bol 0)
      (start_cnum 18)
      (end_bol 0)
      (end_cnum 19)))
    (related_group_size 0))
   ((kind impl)
    (comp_unit Mylib__Helper)
    (id 3)
    (locs
     ((name x)
      (file helper.ml)
      (line 2)
      (start_bol 22)
      (start_cnum 40)
      (end_bol 22)
      (end_cnum 41)))
    (related_group_size 0))
   ((kind impl)
    (comp_unit Mylib__Helper)
    (id 2)
    (locs
     ((name unused_fn)
      (file helper.ml)
      (line 2)
      (start_bol 22)
      (start_cnum 26)
      (end_bol 22)
      (end_cnum 35)))
    (related_group_size 0))
   ((kind impl)
    (comp_unit Mylib__Helper)
    (id 1)
    (locs
     ((name x)
      (file helper.ml)
      (line 1)
      (start_bol 0)
      (start_cnum 16)
      (end_bol 0)
      (end_cnum 17)))
    (related_group_size 0))
   ((kind intf)
    (comp_unit Mylib__Helper)
    (id 1)
    (locs
     ((name unused_fn)
      (file helper.mli)
      (line 2)
      (start_bol 25)
      (start_cnum 29)
      (end_bol 25)
      (end_cnum 38)))
    (related_group_size 2)
    (impl_id 2))
   ((kind impl)
    (comp_unit Mylib__Helper)
    (id 0)
    (locs
     ((name used_fn)
      (file helper.ml)
      (line 1)
      (start_bol 0)
      (start_cnum 4)
      (end_bol 0)
      (end_cnum 11))
     ((name Helper.used_fn)
      (file mylib.ml)
      (line 1)
      (start_bol 0)
      (start_cnum 13)
      (end_bol 0)
      (end_cnum 27)))
    (related_group_size 0))
   ((kind intf)
    (comp_unit Mylib__Helper)
    (id 0)
    (locs
     ((name used_fn)
      (file helper.mli)
      (line 1)
      (start_bol 0)
      (start_cnum 4)
      (end_bol 0)
      (end_cnum 11)))
    (related_group_size 2)
    (impl_id 0))
   ((kind impl)
    (comp_unit Mylib__Dead)
    (id 1)
    (locs
     ((name x)
      (file dead.ml)
      (line 1)
      (start_bol 0)
      (start_cnum 16)
      (end_bol 0)
      (end_cnum 17)))
    (related_group_size 0))
   ((kind impl)
    (comp_unit Mylib__Dead)
    (id 0)
    (locs
     ((name dead_fn)
      (file dead.ml)
      (line 1)
      (start_bol 0)
      (start_cnum 4)
      (end_bol 0)
      (end_cnum 11)))
    (related_group_size 0))
   ((kind intf)
    (comp_unit Mylib__Dead)
    (id 0)
    (locs
     ((name dead_fn)
      (file dead.mli)
      (line 1)
      (start_bol 0)
      (start_cnum 4)
      (end_bol 0)
      (end_cnum 11)))
    (related_group_size 2)
    (impl_id 0))
   ((kind impl)
    (comp_unit Mylib__)
    (id 1)
    (locs
     ((name Helper)
      (file mylib.ml)
      (line 1)
      (start_bol 0)
      (start_cnum 13)
      (end_bol 0)
      (end_cnum 19)))
    (related_group_size 0))
   ((kind impl)
    (comp_unit Mylib)
    (id 0)
    (locs
     ((name result)
      (file mylib.ml)
      (line 1)
      (start_bol 0)
      (start_cnum 4)
      (end_bol 0)
      (end_cnum 10)))
    (related_group_size 0))
   ((kind intf)
    (comp_unit Mylib)
    (id 0)
    (locs
     ((name result)
      (file mylib.mli)
      (line 1)
      (start_bol 0)
      (start_cnum 4)
      (end_bol 0)
      (end_cnum 10)))
    (related_group_size 2)
    (impl_id 0)))
