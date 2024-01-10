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


