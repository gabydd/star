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
      log "";
      flush Editor.log_file;
      Terminal.pop_term ();
      Terminal.show_cursor ();
      Terminal.exit_raw ();
      print_endline str;
      Printexc.print_backtrace stdout
  | _ ->
      Rope.print_rope Editor.log_file 0 editor.text;
      log "";
      flush Editor.log_file;
      Terminal.pop_term ();
      Terminal.show_cursor ();
      Terminal.exit_raw ();
      Printexc.print_backtrace stdout

