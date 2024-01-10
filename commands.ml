let move_left (editor: Editor.t) =
  let pos = editor.pos in
  if pos.abs <> Rope.len editor.text then
    match Rope.get pos.abs editor.text with
    | '\n' ->
        pos.y <- pos.y + 1;
        pos.x <- 0;
        pos.abs <- pos.abs + 1
    | _ ->
        pos.x <- pos.x + 1;
        pos.abs <- pos.abs + 1

let insert (editor: Editor.t) ch =
  let pos = editor.pos in
  match ch with
  | '\n' ->
      editor.text <- Rope.insert_char pos.abs '\n' editor.text;
      pos.y <- pos.y + 1;
      pos.x <- 0;
      pos.abs <- pos.abs + 1
  | _ ->
      editor.text <- Rope.insert_char pos.abs ch editor.text;
      pos.x <- pos.x + 1;
      pos.abs <- pos.abs + 1

let move_right (editor: Editor.t) =
  let pos = editor.pos in
  if pos.abs <> 0 then
    match Rope.get (pos.abs - 1) editor.text with
    | '\n' ->
        pos.y <- pos.y - 1;
        pos.x <- Rope.line_len (pos.abs - 1) editor.text - 1;
        pos.abs <- pos.abs - 1
    | _ ->
        pos.x <- pos.x - 1;
        pos.abs <- pos.abs - 1

let delete (editor: Editor.t) =
  editor.text <- Rope.remove editor.pos.abs 1 editor.text

let backspace (editor: Editor.t) =
  let pos = editor.pos in
  if pos.abs <> 0 then (
    (match Rope.get (pos.abs - 1) editor.text with
    | '\n' ->
        pos.y <- pos.y - 1;
        pos.x <- Rope.line_len (pos.abs - 1) editor.text - 1;
        pos.abs <- pos.abs - 1
    | _ ->
        pos.x <- pos.x - 1;
        pos.abs <- pos.abs - 1);
    editor.text <- Rope.remove pos.abs 1 editor.text)

let move_down (editor: Editor.t) =
  let pos = editor.pos in
  let len = Rope.len editor.text in
  if pos.abs <> len then
    let next_start = pos.abs + Rope.line_len pos.abs editor.text - pos.x in
    if next_start < len then (
      let next_len = Rope.line_len next_start editor.text in
      let x = min pos.x (next_len - 1) in
      pos.y <- pos.y + 1;
      pos.x <- x;
      pos.abs <- next_start + x)
    else if next_start = len && Rope.get (len - 1) editor.text = '\n' then (
      pos.y <- pos.y + 1;
      pos.x <- 0;
      pos.abs <- next_start)

let move_up (editor: Editor.t) =
  let pos = editor.pos in
  let past_start = pos.abs - pos.x - 1 in
  if past_start >= 0 then (
    let past_len = Rope.line_len past_start editor.text in
    let x = min pos.x (past_len - 1) in
    pos.y <- pos.y - 1;
    pos.x <- x;
    pos.abs <- past_start - past_len + 1 + x)

let undo (editor: Editor.t) =
  let pos = editor.pos in
  match editor.undo_state with
  | [] -> ()
  | h :: [] -> ()
  | h :: (txt, cord) :: t ->
      editor.text <- txt;
      pos.x <- cord.x;
      pos.y <- cord.y;
      pos.abs <- cord.abs;
      editor.redo_state <- h :: editor.redo_state;
      editor.undo_state <- (txt, cord) :: t

let redo (editor: Editor.t) =
  let pos = editor.pos in
  match editor.redo_state with
  | [] -> ()
  | (txt, cord) :: t ->
      editor.text <- txt;
      pos.x <- cord.x;
      pos.y <- cord.y;
      pos.abs <- cord.abs;
      editor.undo_state <- (txt, cord) :: editor.undo_state;
      editor.redo_state <- t
