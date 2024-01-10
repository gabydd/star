type mode = Normal | Insert
type cord = { mutable x : int; mutable y : int; mutable abs : int }
let empty_pos () = { x = 0; y = 0; abs = 0 }
let clone_cord cord = {x=cord.x;y=cord.y;abs=cord.abs}

let width, height = Terminal.terminal_size Terminal.tty
let past = Terminal.make width height
let current = Terminal.make width height

type t = {pos: cord; mutable width: int; mutable height: int; current: Terminal.t; past: Terminal.t; mutable text: Rope.t; mutable undo_state: (Rope.t * cord) list; mutable redo_state: (Rope.t * cord) list; mutable mode: mode}
let default () = 
  let text = Rope.rope_of_string "hello\nhell\nworld\n" in
  {pos = empty_pos (); width; height; mode= Normal; current; past; text;undo_state= (text,empty_pos ()) :: []; redo_state=[]}
let commit_checkpoint editor = editor.undo_state <- (editor.text, clone_cord editor.pos) :: editor.undo_state; editor.redo_state <- []

let log_file = open_out_gen [ Open_append; Open_creat ] 0o644 "star.log"
