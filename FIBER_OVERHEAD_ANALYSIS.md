# Fiber Library Overhead Analysis

## Executive Summary

The Fiber library implements structured concurrency using continuation-passing style (CPS) with an effect-based scheduler. While the design is clean and functional, there are several identifiable overhead points related to allocations, context management, and continuation handling.

## Architecture Overview

**Core Design:**
- **Type**: `type 'a t = ('a -> eff) -> eff` - pure CPS representation
- **Effects**: GADT with ~20 constructors representing fiber operations
- **Scheduler**: Interpreter loop executing effects with a jobs queue
- **Context**: Execution context carrying parent, error handlers, variables, and map-reduce state

**Key Components:**
- `core.ml` (424 LOC): Core fiber operations and CPS combinators
- `scheduler.ml` (219 LOC): Effect interpreter and scheduler loop
- `var_map.ml` (51 LOC): Array-based heterogeneous map for fiber-local variables
- Synchronization primitives: Ivar, Mvar, Svar, Mutex, Throttle, Pool, Stream

## Identified Overhead Points

### 1. **Context Allocation** ⚠️ HIGH IMPACT
**Location**: `scheduler.ml:99-114`

Every `Fiber.Var.set`, `Fiber.Var.update`, and `with_error_handler` creates a **new context record**:

```ocaml
type context =
  { parent : context          (* 1 word *)
  ; on_error : Exn_with_backtrace.t k  (* 2 words *)
  ; vars : Var_map.t          (* 1 word - array pointer *)
  ; map_reduce_context : map_reduce_context  (* 1 word *)
  }
```

**Overhead:**
- 5 words allocated per context creation
- Happens on **every** var set/update and error handler installation
- No sharing or optimization when vars don't change
- **CR comment** at line 104-105 acknowledges potential optimization

**Evidence:**
```ocaml
(* scheduler.ml:102-110 *)
| Update_var (key, f, k) ->
  let ctx =
    (* CR-someday rgrinberg: If [vars = ctx.vars], we could elide the re-allocation of
       [ctx] here. This doesn't seem important for us at the moment though because all
       existing call sites do change the value of the variable. *)
    let vars = Var_map.update ctx.vars ~f key in
    { ctx with parent = ctx; vars }  (* NEW ALLOCATION HERE *)
  in
  exec ctx k () jobs
```

**Impact**: Fiber vars are used 37 times across 7 files in src/. Each set/update triggers allocation.

### 2. **Var_map Array Copying** ⚠️ MEDIUM IMPACT
**Location**: `var_map.ml:39-44`

Var_map uses array copying for immutability:

```ocaml
let set (type a) (t : t) (key : a Key.t) (x : a) : t =
  let copy =
    if key < Array.length t
    then Array.copy t  (* COPY ENTIRE ARRAY *)
    else Array.init (key + 1) (fun i -> get t i)  (* ALLOCATE NEW ARRAY *)
  in
  copy.(key) <- Obj.repr x;
  copy
```

**Overhead:**
- `Array.copy` allocates new array and copies all elements
- For n variables: O(n) time and space per update
- Documented as "optimized for small collections" but still linear
- Each update allocates 1 + n words (array header + elements)

**Frequency**: Combined with Context allocation, this happens on every var operation.

### 3. **Fork and Continuation Closures** ⚠️ HIGH IMPACT
**Location**: `core.ml:98-122`

Fork operations create continuation closures:

```ocaml
let[@inline always] fork a b =
  match apply a () with
  | End_of_fiber () -> b ()
  | eff -> Fork (eff, b)  (* b is a closure *)

let rec nfork x l f =
  match l with
  | [] -> f x
  | y :: l ->
    (* Manually inline [fork] because the compiler is unfortunately
       not getting rid of the closures. *)
    (match apply f x with
     | End_of_fiber () -> nfork y l f
     | eff -> Fork (eff, fun () -> nfork y l f))  (* CLOSURE ALLOCATION *)
```

**Overhead:**
- Each Fork allocates: effect value (2+ words) + closure (2+ words)
- Comment explicitly states **compiler doesn't eliminate closures** even with manual inlining
- Used by all parallel operations: `parallel_map`, `parallel_iter`, `fork_and_join`

**Usage**: 70 occurrences of parallel operations across 21 files.

### 4. **Parallel Operations Allocations** ⚠️ MEDIUM IMPACT
**Location**: `core.ml:309-336`

Parallel map allocates multiple structures:

```ocaml
let parallel_array_of_list_map' x l ~f k =
  let len = List.length l + 1 in
  let left_over = ref len in          (* REF ALLOCATION *)
  let results = ref [||] in           (* REF ALLOCATION *)
  let f i x =
    f x (fun y ->
      let a =
        match !results with
        | [||] ->
          let a = Array.make len y in  (* ARRAY ALLOCATION *)
          results := a;
          a
        | a ->
          a.(i) <- y;
          a
      in
      decr left_over;  (* MUTATION *)
      if !left_over = 0 then k a else end_of_fiber)
  in
  nforki x l f
```

**Overhead per parallel_map call:**
- 2 ref allocations (left_over, results)
- 1 array allocation (size = list length)
- Multiple closure allocations (one per fork)
- Ref counting overhead (incr/decr operations)

### 5. **Jobs Queue Concatenation** ⚠️ MEDIUM IMPACT
**Location**: `scheduler.ml:6-45, 63-72`

Jobs queue uses tree structure requiring flattening:

```ocaml
type t =
  | Empty
  | Job : context * ('a -> eff) * 'a * t -> t
  | Concat : t * t -> t  (* BUILDS TREE *)

let rec loop2 a b =
  match a with
  | Empty -> loop b
  | Job (ctx, run, x, a) -> exec ctx run x (Jobs.concat a b)
  | Concat (a1, a2) -> loop2 a1 (Jobs.concat a2 b)  (* RECURSIVE FLATTEN *)
```

**Overhead:**
- Concat creates tree nodes (3 words each)
- loop2 recursively flattens trees
- No batching or work-stealing optimization
- Repeated concat operations create unbalanced trees

**Impact**: Every fork and ivar fill creates jobs that may need concatenation.

### 6. **Ivar Reader Chains** ⚠️ LOW-MEDIUM IMPACT
**Location**: `core.ml:33-40, scheduler.ml:18-35`

Multiple readers on an Ivar create linked chains:

```ocaml
and ('a, _) ivar_state =
  | Full : 'a -> ('a, [> `Full ]) ivar_state
  | Empty : ('a, [> `Empty ]) ivar_state
  | Empty_with_readers :
      context * ('a -> eff) * ('a, [ `Empty ]) ivar_state  (* CHAIN *)
      -> ('a, [> `Empty ]) ivar_state

let rec enqueue_readers (readers : (_, [ `Empty ]) ivar_state) x jobs =
  match readers with
  | Empty -> jobs
  | Empty_with_readers (ctx, k, readers) ->
      enqueue_readers readers x (Job (ctx, k, x, jobs))  (* UNWIND CHAIN *)
```

**Overhead:**
- Each blocked reader allocates Empty_with_readers (4+ words)
- Filling ivar traverses entire chain
- Creates Job for each reader during unwinding

**Impact**: Throttle and blocking operations can accumulate reader chains.

### 7. **Effect GADT Pattern Matching** ⚠️ LOW-MEDIUM IMPACT
**Location**: `scheduler.ml:74-145`

Large pattern match on ~20 effect constructors:

```ocaml
and exec : 'a. context -> ('a -> eff) -> 'a -> Jobs.t -> step' =
  fun ctx k x jobs ->
  match k x with  (* CALL CONTINUATION *)
  | exception exn -> (* exception handling *)
  | Done v -> Done v
  | Toplevel_exception exn -> (* ... *)
  | Unwind (k, x) -> (* ... *)
  | Read_ivar (ivar, k) -> (* ... *)
  | Fill_ivar (ivar, x, k) -> (* ... *)
  | Suspend (f, k) -> (* ... *)
  | Resume (suspended, x, k) -> (* ... *)
  | Get_var (key, k) -> (* ... *)
  | Set_var (key, x, k) -> (* ... *)
  | Update_var (key, f, k) -> (* ... *)
  | With_error_handler (on_error, k) -> (* ... *)
  | Map_reduce_errors (...) -> (* ... *)
  | End_of_fiber () -> (* ... *)
  | Unwind_map_reduce (k, x) -> (* ... *)
  | End_of_map_reduce_error_handler (...) -> (* ... *)
  | Never () -> (* ... *)
  | Fork (a, b) -> (* ... *)
  | Reraise exn -> (* ... *)
  | Reraise_all exns -> (* ... *)
```

**Overhead:**
- Large pattern match compiled to jump table or decision tree
- Each step through scheduler calls continuation then pattern matches
- No obvious fast-path optimization
- Branch prediction may struggle with varied workloads

### 8. **Error Handling Infrastructure** ⚠️ LOW IMPACT
**Location**: `scheduler.ml:157-185`

Map-reduce error handling allocates reference-counted context:

```ocaml
and map_reduce_errors ctx (module M : Monoid) on_error f k jobs =
  let map_reduce_context =
    { k = { ctx; run = k }
    ; ref_count = 1  (* REF COUNTING *)
    ; errors = M.empty
    } in
  let on_error =
    { ctx
    ; run = (fun exn ->
        on_error exn (fun m ->
          map_reduce_context.errors <- M.combine map_reduce_context.errors m;
          End_of_map_reduce_error_handler map_reduce_context))
    } in
  let ctx = { ctx with parent = ctx; on_error; map_reduce_context = Map_reduce_context map_reduce_context } in
  exec ctx f () jobs
```

**Overhead:**
- Allocates map_reduce_context' record (3 words)
- Creates new on_error handler (2 words)
- Creates new context (5 words)
- Manual ref counting with mutations
- Used by `collect_errors`, `finalize`, `map_reduce_errors`

### 9. **Queue-Based Synchronization Primitives** ⚠️ LOW IMPACT
**Locations**: `mutex.ml`, `throttle.ml`, `mvar.ml`, `svar.ml`, `pool.ml`

All synchronization primitives use `Queue.t` for waiters:

```ocaml
(* mutex.ml *)
type t = { mutable locked : bool; mutable waiters : unit k Queue.t }

(* throttle.ml *)
type t = { mutable size : int; mutable running : int; waiting : unit Ivar.t Queue.t }

(* mvar.ml *)
type 'a t = { writers : ('a * unit k) Queue.t; readers : 'a k Queue.t; mutable value : 'a option }
```

**Overhead:**
- Queue operations allocate list nodes
- Each push: 2-3 words per node
- Frequently used in high-contention scenarios

**Impact**: 116 uses of `with_lock` and mutex operations across 18 files.

### 10. **CPS Bind Chain Overhead** ⚠️ MEDIUM IMPACT
**Location**: Throughout codebase (217+ uses of `let*` in dune_engine alone)

Every monadic bind creates continuation:

```ocaml
let bind t ~f k = t (fun x -> f x k)
let map t ~f k = t (fun x -> k (f x))
```

**Overhead:**
- Each bind allocates closure: `(fun x -> f x k)`
- Deep bind chains create nested closures
- No TCO (tail call optimization) for CPS in OCaml

**Example from usage**:
```ocaml
let* a = step1 in
let* b = step2 a in
let* c = step3 b in
return c
```
Creates 3 closure allocations for a 3-step sequence.

## Performance Characteristics Summary

| Component | Allocation per Operation | Frequency | Impact |
|-----------|-------------------------|-----------|--------|
| Context (Var.set/update) | 5 words + array copy | Every var operation | HIGH |
| Var_map array copy | n+1 words (n=vars) | Every var update | MEDIUM |
| Fork closures | 4+ words | Every parallel op | HIGH |
| Parallel_map refs+array | 2 refs + n-array | Each parallel_map | MEDIUM |
| Jobs.Concat | 3 words per concat | Fork, ivar fill | MEDIUM |
| Ivar reader chain | 4+ words per reader | Multiple readers | LOW-MED |
| Bind/Map closures | 2-3 words | Every `let*` | MEDIUM |
| Error contexts | 10+ words | Error handlers | LOW |
| Queue operations | 2-3 words per push | Sync primitives | LOW |

## Recommendations

### High Priority
1. **Context allocation optimization**: Implement CR-suggested optimization to avoid re-allocating context when vars don't change
2. **Var_map alternatives**: Consider persistent map structures (e.g., HAMT) for larger variable sets
3. **Closure elimination**: Investigate defunctionalization or trampolines to reduce closure allocations

### Medium Priority
4. **Jobs queue optimization**: Replace tree-based concat with flat queue or work-stealing deque
5. **Parallel operations pooling**: Pre-allocate arrays and refs for parallel operations
6. **Fast-path optimization**: Add fast paths for common effect sequences (e.g., Return after Map)

### Low Priority
7. **Inline small effects**: Aggressively inline simple effects like Get_var, Set_var
8. **Queue pooling**: Pool queue nodes for synchronization primitives
9. **Specialize bind**: Create specialized bind for pure functions vs effectful functions

## Benchmarking Suggestions

To validate these findings, benchmark:
1. Fiber var set/get operations (context + var_map overhead)
2. Deep bind chains (10+ sequential binds)
3. Parallel_map with varying list sizes (1, 10, 100, 1000)
4. Fork_and_join nesting depth
5. Ivar with multiple readers (1, 10, 100 readers)
6. Comparison with alternative concurrency libraries (lwt, async)

## Notes

- Total Fiber library: ~1400 LOC (compact implementation)
- Used extensively: 70+ parallel operations, 217+ bind operations in dune_engine alone
- Clean functional design trades some performance for maintainability
- Most overhead is fundamental to CPS + immutable data structures
- OCaml GC is efficient for short-lived allocations, mitigating some impact
- Effect handlers (OCaml 5.0+) could eliminate much CPS overhead in future
