(* camlp4r *)
(***********************************************************************)
(*                                                                     *)
(*                             Camlp4                                  *)
(*                                                                     *)
(*        Daniel de Rauglaudre, projet Cristal, INRIA Rocquencourt     *)
(*                                                                     *)
(*  Copyright 2001 Institut National de Recherche en Informatique et   *)
(*  Automatique.  Distributed only by permission.                      *)
(*                                                                     *)
(***********************************************************************)

(* Id *)

open Stdpp;;
open Gramext;;

open Format;;

let rec flatten_tree =
  function
    DeadEnd -> []
  | LocAct (_, _) -> [[]]
  | Node {node = n; brother = b; son = s} ->
      List.map (fun l -> n :: l) (flatten_tree s) @ flatten_tree b
;;

let print_str s = print_string ("\"" ^ String.escaped s ^ "\"");;

let rec print_symbol =
  function
    Slist0 s -> print_string "LIST0"; print_string " "; print_symbol1 s
  | Slist0sep (s, t) ->
      print_string "LIST0";
      print_string " ";
      print_symbol1 s;
      print_string " SEP ";
      print_symbol1 t
  | Slist1 s -> print_string "LIST1"; print_string " "; print_symbol1 s
  | Slist1sep (s, t) ->
      print_string "LIST1";
      print_string " ";
      print_symbol1 s;
      print_string " SEP ";
      print_symbol1 t
  | Sopt s -> print_string "OPT "; print_symbol1 s
  | Stoken (con, prm) when con <> "" && prm <> "" ->
      print_string con; print_space (); print_str prm
  | Snterml (e, l) ->
      print_string e.ename;
      print_space ();
      print_string "LEVEL";
      print_space ();
      print_str l
  | s -> print_symbol1 s
and print_symbol1 =
  function
    Stoken ("", s) -> print_str s
  | Snterm e -> print_string e.ename
  | Sself -> print_string "SELF"
  | Snext -> print_string "NEXT"
  | Stoken (con, "") -> print_string con
  | Stree t -> print_level print_space (flatten_tree t)
  | s -> print_string "("; print_symbol s; print_string ")"
and print_rule symbols =
  open_hovbox 0;
  let _ =
    List.fold_left
      (fun sep symbol ->
         sep ();
         print_symbol symbol;
         fun () -> print_string ";"; print_space ())
      (fun () -> ()) symbols
  in
  close_box ()
and print_level print_space rules =
  open_hovbox 0;
  print_string "[ ";
  let _ =
    List.fold_left
      (fun sep rule ->
         sep (); print_rule rule; fun () -> print_space (); print_string "| ")
      (fun () -> ()) rules
  in
  print_string " ]"; close_box ()
;;

let print_levels elev =
  let _ =
    List.fold_left
      (fun sep lev ->
         let rules =
           List.map (fun t -> Sself :: t) (flatten_tree lev.lsuffix) @
             flatten_tree lev.lprefix
         in
         sep ();
         open_hovbox 2;
         begin match lev.lname with
           Some n ->
             print_string ("\"" ^ String.escaped n ^ "\""); print_break 1 2
         | _ -> ()
         end;
         begin match lev.assoc with
           LeftA -> print_string "LEFTA"
         | RightA -> print_string "RIGHTA"
         | NonA -> print_string "NONA"
         end;
         close_box ();
         print_break 1 2;
         print_level force_newline rules;
         fun () -> print_cut (); print_string "| ")
      (fun () -> ()) elev
  in
  ()
;;

let print_entry e =
  open_vbox 0;
  print_string "[ ";
  begin match e.edesc with
    Dlevels elev -> print_levels elev
  | Dparser _ -> print_string "<parser>"
  end;
  print_string " ]";
  close_box ();
  print_newline ()
;;

type g = Gramext.grammar;;

external grammar_obj : g -> grammar = "%identity";;

let floc = ref (fun _ -> failwith "internal error when computing location");;
let loc_of_token_interval bp ep =
  if bp == ep then
    if bp == 0 then 0, 1 else let a = snd (!floc (bp - 1)) in a, a + 1
  else
    let (bp1, bp2) = !floc bp in
    let (ep1, ep2) = !floc (pred ep) in
    (if bp1 < ep1 then bp1 else ep1), (if bp2 > ep2 then bp2 else ep2)
;;

let rec name_of_symbol entry =
  function
    Snterm e -> "[" ^ e.ename ^ "]"
  | Snterml (e, l) -> "[" ^ e.ename ^ " level " ^ l ^ "]"
  | Sself | Snext -> "[" ^ entry.ename ^ "]"
  | Stoken tok -> entry.egram.glexer.Token.text tok
  | _ -> "???"
;;

let rec get_token_list entry tokl last_tok tree =
  match tree with
    Node {node = Stoken tok as s; son = son; brother = DeadEnd} ->
      begin match entry.egram.glexer.Token.tparse tok with
        Some _ ->
          if tokl = [] then None
          else Some (List.rev (last_tok :: tokl), last_tok, tree)
      | None -> get_token_list entry (last_tok :: tokl) tok son
      end
  | _ ->
      if tokl = [] then None
      else Some (List.rev (last_tok :: tokl), last_tok, tree)
;;

let rec name_of_symbol_failed entry =
  function
    Slist0 s -> name_of_symbol_failed entry s
  | Slist0sep (s, _) -> name_of_symbol_failed entry s
  | Slist1 s -> name_of_symbol_failed entry s
  | Slist1sep (s, _) -> name_of_symbol_failed entry s
  | Sopt s -> name_of_symbol_failed entry s
  | Stree t -> name_of_tree_failed entry t
  | s -> name_of_symbol entry s
and name_of_tree_failed entry =
  function
    Node {node = s; brother = bro; son = son} ->
      let tokl =
        match s with
          Stoken tok when entry.egram.glexer.Token.tparse tok = None ->
            get_token_list entry [] tok son
        | _ -> None
      in
      begin match tokl with
        None ->
          let txt = name_of_symbol_failed entry s in
          let txt =
            match s, son with
              Sopt _, Node _ -> txt ^ " or " ^ name_of_tree_failed entry son
            | _ -> txt
          in
          let txt =
            match bro with
              DeadEnd | LocAct (_, _) -> txt
            | _ -> txt ^ " or " ^ name_of_tree_failed entry bro
          in
          txt
      | Some (tokl, last_tok, son) ->
          List.fold_left
            (fun s tok ->
               (if s = "" then "" else s ^ " ") ^
                 entry.egram.glexer.Token.text tok)
            "" tokl
      end
  | DeadEnd | LocAct (_, _) -> "???"
;;

let search_tree_in_entry prev_symb tree =
  function
    Dlevels levels ->
      let rec search_levels =
        function
          [] -> tree
        | level :: levels ->
            match search_level level with
              Some tree -> tree
            | None -> search_levels levels
      and search_level level =
        match search_tree level.lsuffix with
          Some t -> Some (Node {node = Sself; son = t; brother = DeadEnd})
        | None -> search_tree level.lprefix
      and search_tree t =
        if tree <> DeadEnd && t == tree then Some t
        else
          match t with
            Node n ->
              begin match search_symbol n.node with
                Some symb ->
                  Some (Node {node = symb; son = n.son; brother = DeadEnd})
              | None ->
                  match search_tree n.son with
                    Some t ->
                      Some (Node {node = n.node; son = t; brother = DeadEnd})
                  | None -> search_tree n.brother
              end
          | _ -> None
      and search_symbol symb =
        match symb with
          Snterm _ | Snterml (_, _) | Slist0 _ | Slist0sep (_, _) | Slist1 _ |
          Slist1sep (_, _) | Sopt _ | Stoken _ | Stree _
          when symb == prev_symb ->
            Some symb
        | Slist0 symb ->
            begin match search_symbol symb with
              Some symb -> Some (Slist0 symb)
            | None -> None
            end
        | Slist0sep (symb, sep) ->
            begin match search_symbol symb with
              Some symb -> Some (Slist0sep (symb, sep))
            | None ->
                match search_symbol sep with
                  Some sep -> Some (Slist0sep (symb, sep))
                | None -> None
            end
        | Slist1 symb ->
            begin match search_symbol symb with
              Some symb -> Some (Slist1 symb)
            | None -> None
            end
        | Slist1sep (symb, sep) ->
            begin match search_symbol symb with
              Some symb -> Some (Slist1sep (symb, sep))
            | None ->
                match search_symbol sep with
                  Some sep -> Some (Slist1sep (symb, sep))
                | None -> None
            end
        | Sopt symb ->
            begin match search_symbol symb with
              Some symb -> Some (Sopt symb)
            | None -> None
            end
        | Stree t ->
            begin match search_tree t with
              Some t -> Some (Stree t)
            | None -> None
            end
        | _ -> None
      in
      search_levels levels
  | _ -> tree
;;

let error_verbose = ref false;;

let tree_failed entry prev_symb_result prev_symb tree =
  let txt = name_of_tree_failed entry tree in
  let txt =
    match prev_symb with
      Slist0 s ->
        let txt1 = name_of_symbol_failed entry s in
        txt1 ^ " or " ^ txt ^ " expected"
    | Slist1 s ->
        let txt1 = name_of_symbol_failed entry s in
        txt1 ^ " or " ^ txt ^ " expected"
    | Slist0sep (s, sep) ->
        begin match Obj.magic prev_symb_result with
          [] ->
            let txt1 = name_of_symbol_failed entry s in
            txt1 ^ " or " ^ txt ^ " expected"
        | _ ->
            let txt1 = name_of_symbol_failed entry sep in
            txt1 ^ " or " ^ txt ^ " expected"
        end
    | Slist1sep (s, sep) ->
        begin match Obj.magic prev_symb_result with
          [] ->
            let txt1 = name_of_symbol_failed entry s in
            txt1 ^ " or " ^ txt ^ " expected"
        | _ ->
            let txt1 = name_of_symbol_failed entry sep in
            txt1 ^ " or " ^ txt ^ " expected"
        end
    | Sopt _ | Stree _ -> txt ^ " expected"
    | _ -> txt ^ " expected after " ^ name_of_symbol entry prev_symb
  in
  if !error_verbose then
    begin
      let tree = search_tree_in_entry prev_symb tree entry.edesc in
      set_formatter_out_channel stderr;
      open_vbox 0;
      print_newline ();
      print_string "----------------------------------";
      print_newline ();
      printf "Parse error in entry [%s], rule:" entry.ename;
      print_break 0 2;
      open_vbox 0;
      print_level force_newline (flatten_tree tree);
      close_box ();
      print_newline ();
      print_string "----------------------------------";
      print_newline ();
      close_box ();
      print_newline ()
    end;
  txt ^ " (in [" ^ entry.ename ^ "])"
;;

let symb_failed entry prev_symb_result prev_symb symb =
  let tree = Node {node = symb; brother = DeadEnd; son = DeadEnd} in
  tree_failed entry prev_symb_result prev_symb tree
;;

external app : Obj.t -> 'a = "%identity";;

let is_level_labelled n lev =
  match lev.lname with
    Some n1 -> n = n1
  | None -> false
;;

let level_number entry lab =
  let rec lookup levn =
    function
      [] -> failwith ("unknown level " ^ lab)
    | lev :: levs ->
        if is_level_labelled lab lev then levn else lookup (succ levn) levs
  in
  match entry.edesc with
    Dlevels elev -> lookup 0 elev
  | Dparser _ -> raise Not_found
;;

let rec top_symb entry =
  function
    Sself | Snext -> Snterm entry
  | Snterml (e, _) -> Snterm e
  | Slist1sep (s, sep) -> Slist1sep (top_symb entry s, sep)
  | _ -> raise Stream.Failure
;;

let entry_of_symb entry =
  function
    Sself | Snext -> entry
  | Snterm e -> e
  | Snterml (e, _) -> e
  | _ -> raise Stream.Failure
;;

let top_tree entry =
  function
    Node {node = s; brother = bro; son = son} ->
      Node {node = top_symb entry s; brother = bro; son = son}
  | _ -> raise Stream.Failure
;;

let skip_if_empty bp p strm =
  if Stream.count strm == bp then Gramext.action (fun a -> p strm)
  else raise Stream.Failure
;;

let continue entry bp a s son p1 (strm__ : _ Stream.t) =
  let a = (entry_of_symb entry s).econtinue 0 bp a strm__ in
  let act =
    try p1 strm__ with
      Stream.Failure -> raise (Stream.Error (tree_failed entry a s son))
  in
  Gramext.action (fun _ -> app act a)
;;

let
  do_recover
    parser_of_tree
    entry
    nlevn
    alevn
    bp
    a
    s
    son
    (strm__ : _ Stream.t) =
  try parser_of_tree entry nlevn alevn (top_tree entry son) strm__ with
    Stream.Failure ->
      try
        skip_if_empty bp (fun (strm__ : _ Stream.t) -> raise Stream.Failure)
          strm__
      with
        Stream.Failure ->
          continue entry bp a s son (parser_of_tree entry nlevn alevn son)
            strm__
;;

let strict_parsing = ref false;;

let recover parser_of_tree entry nlevn alevn bp a s son strm =
  if !strict_parsing then raise (Stream.Error (tree_failed entry a s son))
  else do_recover parser_of_tree entry nlevn alevn bp a s son strm
;;

let std_token_parse =
  function
    p_con, "" ->
      (fun (strm__ : _ Stream.t) ->
         match Stream.peek strm__ with
           Some (con, prm) when con = p_con -> Stream.junk strm__; prm
         | _ -> raise Stream.Failure)
  | p_con, p_prm ->
      fun (strm__ : _ Stream.t) ->
        match Stream.peek strm__ with
          Some (con, prm) when con = p_con && prm = p_prm ->
            Stream.junk strm__; prm
        | _ -> raise Stream.Failure
;;

let peek_nth n strm =
  let list = Stream.npeek n strm in
  let rec loop list n =
    match list, n with
      x :: _, 1 -> Some x
    | _ :: l, n -> loop l (n - 1)
    | [], _ -> None
  in
  loop list n
;;

let rec parser_of_tree entry nlevn alevn =
  function
    DeadEnd -> (fun (strm__ : _ Stream.t) -> raise Stream.Failure)
  | LocAct (act, _) -> (fun (strm__ : _ Stream.t) -> act)
  | Node {node = Sself; son = LocAct (act, _); brother = DeadEnd} ->
      (fun (strm__ : _ Stream.t) ->
         let a = entry.estart alevn strm__ in app act a)
  | Node {node = Sself; son = LocAct (act, _); brother = bro} ->
      let p2 = parser_of_tree entry nlevn alevn bro in
      (fun (strm__ : _ Stream.t) ->
         match
           try Some (entry.estart alevn strm__) with
             Stream.Failure -> None
         with
           Some a -> app act a
         | _ -> p2 strm__)
  | Node {node = s; son = son; brother = DeadEnd} ->
      let tokl =
        match s with
          Stoken tok when entry.egram.glexer.Token.tparse tok = None ->
            get_token_list entry [] tok son
        | _ -> None
      in
      begin match tokl with
        None ->
          let ps = parser_of_symbol entry nlevn s in
          let p1 = parser_of_tree entry nlevn alevn son in
          let p1 = parser_cont p1 entry nlevn alevn s son in
          (fun (strm__ : _ Stream.t) ->
             let bp = Stream.count strm__ in
             let a = ps strm__ in
             let act =
               try p1 bp a strm__ with
                 Stream.Failure -> raise (Stream.Error "")
             in
             app act a)
      | Some (tokl, last_tok, son) ->
          let p1 = parser_of_tree entry nlevn alevn son in
          let p1 = parser_cont p1 entry nlevn alevn (Stoken last_tok) son in
          parser_of_token_list p1 tokl
      end
  | Node {node = s; son = son; brother = bro} ->
      let tokl =
        match s with
          Stoken tok when entry.egram.glexer.Token.tparse tok = None ->
            get_token_list entry [] tok son
        | _ -> None
      in
      match tokl with
        None ->
          let ps = parser_of_symbol entry nlevn s in
          let p1 = parser_of_tree entry nlevn alevn son in
          let p1 = parser_cont p1 entry nlevn alevn s son in
          let p2 = parser_of_tree entry nlevn alevn bro in
          (fun (strm__ : _ Stream.t) ->
             let bp = Stream.count strm__ in
             match
               try Some (ps strm__) with
                 Stream.Failure -> None
             with
               Some a ->
                 let act =
                   try p1 bp a strm__ with
                     Stream.Failure -> raise (Stream.Error "")
                 in
                 app act a
             | _ -> p2 strm__)
      | Some (tokl, last_tok, son) ->
          let p1 = parser_of_tree entry nlevn alevn son in
          let p1 = parser_cont p1 entry nlevn alevn (Stoken last_tok) son in
          let p1 = parser_of_token_list p1 tokl in
          let p2 = parser_of_tree entry nlevn alevn bro in
          fun (strm__ : _ Stream.t) ->
            try p1 strm__ with
              Stream.Failure -> p2 strm__
and parser_cont p1 entry nlevn alevn s son bp a (strm__ : _ Stream.t) =
  try p1 strm__ with
    Stream.Failure ->
      try recover parser_of_tree entry nlevn alevn bp a s son strm__ with
        Stream.Failure -> raise (Stream.Error (tree_failed entry a s son))
and parser_of_token_list p1 tokl =
  let rec loop n =
    function
      [p_con, ""] ->
        let ps strm =
          match peek_nth n strm with
            Some (con, prm) when p_con = "ANY" || con = p_con ->
              for i = 1 to n do Stream.junk strm done; Obj.repr prm
          | _ -> raise Stream.Failure
        in
        (fun (strm__ : _ Stream.t) ->
           let bp = Stream.count strm__ in
           let a = ps strm__ in
           let act =
             try p1 bp a strm__ with
               Stream.Failure -> raise (Stream.Error "")
           in
           app act a)
    | [p_con, p_prm] ->
        let ps strm =
          match peek_nth n strm with
            Some (con, prm)
            when (p_con = "ANY" || con = p_con) && prm = p_prm ->
              for i = 1 to n do Stream.junk strm done; Obj.repr prm
          | _ -> raise Stream.Failure
        in
        (fun (strm__ : _ Stream.t) ->
           let bp = Stream.count strm__ in
           let a = ps strm__ in
           let act =
             try p1 bp a strm__ with
               Stream.Failure -> raise (Stream.Error "")
           in
           app act a)
    | (p_con, "") :: tokl ->
        let ps strm =
          match peek_nth n strm with
            Some (con, prm) when p_con = "ANY" || con = p_con -> prm
          | _ -> raise Stream.Failure
        in
        let p1 = loop (n + 1) tokl in
        (fun (strm__ : _ Stream.t) ->
           let a = ps strm__ in let act = p1 strm__ in app act a)
    | (p_con, p_prm) :: tokl ->
        let ps strm =
          match peek_nth n strm with
            Some (con, prm)
            when (p_con = "ANY" || con = p_con) && prm = p_prm ->
              prm
          | _ -> raise Stream.Failure
        in
        let p1 = loop (n + 1) tokl in
        (fun (strm__ : _ Stream.t) ->
           let a = ps strm__ in let act = p1 strm__ in app act a)
    | [] -> assert false
  in
  loop 1 tokl
and parser_of_symbol entry nlevn =
  function
    Slist0 s ->
      let ps = parser_of_symbol entry nlevn s in
      let rec loop al (strm__ : _ Stream.t) =
        match
          try Some (ps strm__) with
            Stream.Failure -> None
        with
          Some a -> loop (a :: al) strm__
        | _ -> al
      in
      (fun (strm__ : _ Stream.t) ->
         let a = loop [] strm__ in Obj.repr (List.rev a))
  | Slist0sep (symb, sep) ->
      let ps = parser_of_symbol entry nlevn symb in
      let pt = parser_of_symbol entry nlevn sep in
      let rec kont al (strm__ : _ Stream.t) =
        match
          try Some (pt strm__) with
            Stream.Failure -> None
        with
          Some v ->
            let a =
              try ps strm__ with
                Stream.Failure ->
                  raise (Stream.Error (symb_failed entry v sep symb))
            in
            kont (a :: al) strm__
        | _ -> al
      in
      (fun (strm__ : _ Stream.t) ->
         match
           try Some (ps strm__) with
             Stream.Failure -> None
         with
           Some a -> Obj.repr (List.rev (kont [a] strm__))
         | _ -> Obj.repr [])
  | Slist1 s ->
      let ps = parser_of_symbol entry nlevn s in
      let rec loop al (strm__ : _ Stream.t) =
        match
          try Some (ps strm__) with
            Stream.Failure -> None
        with
          Some a -> loop (a :: al) strm__
        | _ -> al
      in
      (fun (strm__ : _ Stream.t) ->
         let a = ps strm__ in Obj.repr (List.rev (loop [a] strm__)))
  | Slist1sep (symb, sep) ->
      let ps = parser_of_symbol entry nlevn symb in
      let pt = parser_of_symbol entry nlevn sep in
      let rec kont al (strm__ : _ Stream.t) =
        match
          try Some (pt strm__) with
            Stream.Failure -> None
        with
          Some v ->
            let a =
              try ps strm__ with
                Stream.Failure ->
                  try
                    parser_of_symbol entry nlevn (top_symb entry symb) strm__
                  with
                    Stream.Failure ->
                      raise (Stream.Error (symb_failed entry v sep symb))
            in
            kont (a :: al) strm__
        | _ -> al
      in
      (fun (strm__ : _ Stream.t) ->
         let a = ps strm__ in Obj.repr (List.rev (kont [a] strm__)))
  | Sopt s ->
      let ps = parser_of_symbol entry nlevn s in
      (fun (strm__ : _ Stream.t) ->
         match
           try Some (ps strm__) with
             Stream.Failure -> None
         with
           Some a -> Obj.repr (Some a)
         | _ -> Obj.repr None)
  | Stree t ->
      let pt = parser_of_tree entry 1 0 t in
      (fun (strm__ : _ Stream.t) ->
         let bp = Stream.count strm__ in
         let a = pt strm__ in
         let ep = Stream.count strm__ in
         let loc = loc_of_token_interval bp ep in app a loc)
  | Snterm e -> (fun (strm__ : _ Stream.t) -> e.estart 0 strm__)
  | Snterml (e, l) ->
      (fun (strm__ : _ Stream.t) -> e.estart (level_number e l) strm__)
  | Sself -> (fun (strm__ : _ Stream.t) -> entry.estart 0 strm__)
  | Snext -> (fun (strm__ : _ Stream.t) -> entry.estart nlevn strm__)
  | Stoken ("ANY", v) ->
      if v = "" then
        fun (strm__ : _ Stream.t) ->
          match Stream.peek strm__ with
            Some (_, x) -> Stream.junk strm__; Obj.repr x
          | _ -> raise Stream.Failure
      else
        (fun (strm__ : _ Stream.t) ->
           match Stream.peek strm__ with
             Some (_, x) when x = v -> Stream.junk strm__; Obj.repr x
           | _ -> raise Stream.Failure)
  | Stoken tok ->
      match entry.egram.glexer.Token.tparse tok with
        Some f -> (Obj.magic f : Token.t Stream.t -> Obj.t)
      | None -> (Obj.magic (std_token_parse tok) : Token.t Stream.t -> Obj.t)
;;

let rec continue_parser_of_levels entry clevn =
  function
    [] -> (fun levn bp a (strm__ : _ Stream.t) -> raise Stream.Failure)
  | lev :: levs ->
      let p1 = continue_parser_of_levels entry (succ clevn) levs in
      match lev.lsuffix with
        DeadEnd -> p1
      | tree ->
          let alevn =
            match lev.assoc with
              LeftA | NonA -> succ clevn
            | RightA -> clevn
          in
          let p2 = parser_of_tree entry (succ clevn) alevn tree in
          fun levn bp a strm ->
            if levn > clevn then p1 levn bp a strm
            else
              let (strm__ : _ Stream.t) = strm in
              try p1 levn bp a strm__ with
                Stream.Failure ->
                  let act = p2 strm__ in
                  let ep = Stream.count strm__ in
                  let a = app act a (loc_of_token_interval bp ep) in
                  entry.econtinue levn bp a strm
;;

let rec start_parser_of_levels entry clevn =
  function
    [] -> (fun levn (strm__ : _ Stream.t) -> raise Stream.Failure)
  | lev :: levs ->
      let p1 = start_parser_of_levels entry (succ clevn) levs in
      match lev.lprefix with
        DeadEnd -> p1
      | tree ->
          let alevn =
            match lev.assoc with
              LeftA | NonA -> succ clevn
            | RightA -> clevn
          in
          let p2 = parser_of_tree entry (succ clevn) alevn tree in
          match levs with
            [] ->
              (fun levn strm ->
                 let (strm__ : _ Stream.t) = strm in
                 let bp = Stream.count strm__ in
                 let act = p2 strm__ in
                 let ep = Stream.count strm__ in
                 let a = app act (loc_of_token_interval bp ep) in
                 entry.econtinue levn bp a strm)
          | _ ->
              fun levn strm ->
                if levn > clevn then p1 levn strm
                else
                  let (strm__ : _ Stream.t) = strm in
                  let bp = Stream.count strm__ in
                  match
                    try Some (p2 strm__) with
                      Stream.Failure -> None
                  with
                    Some act ->
                      let ep = Stream.count strm__ in
                      let a = app act (loc_of_token_interval bp ep) in
                      entry.econtinue levn bp a strm
                  | _ -> p1 levn strm__
;;

let continue_parser_of_entry entry =
  match entry.edesc with
    Dlevels elev ->
      let p = continue_parser_of_levels entry 0 elev in
      (fun levn bp a (strm__ : _ Stream.t) ->
         try p levn bp a strm__ with
           Stream.Failure -> a)
  | Dparser p -> fun levn bp a (strm__ : _ Stream.t) -> raise Stream.Failure
;;

let empty_entry ename levn strm =
  raise (Stream.Error ("entry [" ^ ename ^ "] is empty"))
;;

let rec start_parser_of_entry entry =
  match entry.edesc with
    Dlevels [] -> empty_entry entry.ename
  | Dlevels elev -> start_parser_of_levels entry 0 elev
  | Dparser p -> fun levn strm -> p strm
;;

let parse_parsable entry efun (cs, (ts, fun_loc)) =
  let restore = let old_floc = !floc in fun () -> floc := old_floc in
  floc := fun_loc;
  try let r = efun ts in restore (); r with
    Stream.Failure ->
      let loc =
        try fun_loc (Stream.count ts) with
          _ -> Stream.count cs, Stream.count cs + 1
      in
      restore ();
      raise_with_loc loc (Stream.Error ("illegal begin of " ^ entry.ename))
  | Stream.Error _ as exc ->
      let loc =
        try fun_loc (Stream.count ts) with
          _ -> Stream.count cs, Stream.count cs + 1
      in
      restore (); raise_with_loc loc exc
  | exc ->
      let loc = Stream.count cs, Stream.count cs + 1 in
      restore (); raise_with_loc loc exc
;;

let wrap_parse entry efun cs =
  let parsable = cs, entry.egram.glexer.Token.func cs in
  parse_parsable entry efun parsable
;;

let create_toktab () = Hashtbl.create 301;;
let create lexer = {gtokens = create_toktab (); glexer = lexer};;

(* Extend syntax *)

let extend_entry entry position rules =
  try
    let elev = Gramext.levels_of_rules entry position rules in
    entry.edesc <- Dlevels elev;
    entry.estart <-
      (fun lev strm ->
         let f = start_parser_of_entry entry in
         entry.estart <- f; f lev strm);
    entry.econtinue <-
      fun lev bp a strm ->
        let f = continue_parser_of_entry entry in
        entry.econtinue <- f; f lev bp a strm
  with
    Token.Error s ->
      Printf.eprintf "Lexer initialization error.\n%s\n"
        (String.capitalize s);
      flush stderr;
      failwith "Grammar.extend"
;;

let extend entry_rules_list =
  let gram = ref None in
  List.iter
    (fun (entry, position, rules) ->
       begin match !gram with
         Some g ->
           if g != entry.egram then
             begin
               Printf.eprintf "Error: entries with different grammars\n";
               flush stderr;
               failwith "Grammar.extend"
             end
       | None -> gram := Some entry.egram
       end;
       extend_entry entry position rules)
    entry_rules_list
;;

(* Deleting a rule *)

let delete_rule entry sl =
  match entry.edesc with
    Dlevels levs ->
      let levs = Gramext.delete_rule_in_level_list entry sl levs in
      entry.edesc <- Dlevels levs;
      entry.estart <-
        (fun lev strm ->
           let f = start_parser_of_entry entry in
           entry.estart <- f; f lev strm);
      entry.econtinue <-
        (fun lev bp a strm ->
           let f = continue_parser_of_entry entry in
           entry.econtinue <- f; f lev bp a strm)
  | _ -> ()
;;

(* Unsafe *)

let clear_entry e =
  e.estart <- (fun _ (strm__ : _ Stream.t) -> raise Stream.Failure);
  e.econtinue <- (fun _ _ _ (strm__ : _ Stream.t) -> raise Stream.Failure);
  match e.edesc with
    Dlevels _ -> e.edesc <- Dlevels []
  | Dparser _ -> ()
;;

let reinit_gram g lexer = Hashtbl.clear g.gtokens; g.glexer <- lexer;;

module Unsafe =
  struct let clear_entry = clear_entry;; let reinit_gram = reinit_gram;; end
;;

exception EntryFound of g_entry;;
let find_entry e s =
  let rec find_levels levs =
    try
      List.iter (fun lev -> find_tree lev.lsuffix; find_tree lev.lprefix)
        levs;
      raise Not_found
    with
      EntryFound e -> e
    | _ -> raise Not_found
  and find_symbol =
    function
      Snterm e -> if e.ename = s then raise (EntryFound e)
    | Snterml (e, _) -> if e.ename = s then raise (EntryFound e)
    | Slist0 s -> find_symbol s
    | Slist0sep (s, _) -> find_symbol s
    | Slist1 s -> find_symbol s
    | Slist1sep (s, _) -> find_symbol s
    | Sopt s -> find_symbol s
    | Stree t -> find_tree t
    | _ -> ()
  and find_tree =
    function
      Node {node = s; brother = bro; son = son} ->
        find_symbol s; find_tree bro; find_tree son
    | _ -> ()
  in
  match e.edesc with
    Dlevels levs -> find_levels levs
  | Dparser _ -> raise Not_found
;;

let of_entry e = e.egram;;

module Entry =
  struct
    type 'a e = g_entry;;
    let create g n =
      {egram = g; ename = n; estart = empty_entry n;
       econtinue = (fun _ _ _ (strm__ : _ Stream.t) -> raise Stream.Failure);
       edesc = Dlevels []}
    ;;
    let parse (entry : 'a e) cs : 'a =
      Obj.magic (wrap_parse entry (entry.estart 0) cs)
    ;;
    let parse_token (entry : 'a e) ts : 'a = Obj.magic (entry.estart 0 ts);;
    let name e = e.ename;;
    let of_parser g n (p : Token.t Stream.t -> 'a) : 'a e =
      {egram = g; ename = n; estart = (fun _ -> Obj.magic p);
       econtinue = (fun _ _ _ (strm__ : _ Stream.t) -> raise Stream.Failure);
       edesc = Dparser (Obj.magic p)}
    ;;
    external obj : 'a e -> Gramext.g_entry = "%identity";;
    let print e = print_entry (obj e);;
    let find e = Obj.magic (find_entry (obj e));;
  end
;;

let tokens g con =
  let g = grammar_obj g in
  let list = ref [] in
  Hashtbl.iter
    (fun (p_con, p_prm) c -> if p_con = con then list := (p_prm, !c) :: !list)
    g.gtokens;
  !list
;;

let warning_verbose = Gramext.warning_verbose;;

(* Functorial interface *)

module type LexerType = sig val lexer : Token.lexer;; end;;

module type S =
  sig
    type parsable;;
    val parsable : char Stream.t -> parsable;;
    val tokens : string -> (string * int) list;;
    module Entry :
      sig
        type 'a e;;
        val create : string -> 'a e;;
        val parse : 'a e -> parsable -> 'a;;
        val parse_token : 'a e -> Token.t Stream.t -> 'a;;
        val name : 'a e -> string;;
        val of_parser : string -> (Token.t Stream.t -> 'a) -> 'a e;;
        val print : 'a e -> unit;;
        external obj : 'a e -> Gramext.g_entry = "%identity";;
      end
    ;;
    module Unsafe :
      sig
        val reinit_gram : Token.lexer -> unit;;
        val clear_entry : 'a Entry.e -> unit;;
      end
    ;;
    val extend :
      'a Entry.e -> Gramext.position option ->
        (string option * Gramext.g_assoc option *
           (Gramext.g_symbol list * Gramext.g_action) list)
          list ->
        unit;;
    val delete_rule : 'a Entry.e -> Gramext.g_symbol list -> unit;;
  end
;;

module Make (L : LexerType) : S =
  struct
    type parsable =
      char Stream.t * (Token.t Stream.t * Token.location_function)
    ;;
    let gram = create L.lexer;;
    let parsable cs = cs, L.lexer.Token.func cs;;
    let tokens = tokens gram;;
    module Entry =
      struct
        type 'a e = g_entry;;
        let create n =
          {egram = gram; ename = n; estart = empty_entry n;
           econtinue =
             (fun _ _ _ (strm__ : _ Stream.t) -> raise Stream.Failure);
           edesc = Dlevels []}
        ;;
        let parse (e : 'a e) p : 'a =
          Obj.magic (parse_parsable e (e.estart 0) p)
        ;;
        let parse_token (e : 'a e) ts : 'a = Obj.magic (e.estart 0 ts);;
        let name e = e.ename;;
        let of_parser n (p : Token.t Stream.t -> 'a) : 'a e =
          {egram = gram; ename = n; estart = (fun _ -> Obj.magic p);
           econtinue =
             (fun _ _ _ (strm__ : _ Stream.t) -> raise Stream.Failure);
           edesc = Dparser (Obj.magic p)}
        ;;
        external obj : 'a e -> Gramext.g_entry = "%identity";;
        let print e = print_entry (obj e);;
      end
    ;;
    module Unsafe =
      struct
        let reinit_gram = Unsafe.reinit_gram gram;;
        let clear_entry = Unsafe.clear_entry;;
      end
    ;;
    let extend = extend_entry;;
    let delete_rule e r = delete_rule (Entry.obj e) r;;
  end
;;
