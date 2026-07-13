open Import

let dune_temp_dir = lazy (Temp.create Dir ~prefix:"dune" ~suffix:"internal")
let action_temp_dir_ = lazy (Temp.create Dir ~prefix:"dune" ~suffix:"actions")
let temp_dir = ref None

let action_temp_dir () =
  match !temp_dir with
  | Some dir -> dir
  | None -> Lazy.force action_temp_dir_
;;

let dune_temp_dir_value = lazy (Path.to_absolute_filename (Lazy.force dune_temp_dir))
let action_temp_dir_value = lazy (Path.to_absolute_filename (Lazy.force action_temp_dir_))

let temp_dir_value (purpose : Process_metadata.purpose) =
  match purpose with
  | Internal_job -> Lazy.force dune_temp_dir_value
  | Build_job _ ->
    (match !temp_dir with
     | Some dir -> Path.to_absolute_filename dir
     | None -> Lazy.force action_temp_dir_value)
;;

let file ~prefix ~suffix =
  Temp.temp_in_dir File ~dir:(Lazy.force dune_temp_dir) ~suffix ~prefix
;;

let action what ~prefix ~suffix =
  Temp.temp_in_dir what ~dir:(action_temp_dir ()) ~suffix ~prefix
;;

let add_to_env env ~purpose =
  let value = temp_dir_value purpose in
  Env.add env ~var:Env.Var.temp_dir ~value
;;

let with_temp_dir_for_shell dir ~f =
  let previous = !temp_dir in
  temp_dir := Some dir;
  Fiber.finalize f ~finally:(fun () ->
    temp_dir := previous;
    Fiber.return ())
;;

let destroy = Temp.destroy

let clear () =
  List.iter [ dune_temp_dir; action_temp_dir_ ] ~f:(fun temp_dir ->
    if Lazy.is_val temp_dir then Temp.clear_dir (Lazy.force temp_dir));
  Option.iter !temp_dir ~f:Temp.clear_dir
;;
