/*  $Id$

    Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        wielemak@science.uva.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 2007, University of Amsterdam

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(pldoc_latex,
	  [ doc_latex/3,		% +Items, +OutFile, +Options
	    latex_for_file/3,		% +FileSpec, +Out, +Options
	    latex_for_wiki_file/3,	% +FileSpec, +Out, +Options
	    latex_for_predicates/3	% +PI, +Out, +Options
	  ]).
:- use_module(library(readutil)).
:- use_module(library(error)).
:- use_module(library(option)).
:- use_module(library(lists)).
:- use_module(library(debug)).
:- use_module(doc_wiki).
:- use_module(doc_process).
:- use_module(doc_modes).
:- use_module(doc_html,			% we cannot import all as the
	      [ doc_file_objects/5,	% \commands have the same name
		doc_tag_title/2,
		existing_linked_file/2,
		pred_anchor_name/3,
		private/2,
		is_pi/1
	      ]).

/** <module> PlDoc LaTeX backend

This  module  translates  the  Herbrand   term  from  the  documentation
extracting module doc_wiki.pl into a  LaTeX   document  for  us with the
pl.sty LaTeX style file. The function of  this module is very similar to
doc_html.pl, providing the HTML backend,  and the implementation follows
the same paradigm. The module can

	* Generate LaTeX documentation for a Prolog file, both for
	printing and embedding in a larger document using
	latex_for_file/3.

	* Generate LaTeX from a Wiki file using latex_for_wiki_file/3
	
	* Generate LaTeX for a single predicate or a list of predicates
	for embedding in a document using latex_for_predicates/3.

@tbd See TODO
@author Jan Wielemaker
*/

:- thread_local
	options/1.

current_options(Options) :-
	options(Current), !,
	Options = Current.
current_options([]).

%%	doc_latex(+Spec, +OutFile, +Options) is det.
%
%	Process one or  more  objects,  writing   the  LaTeX  output  to
%	OutFile.  Spec is one of:
%	
%		* Name/Arity
%		Generate documentation for predicate
%		
%		* Name//Arity
%		Generate documentation for DCG rule
%		
%		* File
%		If File is a prolog file (as defined by
%		prolog_file_type/2), process using latex_for_file/3,
%		otherwise process using latex_for_wiki_file/3
%		
%	Typically Spec is either a  list  of   filenames  or  a  list of
%	predicate indicators. 
	

doc_latex(Spec, OutFile, Options) :-
	asserta(options(Options), Ref),
	call_cleanup(phrase(process_items(Spec, [body], Options), Tokens),
		     erase(Ref)),
	open(OutFile, write, Out),
	call_cleanup(print_latex(Out, Tokens, Options),
		     close(Out)).

process_items([], Mode, _) --> !,
	pop_mode(body, Mode, _).
process_items([H|T], Mode, Options) -->
	process_items(H, Mode, Mode1, Options),
	process_items(T, Mode1, Options).
process_items(Spec, Mode, Options) -->
	{Mode = [Mode0|_]},
	process_items(Spec, Mode, Mode1, Options),
	pop_mode(Mode0, Mode1, _).

process_items(PI, Mode0, Mode, Options) -->
	{ is_pi(PI) }, !,
	need_mode(description, Mode0, Mode),
	latex_tokens_for_predicates(PI, Options).
process_items(FileSpec, Mode0, Mode, Options) -->
	{   (   absolute_file_name(FileSpec,
				   [ file_type(prolog),
				     access(read),
				     file_errors(fail)
				   ],
				   File)
	    ->  true
	    ;	absolute_file_name(FileSpec,
				   [ access(read)
				   ],
				   File)
	    ),
	    file_name_extension(_Base, Ext, File)
	},
	need_mode(body, Mode0, Mode),
	(   { prolog_file_type(Ext, prolog) }
	->  latex_tokens_for_file(File, Options)
	;   latex_tokens_for_wiki_file(File, Options)
	).


%%	latex_for_file(+File, +Out, +Options) is det.
%
%	Generate a LaTeX description of all commented predicates in
%	File, writing the LaTeX text to the stream Out. Options:
%	
%		* stand_alone(+Bool)
%		If =true= (default), create a document that can be run
%		through LaTeX.  If =false=, produce a document to be
%		included in another LaTeX document.
%		
%		* public_only(+Bool)
%		If =true= (default), only emit documentation for
%		exported predicates.
%		
%		* section_level(+Level)
%		Outermost section level produced. Level is the
%		name of a LaTeX section command.  Default is =section=.

latex_for_file(FileSpec, Out, Options) :-
	phrase(latex_tokens_for_file(FileSpec, Options), Tokens),
	print_latex(Out, Tokens, Options).


%%	latex_tokens_for_file(+FileSpec, +Options)//

latex_tokens_for_file(FileSpec, Options, Tokens, Tail) :-
	absolute_file_name(FileSpec,
			   [ file_type(prolog),
			     access(read)
			   ],
			   File),
	doc_file_objects(FileSpec, File, Objects, FileOptions, Options),
	asserta(options(Options), Ref),
	call_cleanup(phrase(latex([ \file_header(File, FileOptions)
				  | \objects(Objects, FileOptions)
				  ]),
			    Tokens, Tail),
		     erase(Ref)).


%%	latex_for_wiki_file(+File, +Out, +Options) is det.
%
%	Write a LaTeX translation of a Wiki file to the steam Out.
%	Options:
%	
%		* public_only(+Bool)
%		If =true= (default), only emit documentation for
%		exported predicates.
%		
%		* section_level(+Level)
%		Outermost section level produced. Level is the
%		name of a LaTeX section command.  Default is =section=.

latex_for_wiki_file(FileSpec, Out, Options) :-
	phrase(latex_tokens_for_wiki_file(FileSpec, Options), Tokens),
	print_latex(Out, Tokens, Options).

latex_tokens_for_wiki_file(FileSpec, Options, Tokens, Tail) :-
	absolute_file_name(FileSpec, File,
			   [ access(read)
			   ]),
	read_file_to_codes(File, String, []),
	b_setval(pldoc_file, File),
	asserta(options(Options), Ref),
	call_cleanup((wiki_string_to_dom(String, [], DOM),
		      phrase(latex(DOM), Tokens, Tail)
		     ),
		     (nb_delete(pldoc_file),
		      erase(Ref))).


%%	latex_for_predicates(+PI:list, +Out, +Options) is det.
%
%	Generate LaTeX for a list  of   predicate  indicators. This does
%	*not*   produce   the    \begin{description}...\end{description}
%	environment, just a plain list   of \predicate, etc. statements.
%	The current implementation ignores Options.

latex_for_predicates(Spec, Out, Options) :-
	phrase(latex_tokens_for_predicates(Spec, Options), Tokens),
	print_latex(Out, [nl_exact(0)|Tokens], Options).

latex_tokens_for_predicates([], _Options) --> !.
latex_tokens_for_predicates([H|T], Options) --> !,
	latex_tokens_for_predicates(H, Options),
	latex_tokens_for_predicates(T, Options).
latex_tokens_for_predicates(PI, Options) -->
	{ PI = _:_/_, !,
	  (   doc_comment(PI, Pos, _Summary, Comment)
	  ->  true
	  ;   Comment = ''
	  )
	},
	object(PI, Pos, Comment, [description], _, Options).
latex_tokens_for_predicates(Spec, Options) -->
	{ findall(PI, documented_pi(Spec, PI), List),
	  (   List == []
	  ->  print_message(warning, pldoc(no_predicates_from(Spec)))
	  ;   true
	  )
	},
	latex_tokens_for_predicates(List, Options).

documented_pi(Spec, PI) :-
	generalise_spec(Spec, PI),
	doc_comment(PI, _Pos, _Summary, _Comment).

generalise_spec(Name/Arity, _M:Name/Arity).
generalise_spec(Name//Arity, _M:Name//Arity).


		 /*******************************
		 *	 LATEX PRODUCTION	*
		 *******************************/

:- thread_local
	fragile/0.			% provided when in fragile mode

latex([]) --> !,
	[].
latex(Atomic) -->
	{ atomic(Atomic), !,
	  findall(x, sub_atom(Atomic, _, _, _, '\n'), Xs),
	  length(Xs, Lines)
	},
	(   {Lines == 0}
	->  [ Atomic ]
	;   [ nl(Lines) ]
	).
latex([H|T]) -->
	(   latex(H)
	->  latex(T)
	;   { print_message(error, latex(failed(H))) },
	    latex(T)
	).

% high level commands
latex(h1(_Class, Content)) -->
	latex_section(0, Content).
latex(h2(_Class, Content)) -->
	latex_section(1, Content).
latex(h3(_Class, Content)) -->
	latex_section(2, Content).
latex(h4(_Class, Content)) -->
	latex_section(3, Content).
latex(p(Content)) -->
	[ nl_exact(2) ],
	latex(Content).
latex(a(Attrs, Content)) -->
	{ attribute(href(HREF), Attrs) },
	(   {HREF == Content}
	->  latex(cmd(url(HREF)))
	;   latex(cmd(url(opt(Content), HREF)))
	).
latex(code(CodeList)) -->
	{ is_list(CodeList), !,
	  concat_atom(CodeList, Atom)
	},
	[ verb(Atom) ].
latex(code(Code)) -->
	{ identifier(Code) }, !,
	latex(cmd(const(Code))).
latex(code(Code)) -->
	[ verb(Code) ].
latex(b(Code)) -->
	latex(cmd(textbf(Code))).
latex(i(Code)) -->
	latex(cmd(textit(Code))).
latex(var(Var)) -->
	latex(cmd(arg(Var))).
latex(pre(_Class, Code)) -->
	[ code(Code) ].
latex(ul(Content)) -->
	latex(cmd(begin(itemize))),
	latex(Content),
	latex(cmd(end(itemize))).
latex(ol(Content)) -->
	latex(cmd(begin(enumerate))),
	latex(Content),
	latex(cmd(end(enumerate))).
latex(li(Content)) -->
	latex(cmd(item)),
	latex(Content).
latex(dl(_, Content)) -->
	latex(cmd(begin(description))),
	latex(Content),
	latex(cmd(end(description))).
latex(dd(_, Content)) -->
	latex(Content).
latex(dd(Content)) -->
	latex(Content).
latex(dt(class=term, \term(Term, Bindings))) --> 
	termitem(Term, Bindings).
latex(\Cmd, List, Tail) :-
	call(Cmd, List, Tail).

% low level commands
latex(latex(Text)) -->
	[ latex(Text) ].
latex(cmd(Term)) -->
	{ Term =.. [Cmd|Args] },
	indent(Cmd),
	[ cmd(Cmd) ],
	latex_arguments(Args),
	outdent(Cmd).

indent(begin) --> !,	       [ nl(2) ].
indent(end) --> !,	       [ nl_exact(1) ].
indent(section) --> !,	       [ nl(2) ].
indent(subsection) --> !,      [ nl(2) ].
indent(subsubsection) --> !,   [ nl(2) ].
indent(item) --> !,	       [ nl(1), indent(4) ].
indent(definition) --> !,      [ nl(1), indent(4) ].
indent(tag) --> !,	       [ nl(1), indent(4) ].
indent(termitem) --> !,	       [ nl(1), indent(4) ].
indent(prefixtermitem) --> !,  [ nl(1), indent(4) ].
indent(infixtermitem) --> !,   [ nl(1), indent(4) ].
indent(postfixtermitem) --> !, [ nl(1), indent(4) ].
indent(predicate) --> !,       [ nl(1), indent(4) ].
indent(dcg) --> !,	       [ nl(1), indent(4) ].
indent(infixop) --> !,	       [ nl(1), indent(4) ].
indent(prefixop) --> !,	       [ nl(1), indent(4) ].
indent(postfixop) --> !,       [ nl(1), indent(4) ].
indent(_) -->		       [].

outdent(begin) --> !,		[ nl_exact(1) ].
outdent(end) --> !,		[ nl(2) ].
outdent(item) --> !,		[ ' ' ].
outdent(tag) --> !,		[ nl(1) ].
outdent(termitem) --> !,	[ nl(1) ].
outdent(prefixtermitem) --> !,	[ nl(1) ].
outdent(infixtermitem) --> !,	[ nl(1) ].
outdent(postfixtermitem) --> !,	[ nl(1) ].
outdent(definition) --> !,	[ nl(1) ].
outdent(section) --> !,		[ nl(2) ].
outdent(subsection) --> !,	[ nl(2) ].
outdent(subsubsection) --> !,	[ nl(2) ].
outdent(predicate) --> !,	[ nl(1) ].
outdent(dcg) --> !,		[ nl(1) ].
outdent(infixop) --> !,		[ nl(1) ].
outdent(prefixop) --> !,	[ nl(1) ].
outdent(postfixop) --> !,	[ nl(1) ].
outdent(_) -->			[].

%%	latex_arguments(+Args:list)// is det.
%
%	Write LaTeX command arguments. If  an   argument  is of the form
%	opt(Arg) it is written as  [Arg],   Otherwise  it  is written as
%	{Arg}. Note that opt([]) is omitted. I think no LaTeX command is
%	designed to handle an empty optional argument special.
%	
%	During processing the arguments it asserts fragile/0 to allow is
%	taking care of LaTeX fragile   constructs  (i.e. constructs that
%	are not allows inside {...}).

latex_arguments(List, Out, Tail) :-
	asserta(fragile, Ref),
	call_cleanup(fragile_list(List, Out, Tail),
		     erase(Ref)).
	
fragile_list([]) --> [].
fragile_list([opt([])|T]) --> !,
	fragile_list(T).
fragile_list([opt(H)|T]) --> !,
	[ '[' ],
	latex(H),
	[ ']' ],
	fragile_list(T).
fragile_list([H|T]) -->
	[ curl(open) ],
	latex(H),
	[ curl(close) ],
	fragile_list(T).


attribute(Att, Attrs) :-
	is_list(Attrs), !,
	option(Att, Attrs).
attribute(Att, One) :-
	option(Att, [One]).

%%	latex_section(+Level, +Content)// is det.
%
%	Emit a LaTeX section,  keeping  track   of  the  desired highest
%	section level.
%	
%	@param Level	Desired level, relative to the base-level.  Must
%			be a non-negative integer.

latex_section(Level, Content) -->
	{ current_options(Options),
	  option(section_level(LaTexSection), Options, section),
	  latex_section_level(LaTexSection, BaseLevel),
	  FinalLevel is BaseLevel+Level,
	  (   latex_section_level(SectionCommand, FinalLevel)
	  ->  Term =.. [SectionCommand, Content]
	  ;   domain_error(latex_section_level, FinalLevel)
	  )
	},
	latex(cmd(Term)).

latex_section_level(chapter,	   0).
latex_section_level(section,	   1).
latex_section_level(subsection,	   2).
latex_section_level(subsubsection, 3).
latex_section_level(paragraph,	   4).

deepen_section_level(Level0, Level1) :-
	latex_section_level(Level0, N),
	N1 is N + 1,
	latex_section_level(Level1, N1).


		 /*******************************
		 *	   \ COMMANDS		*
		 *******************************/

%%	include(+File, +Type)// is det.
%
%	Called from [[File]].

include(PI, predicate) --> !,
	(   latex_tokens_for_predicates(PI, [])
	->  []
	;   latex(cmd(item(['[[', \predref(PI), ']]'])))
	).
include(File, Type) -->
	{ existing_linked_file(File, Path) }, !,
	include_file(Path, Type).
include(File, _) -->
	latex(code(['[[', File, ']]'])).

include_file(Path, image) --> !,
	latex(cmd(includegraphics(Path))).
include_file(Path, Type) -->
	{ assertion(memberchk(Type, [prolog,wiki])),
	  current_options(Options0),
	  select_option(stand_alone(_), Options0, Options1, _),
	  select_option(section_level(Level0), Options1, Options2, section),
	  deepen_section_level(Level0, Level),
	  Options = [stand_alone(false), section_level(Level)|Options2]
	},
	(   {Type == prolog}
	->  latex_tokens_for_file(Path, Options)
	;   latex_tokens_for_wiki_file(Path, Options)
	).

%%	file(+File)// is det.
%
%	Called from implicitely linked files.  The HTML version creates
%	a hyperlink.  We just name the file.

file(File) -->
	{ fragile }, !,
	latex(cmd(texttt(File))).
file(File) -->
	latex(cmd(file(File))).

%%	predref(+PI)// is det.
%
%	Called  from  name/arity  or   name//arity    patterns   in  the
%	documentation.

predref(Name/Arity) -->
	latex(cmd(predref(Name, Arity))).
predref(Name//Arity) -->
	latex(cmd(dcgref(Name, Arity))).

%%	tags(+Tags:list(Tag)) is det.
%
%	Emit tag list produced by the   Wiki processor from the @keyword
%	commands.

tags([\params(Params)|Rest]) --> !,
	params(Params),
	tags_list(Rest).
tags(List) -->
	tags_list(List).

tags_list([]) -->
	[].
tags_list(List) -->
	[ nl(2) ],
	latex(cmd(begin(tags))),
	latex(List),
	latex(cmd(end(tags))),
	[ nl(2) ].

%%	tag(+Tag, +Value)// is det.
%
%	Called from \tag(Name, Value) terms produced by doc_wiki.pl.

tag(Tag, Value) -->
	{ doc_tag_title(Tag, Title) },
	latex([cmd(tag(Title)), Value]).


%%	params(+Params:list) is det.
%
%	Called from \params(List) created by   doc_wiki.pl.  Params is a
%	list of param(Name, Descr).

params(Params) -->
	latex([ cmd(begin(parameters)),
		\param_list(Params),
		cmd(end(parameters))
	      ]).

param_list([]) -->
	[].
param_list([H|T]) -->
	param(H),
	param_list(T).

param(param(Name,Descr)) -->
	[ nl(1) ],
	latex(cmd(arg(Name))), [ latex(' & ') ],
	latex(Descr), [latex(' \\\\')].

%%	file_header(+File, +Options)// is det.
%
%	Create the file header.

file_header(File, Options) -->
	{ memberchk(file(Title, Comment), Options), !,
	  file_base_name(File, Base)
	},
	file_title([Base, ' -- ', Title], File, Options),
	{ is_structured_comment(Comment, Prefixes),
	  indented_lines(Comment, Prefixes, Lines),
	  section_comment_header(Lines, _Header, Lines1),
	  wiki_lines_to_dom(Lines1, [], DOM)
	},
	latex(DOM),
	latex(cmd(vspace('0.7cm'))).
file_header(File, Options) -->
	{ file_base_name(File, Base)
	},
	file_title([Base], File, Options).


%%	file_title(+Title:list, +File, +Options)// is det
%
%	Emit the file-header and manipulation buttons.

file_title(Title, _File, Options) -->
	{ option(section_level(Level), Options, section),
	  Section =.. [Level,Title]
	},
	latex(cmd(Section)).


%%	objects(+Objects:list, +Options)// is det.
%
%	Emit the documentation body.

objects(Objects, Options) -->
	objects(Objects, [body], Options).

objects([], Mode, _) -->
	pop_mode(body, Mode, _).
objects([Obj|T], Mode, Options) -->
	object(Obj, Mode, Mode1, Options),
	objects(T, Mode1, Options).

object(doc(Obj,Pos,Comment), Mode0, Mode, Options) --> !,
	object(Obj, Pos, Comment, Mode0, Mode, Options).
object(Obj, Mode0, Mode, Options) -->
	{ doc_comment(Obj, Pos, _Summary, Comment)
	}, !,
	object(Obj, Pos, Comment, Mode0, Mode, Options).

object(Obj, Pos, Comment, Mode0, Mode, Options) -->
	{ is_pi(Obj), !,
	  is_structured_comment(Comment, Prefixes),
	  indented_lines(Comment, Prefixes, Lines),
	  process_modes(Lines, Pos, Modes, Args, Lines1),
	  (   private(Obj, Options)
	  ->  Class = privdef		% private definition
	  ;   Class = pubdef		% public definition
	  ),
	  (   Obj = Module:_
	  ->  POptions = [module(Module)|Options]
	  ;   POptions = Options
	  ),
	  DOM = [\pred_dt(Modes, Class, POptions), dd(class=defbody, DOM1)],
	  wiki_lines_to_dom(Lines1, Args, DOM0),
	  strip_leading_par(DOM0, DOM1)
	},
	need_mode(description, Mode0, Mode),
	latex(DOM).
object([Obj|_Same], Pos, Comment, Mode0, Mode, Options) --> !,
	object(Obj, Pos, Comment, Mode0, Mode, Options).
object(Obj, _Pos, _Comment, Mode, Mode, _Options) -->
	{ debug(pldoc, 'Skipped ~p', [Obj]) },
	[].
	

%%	need_mode(+Mode:atom, +Stack:list, -NewStack:list)// is det.
%
%	While predicates are part of a   description  list, sections are
%	not and we therefore  need  to   insert  <dl>...</dl>  into  the
%	output. We do so by demanding  an outer environment and push/pop
%	the required elements.

need_mode(Mode, Stack, Stack) -->
	{ Stack = [Mode|_] }, !,
	[].
need_mode(Mode, Stack, Rest) -->
	{ memberchk(Mode, Stack)
	}, !,
	pop_mode(Mode, Stack, Rest).	
need_mode(Mode, Stack, [Mode|Stack]) --> !,
	latex(cmd(begin(Mode))).

pop_mode(Mode, Stack, Stack) -->
	{ Stack = [Mode|_] }, !,
	[].
pop_mode(Mode, [H|Rest0], Rest) -->
	latex(cmd(end(H))),
	pop_mode(Mode, Rest0, Rest).


%%	pred_dt(+Modes, +Class, Options)// is det.
%
%	Emit the \predicate{}{}{} header.
%	
%	@param Modes	List as returned by process_modes/5.
%	@param Class	One of =privdef= or =pubdef=.
%	
%	@tbd	Determinism

pred_dt(Modes, Class, Options) -->
	[nl(2)],
	pred_dt(Modes, [], _Done, [class(Class)|Options]).

pred_dt([], Done, Done, _) -->
	[].
pred_dt([H|T], Done0, Done, Options) -->
	pred_mode(H, Done0, Done1, Options),
	(   {T == []}
	->  []
	;   latex(cmd(nodescription)),
	    pred_dt(T, Done1, Done, Options)
	).

pred_mode(mode(Head,Vars), Done0, Done, Options) --> !,
	{ bind_vars(Head, Vars) },
	pred_mode(Head, Done0, Done, Options).
pred_mode(Head is Det, Done0, Done, Options) --> !,
	anchored_pred_head(Head, Done0, Done, [det(Det)|Options]).
pred_mode(Head, Done0, Done, Options) -->
	anchored_pred_head(Head, Done0, Done, Options).

bind_vars(Term, Bindings) :-
	bind_vars(Bindings),
	anon_vars(Term).

bind_vars([]).
bind_vars([Name=Var|T]) :-
	Var = '$VAR'(Name),
	bind_vars(T).

%%	anon_vars(+Term) is det.
%
%	Bind remaining variables in Term to '$VAR'('_'), so they are
%	printed as '_'.

anon_vars(Var) :-
	var(Var), !,
	Var = '$VAR'('_').
anon_vars(Term) :-
	compound(Term), !,
	Term =.. [_|Args],
	maplist(anon_vars, Args).
anon_vars(_).


anchored_pred_head(Head, Done0, Done, Options) -->
	{ pred_anchor_name(Head, PI, _Name) },
	(   { memberchk(PI, Done0) }
	->  { Done = Done0 },
	    pred_head(Head, Options)
	;   { Done = [PI|Done0] }
	),
	pred_head(Head, Options).


%%	pred_head(+Term, Options) is det.
%
%	Emit a predicate head. The functor is  typeset as a =span= using
%	class =pred= and the arguments and =var= using class =arglist=.
%	
%	@tbd Support determinism in operators

pred_head(//(Head), Options) --> !,
	{ pred_attributes(Options, Atts),
	  Head =.. [Functor|Args],
	  length(Args, Arity)
	},
	latex(cmd(dcg(opt(Atts), Functor, Arity, \pred_args(Args, 1)))).
pred_head(Head, _Options) -->			% Infix operators
	{ Head =.. [Functor,Left,Right],
	  is_op(Functor, infix), !
	},
	latex(cmd(infixop(Functor, \pred_arg(Left, 1), \pred_arg(Right, 2)))).
pred_head(Head, _Options) -->			% Prefix operators
	{ Head =.. [Functor,Arg],
	  is_op(Functor, prefix), !
	},
	latex(cmd(prefixop(Functor, \pred_arg(Arg, 1)))).
pred_head(Head, _Options) -->			% Postfix operators
	{ Head =.. [Functor,Arg],
	  is_op(Functor, postfix), !
	},
	latex(cmd(postfixop(Functor, \pred_arg(Arg, 1)))).
pred_head(Head, Options) -->			% Plain terms
	{ pred_attributes(Options, Atts),
	  Head =.. [Functor|Args],
	  length(Args, Arity)
	},
	latex(cmd(predicate(opt(Atts), 
			    Functor, Arity, \pred_args(Args, 1)))).

%%	pred_attributes(+Options, -Attributes) is det.
%
%	Create a comma-separated list of   predicate attributes, such as
%	determinism, etc.

pred_attributes(Options, Attrs) :-
	findall(A, pred_att(Options, A), As),
	insert_comma(As, Attrs).

pred_att(Options, Det) :-
	option(det(Det), Options).
pred_att(Options, private) :-
	option(class(privdef), Options).

insert_comma([H1,H2|T0], [H1, ','|T]) :- !,
	insert_comma([H2|T0], T).
insert_comma(L, L).


is_op(Functor, Type) :-
	current_op(_Pri, F, Functor),
	op_type(F, Type).

op_type(fx,  prefix).
op_type(fy,  prefix).
op_type(xf,  postfix).
op_type(yf,  postfix).
op_type(xfx, infix).
op_type(xfy, infix).
op_type(yfx, infix).
op_type(yfy, infix).


pred_args([], _) -->
	[].
pred_args([H|T], I) -->
	pred_arg(H, I),
	(   {T==[]}
	->  []
	;   latex(', '),
	    { I2 is I + 1 },
	    pred_args(T, I2)
	).

pred_arg(Var, I) -->
	{ var(Var) }, !,
	latex(['Arg', I]).
pred_arg(...(Term), I) --> !,
	pred_arg(Term, I),
	latex(cmd(ldots)).
pred_arg(Term, I) -->
	{ Term =.. [Ind,Arg],
	  mode_indicator(Ind)
	}, !,
	latex([Ind, \pred_arg(Arg, I)]).
pred_arg(Arg:Type, _) --> !,
	latex([\argname(Arg), :, \argtype(Type)]).
pred_arg(Arg, _) -->
	argname(Arg).

argname('$VAR'(Name)) --> !,
	latex(Name).
argname(Name) --> !,
	latex(Name).

argtype(Term) -->
	{ format(string(S), '~W',
		 [ Term,
		   [ quoted(true),
		     numbervars(true)
		   ]
		 ]) },
	latex(S).

%%	term(+Term, +Bindings)// is det.
%
%	Process the \term element as produced by doc_wiki.pl.
%	
%	@tbd	Properly merge with pred_head//1

term(Term, Bindings) -->
	{ bind_vars(Bindings) },
	term(Term).

term('$VAR'(Name)) --> !,
	latex(cmd(arg(Name))).
term(Compound) -->
	{ callable(Compound), !,
	  Compound =.. [Functor|Args]
	}, !,
	term_with_args(Functor, Args).
term(Rest) -->
	latex(Rest).

term_with_args(Functor, [Left, Right]) -->
	{ is_op(Functor, infix) }, !,
	latex(cmd(infixterm(Functor, \term(Left), \term(Right)))).
term_with_args(Functor, [Arg]) -->
	{ is_op(Functor, prefix) }, !,
	latex(cmd(prefixterm(Functor, \term(Arg)))).
term_with_args(Functor, [Arg]) -->
	{ is_op(Functor, postfix) }, !,
	latex(cmd(postfixterm(Functor, \term(Arg)))).
term_with_args(Functor, Args) -->
	latex(cmd(term(Functor, \pred_args(Args, 1)))).


%%	termitem(+Term, +Bindings)// is det.
%
%	Create a termitem or one of its variations.

termitem(Term, Bindings) -->
	{ bind_vars(Bindings) },
	termitem(Term).

termitem('$VAR'(Name)) --> !,
	latex(cmd(termitem(var(Name), ''))).
termitem(Compound) -->
	{ callable(Compound), !,
	  Compound =.. [Functor|Args]
	}, !,
	termitem_with_args(Functor, Args).
termitem(Rest) -->
	latex(cmd(termitem(Rest, ''))).

termitem_with_args(Functor, [Left, Right]) -->
	{ is_op(Functor, infix) }, !,
	latex(cmd(infixtermitem(Functor, \term(Left), \term(Right)))).
termitem_with_args(Functor, [Arg]) -->
	{ is_op(Functor, prefix) }, !,
	latex(cmd(prefixtermitem(Functor, \term(Arg)))).
termitem_with_args(Functor, [Arg]) -->
	{ is_op(Functor, postfix) }, !,
	latex(cmd(postfixtermitem(Functor, \term(Arg)))).
termitem_with_args(Functor, Args) -->
	latex(cmd(termitem(Functor, \pred_args(Args, 1)))).


		 /*******************************
		 *	    PRINT TOKENS	*
		 *******************************/

print_latex(Out, Tokens, Options) :-
	latex_header(Out, Options),
	print_latex_tokens(Tokens, Out),
	latex_footer(Out, Options).


%%	print_latex_tokens(+Tokens, +Out)
%
%	Print primitive LaTeX tokens to Output

print_latex_tokens([], _).
print_latex_tokens([nl(N)|T0], Out) :- !,
	max_nl(T0, T, N, NL),
	nl(Out, NL),
	print_latex_tokens(T, Out).
print_latex_tokens([nl_exact(N)|T0], Out) :- !,
	nl_exact(T0, T,N, NL),
	nl(Out, NL),
	print_latex_tokens(T, Out).
print_latex_tokens([H|T], Out) :-
	print_latex_token(H, Out),
	print_latex_tokens(T, Out).

print_latex_token(cmd(Cmd), Out) :- !,
	format(Out, '\\~w', [Cmd]).
print_latex_token(curl(open), Out) :- !,
	format(Out, '{', []).
print_latex_token(curl(close), Out) :- !,
	format(Out, '}', []).
print_latex_token(indent(N), Out) :- !,
	format(Out, '~t~*|', [N]).
print_latex_token(nl(N), Out) :- !,
	format(Out, '~N', []),
	forall(between(2,N,_), nl(Out)).
print_latex_token(verb(Verb), Out) :-
	is_list(Verb), Verb \== [], !,
	concat_atom(Verb, Atom),
	print_latex_token(verb(Atom), Out).
print_latex_token(verb(Verb), Out) :- !,
	(   member(C, [$,'|',@,=,'"',^,!]),
	    \+ sub_atom(Verb, _, _, _, C)
	->  format(Out, '\\verb~w~w~w', [C,Verb,C])
	;   assertion(fail)
	).
print_latex_token(code(Code), Out) :- !,
	format(Out, '~N\\begin{code}~n', []),
	format(Out, '~w', [Code]),
	format(Out, '~N\\end{code}~n', []).
print_latex_token(latex(Code), Out) :- !,
	write(Out, Code).
print_latex_token(Rest, Out) :-
	(   atomic(Rest)
	->  print_latex(Out, Rest)
	;   %type_error(latex_token, Rest)
	    write(Out, Rest)
	).

%%	print_latex(+Out, +Text:atomic) is det.
%
%	Print Text, such that it comes out as normal LaTeX text.

print_latex(Out, String) :-
	atom_chars(String, Chars),
	print_chars(Chars, Out).

print_chars([], _).
print_chars([H|T], Out) :-
	print_char(H, Out),
	print_chars(T, Out).


%%	max_nl(T0, T, M0, M)
%
%	Remove leading sequence of nl(N) and return the maximum of it.

max_nl([nl(M1)|T0], T, M0, M) :- !,
	M2 is max(M1, M0),
	max_nl(T0, T, M2, M).
max_nl([nl_exact(M1)|T0], T, _, M) :- !,
	nl_exact(T0, T, M1, M).
max_nl(T, T, M, M).

nl_exact([nl(_)|T0], T, M0, M) :- !,
	max_nl(T0, T, M0, M).
nl_exact([nl_exact(M1)|T0], T, M0, M) :- !,
	M2 is max(M1, M0),
	max_nl(T0, T, M2, M).
nl_exact(T, T, M, M).


nl(Out, N) :-
	forall(between(1, N, _), nl(Out)).


print_char('<', Out) :- !, write(Out, '$<$').
print_char('>', Out) :- !, write(Out, '$>$').
print_char('{', Out) :- !, write(Out, '\\{').
print_char('}', Out) :- !, write(Out, '\\}').
print_char('$', Out) :- !, write(Out, '\\$').
print_char('#', Out) :- !, write(Out, '\\#').
print_char('\\',Out) :- !, write(Out, '\\bsl{}').
print_char(C,   Out) :- put_char(Out, C).


%%	identifier(+Atom) is semidet.
%
%	True if Atom is (lower, alnum*).

identifier(Atom) :-
	atom_chars(Atom, [C0|Chars]),
	char_type(C0, lower),
	all_chartype(Chars, alnum).

all_chartype([], _).
all_chartype([H|T], Type) :-
	char_type(H, Type),
	all_chartype(T, Type).


		 /*******************************
		 *	   HEADER/FOOTER	*
		 *******************************/

latex_header(Out, Options) :-
	(   option(stand_alone(true), Options, true)
	->  forall(header(Line), format(Out, '~w~n', [Line]))
	;   true
	).

latex_footer(Out, Options) :-
	(   option(stand_alone(true), Options, true)
	->  forall(footer(Line), format(Out, '~w~n', [Line]))
	;   true
	).

header('\\documentclass[11pt]{article}').
header('\\usepackage{times}').
header('\\usepackage{pl}').
header('\\sloppy').
header('\\makeindex').
header('').
header('\\begin{document}').

footer('').
footer('\\printindex').
footer('\\end{document}').
