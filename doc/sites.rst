.. _sites:

***************************************
How to Load Additional Files at Runtime
***************************************

.. TODO(diataxis)

   Split between:

   - an how-to guide
   - some reference material

There are many ways for applications to load files at runtime and Dune provides
a well-tested, key-in-hand portable system for doing so. The Dune model works by
defining ``sites`` where files will be installed and looked up at runtime. At
runtime, each site is associated to a list of directories which contain the
files added in the site.

*WARNING*: This feature remains experimental and is subject to breaking changes
without warning. It must be explicitly enabled in the ``dune-project`` file with
``(using dune_site 0.1)``

Sites
=====

Defining a Site
---------------

A site is defined in a package :doc:`/reference/dune-project/package` in the
``dune-project`` file. It consists of a name and a :doc:`section
</reference/dune/install>` (e.g ``lib``, ``share``, ``etc``) where the site
will be installed as a sub-directory.

.. code:: dune

   (lang dune 3.20)
   (using dune_site 0.1)
   (name mygui)

   (package
    (name mygui)
    (sites (share themes)))

Adding Files to a Site
----------------------

Here the package ``mygui`` defines a site named ``themes`` that will be located
in the section ``share``. This package can add files to this ``site`` using the
:doc:`install stanza </reference/dune/install>`:

.. code:: dune

   (install
    (section (site (mygui themes)))
    (files
     (layout.css as default/layout.css)
     (ok.png  as default/ok.png)
     (ko.png  as default/ko.png)))

Another package ``mygui_material_theme`` can install files inside ``mygui``
directory for adding a new theme. Inside the scope of ``mygui_material_theme``
the ``dune`` file contains:

.. code:: dune

   (install
    (section (site mygui themes))
    (files
     (layout.css as material/layout.css)
     (ok.png  as material/ok.png)
     (ko.png  as material/ko.png)))

The package ``mygui`` must be present in the workspace or installed.

.. warning::

   Two files should not be installed by different packages at the same destination.

Getting the Locations of a Site at Runtime
------------------------------------------

The executable ``mygui`` will be able to get the locations of the ``themes``
site using the :doc:`generate_sites_module stanza
</reference/dune/generate_sites_module>`.

.. code:: dune

   (executable
    (name mygui)
    (modules mygui mysites)
    (libraries dune-site))

   (generate_sites_module
    (module mysites)
    (sites mygui))

The generated module ``mysites`` depends on the library ``dune-site`` provided
by Dune. As such, the the dependency on ``dune-site`` must be specified
explicitly.

.. note::

   The dependency on ``dune-site`` also needs to be added to the ``depends``
   field of your project. If left out it might be accidentally captured via
   transitive dependencies, however this will not work if
   :doc:`implicit_transitive_deps </reference/dune-project/implicit_transitive_deps>`
   is set to ``false`` in the ``dune-project`` file. It is always recommended
   to specify ``dune-site`` as a dependency explicitly.

Then inside ``mygui.ml`` module the locations can be recovered and used:

.. code:: ocaml

   (** Locations of the site for the themes *)
   let themes_locations : string list = Mysites.Sites.themes

   (** Merge the contents of the directories in [dirs] *)
   let lookup_dirs dirs =
     List.filter Sys.file_exists dirs
     |> List.map (fun dir -> Array.to_list (Sys.readdir dir))
     |> List.concat

   (** Get the available themes *)
   let find_available_themes () = lookup_dirs themes_locations

   (** [lookup_file name dirs] finds the first file called [name] in [dirs] *)
   let lookup_file filename dirs =
     List.find_map
       (fun dir ->
         let filename' = Filename.concat dir filename in
         if Sys.file_exists filename' then Some filename' else None)
       dirs

   (** [lookup_theme_file theme file] get the [file] of the [theme] *)
   let lookup_theme_file file theme =
     lookup_file (Filename.concat theme file) themes_locations

   let get_layout_css = lookup_theme_file "layout.css"
   let get_ok_ico = lookup_theme_file "ok.png"
   let get_ko_ico = lookup_theme_file "ko.png"


Tests
-----

During tests, the files are copied into the sites through the dependency
``(package mygui)`` and ``(package mygui_material_theme)`` as for other files in
install stanza.

Installation
------------

Installation is done simply with ``dune install``; however, if one wants to
install this tool to make it relocatable, one can use ``dune
install --relocatable --prefix $dir``. The files will be copied to the directory
``$dir`` but the binary ``$dir/bin/mygui`` will find the site location relative
to its location. So even if the directory ``$dir`` is moved,
``themes_locations`` will be correct.

For installation through opam, ``dune install`` must be invoked with the option
``--create-install-files`` which creates an install file ``<pkg>.install`` and
copy the file that needs substitution to an intermediary directory. The
``<pkg>.opam`` file generated by Dune
:doc:`/reference/dune-project/generate_opam_files` does the right
invocation.

Implementation Details
----------------------

The main difficulty for sites is that their directories are found at different
locations at different times:

- When the package is available locally, the location is inside ``_build``
- When the package is installed, the location is inside the install prefix
- If a local package wants to install files to the site of another installed
  package the location is at the same time in ``_build`` and in the install prefix
  of the second package.

With the last example, we see that the location of a site is not always a single
directory, but rather it can consist of a sequence of directories: ``["dir1" ; "dir2"]``.
So a lookup must first look into `dir1`, then into `dir2`.

.. _plugins:

Plugins and Dynamic Loading of Packages
========================================

Dune allows you to define and load plugins without having to deal with specific
compilation, installation directories, dependencies, or the ``Dynlink_`` module.

To define a plugin:

- The package defining the plugin interface must define a `site` where the
  plugins must live. Traditionally, this is in ``(lib plugins)``, but it's just
  a convention.

- Define a library that each plugin must use to register itself (or otherwise
  provide its functionality).

- Define the plugin in another package using the `plugin` stanza.

- Generate a module that may load all available plugins using the
  `generated_module` stanza.

Example
-------

We demonstrate an example of the scheme above. The example consists of the
following components:

Inside package `app`:

- An executable `app`, that we intend to extend with plugins

- A library `app.registration` which defines the plugin registration interface

- A generated module `Sites` which can load available plugins at runtime

- An executable `app` that will use the module `Sites` to load all the plugins

Inside package `Plugin1`, we declare a plugin using the `app.registration` api and the
`plugin` stanza.

Directory structure
^^^^^^^^^^^^^^^^^^^

.. code::

  .
  ├── app.ml
  ├── dune
  ├── dune-project
  ├── plugin
  │   ├── dune
  │   ├── dune-project
  │   └── plugin1_impl.ml
  └── registration.ml


Main Executable (C)
^^^^^^^^^^^^^^^^^^^^^

- The ``dune-project`` file:

.. code:: dune

  (lang dune 3.20)
  (using dune_site 0.1)
  (name app)

  (package
    (name app)
    (sites (lib plugins)))


- The ``dune`` file:

.. code:: dune

  (executable
    (public_name app)
    (modules sites app)
    (libraries app.register dune-site dune-site.plugins))

  (library
    (public_name app.register)
    (name registration)
    (modules registration))

  (generate_sites_module
  (module sites)
  (plugins (app plugins)))

The generated module `sites` depends here also on the library
`dune-site.plugins` because the `plugins` optional field is requested.

If the executable being created is an OCaml toplevel, then the
``libraries`` stanza needs to also include the ``dune-site.toplevel``
library.  This causes the loading to use the toplevel's normal loading
mechanism rather than ``Dynload.loadfile`` (which is not allowed in
toplevels).

- The module ``registration.ml`` of the library ``app.registration``:

.. code:: ocaml

  let todo : (unit -> unit) Queue.t = Queue.create ()

- The code of the executable ``app.ml``:

.. code:: ocaml

  (* load all the available plugins *)
  let () = Sites.Plugins.Plugins.load_all ()

  let () = print_endline "Main app starts..."
  (* Execute the code registered by the plugins *)
  let () = Queue.iter (fun f -> f ()) Registration.todo

The Plugin "plugin1"
^^^^^^^^^^^^^^^^^^^^

- The ``plugin/dune-project`` file:

.. code:: dune

  (lang dune 3.20)
  (using dune_site 0.1)

  (generate_opam_files true)

  (package
    (name plugin1))


- The ``plugin/dune`` file:

.. code:: dune

  (library
    (public_name plugin1.plugin1_impl)
    (name plugin1_impl)
    (modules plugin1_impl)
    (libraries app.register))

  (plugin
    (name plugin1)
    (libraries plugin1.plugin1_impl)
    (site (app plugins)))



- The code of the plugin ``plugin/plugin1_impl.ml``:

.. code:: ocaml

  let () =
    print_endline "Registration of Plugin1";
    Queue.add (fun () -> print_endline "Plugin1 is doing something...") Registration.todo

Running the Example
^^^^^^^^^^^^^^^^^^^

.. code:: console

  $ dune build @install && dune exec ./app.exe
  Registration of Plugin1
  Main app starts...
  Plugin1 is doing something...



.. _Dynlink: https://caml.inria.fr/pub/docs/manual-ocaml/libref/Dynlink.html
