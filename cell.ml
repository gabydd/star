type color = Reset | Rgb of {r:int;b:int;g:int}
let empty_color = Reset
type t = {bg:color;fg:color;content:Bytes.t}
let b = Bytes.of_string
let empty = {bg=empty_color;fg=empty_color;content=b" "}
