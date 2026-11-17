A ppx driver of a nested project can link dune-build-info.

  $ make_dune_project 3.25
  $ mkdir -p sub/driver
  $ (cd sub && make_dune_project 3.25)
  $ cat > sub/dune <<'EOF2'
  > (library (name bar) (preprocess (pps identity)))
  > EOF2
  $ echo 'let value = 3' > sub/bar.ml
  $ cat > sub/driver/dune <<'EOF2'
  > (library
  >  (name identity)
  >  (kind ppx_rewriter)
  >  (libraries dune-build-info)
  >  (ppx.driver (main Identity.main)))
  > EOF2
  $ cat > sub/driver/identity.ml <<'EOF2'
  > let main () =
  >   ignore (Build_info.V1.version ());
  >   let rec find flag = function
  >     | f :: v :: _ when f = flag -> v
  >     | _ :: rest -> find flag rest
  >     | [] -> failwith flag
  >   in
  >   let args = Array.to_list Sys.argv in
  >   let input = open_in_bin (find "--impl" args) in
  >   let contents = really_input_string input (in_channel_length input) in
  >   close_in input;
  >   let output = open_out_bin (find "-o" args) in
  >   output_string output contents;
  >   close_out output
  > EOF2
  $ dune build sub/bar.cma
