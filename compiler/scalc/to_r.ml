(* This file is part of the Catala compiler, a specification language for tax
   and social benefits computation rules. Copyright (C) 2020 Inria, contributor:
   Denis Merigoux <denis.merigoux@inria.fr>

   Licensed under the Apache License, Version 2.0 (the "License"); you may not
   use this file except in compliance with the License. You may obtain a copy of
   the License at

   http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
   WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
   License for the specific language governing permissions and limitations under
   the License. *)

open Catala_utils
open Shared_ast
open Ast
module Runtime = Runtime_ocaml.Runtime
module D = Dcalc.Ast
module L = Lcalc.Ast

let format_lit (fmt : Format.formatter) (l : lit Mark.pos) : unit =
  match Mark.remove l with
  | LBool true -> Format.pp_print_string fmt "TRUE"
  | LBool false -> Format.pp_print_string fmt "FALSE"
  | LInt i ->
    if Z.fits_nativeint i then
      Format.fprintf fmt "catala_integer_from_numeric(%s)"
        (Runtime.integer_to_string i)
    else
      Format.fprintf fmt "catala_integer_from_string(\"%s\")"
        (Runtime.integer_to_string i)
  | LUnit -> Format.pp_print_string fmt "new(\"catala_unit\",v=0)"
  | LRat i ->
    Format.fprintf fmt "catala_decimal_from_fraction(%s,%s)"
      (if Z.fits_nativeint (Q.num i) then Z.to_string (Q.num i)
       else "\"" ^ Z.to_string (Q.num i) ^ "\"")
      (if Z.fits_nativeint (Q.den i) then Z.to_string (Q.den i)
       else "\"" ^ Z.to_string (Q.den i) ^ "\"")
  | LMoney e ->
    if Z.fits_nativeint e then
      Format.fprintf fmt "catala_money_from_cents(%s)"
        (Runtime.integer_to_string (Runtime.money_to_cents e))
    else
      Format.fprintf fmt "catala_money_from_cents(\"%s\")"
        (Runtime.integer_to_string (Runtime.money_to_cents e))
  | LDate d ->
    Format.fprintf fmt "catala_date_from_ymd(%d,%d,%d)"
      (Runtime.integer_to_int (Runtime.year_of_date d))
      (Runtime.integer_to_int (Runtime.month_number_of_date d))
      (Runtime.integer_to_int (Runtime.day_of_month_of_date d))
  | LDuration d ->
    let years, months, days = Runtime.duration_to_years_months_days d in
    Format.fprintf fmt "catala_duration_from_ymd(%d,%d,%d)" years months days

let format_op (fmt : Format.formatter) (op : operator Mark.pos) : unit =
  match Mark.remove op with
  | Log (_entry, _infos) -> assert false
  | Minus_int | Minus_rat | Minus_mon | Minus_dur ->
    Format.pp_print_string fmt "-"
  (* Todo: use the names from [Operator.name] *)
  | Not -> Format.pp_print_string fmt "!"
  | Length -> Format.pp_print_string fmt "catala_list_length"
  | ToRat_int -> Format.pp_print_string fmt "catala_decimal_from_integer"
  | ToRat_mon -> Format.pp_print_string fmt "catala_decimal_from_money"
  | ToMoney_rat -> Format.pp_print_string fmt "catala_money_from_decimal"
  | GetDay -> Format.pp_print_string fmt "catala_day_of_month_of_date"
  | GetMonth -> Format.pp_print_string fmt "catala_month_number_of_date"
  | GetYear -> Format.pp_print_string fmt "catala_year_of_date"
  | FirstDayOfMonth ->
    Format.pp_print_string fmt "catala_date_first_day_of_month"
  | LastDayOfMonth -> Format.pp_print_string fmt "catala_date_last_day_of_month"
  | Round_mon -> Format.pp_print_string fmt "catala_money_round"
  | Round_rat -> Format.pp_print_string fmt "catala_decimal_round"
  | Add_int_int | Add_rat_rat | Add_mon_mon | Add_dat_dur _ | Add_dur_dur
  | Concat ->
    Format.pp_print_string fmt "+"
  | Sub_int_int | Sub_rat_rat | Sub_mon_mon | Sub_dat_dat | Sub_dat_dur
  | Sub_dur_dur ->
    Format.pp_print_string fmt "-"
  | Mult_int_int | Mult_rat_rat | Mult_mon_rat | Mult_dur_int ->
    Format.pp_print_string fmt "*"
  | Div_int_int | Div_rat_rat | Div_mon_mon | Div_mon_rat | Div_dur_dur ->
    Format.pp_print_string fmt "/"
  | And -> Format.pp_print_string fmt "&&"
  | Or -> Format.pp_print_string fmt "||"
  | Eq -> Format.pp_print_string fmt "=="
  | Xor -> Format.pp_print_string fmt "!="
  | Lt_int_int | Lt_rat_rat | Lt_mon_mon | Lt_dat_dat | Lt_dur_dur ->
    Format.pp_print_string fmt "<"
  | Lte_int_int | Lte_rat_rat | Lte_mon_mon | Lte_dat_dat | Lte_dur_dur ->
    Format.pp_print_string fmt "<="
  | Gt_int_int | Gt_rat_rat | Gt_mon_mon | Gt_dat_dat | Gt_dur_dur ->
    Format.pp_print_string fmt ">"
  | Gte_int_int | Gte_rat_rat | Gte_mon_mon | Gte_dat_dat | Gte_dur_dur ->
    Format.pp_print_string fmt ">="
  | Eq_int_int | Eq_rat_rat | Eq_mon_mon | Eq_dat_dat | Eq_dur_dur ->
    Format.pp_print_string fmt "=="
  | Map -> Format.pp_print_string fmt "catala_list_map"
  | Map2 -> Format.pp_print_string fmt "catala_list_map2"
  | Reduce -> Format.pp_print_string fmt "catala_list_reduce"
  | Filter -> Format.pp_print_string fmt "catala_list_filter"
  | Fold -> Format.pp_print_string fmt "catala_list_fold_left"
  | HandleDefault -> Format.pp_print_string fmt "catala_handle_default"
  | HandleDefaultOpt | FromClosureEnv | ToClosureEnv -> failwith "unimplemented"

let format_string_list (fmt : Format.formatter) (uids : string list) : unit =
  let sanitize_quotes = Re.compile (Re.char '"') in
  Format.fprintf fmt "c(%a)"
    (Format.pp_print_list
       ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ")
       (fun fmt info ->
         Format.fprintf fmt "\"%s\""
           (Re.replace sanitize_quotes ~f:(fun _ -> "\\\"") info)))
    uids

let avoid_keywords (s : string) : string =
  if
    match s with
    (* list taken from
       https://cran.r-project.org/doc/manuals/r-release/R-lang.html#Reserved-words *)
    | "if" | "else" | "repeat" | "while" | "function" | "for" | "in" | "next"
    | "break" | "TRUE" | "FALSE" | "NULL" | "Inf" | "NaN" | "NA" | "NA_integer_"
    | "NA_real_" | "NA_complex_" | "NA_character_"
    (* additions of things that are not keywords but that we should not
       overwrite*)
    | "list" | "c" | "character" | "logical" | "complex" | "setClass" | "new" ->
      true
    | _ -> false
  then s ^ "_"
  else s

let format_struct_name (fmt : Format.formatter) (v : StructName.t) : unit =
  Format.fprintf fmt "%s"
    (avoid_keywords
       (String.to_camel_case
          (String.to_ascii (Format.asprintf "%a" StructName.format v))))

let format_struct_field_name (fmt : Format.formatter) (v : StructField.t) : unit
    =
  Format.fprintf fmt "%s"
    (avoid_keywords
       (String.to_ascii (Format.asprintf "%a" StructField.format v)))

let format_enum_name (fmt : Format.formatter) (v : EnumName.t) : unit =
  Format.fprintf fmt "%s"
    (avoid_keywords
       (String.to_camel_case
          (String.to_ascii (Format.asprintf "%a" EnumName.format v))))

let format_enum_cons_name (fmt : Format.formatter) (v : EnumConstructor.t) :
    unit =
  Format.fprintf fmt "%s"
    (avoid_keywords
       (String.to_ascii (Format.asprintf "%a" EnumConstructor.format v)))

let rec format_typ ~inside_comment (fmt : Format.formatter) (typ : typ) : unit =
  let format_typ = format_typ in
  match Mark.remove typ with
  | TLit TUnit -> Format.fprintf fmt "\"catala_unit\""
  | TLit TMoney -> Format.fprintf fmt "\"catala_money\""
  | TLit TInt -> Format.fprintf fmt "\"catala_integer\""
  | TLit TRat -> Format.fprintf fmt "\"catala_decimal\""
  | TLit TDate -> Format.fprintf fmt "\"catala_date\""
  | TLit TDuration -> Format.fprintf fmt "\"catala_duration\""
  | TLit TBool -> Format.fprintf fmt "\"logical\""
  | TTuple ts ->
    Format.fprintf fmt "\"list\"@ # tuple(%a)%t"
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@;")
         (format_typ ~inside_comment:true))
      ts
      (fun fmt -> if inside_comment then () else Format.pp_force_newline fmt ())
  | TStruct s -> Format.fprintf fmt "\"catala_struct_%a\"" format_struct_name s
  | TOption some_typ | TDefault some_typ ->
    (* We loose track of optional value as they're crammed into NULL *)
    format_typ ~inside_comment:false fmt some_typ
  | TEnum e -> Format.fprintf fmt "\"catala_enum_%a\"" format_enum_name e
  | TArrow (t1, t2) ->
    Format.fprintf fmt "\"function\" # %a -> %a%t"
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt ", ")
         (format_typ ~inside_comment:true))
      t1
      (format_typ ~inside_comment:true)
      t2
      (fun fmt -> if inside_comment then () else Format.pp_force_newline fmt ())
  | TArray t1 ->
    Format.fprintf fmt "\"list\" # array(%a)%t"
      (format_typ ~inside_comment:true) t1 (fun fmt ->
        if inside_comment then () else Format.pp_force_newline fmt ())
  | TAny -> Format.fprintf fmt "\"ANY\""
  | TClosureEnv -> failwith "unimplemented!"

let format_name_cleaned (fmt : Format.formatter) (s : string) : unit =
  s
  |> String.to_ascii
  |> String.to_snake_case
  |> Re.Pcre.substitute ~rex:(Re.Pcre.regexp "\\.") ~subst:(fun _ -> "_dot_")
  |> String.to_ascii
  |> avoid_keywords
  |> Format.fprintf fmt "%s"

module StringMap = String.Map

module IntMap = Map.Make (struct
  include Int

  let format ppf i = Format.pp_print_int ppf i
end)

(** For each `VarName.t` defined by its string and then by its hash, we keep
    track of which local integer id we've given it. This is used to keep
    variable naming with low indices rather than one global counter for all
    variables. TODO: should be removed when
    https://github.com/CatalaLang/catala/issues/240 is fixed. *)
let string_counter_map : int IntMap.t StringMap.t ref = ref StringMap.empty

let format_var (fmt : Format.formatter) (v : VarName.t) : unit =
  let v_str = Mark.remove (VarName.get_info v) in
  let id = VarName.id v in
  let local_id =
    match StringMap.find_opt v_str !string_counter_map with
    | Some ids -> (
      match IntMap.find_opt id ids with
      | None ->
        let max_id =
          snd
            (List.hd
               (List.fast_sort
                  (fun (_, x) (_, y) -> Int.compare y x)
                  (IntMap.bindings ids)))
        in
        string_counter_map :=
          StringMap.add v_str
            (IntMap.add id (max_id + 1) ids)
            !string_counter_map;
        max_id + 1
      | Some local_id -> local_id)
    | None ->
      string_counter_map :=
        StringMap.add v_str (IntMap.singleton id 0) !string_counter_map;
      0
  in
  if v_str = "_" then Format.fprintf fmt "dummy_var"
    (* special case for the unit pattern TODO escape dummy_var *)
  else if local_id = 0 then format_name_cleaned fmt v_str
  else Format.fprintf fmt "%a_%d" format_name_cleaned v_str local_id

let format_func_name (fmt : Format.formatter) (v : FuncName.t) : unit =
  let v_str = Mark.remove (FuncName.get_info v) in
  format_name_cleaned fmt v_str

let format_position ppf pos =
  Format.fprintf ppf
    "@[<hov 2>catala_position(@,\
     filename=\"%s\",@ start_line=%d, start_column=%d,@ end_line=%d, \
     end_column=%d,@ law_headings=%a@;\
     <0 -2>)@]" (Pos.get_file pos) (Pos.get_start_line pos)
    (Pos.get_start_column pos) (Pos.get_end_line pos) (Pos.get_end_column pos)
    format_string_list (Pos.get_law_info pos)

let format_error (ppf : Format.formatter) (err : Runtime.error Mark.pos) : unit
    =
  let pos = Mark.get err in
  let tag = String.to_snake_case (Runtime.error_to_string (Mark.remove err)) in
  Format.fprintf ppf "%s(%a)" tag format_position pos

let rec format_expression (ctx : decl_ctx) (fmt : Format.formatter) (e : expr) :
    unit =
  match Mark.remove e with
  | EVar v -> format_var fmt v
  | EFunc f -> format_func_name fmt f
  | EStruct { fields = es; name = s } ->
    Format.fprintf fmt "new(\"catala_struct_%a\",@ %a)" format_struct_name s
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ")
         (fun fmt (struct_field, e) ->
           Format.fprintf fmt "%a = %a" format_struct_field_name struct_field
             (format_expression ctx) e))
      (StructField.Map.bindings es)
  | EStructFieldAccess { e1; field; _ } ->
    Format.fprintf fmt "%a@%a" (format_expression ctx) e1
      format_struct_field_name field
  | EInj { cons; name = e_name; _ }
    when EnumName.equal e_name Expr.option_enum
         && EnumConstructor.equal cons Expr.none_constr ->
    (* We translate the option type with an overloading by R's [NULL] *)
    Format.fprintf fmt "NULL"
  | EInj { e1 = e; cons; name = e_name; _ }
    when EnumName.equal e_name Expr.option_enum
         && EnumConstructor.equal cons Expr.some_constr ->
    (* We translate the option type with an overloading by R's [NULL] *)
    format_expression ctx fmt e
  | EInj { e1 = e; cons; name = enum_name; _ } ->
    Format.fprintf fmt "new(\"catala_enum_%a\", code = \"%a\",@ value = %a)"
      format_enum_name enum_name format_enum_cons_name cons
      (format_expression ctx) e
  | EArray es ->
    Format.fprintf fmt "list(%a)"
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ")
         (fun fmt e -> Format.fprintf fmt "%a" (format_expression ctx) e))
      es
  | ELit l -> Format.fprintf fmt "%a" format_lit (Mark.copy e l)
  | EAppOp { op = ((Map | Filter), _) as op; args = [arg1; arg2] } ->
    Format.fprintf fmt "%a(%a,@ %a)" format_op op (format_expression ctx) arg1
      (format_expression ctx) arg2
  | EAppOp { op; args = [arg1; arg2] } ->
    Format.fprintf fmt "(%a %a@ %a)" (format_expression ctx) arg1 format_op op
      (format_expression ctx) arg2
  | EAppOp { op = (Not, _) as op; args = [arg1] } ->
    Format.fprintf fmt "%a %a" format_op op (format_expression ctx) arg1
  | EAppOp
      {
        op = ((Minus_int | Minus_rat | Minus_mon | Minus_dur), _) as op;
        args = [arg1];
      } ->
    Format.fprintf fmt "%a %a" format_op op (format_expression ctx) arg1
  | EAppOp { op; args = [arg1] } ->
    Format.fprintf fmt "%a(%a)" format_op op (format_expression ctx) arg1
  | EAppOp { op = HandleDefaultOpt, _; _ } ->
    Message.error ~internal:true
      "R compilation does not currently support the avoiding of exceptions"
  | EAppOp { op = (HandleDefault as op), _; args; _ } ->
    let pos = Mark.get e in
    Format.fprintf fmt
      "%a(@[<hov 0>catala_position(filename=\"%s\",@ start_line=%d,@ \
       start_column=%d,@ end_line=%d, end_column=%d,@ law_headings=%a), %a)@]"
      format_op (op, pos) (Pos.get_file pos) (Pos.get_start_line pos)
      (Pos.get_start_column pos) (Pos.get_end_line pos) (Pos.get_end_column pos)
      format_string_list (Pos.get_law_info pos)
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ")
         (format_expression ctx))
      args
  | EApp { f = EFunc x, pos; args }
    when Ast.FuncName.compare x Ast.handle_default = 0
         || Ast.FuncName.compare x Ast.handle_default_opt = 0 ->
    Format.fprintf fmt
      "%a(@[<hov 0>catala_position(filename=\"%s\",@ start_line=%d,@ \
       start_column=%d,@ end_line=%d, end_column=%d,@ law_headings=%a), %a)@]"
      format_func_name x (Pos.get_file pos) (Pos.get_start_line pos)
      (Pos.get_start_column pos) (Pos.get_end_line pos) (Pos.get_end_column pos)
      format_string_list (Pos.get_law_info pos)
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ")
         (format_expression ctx))
      args
  | EApp { f; args } ->
    Format.fprintf fmt "%a(@[<hov 0>%a)@]" (format_expression ctx) f
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ")
         (format_expression ctx))
      args
  | EAppOp { op; args } ->
    Format.fprintf fmt "%a(@[<hov 0>%a)@]" format_op op
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ")
         (format_expression ctx))
      args
  | ETuple args ->
    Format.fprintf fmt "list(@[<hov 0>%a)@]"
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ")
         (format_expression ctx))
      args
  | ETupleAccess { e1; index } ->
    Format.fprintf fmt "(%a)[%d]" (format_expression ctx) e1 index
  | EExternal _ -> failwith "TODO"

let rec format_statement
    (ctx : decl_ctx)
    (fmt : Format.formatter)
    (s : stmt Mark.pos) : unit =
  match Mark.remove s with
  | SInnerFuncDef { name; func = { func_params; func_body; _ } } ->
    Format.fprintf fmt "@[<hov 2>%a <- function(@\n%a) {@\n%a@]@\n}" format_var
      (Mark.remove name)
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt "@\n,@;")
         (fun fmt (var, typ) ->
           Format.fprintf fmt "%a# (%a)@\n" format_var (Mark.remove var)
             (format_typ ~inside_comment:true)
             typ))
      func_params (format_block ctx) func_body
  | SLocalDecl _ ->
    assert false (* We don't need to declare variables in Python *)
  | SLocalDef { name = v; expr = e; _ } | SLocalInit { name = v; expr = e; _ }
    ->
    Format.fprintf fmt "@[<hov 2>%a <- %a@]" format_var (Mark.remove v)
      (format_expression ctx) e
  | STryWEmpty { try_block = try_b; with_block = catch_b } ->
    Format.fprintf fmt
      (* TODO escape dummy__arg*)
      "@[<hov 2>tryCatch(@[<hov 2>{@;\
       %a@;\
       }@],@;\
       catala_empty_error() = function(dummy__arg) @[<hov 2>{@;\
       %a@;\
       }@])@]"
      (format_block ctx) try_b (format_block ctx) catch_b
  | SRaiseEmpty -> Format.pp_print_string fmt "stop(catala_empty_error())"
  | SFatalError err ->
    Format.fprintf fmt "@[<hov 2>stop(%a)@]" format_error (err, Mark.get s)
  | SIfThenElse { if_expr = cond; then_block = b1; else_block = b2 } ->
    Format.fprintf fmt
      "@[<hov 2>if (%a) {@\n%a@]@\n@[<hov 2>} else {@\n%a@]@\n}"
      (format_expression ctx) cond (format_block ctx) b1 (format_block ctx) b2
  | SSwitch
      {
        switch_expr = e1;
        enum_name = e_name;
        switch_cases =
          [
            { case_block = case_none; _ };
            { case_block = case_some; payload_var_name = case_some_var; _ };
          ];
        _;
      }
    when EnumName.equal e_name Expr.option_enum ->
    (* We translate the option type with an overloading by Python's [None] *)
    let tmp_var = VarName.fresh ("perhaps_none_arg", Pos.no_pos) in
    Format.fprintf fmt
      "%a <- %a@\n\
       @[<hov 2>if (is.null(%a)) {@\n\
       %a@]@\n\
       @[<hov 2>} else {@\n\
       %a = %a@\n\
       %a@]@\n\
       }"
      format_var tmp_var (format_expression ctx) e1 format_var tmp_var
      (format_block ctx) case_none format_var case_some_var format_var tmp_var
      (format_block ctx) case_some
  | SSwitch { switch_expr = e1; enum_name = e_name; switch_cases = cases; _ } ->
    let cases =
      List.map2
        (fun x (cons, _) -> x, cons)
        cases
        (EnumConstructor.Map.bindings (EnumName.Map.find e_name ctx.ctx_enums))
    in
    let tmp_var = VarName.fresh ("match_arg", Pos.no_pos) in
    Format.fprintf fmt "@[<hov 2>%a <- %a@]@\n@[<hov 2>if %a@]@\n}" format_var
      tmp_var (format_expression ctx) e1
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt "@]@\n@[<hov 2>} else if ")
         (fun fmt ({ case_block; payload_var_name; _ }, cons_name) ->
           Format.fprintf fmt "(%a@code == \"%a\") {@\n%a <- %a@value@\n%a"
             format_var tmp_var format_enum_cons_name cons_name format_var
             payload_var_name format_var tmp_var (format_block ctx) case_block))
      cases
  | SReturn e1 ->
    Format.fprintf fmt "@[<hov 2>return(%a)@]" (format_expression ctx)
      (e1, Mark.get s)
  | SAssert e1 ->
    let pos = Mark.get s in
    Format.fprintf fmt
      "@[<hov 2>if (!(%a)) {@\n\
       stop(catala_assertion_failure(@[<hov 0>catala_position(@[<hov \
       0>filename=\"%s\",@ start_line=%d,@ start_column=%d,@ end_line=%d,@ \
       end_column=%d,@ law_headings=@[<hv>%a@])@])@])@]@\n\
       }"
      (format_expression ctx)
      (e1, Mark.get s)
      (Pos.get_file pos) (Pos.get_start_line pos) (Pos.get_start_column pos)
      (Pos.get_end_line pos) (Pos.get_end_column pos) format_string_list
      (Pos.get_law_info pos)
  | SSpecialOp _ -> failwith "should not happen"

and format_block (ctx : decl_ctx) (fmt : Format.formatter) (b : block) : unit =
  Format.pp_print_list
    ~pp_sep:(fun fmt () -> Format.fprintf fmt "@\n")
    (format_statement ctx) fmt
    (List.filter
       (fun s -> match Mark.remove s with SLocalDecl _ -> false | _ -> true)
       b)

let format_ctx
    (type_ordering : Scopelang.Dependency.TVertex.t list)
    (fmt : Format.formatter)
    (ctx : decl_ctx) : unit =
  let format_struct_decl fmt (struct_name, struct_fields) =
    let fields = StructField.Map.bindings struct_fields in
    Format.fprintf fmt
      "@[<hov 2>setClass(@,\
       \"catala_struct_%a\",@;\
       representation@[<hov 2>(%a)@]@\n\
       )@]"
      format_struct_name struct_name
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@;")
         (fun fmt (struct_field, typ) ->
           Format.fprintf fmt "%a = %a" format_struct_field_name struct_field
             (format_typ ~inside_comment:false)
             typ))
      fields
  in
  let format_enum_decl fmt (enum_name, enum_cons) =
    if EnumConstructor.Map.is_empty enum_cons then
      failwith "no constructors in the enum"
    else
      Format.fprintf fmt
        "# Enum cases: %a@\n\
         @[<hov 2>setClass(@,\
         \"catala_enum_%a\",@;\
         representation@[<hov 2>(code =@;\
         \"character\",@;\
         value =@;\
         \"ANY\")@])@]"
        (Format.pp_print_list
           ~pp_sep:(fun fmt () -> Format.fprintf fmt ", ")
           (fun fmt (enum_cons, enum_cons_type) ->
             Format.fprintf fmt "\"%a\" (%a)" format_enum_cons_name enum_cons
               (format_typ ~inside_comment:false)
               enum_cons_type))
        (EnumConstructor.Map.bindings enum_cons)
        format_enum_name enum_name
  in

  let is_in_type_ordering s =
    List.exists
      (fun struct_or_enum ->
        match struct_or_enum with
        | Scopelang.Dependency.TVertex.Enum _ -> false
        | Scopelang.Dependency.TVertex.Struct s' -> s = s')
      type_ordering
  in
  let scope_structs =
    List.map
      (fun (s, _) -> Scopelang.Dependency.TVertex.Struct s)
      (StructName.Map.bindings
         (StructName.Map.filter
            (fun s _ -> not (is_in_type_ordering s))
            ctx.ctx_structs))
  in
  List.iter
    (fun struct_or_enum ->
      match struct_or_enum with
      | Scopelang.Dependency.TVertex.Struct s ->
        Format.fprintf fmt "%a@\n@\n" format_struct_decl
          (s, StructName.Map.find s ctx.ctx_structs)
      | Scopelang.Dependency.TVertex.Enum e ->
        Format.fprintf fmt "%a@\n@\n" format_enum_decl
          (e, EnumName.Map.find e ctx.ctx_enums))
    (type_ordering @ scope_structs)

let format_program
    (fmt : Format.formatter)
    (p : Ast.program)
    (type_ordering : Scopelang.Dependency.TVertex.t list) : unit =
  (* We disable the style flag in order to enjoy formatting from the
     pretty-printers of Dcalc and Lcalc but without the color terminal
     markers. *)
  Format.fprintf fmt
    "@[<v># This file has been generated by the Catala compiler, do not edit!@,\
     @,\
     library(catalaRuntime)@,\
     @,\
     @[<v>%a@]@,\
     @,\
     %a@]@?"
    (format_ctx type_ordering) p.ctx.decl_ctx
    (Format.pp_print_list ~pp_sep:Format.pp_print_newline (fun fmt -> function
       | SVar { var; expr; typ = _ } ->
         Format.fprintf fmt "@[<hv 2>%a <- (@,%a@,@])@," format_var var
           (format_expression p.ctx.decl_ctx)
           expr
       | SFunc { var; func }
       | SScope { scope_body_var = var; scope_body_func = func; _ } ->
         let { Ast.func_params; Ast.func_body; _ } = func in
         Format.fprintf fmt "@[<hv 2>%a <- function(@\n%a) {@\n%a@]@\n}@,"
           format_func_name var
           (Format.pp_print_list
              ~pp_sep:(fun fmt () -> Format.fprintf fmt "@\n,@;")
              (fun fmt (var, typ) ->
                Format.fprintf fmt "%a# (%a)@\n" format_var (Mark.remove var)
                  (format_typ ~inside_comment:true)
                  typ))
           func_params
           (format_block p.ctx.decl_ctx)
           func_body))
    p.code_items
