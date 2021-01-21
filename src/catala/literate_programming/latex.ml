(* This file is part of the Catala compiler, a specification language for tax and social benefits
   computation rules. Copyright (C) 2020 Inria, contributor: Denis Merigoux
   <denis.merigoux@inria.fr>

   Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
   in compliance with the License. You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software distributed under the License
   is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
   or implied. See the License for the specific language governing permissions and limitations under
   the License. *)

(** This modules weaves the source code and the legislative text together into a document that law
    professionals can understand. *)

open Utils
module A = Surface.Ast
module R = Re.Pcre
module C = Cli

(** {1 Helpers} *)

(** Espaces various LaTeX-sensitive characters *)
let pre_latexify (s : string) =
  let percent = R.regexp "%" in
  let s = R.substitute ~rex:percent ~subst:(fun _ -> "\\%") s in
  let dollar = R.regexp "\\$" in
  let s = R.substitute ~rex:dollar ~subst:(fun _ -> "\\$") s in
  let premier = R.regexp "1er" in
  let s = R.substitute ~rex:premier ~subst:(fun _ -> "1\\textsuperscript{er}") s in
  let underscore = R.regexp "\\_" in
  let s = R.substitute ~rex:underscore ~subst:(fun _ -> "\\_") s in
  s

(** Usage: [wrap_latex source_files custom_pygments language fmt wrapped]

    Prints an LaTeX complete documùent structure around the [wrapped] content. *)
let wrap_latex (source_files : string list) (custom_pygments : string option)
    (language : C.backend_lang) (fmt : Format.formatter) (wrapped : Format.formatter -> unit) =
  Format.fprintf fmt
    "\\documentclass[11pt, a4paper]{article}\n\n\
     \\usepackage[T1]{fontenc}\n\
     \\usepackage[utf8]{inputenc}\n\
     \\usepackage[%s]{babel}\n\
     \\usepackage{lmodern}\n\
     \\usepackage{minted}\n\
     \\usepackage{amssymb}\n\
     \\usepackage{newunicodechar}\n\
     %s\n\
     \\usepackage{textcomp}\n\
     \\usepackage[hidelinks]{hyperref}\n\
     \\usepackage[dvipsnames]{xcolor}\n\
     \\usepackage{fullpage}\n\
     \\usepackage[many]{tcolorbox}\n\n\
     \\newunicodechar{÷}{$\\div$}\n\
     \\newunicodechar{×}{$\\times$}\n\
     \\newunicodechar{≤}{$\\leqslant$}\n\
     \\newunicodechar{≥}{$\\geqslant$}\n\
     \\newunicodechar{→}{$\\rightarrow$}\n\
     \\newunicodechar{≠}{$\\neq$}\n\n\
     \\fvset{\n\
     numbers=left,\n\
     frame=lines,\n\
     framesep=3mm,\n\
     rulecolor=\\color{gray!70},\n\
     firstnumber=last,\n\
     codes={\\catcode`\\$=3\\catcode`\\^=7}\n\
     }\n\n\
     \\title{\n\
     %s\n\
     }\n\
     \\author{\n\
     %s Catala version %s\n\
     }\n\
     \\begin{document}\n\
     \\maketitle\n\n\
     %s : \n\
     \\begin{itemize}%s\\end{itemize}\n\n\
     \\[\\star\\star\\star\\]\\\\\n"
    (match language with `Fr -> "french" | `En -> "english")
    ( match custom_pygments with
    | None -> ""
    | Some p -> Printf.sprintf "\\renewcommand{\\MintedPygmentize}{%s}" p )
    ( match language with
    | `Fr -> "Implémentation de texte législatif"
    | `En -> "Legislative text implementation" )
    (match language with `Fr -> "Document généré par" | `En -> "Document generated by")
    Utils.Cli.version
    ( match language with
    | `Fr -> "Fichiers sources tissés dans ce document"
    | `En -> "Source files weaved in this document" )
    (String.concat ","
       (List.map
          (fun filename ->
            let mtime = (Unix.stat filename).Unix.st_mtime in
            let ltime = Unix.localtime mtime in
            let ftime =
              Printf.sprintf "%d-%02d-%02d, %d:%02d" (1900 + ltime.Unix.tm_year)
                (ltime.Unix.tm_mon + 1) ltime.Unix.tm_mday ltime.Unix.tm_hour ltime.Unix.tm_min
            in
            Printf.sprintf "\\item\\texttt{%s}, %s %s"
              (pre_latexify (Filename.basename filename))
              (match language with `Fr -> "dernière modification le" | `En -> "last modification")
              ftime)
          source_files));
  wrapped fmt;
  Format.fprintf fmt "\n\n\\end{document}"

(** Replaces math operators by their nice unicode counterparts *)
let math_syms_replace (c : string) : string =
  let date = "\\d\\d/\\d\\d/\\d\\d\\d\\d" in
  let syms = R.regexp (date ^ "|!=|<=|>=|--|->|\\*|/") in
  let syms2cmd = function
    | "!=" -> "≠"
    | "<=" -> "≤"
    | ">=" -> "≥"
    | "--" -> "—"
    | "->" -> "→"
    | "*" -> "×"
    | "/" -> "÷"
    | s -> s
  in
  R.substitute ~rex:syms ~subst:syms2cmd c

(** {1 Weaving} *)

let law_article_item_to_latex (language : C.backend_lang) (fmt : Format.formatter)
    (i : A.law_article_item) : unit =
  match i with
  | A.LawText t -> Format.fprintf fmt "%s" (pre_latexify t)
  | A.CodeBlock (_, c) ->
      Format.fprintf fmt
        "\\begin{minted}[label={\\hspace*{\\fill}\\texttt{%s}},firstnumber=%d]{%s}\n\
         /*%s*/\n\
         \\end{minted}"
        (pre_latexify (Filename.basename (Pos.get_file (Pos.get_position c))))
        (Pos.get_start_line (Pos.get_position c) - 1)
        (match language with `Fr -> "catala_fr" | `En -> "catala_en")
        (math_syms_replace (Pos.unmark c))

let rec law_structure_to_latex (language : C.backend_lang) (fmt : Format.formatter)
    (i : A.law_structure) : unit =
  match i with
  | A.LawHeading (heading, children) ->
      Format.fprintf fmt "\\%ssection*{%s}\n\n"
        ( match heading.law_heading_precedence with
        | 0 -> ""
        | 1 -> ""
        | 2 -> "sub"
        | 3 -> "sub"
        | _ -> "subsub" )
        (pre_latexify heading.law_heading_name);
      Format.pp_print_list
        ~pp_sep:(fun fmt () -> Format.fprintf fmt "\n\n")
        (law_structure_to_latex language) fmt children
  | A.LawInclude (A.PdfFile ((file, _), page)) ->
      let label = file ^ match page with None -> "" | Some p -> Format.sprintf "_page_%d," p in
      Format.fprintf fmt
        "\\begin{center}\\textit{Annexe incluse, retranscrite page \\pageref{%s}}\\end{center} \
         \\begin{figure}[p]\\begin{center}\\includegraphics[%swidth=\\textwidth]{%s}\\label{%s}\\end{center}\\end{figure}"
        label
        (match page with None -> "" | Some p -> Format.sprintf "page=%d," p)
        file label
  | A.LawInclude (A.CatalaFile _ | A.LegislativeText _) -> ()
  | A.LawArticle (article, children) ->
      Format.fprintf fmt "\\paragraph{%s}\n\n" (pre_latexify (Pos.unmark article.law_article_name));
      Format.pp_print_list
        ~pp_sep:(fun fmt () -> Format.fprintf fmt "\n")
        (law_article_item_to_latex language)
        fmt children
  | A.MetadataBlock (_, c) ->
      let metadata_title = match language with `Fr -> "Métadonnées" | `En -> "Metadata" in
      Format.fprintf fmt
        "\\begin{tcolorbox}[colframe=OliveGreen, breakable, \
         title=\\textcolor{black}{\\texttt{%s}},title after \
         break=\\textcolor{black}{\\texttt{%s}},before skip=1em, after skip=1em]\n\
         \\begin{minted}[numbersep=9mm, firstnumber=%d, label={\\hspace*{\\fill}\\texttt{%s}}]{%s}\n\
         /*%s*/\n\
         \\end{minted}\n\
         \\end{tcolorbox}"
        metadata_title metadata_title
        (Pos.get_start_line (Pos.get_position c) - 1)
        (pre_latexify (Filename.basename (Pos.get_file (Pos.get_position c))))
        (match language with `Fr -> "catala_fr" | `En -> "catala_en")
        (math_syms_replace (Pos.unmark c))
  | A.IntermediateText t -> Format.fprintf fmt "%s" (pre_latexify t)

let program_item_to_latex (language : C.backend_lang) (fmt : Format.formatter) (i : A.program_item)
    : unit =
  match i with A.LawStructure law_s -> law_structure_to_latex language fmt law_s

(** {1 API} *)

let ast_to_latex (language : C.backend_lang) (fmt : Format.formatter) (program : A.program) : unit =
  Format.pp_print_list
    ~pp_sep:(fun fmt () -> Format.fprintf fmt "\n\n")
    (program_item_to_latex language) fmt program.program_items
