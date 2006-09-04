/*  $Id$

    Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        wielemak@science.uva.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 1985-2006, University of Amsterdam

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

:- module(pldoc_htmlsrc,
	  [ source_to_html/3,		% +Source, +OutStream, +Options
	    write_source_css/1		% +Stream
	  ]).
:- use_module(library(option)).
:- use_module(doc_colour).
:- use_module(doc_wiki).
:- use_module(library('http/html_write')).

/** <module> HTML source pretty-printer

This module colourises Prolog  source  using   HTML+CSS  using  the same
cross-reference based technology as used by PceEmacs.

	* HTML generation must move to another module
		* Process structured comments here?
*/


%%	source_to_html(+In:filename, +Out, +Options) is det.
%
%	Colourise Prolog source as HTML. The idea is to first create a
%	sequence of fragments and then to apply these to the code.
%	
%	@param In	A filename
%	@param Out	Term stream(Stream) or file-name specification

source_to_html(Src, stream(Out), Options) :- !,
	colour_fragments(Src, Fragments),
	open(Src, read, In),
	file_base_name(Src, Base),
	print_html_head(Out, [title(Base), Options]),
	format(Out, '<pre class="listing">~n', [Out]),
	html_fragments(Fragments, In, Out, [pre(class(listing))], State),
	copy_rest(In, Out, State, State1),
	pop_state(State1, Out),
	print_html_footer(Out, Options).
source_to_html(Src, FileSpec, Options) :-
	absolute_file_name(FileSpec, OutFile, [access(write)]),
	open(OutFile, write, Out, [encoding(utf8)]),
	call_cleanup(source_to_html(Src, stream(Out), Options),
		     close(Out)).

%%	print_html_head(+Out:stream, +Options) is det.
%
%	Print the =DOCTYPE= line and HTML header.  Options:
%	
%		* header(Bool)
%		Only print the header if Bool is not =false=
%		* title(Title)
%		Title of the HTML document
%		* stylesheet(HREF)
%		Reference to the CSS style-sheet.

print_html_head(Out, Options) :-
	option(header(true), Options, true), !,
	option(title(Title), Options, 'Prolog source'),
	option(stylesheet(Sheet), Options, 'pllisting.css'),
	format(Out,
	       '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" \
	       "http://www.w3.org/TR/html4/strict.dtd">~n~n', []),
	format(Out, '<html>~n', []),
	format(Out, '  <head>~n', []),
	format(Out, '    <title>~w</title>~n', [Title]),
	format(Out, '    <link rel="stylesheet" type="text/css" href="~w">~n', [Sheet]),
	format(Out, '  </head>~n', []),
	format(Out, '<body>~n', []).
print_html_head(_, _).

print_html_footer(Out, Options) :-
	option(header(true), Options, true), !,
	format(Out, '~N</body>~n', []),
	format(Out, '</html>', []).
print_html_footer(_, _).


%%	html_fragments(+Fragments, +In, +Out, +State) is det.
%
%	Copy In to Out, inserting HTML elements using Fragments.

html_fragments([], _, _, State, State).
html_fragments([H|T], In, Out, State0, State) :-
	html_fragment(H, In, Out, State0, State1),
	html_fragments(T, In, Out, State1, State).

%%	html_fragment(+Fragment, +In, +Out, +StateIn, -StateOut) is det.
%
%	Print from current position upto the end of Fragment.  First
%	clause deals with structured comments.
%	
%	@tbd	Handle mode decl of structured comment
%	@tbd	copy_to should ensure <pre> state if emoty.
%	@tbd	wiki_string_to_dom/3 to accept code-list

html_fragment(fragment(Start, End, structured_comment, []),
	      In, Out, State0, []) :-
	fail, !,			% TBD
	copy_to(In, Start, Out, State0),
	pop_state(State0, Out),
	Len is End - Start,
	read_n_codes(In, Len, Comment),
	wiki_string_to_dom(Comment, [], DOM0),
	strip_leading_par(DOM0, DOM),
	phrase(html(DOM), Tokens),
	print_html(Out, Tokens).
html_fragment(fragment(Start, End, Class, Sub),
	      In, Out, State0, State) :-
	copy_to(In, Start, Out, State0),
	start_fragment(Class, Out, State0, State1),
	html_fragments(Sub, In, Out, State1, State2),
	copy_to(In, End, Out, State2),	% TBD: pop-to?
	end_fragment(Out, State2, State).

start_fragment(Class, Out, State, [Push|State]) :-
	element(Class, Tag, CSSClass), !,
	Push =.. [Tag,class(CSSClass)],
	format(Out, '<~w class="~w">', [Tag, CSSClass]).
start_fragment(Class, Out, State, [span(class(SpanClass))|State]) :-
	functor(Class, SpanClass, _),
	format(Out, '<span class="~w">', [SpanClass]).

end_fragment(Out, [Open|State], State) :-
	functor(Open, Element, _),
	format(Out, '</~w>', [Element]).

pop_state([], _Out) :- !.
pop_state(State, Out) :-
	end_fragment(Out, State, State1),
	pop_state(State1, Out).


copy_to(In, End, Out, State) :-
	character_count(In, Here),
	Len is End - Here,
	copy_n(Len, In, Out, State).

copy_n(N, In, Out, State) :-
	N > 0,
	get_code(In, Code),
	Code \== -1, !,
	content_escape(Code, Out),
	N2 is N - 1,
	copy_n(N2, In, Out, State).
copy_n(_, _, _, _).


content_escape(0'<, Out) :- !, format(Out, '&lt;', []).
content_escape(0'>, Out) :- !, format(Out, '&gt;', []).
content_escape(0'&, Out) :- !, format(Out, '&amp;', []).	% 0'
content_escape(C, Out) :-
	put_code(Out, C).

copy_rest(In, Out, State, State) :-
	copy_n(1000000000, In, Out, State).

%%	read_n_codes(+In, +N, -Codes)
%
%	Read the next N codes from In as a list of codes.

read_n_codes(_, 0, []) :- !.
read_n_codes(In, N, Codes) :-
	get_code(In, C0),
	read_n_codes(N, C0, In, Codes).

read_n_codes(1, C, _, [C]) :- !.
read_n_codes(N, C, In, [C|T]) :-
	get_code(In, C2),
	N2 is N - 1,
	read_n_codes(N2, C2, In, T).


%%	element(+Class, -HTMLElement, -CSSClass) is nondet.
%
%	Map classified objects to an  HTML   element  and CSS class. The
%	actual  clauses  are  created   from    the   1st   argument  of
%	prolog_src_style/2.

term_expansion(element/3, Clauses) :-
	findall(C, element_clause(C), Clauses).

%element_tag(directive, div) :- !.
element_tag(_, span).

element_clause(element(Term, Tag, CSS)) :-
	span_term(Term, CSS),
	element_tag(Term, Tag).

span_term(Classification, Class) :-
	prolog_src_style(Classification, _Style),
	css_class(Classification, Class).

css_class(Class, Class) :-
	atom(Class), !.
css_class(Term, Class) :-
	Term =.. [P1,A|_],
	(   var(A)
	->  Class = P1
	;   css_class(A, P2),
	    concat_atom([P1, -, P2], Class)
	).

element/3.

%%	write_source_css is det.
%%	write_source_css(+Out:stream) is det.
%
%	Create   a   style-sheet   from    the   style-declarations   in
%	doc_colour.pl    and    the    element     declaration    above.
%	write_style_sheet/0 writes the style-sheet to =|pllisting.css|=.

write_source_css :-
	open('pllisting.css', write, Out),
	call_cleanup(write_source_css(Out),
		     close(Out)).

write_source_css(Out) :-
	(   prolog_src_style(Term, Style0),
	    (	html_style(Term, Style)
	    ->	true
	    ;	Style = Style0
	    ),
	    element(Term2, Tag, Class),
	    Term2 =@= Term,
	    findall(Name=Value, style_attr(Style, Name, Value),
		    [N=V|NV]),
	    format(Out, '~w.~w~n', [Tag, Class]),
	    format(Out, '{ ~w: ~w;~n', [N, V]),
	    forall(member(N2=V2, NV),
		   format(Out, '  ~w: ~w;~n', [N2, V2])),
	    format(Out, '}~n~n', []),
	    fail
	;   true
	).

style_attr(Style, Name, Value) :-
	arg(_, Style, PceName := PceValue),
	pce_to_css_attr(PceName, Name),
	pce_to_css_value(Name, PceValue, Value).

pce_to_css_attr(colour, color).
pce_to_css_attr(background, 'background-color').
pce_to_css_attr(underline, 'text-decoration').
pce_to_css_attr(bold, 'font-weight').
pce_to_css_attr('font-style', 'font-style').

pce_to_css_value(color, Name, RGB) :-
	x11_colour_name_to_rgb(Name, RGB).
pce_to_css_value('background-color', Name, RGB) :-
	x11_colour_name_to_rgb(Name, RGB).
pce_to_css_value('text-decoration', @on, underline).
pce_to_css_value('font-weight', @on, bold).
pce_to_css_value('font-style', Style, Style).

x11_colour_name_to_rgb(red, red) :- !.
x11_colour_name_to_rgb(blue, blue) :- !.
x11_colour_name_to_rgb(Name, RGB) :-
	get(@pce, convert, Name, colour, Obj),
	get(Obj, red, R),
	get(Obj, green, G),
	get(Obj, blue, B),
	R256 is R//256,
	G256 is G//256,
	B256 is B//256,
	format(atom(RGB), 
	       '#~|~`0t~16r~2+~`0t~16r~2+~`0t~16r~2+',
	       [R256, G256, B256]).

%%	html_style(+Term, -Style) is semidet.
%
%	Redefine styles from prolog_src_style/2 for better ones on
%	HTML output.

html_style(var, style(colour := red4,
		      'font-style' := italic)).

	
