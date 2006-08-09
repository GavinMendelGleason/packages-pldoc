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

:- module(pldoc_http,
	  [ doc_server/1		% ?Port
	  ]).
:- use_module(library('http/thread_httpd')).
:- use_module(library('http/http_parameters')).
:- use_module(library('http/html_write')).
:- use_module(library('http/mimetype')).
:- use_module(library('debug')).
:- use_module(library(pldoc)).
:- use_module(html).

%:- debug(pldoc).

doc_server(Port) :-
	doc_server(Port,
		   [ workers(1)
		   ]).

doc_server(Port, Options) :-
	prepare_editor,
	http_server(doc_reply,
                    [ port(Port),
                      timeout(60),
		      keep_alive_timeout(1)
                    | Options
                    ]),
	print_message(informational, pldoc(server_started(Port))).

%%	prepare_editor
%
%	Start XPCE as edit requests comming from the document server can
%	only be handled if XPCE is running.

prepare_editor :-
	current_prolog_flag(editor, pce_emacs), !,
	start_emacs.
prepare_editor.


doc_reply(Request) :-
	memberchk(path(Path), Request),
	debug(pldoc, 'HTTP ~q', [Path]),
	reply(Path, Request).

:- discontiguous
	reply/2.

%	/
%	
%	Reply with frameset

reply(/, _) :-
	phrase(html([ head(title('SWI-Prolog documentation server')),
		      frameset([cols('200,*')],
			       [ frame([ src('sidebar.html'),
					 name(sidebar)
				       ]),
				 frame([ src('welcome.html'),
					 name(main)
				       ])
			       ])
		    ]), HTML),
	format('Content-type: text/html~n~n'),
	print_html(HTML).

%	/sidebar.html
%	
%	Reply with main menu.

reply('/sidebar.html', _Request) :- !,
	findall(File, documented_file(File), Files0),
	sort(Files0, Files),
	reply_page('Sidebar',
		   [ p(file),
		     p(\files(Files))
		   ]).

documented_file(File) :-
	pldoc_comment(_, File:_, _, _).

files([]) -->
	[].
files([H|T]) -->
	file(H),
	files(T).

file(File) -->
	{ format(string(FileRef), '/documentation~w', [File]),
	  file_base_name(File, Base),
	  file_directory_name(File, Path),
	  file_base_name(Path, Parent),
	  format(string(Title), '.../~w/~w', [Parent, Base])
	},
	html([ a([target=main, href=FileRef], Title),
	       br([])
	     ]).


%	/file?file=REF
%	
%	Reply using documentation of file

reply('/file', Request) :-
	http_parameters(Request,
			[ file(File, [])
			]),
	format('Content-type: text/html~n~n'),
	doc_for_file(File, current_output, []).

%	/edit?file=REF
%	
%	Start SWI-Prolog editor on file

reply('/edit', Request) :-
	http_parameters(Request,
			[ file(File,     [optional(true)]),
			  module(Module, [optional(true)]),
			  name(Name,     [optional(true)]),
			  arity(Arity,   [integer, optional(true)])
			]),
	format('Content-type: text/html~n~n'),
	(   atom(File)
	->  edit(file(File))
	;   atom(Name), integer(Arity)
	->  (   atom(Module)
	    ->	edit(Module:Name/Arity)
	    ;	edit(Name/Arity)
	    )
	).


%	/documentation/Path
%	
%	Reply documentation of file. Path is   the  absolute path of the
%	file for which to return the  documentation. Extension is either
%	none, the Prolog extension or the HTML extension.
%	
%	Note that we reply  with  pldoc.css   if  the  file  basename is
%	pldoc.css to allow for a relative link from any directory.

reply(ReqPath, Request) :-
	atom_concat('/documentation/', DocPath, ReqPath),
	(   file_base_name(ReqPath, 'pldoc.css')
	->  reply_file(pldoc('pldoc.css'))
	;   http_parameters(Request,
			    [ public_only(Public)
			    ],
			    [ attribute_declarations(param)
			    ]),
	    atom_concat('/', DocPath, AbsFile),
	    pl_file(AbsFile, File),
	    format('Content-type: text/html~n~n'),
	    doc_for_file(File, current_output,
			 [ public_only(Public)
			 ])
	).

%%	pl_file(+File, -PlFile) is det.
%
%	@error existence_error(file, File)

pl_file(File, PlFile) :-
	file_name_extension(Base, html, File), !,
	absolute_file_name(Base,
			   [ file_type(prolog),
			     access(read)
			   ], PlFile).
pl_file(File, File).


%	/welcome.html
%	
%	Initial empty page


reply('/welcome.html', _Request) :- !,
	reply_page('Welcome', []).


%	/pldoc.css
%	
%	Reply the documentation style-sheet.

reply(Path, _Request) :-
	file(Path, LocalFile),
	reply_file(pldoc(LocalFile)).

file('/pldoc.css',   'pldoc.css').
file('/pldoc.js',    'pldoc.js').
file('/edit.gif',    'edit.gif').
file('/zoomin.gif',  'zoomin.gif').
file('/zoomout.gif', 'zoomout.gif').
file('/favicon.ico', 'favicon.ico').


%	/man?predicate=PI
%	
%	Provide documentation from the manual.
%	
%	@tbd	Make link to reference manual.

reply('/man', Request) :-
	http_parameters(Request,
			[ predicate(PI, [])
			]),
	reply_page('SWI-Prolog Reference Manual',
		   [ 'TBD: Documentation for ', b(PI)
		   ]).



		 /*******************************
		 *	       UTIL		*
		 *******************************/

reply_page(Title, Content) :-
	phrase(page(title(Title), Content), HTML),
	format('Content-type: text/html~n~n'),
	print_html(HTML).

reply_file(File) :-
	absolute_file_name(File, Path, [access(read)]),
	file_mime_type(Path, MimeType),
	throw(http_reply(file(MimeType, Path))).


		 /*******************************
		 *     HTTP PARAMETER TYPES	*
		 *******************************/

param(public_only,
      [ oneof([true,false]),
	default(true)
      ]).


		 /*******************************
		 *	     MESSAGES		*
		 *******************************/

:- multifile
	prolog:message/3.

prolog:message(pldoc(server_started(Port))) -->
	[ 'Started Prolog Documentatiuon server at port ~w'-[Port], nl,
	  'You may access the server at http://localhost:~w/'-[Port]
	].


                 /*******************************
                 *        PCEEMACS SUPPORT      *
                 *******************************/

:- multifile
        emacs_prolog_colours:goal_colours/2,
        prolog:called_by/2.


emacs_prolog_colours:goal_colours(reply_page(_, HTML),
                                  built_in-[classify, Colours]) :-
        catch(html_write:html_colours(HTML, Colours), _, fail).

prolog:called_by(reply_page(_, HTML), Called) :-
        catch(phrase(html_write:called_by(HTML), Called), _, fail).
