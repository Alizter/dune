(* Benchmarks for the SAT solver used in package dependency resolution.

   These benchmarks create synthetic SAT problems that mirror worst-case
   scenarios in package solving:
   - Deep dependency chains (backtracking depth)
   - Wide dependency trees (branching factor)
   - Diamond patterns with version conflicts
   - Unsatisfiable problems (pigeonhole)
   - Dense conflict class graphs
*)

open Stdune

module Sat = Sat.Make (struct
    type t = string

    let pp t = Pp.text t
  end)

(* Helper to create a simple decider that returns None (let solver decide) *)
let null_decider () = None

(* Scenario 1: Linear chain of dependencies
   A₁ → A₂ → A₃ → ... → Aₙ
   Tests: propagation depth, no backtracking needed *)
let gen_chain ~depth =
  let sat = Sat.create () in
  let vars =
    Array.init depth ~f:(fun i -> Sat.add_variable sat (Printf.sprintf "pkg_%d" i))
  in
  (* Each package implies the next *)
  for i = 0 to depth - 2 do
    Sat.implies sat vars.(i) [ vars.(i + 1) ]
  done;
  (* Must have the first package *)
  Sat.at_least_one sat [ vars.(0) ];
  sat
;;

let%bench_fun ("chain_satisfiable" [@indexed depth = [ 10; 50; 100; 500; 1000 ]]) =
  let sat = gen_chain ~depth in
  fun () -> ignore (Sat.run_solver sat null_decider : bool)
;;

(* Scenario 2: Wide dependencies - root depends on N packages, each with M versions
       root
      /|...\
     B₁ B₂ ... Bₙ  (each has M versions, at_most_one selected)
*)
let gen_wide ~width ~versions =
  let sat = Sat.create () in
  let root = Sat.add_variable sat "root" in
  (* For each dependency slot, create M version choices *)
  for i = 0 to width - 1 do
    let versions_vars =
      Array.init versions ~f:(fun v ->
        Sat.add_variable sat (Printf.sprintf "pkg_%d_v%d" i v))
    in
    (* At most one version of each package *)
    let _clause = Sat.at_most_one (Array.to_list versions_vars) in
    (* Root implies at least one version of this package *)
    Sat.implies sat root (Array.to_list versions_vars)
  done;
  (* Must have root *)
  Sat.at_least_one sat [ root ];
  sat
;;

let%bench_fun ("wide_satisfiable" [@indexed width = [ 5; 10; 20; 50 ]]) =
  let sat = gen_wide ~width ~versions:5 in
  fun () -> ignore (Sat.run_solver sat null_decider : bool)
;;

let%bench_fun ("wide_many_versions" [@indexed versions = [ 3; 5; 10; 20 ]]) =
  let sat = gen_wide ~width:10 ~versions in
  fun () -> ignore (Sat.run_solver sat null_decider : bool)
;;

(* Scenario 3: Diamond with version conflict
        root
       /    \
      B      C
       \    /
         D (M versions)
   B requires D_v >= mid, C requires D_v < mid
   Forces backtracking when wrong version chosen first *)
let gen_diamond ~versions =
  let sat = Sat.create () in
  let root = Sat.add_variable sat "root" in
  let b = Sat.add_variable sat "B" in
  let c = Sat.add_variable sat "C" in
  let d_versions =
    Array.init versions ~f:(fun v -> Sat.add_variable sat (Printf.sprintf "D_v%d" v))
  in
  let mid = versions / 2 in
  (* At most one version of D *)
  let _clause = Sat.at_most_one (Array.to_list d_versions) in
  (* Root requires B and C *)
  Sat.implies sat root [ b ];
  Sat.implies sat root [ c ];
  (* B requires D >= mid (versions mid..versions-1) *)
  let high_versions = Array.sub d_versions ~pos:mid ~len:(versions - mid) in
  Sat.implies sat b (Array.to_list high_versions);
  (* C requires D < mid (versions 0..mid-1) *)
  let low_versions = Array.sub d_versions ~pos:0 ~len:mid in
  Sat.implies sat c (Array.to_list low_versions);
  Sat.at_least_one sat [ root ];
  sat
;;

(* This should be unsatisfiable - B and C have incompatible requirements *)
let%bench_fun ("diamond_conflict_unsat" [@indexed versions = [ 4; 10; 20; 50 ]]) =
  let sat = gen_diamond ~versions in
  fun () -> ignore (Sat.run_solver sat null_decider : bool)
;;

(* Scenario 4: Pigeonhole - N pigeons, N-1 holes
   Classic SAT hardness. Each pigeon must be in a hole, but at most one pigeon per hole.
   Guaranteed unsatisfiable, forces exhaustive search. *)
let gen_pigeonhole ~pigeons =
  let sat = Sat.create () in
  let holes = pigeons - 1 in
  (* Variables: pigeon i in hole j *)
  let vars =
    Array.init pigeons ~f:(fun i ->
      Array.init holes ~f:(fun j ->
        Sat.add_variable sat (Printf.sprintf "p%d_h%d" i j)))
  in
  (* Each pigeon must be in some hole *)
  for i = 0 to pigeons - 1 do
    Sat.at_least_one sat (Array.to_list vars.(i))
  done;
  (* Each hole has at most one pigeon *)
  for j = 0 to holes - 1 do
    let pigeons_in_hole = Array.init pigeons ~f:(fun i -> vars.(i).(j)) in
    let _clause = Sat.at_most_one (Array.to_list pigeons_in_hole) in
    ()
  done;
  sat
;;

let%bench_fun ("pigeonhole_unsat" [@indexed pigeons = [ 5; 7; 9; 11 ]]) =
  let sat = gen_pigeonhole ~pigeons in
  fun () -> ignore (Sat.run_solver sat null_decider : bool)
;;

(* Scenario 5: Conflict class density
   Many packages with overlapping conflict classes.
   Packages are grouped into classes, and at most one package per class can be selected. *)
let gen_conflict_classes ~packages ~classes =
  let sat = Sat.create () in
  let root = Sat.add_variable sat "root" in
  let pkg_vars =
    Array.init packages ~f:(fun i -> Sat.add_variable sat (Printf.sprintf "pkg_%d" i))
  in
  (* Root requires all packages *)
  Sat.implies sat root (Array.to_list pkg_vars);
  (* Assign packages to conflict classes (round-robin + overlap) *)
  for class_id = 0 to classes - 1 do
    let members =
      Array.to_list pkg_vars
      |> List.filteri ~f:(fun i _ ->
        (* Each package is in 2 adjacent classes for overlap *)
        i mod classes = class_id || (i + 1) mod classes = class_id)
    in
    if List.length members >= 2
    then (
      let _clause = Sat.at_most_one members in
      ())
  done;
  Sat.at_least_one sat [ root ];
  sat
;;

(* With overlapping classes, this becomes hard/unsatisfiable *)
let%bench_fun ("conflict_classes" [@indexed packages = [ 10; 20; 50; 100 ]]) =
  let sat = gen_conflict_classes ~packages ~classes:5 in
  fun () -> ignore (Sat.run_solver sat null_decider : bool)
;;

(* Scenario 6: Satisfiable diamond - no conflict
   Same structure as diamond but with compatible requirements *)
let gen_diamond_satisfiable ~versions =
  let sat = Sat.create () in
  let root = Sat.add_variable sat "root" in
  let b = Sat.add_variable sat "B" in
  let c = Sat.add_variable sat "C" in
  let d_versions =
    Array.init versions ~f:(fun v -> Sat.add_variable sat (Printf.sprintf "D_v%d" v))
  in
  (* At most one version of D *)
  let _clause = Sat.at_most_one (Array.to_list d_versions) in
  (* Root requires B and C *)
  Sat.implies sat root [ b ];
  Sat.implies sat root [ c ];
  (* Both B and C accept any version of D *)
  Sat.implies sat b (Array.to_list d_versions);
  Sat.implies sat c (Array.to_list d_versions);
  Sat.at_least_one sat [ root ];
  sat
;;

let%bench_fun ("diamond_satisfiable" [@indexed versions = [ 4; 10; 20; 50 ]]) =
  let sat = gen_diamond_satisfiable ~versions in
  fun () -> ignore (Sat.run_solver sat null_decider : bool)
;;

(* Scenario 7: Deep chain with late conflict
   A₁ → A₂ → ... → Aₙ → X, where X conflicts with A₁
   Forces deep backtracking *)
let gen_chain_with_conflict ~depth =
  let sat = Sat.create () in
  let vars =
    Array.init depth ~f:(fun i -> Sat.add_variable sat (Printf.sprintf "pkg_%d" i))
  in
  let conflict = Sat.add_variable sat "conflict" in
  (* Chain of implies *)
  for i = 0 to depth - 2 do
    Sat.implies sat vars.(i) [ vars.(i + 1) ]
  done;
  (* Last in chain implies conflict *)
  Sat.implies sat vars.(depth - 1) [ conflict ];
  (* Conflict and first package can't both be true *)
  let _clause = Sat.at_most_one [ vars.(0); conflict ] in
  (* Must have first package *)
  Sat.at_least_one sat [ vars.(0) ];
  sat
;;

let%bench_fun ("chain_late_conflict_unsat" [@indexed depth = [ 10; 50; 100; 200 ]]) =
  let sat = gen_chain_with_conflict ~depth in
  fun () -> ignore (Sat.run_solver sat null_decider : bool)
;;
