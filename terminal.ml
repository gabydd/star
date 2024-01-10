type t = {
  mutable buffer : Cell.t array;
  mutable height : int;
  mutable width : int;
}

type rect = { x : int; y : int }

let empty_rect = { x = 0; y = 0 }

let print_color f = function
  | Cell.Reset -> Printf.fprintf f "Reset"
  | Cell.Rgb { r; g; b } -> Printf.fprintf f "Rgb {r=%d;g=%d;b=%d}" r g b

let print_cell f (c : Cell.t) =
  Printf.fprintf f "{content=%s;fg=%a;bg=%a},"
    (Bytes.to_string c.content)
    print_color c.fg print_color c.bg

external terminal_size : Unix.file_descr -> int * int = "terminal_size"

let resize width height b =
  let len = width * height in
  if len > b.height * b.width then
    b.buffer <- Array.make (width * height) Cell.empty;
  b.height <- height;
  b.width <- width

let make width height =
  { buffer = Array.make (width * height) Cell.empty; height; width }

let empty b = Array.fill b.buffer 0 (b.height * b.width) Cell.empty
let put_cell x y cell b r = b.buffer.(((y + r.y) * b.width) + x + r.x) <- cell

let rec put_substring x y s start ofs bg fg b r =
  if 0 = ofs then ()
  else (
    put_cell x y { bg; fg; content = Bytes.make 1 (String.get s start) } b r;
    put_substring (x + 1) y s (start + 1) (ofs - 1) bg fg b r)

let put_string x y s bg fg b r =
  put_substring x y s 0 (String.length s) bg fg b r

let patch_bg bg x y b r =
  let i = ((y + r.y) * b.width) + x + r.x in
  b.buffer.(i) <- { (b.buffer.(i)) with bg }

let patch_fg fg x y b r =
  let i = ((y + r.y) * b.width) + x + r.y in
  b.buffer.(i) <- { (b.buffer.(i)) with fg }

let patch bg fg x y b r =
  patch_bg bg x y b r;
  patch_fg fg x y b r

let rec diff_loop a b i acc =
  if i = -1 then acc
  else
    diff_loop a b (i - 1)
      (if a.buffer.(i) = b.buffer.(i) then acc
       else (b.buffer.(i), i mod b.width, i / b.width) :: acc)

let diff a b = diff_loop a b ((a.height * a.width) - 1) []
let tty = Unix.openfile "/dev/tty" [ Unix.O_RDWR ] 0
let stdout = Unix.out_channel_of_descr tty
let write_string = output_string stdout

let claim_term () =
  write_string "\x1b[?1049h";
  flush stdout

let clear_screen () =
  write_string "\x1b[2J";
  flush stdout

let move row col =
  write_string (Printf.sprintf "\x1b[%d;%dH" (row + 1) (col + 1))

let hide_cursor () =
  write_string "\x1b[?25l";
  flush stdout

let show_cursor () =
  write_string "\x1b[?25h";
  flush stdout

let pop_term () =
  write_string "\x1b[?1049l";
  flush stdout

let old_termio = Unix.tcgetattr tty
let log_file = open_out_gen [ Open_append; Open_creat ] 0o644 "star.log"
let log = Printf.fprintf log_file

type edit = InsertC of int * char | RemoveC of int

let trace = ref []

let enter_raw () =
  Unix.tcsetattr tty Unix.TCSAFLUSH
    {
      old_termio with
      c_ignbrk = false;
      c_brkint = false;
      c_parmrk = false;
      c_istrip = false;
      c_inlcr = false;
      c_igncr = false;
      c_ixon = false;
      c_opost = false;
      c_echo = false;
      c_echonl = false;
      c_icanon = false;
      c_isig = false;
      c_parenb = false;
      c_csize = 8;
      c_vmin = 0;
      c_vtime = 1;
    }

let exit_raw () = Unix.tcsetattr tty Unix.TCSAFLUSH old_termio

let set_bg = function
  | Cell.Reset -> write_string "\x1b[49m"
  | Cell.Rgb { r; g; b } ->
      write_string (Printf.sprintf "\x1b[48;2;%d;%d;%dm" r g b)

let set_fg = function
  | Cell.Reset -> write_string "\x1b[39m"
  | Cell.Rgb { r; g; b } ->
      write_string (Printf.sprintf "\x1b[38;2;%d;%d;%dm" r g b)

let rec render_loop bg fg lx ly (acc : (Cell.t * int * int) list) =
  match acc with
  | [] -> ()
  | (c, x, y) :: t ->
      if c.bg <> bg then set_bg c.bg;
      if c.fg <> fg then set_fg c.fg;
      if y <> ly || x <> lx + 1 then move y x;
      output_bytes stdout c.content;
      render_loop c.bg c.fg x y t

let render a b =
  set_bg Cell.Reset;
  set_fg Cell.Reset;
  move 0 0;
  render_loop Cell.Reset Cell.Reset 0 (-1) (diff a b);
  flush stdout;
  let past = b.buffer in
  empty a;
  b.buffer <- a.buffer;
  a.buffer <- past

type mode = Normal | Insert
type cord = { mutable x : int; mutable y : int; mutable abs : int }
let clone_cord cord = {x=cord.x;y=cord.y;abs=cord.abs}

let pos = { x = 0; y = 0; abs = 0 }
let width, height = terminal_size tty
let current_mode = ref Normal
let past = make width height
let current = make width height
let text = ref (Rope.rope_of_string "hello\nhell\nworld\n")

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

let render_line_number y pad last =
  let num = (if last then "~" else string_of_int (y + 1)) ^ " " in
  put_string
    (pad - String.length num + 1)
    y num Cell.Reset
    (Cell.Rgb { r = 255; b = 255; g = 255 })
    current empty_rect

let text_rect = ref empty_rect

let count_digits n =
  let rec loop i n = if n < 10 then i + 1 else loop (i + 1) (n / 10) in
  loop 0 n

let render_text () =
  let x = ref 0 in
  let y = ref 0 in
  let a = ref 0 in
  let pad = count_digits (Rope.lines !text) in
  let len = Rope.len !text in
  text_rect := { x = pad + 1; y = 0 };
  render_line_number !y pad (!a = len);
  Rope.iter
    (fun c ->
      a := !a + 1;
      match c with
      | '\n' ->
          put_cell !x !y
            {
              bg = Cell.Reset;
              fg = Cell.Rgb { r = 255; g = 255; b = 255 };
              content = newline;
            }
            current !text_rect;
          x := 0;
          y := !y + 1;
          render_line_number !y pad (!a = len)
      | _ ->
          put_cell !x !y
            {
              bg = Cell.Reset;
              fg = Cell.Rgb { r = 255; g = 255; b = 255 };
              content = Bytes.make 1 c;
            }
            current !text_rect;
          x := !x + 1)
    !text;
  patch_bg (Cell.Rgb { r = 10; g = 100; b = 50 }) pos.x pos.y current !text_rect;
  let x_str = string_of_int pos.x in
  let y_str = string_of_int pos.y in
  put_string 0 (height - 2) ("x: " ^ x_str) Cell.Reset
    (Cell.Rgb { r = 255; g = 255; b = 255 })
    current empty_rect;
  put_string
    (4 + String.length x_str)
    (height - 2) ("y: " ^ y_str) Cell.Reset
    (Cell.Rgb { r = 255; g = 255; b = 255 })
    current empty_rect;
  put_string
    (4 + String.length x_str + 4 + String.length y_str)
    (height - 2)
    ("abs: " ^ string_of_int pos.abs)
    Cell.Reset
    (Cell.Rgb { r = 255; g = 255; b = 255 })
    current empty_rect;
  render past current

type state = Continue | Quit

let undo_state = ref ((!text, clone_cord pos) :: [])
let redo_state = ref []
let commit_checkpoint () = undo_state := (!text, clone_cord pos) :: !undo_state; redo_state := []

let move_left () =
  if pos.abs <> Rope.len !text then
    match Rope.get pos.abs !text with
    | '\n' ->
        pos.y <- pos.y + 1;
        pos.x <- 0;
        pos.abs <- pos.abs + 1
    | _ ->
        pos.x <- pos.x + 1;
        pos.abs <- pos.abs + 1

let insert ch =
  match ch with
  | '\n' ->
      text := Rope.insert_char pos.abs '\n' !text;
      trace := InsertC (pos.abs, '\n') :: !trace;
      pos.y <- pos.y + 1;
      pos.x <- 0;
      pos.abs <- pos.abs + 1
  | _ ->
      text := Rope.insert_char pos.abs ch !text;
      trace := InsertC (pos.abs, ch) :: !trace;
      pos.x <- pos.x + 1;
      pos.abs <- pos.abs + 1

let move_right () =
  if pos.abs <> 0 then
    match Rope.get (pos.abs - 1) !text with
    | '\n' ->
        pos.y <- pos.y - 1;
        pos.x <- Rope.line_len (pos.abs - 1) !text - 1;
        pos.abs <- pos.abs - 1
    | _ ->
        pos.x <- pos.x - 1;
        pos.abs <- pos.abs - 1

let delete () =
  text := Rope.remove pos.abs 1 !text;
  trace := RemoveC pos.abs :: !trace

let backspace () =
  if pos.abs <> 0 then (
    (match Rope.get (pos.abs - 1) !text with
    | '\n' ->
        pos.y <- pos.y - 1;
        pos.x <- Rope.line_len (pos.abs - 1) !text - 1;
        pos.abs <- pos.abs - 1
    | _ ->
        pos.x <- pos.x - 1;
        pos.abs <- pos.abs - 1);
    text := Rope.remove pos.abs 1 !text;
    trace := RemoveC pos.abs :: !trace)

let move_down () =
  let len = Rope.len !text in
  if pos.abs <> len then
    let next_start = pos.abs + Rope.line_len pos.abs !text - pos.x in
    if next_start < len then (
      let next_len = Rope.line_len next_start !text in
      let x = min pos.x (next_len - 1) in
      pos.y <- pos.y + 1;
      pos.x <- x;
      pos.abs <- next_start + x)
    else if next_start = len && Rope.get (len - 1) !text = '\n' then (
      pos.y <- pos.y + 1;
      pos.x <- 0;
      pos.abs <- next_start)

let move_up () =
  let past_start = pos.abs - pos.x - 1 in
  if past_start >= 0 then (
    let past_len = Rope.line_len past_start !text in
    let x = min pos.x (past_len - 1) in
    pos.y <- pos.y - 1;
    pos.x <- x;
    pos.abs <- past_start - past_len + 1 + x)

let undo () =
  match !undo_state with
  | [] -> ()
  | h :: [] -> ()
  | h :: (txt, cord) :: t ->
      text := txt;
      pos.x <- cord.x;
      pos.y <- cord.y;
      pos.abs <- cord.abs;
      redo_state := h :: !redo_state;
      undo_state := (txt, cord) :: t
let redo () =
  match !redo_state with
  | [] -> ()
  | (txt, cord) :: t ->
      text := txt;
      pos.x <- cord.x;
      pos.y <- cord.y;
      pos.abs <- cord.abs;
      undo_state := (txt, cord) :: !undo_state;
      redo_state := t

let handle_event ev =
  match !current_mode with
  | Normal ->
      if ev = Chr 'q' then Quit
      else (
        (match ev with
        | Chr 'i' -> current_mode := Insert
        | Chr 'l' -> move_left ()
        | Chr 'h' -> move_right ()
        | Chr 'j' -> move_down ()
        | Chr 'k' -> move_up ()
        | Chr 'u' -> undo ()
        | Chr 'U' -> redo ()
        | _ -> ());
        Continue)
  | Insert ->
      (match ev with
      | Escape -> current_mode := Normal; commit_checkpoint ()
      | Delete -> delete ()
      | Backspace -> backspace ()
      | Chr ch -> insert ch
      | None -> ());
      Continue

let rec handle_event_loop = function
  | [] -> Continue
  | h :: t -> (
      match handle_event h with Continue -> handle_event_loop t | Quit -> Quit)

let rec input_loop () =
  render_text ();
  let char = Bytes.create 10 in
  let len = Unix.read tty char 0 10 in
  match handle_event_loop (parse_events_loop char 0 len) with
  | Continue -> input_loop ()
  | Quit -> ()

let rec print_trace = function
  | [] -> ()
  | h :: t -> (
      match h with
      | InsertC (pos, c) ->
          Printf.fprintf log_file "insert %d '%s'" pos (Char.escaped c);
          print_trace t
      | RemoveC pos ->
          Printf.fprintf log_file "remove %d 1;" pos;
          print_trace t)

let _ =
  Printexc.record_backtrace true;
  try
    enter_raw ();
    claim_term ();
    hide_cursor ();
    flush stdout;
    input_loop ();
    pop_term ();
    show_cursor ();
    exit_raw ();
    log "[";
    print_trace (List.rev !trace);
    log "]\n";
    flush log_file
  with
  | Failure str ->
      log "";
      flush log_file;
      pop_term ();
      show_cursor ();
      exit_raw ();
      print_endline str;
      Printexc.print_backtrace stdout
  | _ ->
      Rope.print_rope log_file 0 !text;
      log "";
      flush log_file;
      pop_term ();
      show_cursor ();
      exit_raw ();
      Printexc.print_backtrace stdout
