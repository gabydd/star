let log = Printf.fprintf Editor.log_file
let _ =
  let editor = Editor.default () in
  Printexc.record_backtrace true;
  try
    Terminal.enter_raw ();
    Terminal.claim_term ();
    Terminal.hide_cursor ();
    flush stdout;
    Render.loop editor;
    Terminal.pop_term ();
    Terminal.show_cursor ();
    Terminal.exit_raw ();
    log "[";
    log "]\n";
    flush Editor.log_file
  with
  | Failure str ->
      Terminal.pop_term ();
      Terminal.show_cursor ();
      Terminal.exit_raw ();
      Printexc.print_backtrace Editor.log_file;
      flush Editor.log_file
  | _ as e->
      Terminal.pop_term ();
      Terminal.show_cursor ();
      Terminal.exit_raw ();
      let str = Printexc.to_string e in
      output_string Editor.log_file str;
      log "hi";
      flush Editor.log_file

