(* This file is part of the Catala compiler, a specification language for tax
   and social benefits computation rules. Copyright (C) 2020-2022 Inria,
   contributor: Denis Merigoux <denis.merigoux@inria.fr>, Alain Delaët-Tixeuil
   <alain.delaet--tixeuil@inria.fr>, Louis Gesbert <louis.gesbert@inria.fr>

   Licensed under the Apache License, Version 2.0 (the "License"); you may not
   use this file except in compliance with the License. You may obtain a copy of
   the License at

   http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
   WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
   License for the specific language governing permissions and limitations under
   the License. *)

(** This module defines generic types for types, literals and expressions shared
    through several of the different ASTs. *)

(* Doesn't define values, so OK to have without an mli *)

open Utils
module Runtime = Runtime_ocaml.Runtime

module ScopeName : Uid.Id with type info = Uid.MarkedString.info =
  Uid.Make (Uid.MarkedString) ()

module StructName : Uid.Id with type info = Uid.MarkedString.info =
  Uid.Make (Uid.MarkedString) ()

module StructFieldName : Uid.Id with type info = Uid.MarkedString.info =
  Uid.Make (Uid.MarkedString) ()

module StructMap : Map.S with type key = StructName.t = Map.Make (StructName)

module EnumName : Uid.Id with type info = Uid.MarkedString.info =
  Uid.Make (Uid.MarkedString) ()

module EnumConstructor : Uid.Id with type info = Uid.MarkedString.info =
  Uid.Make (Uid.MarkedString) ()

module EnumMap : Map.S with type key = EnumName.t = Map.Make (EnumName)

(** Only used by desugared/scopelang *)

module ScopeVar : Uid.Id with type info = Uid.MarkedString.info =
  Uid.Make (Uid.MarkedString) ()

module ScopeVarSet : Set.S with type elt = ScopeVar.t = Set.Make (ScopeVar)
module ScopeVarMap : Map.S with type key = ScopeVar.t = Map.Make (ScopeVar)

module SubScopeName : Uid.Id with type info = Uid.MarkedString.info =
  Uid.Make (Uid.MarkedString) ()

module StructFieldMap : Map.S with type key = StructFieldName.t =
  Map.Make (StructFieldName)

module EnumConstructorMap : Map.S with type key = EnumConstructor.t =
  Map.Make (EnumConstructor)

module StateName : Uid.Id with type info = Uid.MarkedString.info =
  Uid.Make (Uid.MarkedString) ()

(** {1 Abstract syntax tree} *)

(** {2 Types} *)

type typ_lit = TBool | TUnit | TInt | TRat | TMoney | TDate | TDuration

type marked_typ = typ Marked.pos

and typ =
  | TLit of typ_lit
  | TTuple of marked_typ list
  | TStruct of StructName.t
  | TEnum of EnumName.t
  | TOption of marked_typ
  | TArrow of marked_typ * marked_typ
  | TArray of marked_typ
  | TAny

(** {2 Constants and operators} *)

type date = Runtime.date
type duration = Runtime.duration

type op_kind =
  | KInt
  | KRat
  | KMoney
  | KDate
  | KDuration  (** All ops don't have a KDate and KDuration. *)

type ternop = Fold

type binop =
  | And
  | Or
  | Xor
  | Add of op_kind
  | Sub of op_kind
  | Mult of op_kind
  | Div of op_kind
  | Lt of op_kind
  | Lte of op_kind
  | Gt of op_kind
  | Gte of op_kind
  | Eq
  | Neq
  | Map
  | Concat
  | Filter

type log_entry =
  | VarDef of typ
      (** During code generation, we need to know the type of the variable being
          logged for embedding *)
  | BeginCall
  | EndCall
  | PosRecordIfTrueBool

type unop =
  | Not
  | Minus of op_kind
  | Log of log_entry * Uid.MarkedString.info list
  | Length
  | IntToRat
  | MoneyToRat
  | RatToMoney
  | GetDay
  | GetMonth
  | GetYear
  | FirstDayOfMonth
  | LastDayOfMonth
  | RoundMoney
  | RoundDecimal

type operator = Ternop of ternop | Binop of binop | Unop of unop
type except = ConflictError | EmptyError | NoValueProvided | Crash

(** {2 Generic expressions} *)

(** Define a common base type for the expressions in most passes of the compiler *)

type desugared = [ `Desugared ]
type scopelang = [ `Scopelang ]
type dcalc = [ `Dcalc ]
type lcalc = [ `Lcalc ]

(* type scalc = [ `Scalc ] *)

type 'a any = [< desugared | scopelang | dcalc | lcalc ] as 'a

(** Literals are the same throughout compilation except for the [LEmptyError]
    case which is eliminated midway through. *)
type 'a glit =
  | LBool : bool -> 'a glit
  | LEmptyError : [< desugared | scopelang | dcalc ] glit
  | LInt : Runtime.integer -> 'a glit
  | LRat : Runtime.decimal -> 'a glit
  | LMoney : Runtime.money -> 'a glit
  | LUnit : 'a glit
  | LDate : date -> 'a glit
  | LDuration : duration -> 'a glit

(** Locations are handled differently in [desugared] and [scopelang] *)
type 'a glocation =
  | DesugaredScopeVar :
      ScopeVar.t Marked.pos * StateName.t option
      -> desugared glocation
  | ScopelangScopeVar : ScopeVar.t Marked.pos -> scopelang glocation
  | SubScopeVar :
      ScopeName.t * SubScopeName.t Marked.pos * ScopeVar.t Marked.pos
      -> [< desugared | scopelang ] glocation

type ('a, 't) gexpr = (('a, 't) naked_gexpr, 't) Marked.t
(** General expressions: groups all expression cases of the different ASTs, and
    uses a GADT to eliminate irrelevant cases for each one. The ['t] annotations
    are also totally unconstrained at this point. The dcalc exprs, for example,
    are then defined with [type expr = dcalc naked_gexpr] plus the annotations.

    A few tips on using this GADT:

    - To write a function that handles cases from different ASTs, explicit the
      type variables: [fun (type a) (x: a naked_gexpr) -> ...]
    - For recursive functions, you may need to additionally explicit the
      generalisation of the variable: [let rec f: type a . a naked_gexpr -> ...] *)

(** The expressions use the {{:https://lepigre.fr/ocaml-bindlib/} Bindlib}
    library, based on higher-order abstract syntax *)
and ('a, 't) naked_gexpr =
  (* Constructors common to all ASTs *)
  | ELit : 'a glit -> ('a any, 't) naked_gexpr
  | EApp :
      ('a, 't) gexpr * ('a, 't) gexpr list
      -> ('a any, 't) naked_gexpr
  | EOp : operator -> ('a any, 't) naked_gexpr
  | EArray : ('a, 't) gexpr list -> ('a any, 't) naked_gexpr
  (* All but statement calculus *)
  | EVar :
      ('a, 't) naked_gexpr Bindlib.var
      -> (([< desugared | scopelang | dcalc | lcalc ] as 'a), 't) naked_gexpr
  | EAbs :
      (('a, 't) naked_gexpr, ('a, 't) gexpr) Bindlib.mbinder * marked_typ list
      -> (([< desugared | scopelang | dcalc | lcalc ] as 'a), 't) naked_gexpr
  | EIfThenElse :
      ('a, 't) gexpr * ('a, 't) gexpr * ('a, 't) gexpr
      -> (([< desugared | scopelang | dcalc | lcalc ] as 'a), 't) naked_gexpr
  (* Early stages *)
  | ELocation : 'a glocation -> (([< desugared | scopelang ] as 'a), 't) naked_gexpr
  | EStruct :
      StructName.t * ('a, 't) gexpr StructFieldMap.t
      -> (([< desugared | scopelang ] as 'a), 't) naked_gexpr
  | EStructAccess :
      ('a, 't) gexpr * StructFieldName.t * StructName.t
      -> (([< desugared | scopelang ] as 'a), 't) naked_gexpr
  | EEnumInj :
      ('a, 't) gexpr * EnumConstructor.t * EnumName.t
      -> (([< desugared | scopelang ] as 'a), 't) naked_gexpr
  | EMatchS :
      ('a, 't) gexpr
      * EnumName.t
      * ('a, 't) gexpr EnumConstructorMap.t
      -> (([< desugared | scopelang ] as 'a), 't) naked_gexpr
  (* Lambda-like *)
  | ETuple :
      ('a, 't) gexpr list * StructName.t option
      -> (([< dcalc | lcalc ] as 'a), 't) naked_gexpr
  | ETupleAccess :
      ('a, 't) gexpr * int * StructName.t option * marked_typ list
      -> (([< dcalc | lcalc ] as 'a), 't) naked_gexpr
  | EInj :
      ('a, 't) gexpr * int * EnumName.t * marked_typ list
      -> (([< dcalc | lcalc ] as 'a), 't) naked_gexpr
  | EMatch :
      ('a, 't) gexpr * ('a, 't) gexpr list * EnumName.t
      -> (([< dcalc | lcalc ] as 'a), 't) naked_gexpr
  | EAssert : ('a, 't) gexpr -> (([< dcalc | lcalc ] as 'a), 't) naked_gexpr
  (* Default terms *)
  | EDefault :
      ('a, 't) gexpr list * ('a, 't) gexpr * ('a, 't) gexpr
      -> (([< desugared | scopelang | dcalc ] as 'a), 't) naked_gexpr
  | ErrorOnEmpty :
      ('a, 't) gexpr
      -> (([< desugared | scopelang | dcalc ] as 'a), 't) naked_gexpr
  (* Lambda calculus with exceptions *)
  | ERaise : except -> ((lcalc as 'a), 't) naked_gexpr
  | ECatch :
      ('a, 't) gexpr * except * ('a, 't) gexpr
      -> ((lcalc as 'a), 't) naked_gexpr

(* (\* Statement calculus *\)
 * | ESVar: LocalName.t -> (scalc as 'a, 't) naked_gexpr
 * | ESStruct: ('a, 't) gexpr list * StructName.t -> (scalc as 'a, 't) naked_gexpr
 * | ESStructFieldAccess: ('a, 't) gexpr * StructFieldName.t * StructName.t -> (scalc as 'a, 't) naked_gexpr
 * | ESInj: ('a, 't) gexpr * EnumConstructor.t * EnumName.t -> (scalc as 'a, 't) naked_gexpr
 * | ESFunc: TopLevelName.t -> (scalc as 'a, 't) naked_gexpr *)

type 'e anyexpr = 'e constraint 'e = (_ any, _) naked_gexpr
(** Shorter alias for functions taking any kind of expression *)

(** {2 Markings} *)

type untyped = { pos : Pos.t } [@@ocaml.unboxed]
type typed = { pos : Pos.t; ty : marked_typ }

(** The generic type of AST markings. Using a GADT allows functions to be
    polymorphic in the marking, but still do transformations on types when
    appropriate. Expected to fill the ['t] parameter of [naked_gexpr] and
    [gexpr] (a ['t] annotation different from this type is used in the
    middle of the typing processing, but all visible ASTs should otherwise use
    this. *)
type _ mark = Untyped : untyped -> untyped mark | Typed : typed -> typed mark

type 'e marked = ('e, 'm mark) Marked.t constraint 'e = ('a, 'm mark) naked_gexpr
(** [('a, 't) naked_gexpr marked] is equivalent to [('a, 'm mark) gexpr] but
    often more convenient to write since we generally use the type of
    expressions ['e = (_, _ mark) naked_gexpr] as type parameter. *)

(** Useful for errors and printing, for example *)
type any_marked_expr =
  | AnyExpr : (_ any, _ mark) gexpr -> any_marked_expr

(** {2 Higher-level program structure} *)

(** Constructs scopes and programs on top of expressions. The ['e] type
    parameter throughout is expected to match instances of the [naked_gexpr] type
    defined above. Markings are constrained to the [mark] GADT defined above.
    Note that this structure is at the moment only relevant for [dcalc] and
    [lcalc], as [scopelang] has its own scope structure, as the name implies. *)

(** This kind annotation signals that the let-binding respects a structural
    invariant. These invariants concern the shape of the expression in the
    let-binding, and are documented below. *)
type scope_let_kind =
  | DestructuringInputStruct  (** [let x = input.field]*)
  | ScopeVarDefinition  (** [let x = error_on_empty e]*)
  | SubScopeVarDefinition
      (** [let s.x = fun _ -> e] or [let s.x = error_on_empty e] for input-only
          subscope variables. *)
  | CallingSubScope  (** [let result = s ({ x = s.x; y = s.x; ...}) ]*)
  | DestructuringSubScopeResults  (** [let s.x = result.x ]**)
  | Assertion  (** [let _ = assert e]*)

type 'e scope_let = {
  scope_let_kind : scope_let_kind;
  scope_let_typ : marked_typ;
  scope_let_expr : 'e marked;
  scope_let_next : ('e, 'e scope_body_expr) Bindlib.binder;
  scope_let_pos : Pos.t;
}
  constraint 'e = ('a, 'm mark) naked_gexpr
(** This type is parametrized by the expression type so it can be reused in
    later intermediate representations. *)

(** A scope let-binding has all the information necessary to make a proper
    let-binding expression, plus an annotation for the kind of the let-binding
    that comes from the compilation of a {!module: Scopelang.Ast} statement. *)
and 'e scope_body_expr =
  | Result of 'e marked
  | ScopeLet of 'e scope_let
  constraint 'e = ('a, 'm mark) naked_gexpr

type 'e scope_body = {
  scope_body_input_struct : StructName.t;
  scope_body_output_struct : StructName.t;
  scope_body_expr : ('e, 'e scope_body_expr) Bindlib.binder;
}
(** Instead of being a single expression, we give a little more ad-hoc structure
    to the scope body by decomposing it in an ordered list of let-bindings, and
    a result expression that uses the let-binded variables. The first binder is
    the argument of type [scope_body_input_struct]. *)

type 'e scope_def = {
  scope_name : ScopeName.t;
  scope_body : 'e scope_body;
  scope_next : ('e, 'e scopes) Bindlib.binder;
}

(** Finally, we do the same transformation for the whole program for the kinded
    lets. This permit us to use bindlib variables for scopes names. *)
and 'e scopes =
  | Nil
  | ScopeDef of 'e scope_def
  constraint 'e = ('a, 'm mark) naked_gexpr

type struct_ctx = (StructFieldName.t * marked_typ) list StructMap.t
type enum_ctx = (EnumConstructor.t * marked_typ) list EnumMap.t
type decl_ctx = { ctx_enums : enum_ctx; ctx_structs : struct_ctx }
type 'e program = { decl_ctx : decl_ctx; scopes : 'e scopes }
