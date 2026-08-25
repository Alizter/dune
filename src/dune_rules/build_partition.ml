open Import

type purpose =
  | Workspace
  | Mounted

type t =
  { resolver : Context.t
  ; output_root : Path.Build.t
  ; purpose : purpose
  ; implicit_workspace_targets : bool
  }

let workspace resolver =
  { resolver
  ; output_root = Context.build_dir resolver
  ; purpose = Workspace
  ; implicit_workspace_targets = true
  }
;;

let mounted ~resolver ~output_root =
  { resolver; output_root; purpose = Mounted; implicit_workspace_targets = false }
;;

let resolver t = t.resolver
let build_context t = Context.build_context t.resolver
let output_root t = t.output_root
let purpose t = t.purpose
let implicit_workspace_targets t = t.implicit_workspace_targets
let dir t relative = Path.Build.append_local t.output_root relative

let to_dyn t =
  Dyn.record
    [ "resolver", Context.to_dyn_concise t.resolver
    ; "output_root", Path.Build.to_dyn t.output_root
    ; ( "purpose"
      , Dyn.variant
          (match t.purpose with
           | Workspace -> "Workspace"
           | Mounted -> "Mounted")
          [] )
    ; "implicit_workspace_targets", Dyn.bool t.implicit_workspace_targets
    ]
;;
