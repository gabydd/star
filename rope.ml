type info = { chars : int; breaks : int }
type 'a array5 = 'a * 'a * 'a * 'a * 'a

type buffer = {
  internal : bytes;
  mutable start : int;
  mutable len : int;
  size : int;
}

module Buffer = struct
  let create () =
    { internal = Bytes.make 50 '_'; start = 50 / 2; len = 0; size = 50 }

  let from_str str start len =
    let b = create () in
    Bytes.blit_string str start b.internal b.start len;
    b.len <- len;
    b

  let from_bytes bytes start len =
    let b = create () in
    Bytes.blit bytes start b.internal b.start len;
    b.len <- len;
    b

  let from_char ch =
    let b = create () in
    Bytes.set b.internal b.start ch;
    b.len <- 1;
    b

  let append_char c b =
    Bytes.set b.internal (b.start + b.len) c;
    b.len <- b.len + 1

  let append_str str start len (b : buffer) =
    Bytes.blit_string str start b.internal (b.start + b.len) len;
    b.len <- b.len + len

  let append_bytes bytes start len (b : buffer) =
    Bytes.blit bytes start b.internal (b.start + b.len) len;
    b.len <- b.len + len

  let prepend_char c (b : buffer) =
    Bytes.set b.internal (b.start - 1) c;
    b.start <- b.start - 1;
    b.len <- b.len + 1

  let prepend_str str start len (b : buffer) =
    Bytes.blit_string str start b.internal (b.start - len) len;
    b.start <- b.start - len

  let prepend_bytes bytes start len (b : buffer) =
    Bytes.blit bytes start b.internal (b.start - len) len;
    b.start <- b.start - len;
    b.start

  let can_append len b = len < b.size - b.start - b.len
  let can_prepend len (b : buffer) = len < b.start
  let get (b : buffer) i = Bytes.get b.internal i
  let index_from (b : buffer) i c = Bytes.index_from b.internal i c
  let rindex_from (b : buffer) i c = Bytes.rindex_from b.internal i c
end

type rope_string = { internal : buffer; start : int; len : int }

type t =
  | Internal of { children : t array5; info : info array5; len : int }
  | Leaf of rope_string

module RString = struct
  let fold_left f str acc =
    let r = ref acc in
    for i = str.start to str.start + str.len - 1 do
      r := f !r (Buffer.get str.internal i)
    done;
    !r

  let from_string str =
    let str = Buffer.from_str str 0 (String.length str) in
    { internal = str; start = str.start; len = str.len }

  let from_char ch =
    let str = Buffer.from_char ch in
    { internal = str; start = str.start; len = str.len }

  let sub str ofs len =
    { internal = str.internal; start = str.start + ofs; len }

  let iter f str =
    for i = str.start to str.start + str.len - 1 do
      f (Buffer.get str.internal i)
    done

  let get i str = Buffer.get str.internal (i + str.start)

  let index_from i str c =
    Buffer.index_from str.internal (str.start + i) c - str.start

  let index str c = index_from 0 str c

  let rindex_from i str c =
    Buffer.rindex_from str.internal (str.start + i) c - str.start

  let rindex str c = rindex_from (str.len - 1) str c

  let to_string str =
    String.sub (Bytes.to_string str.internal.internal) str.start str.len

  let can_append i len str =
    i = str.len
    && str.start + str.len = str.internal.start + str.internal.len
    && Buffer.can_append len str.internal

  let can_prepend i len str =
    i = 0
    && str.start = str.internal.start
    && Buffer.can_prepend len str.internal

  let append_char c str =
    Buffer.append_char c str.internal;
    { internal = str.internal; start = str.start; len = str.len + 1 }

  let prepend_char c str =
    Buffer.prepend_char c str.internal;
    { internal = str.internal; start = str.internal.start; len = str.len + 1 }
end

let empty = Leaf (RString.from_string "")
let empty_info = { chars = 0; breaks = 0 }

let insert5 len a = function
  | a1, a2, a3, a4, a5 -> (
      match len with
      | 0 -> (a, a2, a3, a4, a5)
      | 1 -> (a1, a, a3, a4, a5)
      | 2 -> (a1, a2, a, a4, a5)
      | 3 -> (a1, a2, a3, a, a5)
      | 4 -> (a1, a2, a3, a4, a)
      | 5 -> failwith "array is full"
      | _ -> failwith "past array length")

let make_last5 len a empty = function
  | a1, a2, a3, a4, a5 -> (
      match len with
      | 0 -> (a, empty, empty, empty, empty)
      | 1 -> (a1, a, empty, empty, empty)
      | 2 -> (a1, a2, a, empty, empty)
      | 3 -> (a1, a2, a3, a, empty)
      | 4 -> (a1, a2, a3, a4, a)
      | 5 -> failwith "array is full"
      | _ -> failwith "past array length")

let shift5 i a = function
  | a1, a2, a3, a4, a5 -> (
      match i with
      | 0 -> (a, a1, a2, a3, a4)
      | 1 -> (a1, a, a2, a3, a4)
      | 2 -> (a1, a2, a, a3, a4)
      | 3 -> (a1, a2, a3, a, a4)
      | 4 -> (a1, a2, a3, a4, a)
      | 5 -> failwith "array is full"
      | _ -> failwith "past array length")

let remove5 len empty = function
  | a1, a2, a3, a4, a5 -> (
      match len with
      | 0 -> (a2, a3, a4, a5, empty)
      | 1 -> (a1, a3, a4, a5, empty)
      | 2 -> (a1, a2, a4, a5, empty)
      | 3 -> (a1, a2, a3, a5, empty)
      | 4 -> (a1, a2, a3, a4, empty)
      | _ -> failwith "past array length")

let map5 len f empty = function
  | a1, a2, a3, a4, a5 -> (
      match len with
      | 0 -> (empty, empty, empty, empty, empty)
      | 1 -> (f a1, empty, empty, empty, empty)
      | 2 -> (f a1, f a2, empty, empty, empty)
      | 3 -> (f a1, f a2, f a3, empty, empty)
      | 4 -> (f a1, f a2, f a3, f a4, empty)
      | 5 -> (f a1, f a2, f a3, f a4, f a5)
      | _ -> failwith "past array length")

let iter5 len f = function
  | a1, a2, a3, a4, a5 -> (
      match len with
      | 0 -> ()
      | 1 -> f a1
      | 2 ->
          f a1;
          f a2
      | 3 ->
          f a1;
          f a2;
          f a3
      | 4 ->
          f a1;
          f a2;
          f a3;
          f a4
      | 5 ->
          f a1;
          f a2;
          f a3;
          f a4;
          f a5
      | _ -> failwith "past array length")

let fold5 len acc f = function
  | a1, a2, a3, a4, a5 -> (
      match len with
      | 0 -> acc
      | 1 -> f acc a1
      | 2 -> f (f acc a1) a2
      | 3 -> f (f (f acc a1) a2) a3
      | 4 -> f (f (f (f acc a1) a2) a3) a4
      | 5 -> f (f (f (f (f acc a1) a2) a3) a4) a5
      | _ -> failwith "past array length")

let get5 index = function
  | a1, a2, a3, a4, a5 -> (
      match index with
      | 0 -> a1
      | 1 -> a2
      | 2 -> a3
      | 3 -> a4
      | 4 -> a5
      | _ -> failwith "past array length")

let iwhen5 f empty len a =
  let rec loop i acc =
    let item = get5 i a in
    let acc, res, stop = f item acc in
    if stop then (i, res)
    else if i = len - 1 then failwith "past last pos"
    else loop (i + 1) acc
  in
  loop 0 empty

let get_pos i info len =
  iwhen5 (fun a acc -> (a.chars + acc, acc, a.chars + acc > i)) 0 len info

let make1 empty a1 = (a1, empty, empty, empty, empty)
let make2 empty a1 a2 = (a1, a2, empty, empty, empty)
let make3 empty a1 a2 a3 = (a1, a2, a3, empty, empty)
let make4 empty a1 a2 a3 a4 = (a1, a2, a3, a4, empty)
let make5 empty a1 a2 a3 a4 a5 = (a1, a2, a3, a4, a5)

let add_info ls rs =
  { chars = ls.chars + rs.chars; breaks = ls.breaks + rs.breaks }

let insert_internal c i = function
  | Internal { children; info; len } ->
      Internal
        {
          children = insert5 len c children;
          info = insert5 len i info;
          len = len + 1;
        }
  | Leaf _ -> failwith "can't insert to leaf"

let get_info = function
  | Leaf str ->
      String.
        {
          chars = str.len;
          breaks =
            RString.fold_left
              (fun acc c -> acc + if c = '\n' then 1 else 0)
              str 0;
        }
  | Internal { info; len } -> fold5 len { chars = 0; breaks = 0 } add_info info

let rec remove_loop i remove start ofs info children len =
  let s_len = (get5 i info).chars in
  if s_len < ofs && start = 0 && i != len - 1 then
    remove_loop i remove start (ofs - s_len)
      (remove5 i empty_info info)
      (remove5 i empty children) (len - 1)
  else if (s_len = ofs || (s_len < ofs && i = len - 1)) && start = 0 then
    (remove5 i empty children, len - 1)
  else if s_len > start && s_len >= start + ofs then
    (insert5 i (remove start ofs (get5 i children)) children, len)
  else if s_len > start then
    remove_loop (i + 1) remove 0
      (ofs - (s_len - start))
      info
      (insert5 i (remove start ofs (get5 i children)) children)
      len
  else remove_loop (i + 1) remove (start - s_len) ofs info children len

let rec remove start ofs = function
  | Internal { children; info; len } ->
      let children, len = remove_loop 0 remove start ofs info children len in
      Internal { children; info = map5 len get_info empty_info children; len }
  | Leaf a ->
      if start = 0 then Leaf (RString.sub a ofs (a.len - ofs))
      else if a.len <= start + ofs then Leaf (RString.sub a 0 start)
      else
        let children : t array5 =
          make2 empty
            (Leaf (RString.sub a 0 start))
            (Leaf (RString.sub a (start + ofs) (a.len - start - ofs)))
        in
        Internal
          { children; info = map5 2 get_info empty_info children; len = 2 }

let ( ^& ) ls rs =
  match ls with
  | Internal { children; info; len } -> insert_internal rs (get_info rs) ls
  | Leaf _ as sl -> (
      match rs with
      | Leaf _ as srl ->
          Internal
            {
              children = make2 empty sl srl;
              info = make2 empty_info (get_info sl) (get_info srl);
              len = 2;
            }
      | Internal _ as i ->
          Internal
            {
              children = make2 empty sl i;
              info = make2 empty_info (get_info sl) (get_info i);
              len = 2;
            })

let rec slice_loop i slice start ofs info children len =
  let s_len = (get5 i info).chars in
  if s_len < start then
    slice_loop i slice (start - s_len) ofs
      (remove5 i empty_info info)
      (remove5 i empty children) (len - 1)
  else if start = 0 && s_len < ofs then
    slice_loop (i + 1) slice start (ofs - s_len) info children (len - 1)
  else if s_len >= ofs || i == len - 1 then
    (make_last5 i (slice start ofs (get5 i children)) empty children, len)
  else
    slice_loop (i + 1) slice 0
      (ofs - (s_len - start))
      info
      (insert5 i (slice start ofs (get5 i children)) children)
      (len - 1)

let rec slice start ofs = function
  | Internal { children; info; len } ->
      let children, len = slice_loop 0 slice start ofs info children len in
      if len = 1 then get5 0 children
      else
        Internal { children; info = map5 len get_info empty_info children; len }
  | Leaf s -> Leaf (RString.sub s start ofs)

let rope_of_string s =
  let l = Leaf (RString.from_string s) in
  Internal
    { children = make1 empty l; info = make1 empty_info (get_info l); len = 1 }

let rope_of_char c =
  let l = Leaf (RString.from_char c) in
  Internal
    { children = make1 empty l; info = make1 empty_info (get_info l); len = 1 }

let rec string_of_rope_loop acc offs = function
  | Leaf s ->
      Bytes.blit s.internal.internal s.start acc !offs s.len;
      offs := !offs + s.len
  | Internal { children; len } ->
      iter5 len (fun b -> string_of_rope_loop acc offs b) children

let rec string_of_rope = function
  | Leaf str -> RString.to_string str
  | Internal { info; len } as i ->
      let bytes = Bytes.create (fold5 len 0 (fun a b -> a + b.chars) info) in
      string_of_rope_loop bytes (ref 0) i;
      String.of_bytes bytes

let rec iter f = function
  | Leaf str -> RString.iter f str
  | Internal { info; len; children } -> iter5 len (iter f) children

let rec fold insert acc index text info children len i =
  if i = len - 1 then
    let ind = acc + (get5 i info).chars in
    if acc <= index && ind >= index then
      insert5 i (insert (index - acc) text (get5 i children)) children
    else children
  else
    let ind = acc + (get5 i info).chars in
    if acc <= index && ind > index then
      insert5 i (insert (index - acc) text (get5 i children)) children
    else fold insert ind index text info children len (i + 1)

let rec insert_rope index text = function
  | Internal { children; info; len } ->
      let children = fold insert_rope 0 index text info children len 0 in
      Internal { children; info = map5 len get_info empty_info children; len }
  | Leaf s ->
      let length = s.len in
      let children, len =
        if index = 0 then
          ( make2 empty (Leaf text) (Leaf (RString.sub s index (length - index))),
            2 )
        else if index = length then
          (make2 empty (Leaf (RString.sub s 0 index)) (Leaf text), 2)
        else
          ( make3 empty
              (Leaf (RString.sub s 0 index))
              (Leaf text)
              (Leaf (RString.sub s index (length - index))),
            3 )
      in
      Internal { children; info = map5 3 get_info empty_info children; len }

let insert index text r = insert_rope index (RString.from_string text) r

type 'a one_or_two = OneOf of 'a | TwoOf of 'a * 'a

let insert_char_leaf s c i =
  let b = s.internal in
  if RString.can_prepend i 1 s then OneOf (Leaf (RString.prepend_char c s))
  else if RString.can_append i 1 s then OneOf (Leaf (RString.append_char c s))
    (*s.start + s.len = b.start + b.len*)
  else if s.start + s.len = b.start + b.len then (
    let b1 = Buffer.from_bytes b.internal s.start i in
    let b2 = Buffer.from_bytes b.internal (s.start + i) (s.len - i) in
    if s.start + s.len = b1.start + b1.len then Buffer.append_char c b2
    else Buffer.append_char c b1;

    TwoOf
      ( Leaf { internal = b1; start = b1.start; len = b1.len },
        Leaf { internal = b2; start = b2.start; len = b2.len } ))
  else
    (*s.start = b.start*)
    let b2 = Buffer.from_bytes b.internal (s.start + i) (s.len - i) in
    Buffer.prepend_char c b2;
    TwoOf
      ( Leaf { internal = b; start = s.start; len = i },
        Leaf { internal = b2; start = b2.start; len = b2.len } )

let rec first_str = function
  | Leaf str -> str
  | Internal { children } -> first_str (get5 0 children)

let rec insert_char index (c : char) = function
  | Internal { children; info; len } ->
      if len = 0 then rope_of_char c
      else
        let i, acc =
          (*handle size being 0*)
          iwhen5
            (fun item acc ->
              let ind = acc + item.chars in
              (ind, acc, acc <= index && ind >= index))
            0 len info
        in
        let children, len =
          let index = index - acc in
          match get5 i children with
          | Internal _ ->
              (insert5 i (insert_char index c (get5 i children)) children, len)
          | Leaf str -> (
              match insert_char_leaf str c index with
              | OneOf l -> (insert5 i l children, len)
              | TwoOf (l1, l2) ->
                  if
                    index = str.len
                    && i <> len - 1
                    && RString.can_prepend 1 0
                         (first_str (get5 (i + 1) children))
                  then
                    ( insert5 (i + 1)
                        (insert_char 0 c (get5 (i + 1) children))
                        children,
                      len )
                  else if len = 5 then
                    ( insert5 i (insert_char index c (get5 i children)) children,
                      len )
                  else (shift5 i l1 (insert5 i l2 children), len + 1))
        in
        Internal { children; info = map5 len get_info empty_info children; len }
  | Leaf s -> (
      match insert_char_leaf s c index with
      | OneOf l -> l
      | TwoOf (l1, l2) ->
          let children = make2 empty l1 l2 in
          Internal
            { children; info = map5 2 get_info empty_info children; len = 2 })

let len = function
  | Leaf { len } -> len
  | Internal { info; len } -> fold5 len 0 (fun a b -> a + b.chars) info

let lines = function
  | Leaf str ->
      RString.fold_left (fun acc c -> acc + if c = '\n' then 1 else 0) str 0
  | Internal { info; len } -> fold5 len 0 (fun a b -> a + b.breaks) info

let rec get_loop i acc a children info len get =
  let s_len = (get5 a info).chars in
  if a = len - 1 || i < acc + s_len then get (i - acc) (get5 a children)
  else get_loop i (acc + s_len) (a + 1) children info len get

let rec get i = function
  | Leaf str -> RString.get i str
  | Internal { children; info; len } -> get_loop i 0 0 children info len get

type length = Full of int | End of int | Start of int | Part of int
type till = NoneTill | EndTill | StartTill

let unwrap_len = function Full len | End len | Start len | Part len -> len

(*
      if lines = 0 then Part str.len
      else if str.len = 1 then
        match till with EndTill | NoneTill -> End 1 | StartTill -> Start 0
      else
        let first_i = RString.index str '\n' in
        (*handle when equal*)
        if first_i > i then End (first_i + 1)
        else if first_i = i then
          match till with
          | EndTill | NoneTill -> End (first_i + 1)
          | StartTill -> Start 0
        else if lines > 1 then
          let last_i = RString.rindex str '\n' in
          if last_i >= i then
            Full
              (RString.index_from i str '\n'
              - RString.rindex_from (i - 1) str '\n')
          else Start (str.len - last_i - 1)
        else Start (str.len - first_i - 1)
*)
let rec line_len_loop i lines till r =
  match r with
  | Leaf str -> (
      if lines = 0 then Part str.len
      else
        match till with
        | EndTill -> End (RString.index str '\n' + 1)
        | StartTill -> Start (str.len - RString.rindex str '\n' - 1)
        | NoneTill ->
            let first_i = RString.index str '\n' in
            if first_i >= i then End (first_i + 1)
            else if lines > 1 then
              let last_i = RString.rindex str '\n' in
              if last_i >= i then
                Full
                  (RString.index_from i str '\n'
                  - RString.rindex_from (i - 1) str '\n')
              else Start (str.len - last_i - 1)
            else Start (str.len - first_i - 1))
  | Internal { children; info; len = ilen } -> (
      let a, acc = get_pos i info ilen in
      let inf = get5 a info in
      match
        (line_len_loop (i - acc) inf.breaks till (get5 a children), till)
      with
      | Full len, _ -> Full len
      | Start len, StartTill -> Full len
      | Start len, NoneTill -> (
          if a = ilen - 1 then Start len
          else
            match line_len_loop (acc + inf.chars) lines EndTill r with
            | Start l | Full l | End l -> Full (l + len)
            | Part l -> Start (l + len))
      | Start len, EndTill -> failwith "got start while searching for end"
      | End len, EndTill -> Full len
      | End len, NoneTill -> (
          if a = 0 then End len
          else
            match line_len_loop (acc - 1) lines StartTill r with
            | Start l | Full l | End l -> Full (l + len)
            | Part l -> End (l + len))
      | End len, StartTill -> failwith "got end when searching for start"
      | Part len, StartTill ->
          if a = 0 then Part len
          else
            Start (unwrap_len (line_len_loop (acc - 1) lines StartTill r) + len)
      | Part len, EndTill ->
          if a = ilen - 1 then Part len
          else
            End
              (len
              + unwrap_len (line_len_loop (acc + inf.chars) lines EndTill r))
      | Part len, NoneTill ->
          if a = 0 && a = ilen - 1 then Part len
          else if a = 0 then
            End
              (len
              + unwrap_len (line_len_loop (acc + inf.chars) lines EndTill r))
          else if a = ilen - 1 then
            End (unwrap_len (line_len_loop (acc - 1) lines StartTill r) + len)
          else
            Full
              (unwrap_len (line_len_loop (acc - 1) lines StartTill r)
              + len
              + unwrap_len (line_len_loop (acc + inf.chars) lines EndTill r)))

let line_len i r = unwrap_len (line_len_loop i (get_info r).breaks NoneTill r)

let rec print_rope f tabs = function
  | Leaf str ->
      for _ = 1 to tabs do
        Printf.fprintf f "\t"
      done;
      Printf.fprintf f "Leaf {internal=%s;start=%d;len=%d}\n"
        (String.escaped (RString.to_string str))
        str.start str.len
  | Internal { children; info; len } ->
      for _ = 1 to tabs do
        Printf.fprintf f "\t"
      done;
      Printf.fprintf f "Internal {\n";
      iter5 len (print_rope f (tabs + 1)) children;
      for _ = 1 to tabs do
        Printf.fprintf f "\t"
      done;
      Printf.fprintf f "Info (";
      iter5 len
        (fun i -> Printf.fprintf f "{chars=%d;breaks=%d}, " i.chars i.breaks)
        info;
      Printf.fprintf f ")\n";
      for _ = 1 to tabs do
        Printf.fprintf f "\t"
      done;
      Printf.fprintf f "}\n"
