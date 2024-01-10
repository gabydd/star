type state = Continue | Quit

let bytes_starts pre s start =
  let len_s = Bytes.length s and len_pre = Bytes.length pre in
  let rec loop i =
    if i = len_pre then true
    else if Bytes.unsafe_get s i <> Bytes.unsafe_get pre (i - start) then false
    else loop (i + 1)
  in
  len_s >= len_pre && loop start

type event = None | Escape | Delete | Backspace | Chr of char

let rec parse_events_loop buf start len =
  if len <= start then []
  else
    match Bytes.unsafe_get buf 0 with
    | '\x1b' when len = 1 -> [ Escape ]
    | '\x1b' ->
        if bytes_starts (Bytes.of_string "\x1b[3~") buf start then
          Delete :: parse_events_loop buf (start + 4) len
        else None :: []
    | '\x7f' -> Backspace :: parse_events_loop buf (start + 1) len
    | ch -> Chr ch :: parse_events_loop buf (start + 1) len

let newline = Bytes.of_string "⏎"

let render_line_number (editor:Editor.t) y pad last =

  let num = (if last then "~" else string_of_int (y + 1)) ^ " " in
  Terminal.put_string
    (pad - String.length num + 1)
    y num Cell.Reset
    (Cell.Rgb { r = 255; b = 255; g = 255 })
    editor.current Terminal.empty_rect

let count_digits n =
  let rec loop i n = if n < 10 then i + 1 else loop (i + 1) (n / 10) in
  loop 0 n

let render_text (editor:Editor.t) =
  let pos = editor.pos in
  let x = ref 0 in
  let y = ref 0 in
  let a = ref 0 in
  let pad = count_digits (Rope.lines editor.text) in
  let len = Rope.len editor.text in
  let text_rect: Terminal.rect = { x = pad + 1; y = 0 } in
  render_line_number editor !y pad (!a = len);
  Rope.iter
    (fun c ->
      a := !a + 1;
      match c with
      | '\n' ->
          Terminal.put_cell !x !y
            {
              bg = Cell.Reset;
              fg = Cell.Rgb { r = 255; g = 255; b = 255 };
              content = newline;
            }
            editor.current text_rect;
          x := 0;
          y := !y + 1;
          render_line_number editor !y pad (!a = len)
      | _ ->
          Terminal.put_cell !x !y
            {
              bg = Cell.Reset;
              fg = Cell.Rgb { r = 255; g = 255; b = 255 };
              content = Bytes.make 1 c;
            }
            editor.current text_rect;
          x := !x + 1)
    editor.text;
  Terminal.patch_bg (Cell.Rgb { r = 10; g = 100; b = 50 }) pos.x pos.y editor.current text_rect;
  let x_str = string_of_int pos.x in
  let y_str = string_of_int pos.y in
  Terminal.put_string 0 (editor.height - 2) ("x: " ^ x_str) Cell.Reset
    (Cell.Rgb { r = 255; g = 255; b = 255 })
    editor.current Terminal.empty_rect;
  Terminal.put_string
    (4 + String.length x_str)
    (editor.height - 2) ("y: " ^ y_str) Cell.Reset
    (Cell.Rgb { r = 255; g = 255; b = 255 })
    editor.current Terminal.empty_rect;
  Terminal.put_string
    (4 + String.length x_str + 4 + String.length y_str)
    (editor.height - 2)
    ("abs: " ^ string_of_int pos.abs)
    Cell.Reset
    (Cell.Rgb { r = 255; g = 255; b = 255 })
    editor.current Terminal.empty_rect;
  Terminal.render editor.past editor.current

let handle_event (editor: Editor.t) ev =
  match editor.mode with
  | Editor.Normal ->
      if ev = Chr 'q' then Quit
      else (
        (match ev with
        | Chr 'i' -> editor.mode <- Insert
        | Chr 'l' -> Commands.move_left editor
        | Chr 'h' -> Commands.move_right editor
        | Chr 'j' -> Commands.move_down editor
        | Chr 'k' -> Commands.move_up editor
        | Chr 'u' -> Commands.undo editor
        | Chr 'U' -> Commands.redo editor
        | _ -> ());
        Continue)
  | Editor.Insert ->
      (match ev with
      | Escape -> editor.mode <- Editor.Normal; Editor.commit_checkpoint editor
      | Delete -> Commands.delete editor
      | Backspace -> Commands.backspace editor
      | Chr ch -> Commands.insert editor ch
      | None -> ());
      Continue

let rec handle_event_loop editor = function
  | [] -> Continue
  | h :: t -> (
      match handle_event editor h with Continue -> handle_event_loop editor t | Quit -> Quit)

let rec loop editor =
  render_text editor;
  let char = Bytes.create 10 in
  let len = Unix.read Terminal.tty char 0 10 in
  match handle_event_loop editor (parse_events_loop char 0 len) with
  | Continue -> loop editor
  | Quit -> ()

