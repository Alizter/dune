Testing the output of coqmod

No file error
  $ coqmod
  Error: No file provided. Please provide a file.

Too many files error
  $ coqmod SomeFile.v SomeOtherFile.v
  Error: Too many files
    provided. Please provide only a single file.

Invalid format
  $ coqmod --format=foo SomeFile.v
  Error: Unkown output format: foo 

Help screen
  $ coqmod --help
  coqmod - A simple module lexer for Coq
    --format Set output format [csexp|sexp|read]
    --debug Output debugging information
    -help  Display this list of options
    --help  Display this list of options

Specification:

## Name
```lisp
  $ cat > FileName.v << EOF
  > EOF
  $ coqmod FileName.v --format=sexp
  (Document (Name FileName.v))
```
## Require
```lisp
  $ cat > Require.v << EOF
  > Require A B.
  > Require B C.
  > EOF
  $ coqmod Require.v --format=sexp
  (Document
   (Name Require.v)
   (Require
    (((Loc (1 9) (1 10)) A))
    (((Loc (2 9) (2 10)) B))
    (((Loc (2 11) (2 12)) C))))
```
## From
```lisp
  $ cat > From.v << EOF
  > From A Require B C.
  > From A Require C D.
  > From R Require E.
  > EOF
  $ coqmod From.v --format=sexp
  (Document
   (Name From.v)
   (Require
    (((Loc (1 6) (1 7)) A) ((Loc (1 16) (1 17)) B))
    (((Loc (1 6) (1 7)) A) ((Loc (1 18) (1 19)) C))
    (((Loc (2 6) (2 7)) A) ((Loc (2 18) (2 19)) D))
    (((Loc (3 6) (3 7)) R) ((Loc (3 16) (3 17)) E))))
```
## Declare
```lisp
  $ cat > Declare.v << EOF
  > Declare ML Module "foo" "bar.baz".
  > Declare ML Module "zoo" "foo".
  > EOF
  $ coqmod Declare.v --format=sexp
  (Document
   (Name Declare.v)
   (Declare
    ((Loc (1 25) (1 34)) bar.baz)
    ((Loc (2 25) (2 30)) foo)
    ((Loc (2 19) (2 24)) zoo)))
```
## Load logical
```lisp
  $ cat > LoadLogical.v << EOF
  > Load A.
  > Load B.
  > EOF
  $ coqmod LoadLogical.v --format=sexp
  (Document
   (Name LoadLogical.v)
   (Require (((Loc (1 6) (1 7)) A)) (((Loc (2 6) (2 7)) B))))
```
## Load physical
```lisp
  $ cat > LoadPhysical.v << EOF
  > Load "a/b/c".
  > Load "c/d/e".
  > EOF
  $ coqmod LoadPhysical.v --format=sexp
  (Document
   (Name LoadPhysical.v)
   (Load ((Loc (1 6) (1 13)) a/b/c) ((Loc (2 6) (2 13)) c/d/e)))
```
## Extra Dependency
```lisp
  $ cat > ExtraDependency.v << EOF
  > From A Extra Dependency "b/c/d".
  > EOF
  $ coqmod ExtraDependency.v --format=sexp
  (Document
   (Name ExtraDependency.v)
   (ExtraDep (((Loc (1 6) (1 7)) A) (Loc (1 25) (1 32)) b/c/d)))
```
End specification

Simple Require
  $ cat > B.v << EOF
  > Require Import A.B.
  > EOF
  $ coqmod B.v
  (8:Document(4:Name3:B.v)(7:Require(((3:Loc(1:12:16)(1:12:19))3:A.B))))
  $ coqmod --format=read B.v
  Begin B.v
  B.v:1 Require A.B
  End B.v
  $ coqmod --format=sexp B.v
  (Document (Name B.v) (Require (((Loc (1 16) (1 19)) A.B))))

Empty file
  $ cat > A.v << EOF
  > EOF
  $ coqmod A.v
  (8:Document(4:Name3:A.v))

Empty opening brace
  $ cat > EmptyBrace.v << EOF
  > {
  > EOF
  $ coqmod EmptyBrace.v
  File "EmptyBrace.v", line 2, characters 0-0:
  Error: Syntax error during lexing.
  File ended unexpectedly.
  skip_to_dot t
  Hint: Did you forget a "."?
  $ cat > EmptyBrace.v << EOF
  > { End.
  > EOF
  $ coqmod EmptyBrace.v
  (8:Document(4:Name12:EmptyBrace.v))

Abruptly ending a file
  $ cat > AbruptEnd.v << EOF
  > Require Suddenly.End.EOF
  $ coqmod AbruptEnd.v --debug
  File "AbruptEnd.v", line 2, characters 0-0:
  Error: Syntax error during lexing.
  File ended unexpectedly.
  parse_require
  Hint: Did you forget a "."?

Not terminating with a .
  $ cat > ForgotDot.v << EOF
  > Require SomeThing
  > EOF
  $ coqmod ForgotDot.v --debug
  File "ForgotDot.v", line 2, characters 0-0:
  Error: Syntax error during lexing.
  File ended unexpectedly.
  parse_require
  Hint: Did you forget a "."?

README.md example
  $ cat > example.v << EOF
  > From A.B.C Require Import R.X L.Y.G Z.W.
  > 
  > Load X.
  > Load "A/b/c".
  > 
  > Declare ML Module "foo.bar.baz".
  > 
  > Require A B C.
  > 
  > Require Import AI BI CI.
  > EOF

  $ coqmod example.v
  (8:Document(4:Name9:example.v)(7:Require(((3:Loc(1:81:9)(1:82:10))1:A))(((3:Loc(2:102:16)(2:102:18))2:AI))(((3:Loc(1:82:11)(1:82:12))1:B))(((3:Loc(2:102:19)(2:102:21))2:BI))(((3:Loc(1:82:13)(1:82:14))1:C))(((3:Loc(2:102:22)(2:102:24))2:CI))(((3:Loc(1:31:6)(1:31:7))1:X))(((3:Loc(1:11:6)(1:12:11))5:A.B.C)((3:Loc(1:12:31)(1:12:36))5:L.Y.G))(((3:Loc(1:11:6)(1:12:11))5:A.B.C)((3:Loc(1:12:27)(1:12:30))3:R.X))(((3:Loc(1:11:6)(1:12:11))5:A.B.C)((3:Loc(1:12:37)(1:12:40))3:Z.W)))(7:Declare((3:Loc(1:62:19)(1:62:32))11:foo.bar.baz))(4:Load((3:Loc(1:41:6)(1:42:13))5:A/b/c)))
  $ coqmod example.v --format=read
  Begin example.v
  example.v:8 Require A
  example.v:10 Require AI
  example.v:8 Require B
  example.v:10 Require BI
  example.v:8 Require C
  example.v:10 Require CI
  example.v:3 Require X
  example.v:1 From A.B.C example.v:1 Require L.Y.G
  example.v:1 From A.B.C example.v:1 Require R.X
  example.v:1 From A.B.C example.v:1 Require Z.W
  example.v:6 Declare ML Module foo.bar.baz
  example.v:4 Physical "A/b/c"
  End example.v
  $ coqmod example.v --format=sexp
  (Document
   (Name example.v)
   (Require
    (((Loc (8 9) (8 10)) A))
    (((Loc (10 16) (10 18)) AI))
    (((Loc (8 11) (8 12)) B))
    (((Loc (10 19) (10 21)) BI))
    (((Loc (8 13) (8 14)) C))
    (((Loc (10 22) (10 24)) CI))
    (((Loc (3 6) (3 7)) X))
    (((Loc (1 6) (1 11)) A.B.C) ((Loc (1 31) (1 36)) L.Y.G))
    (((Loc (1 6) (1 11)) A.B.C) ((Loc (1 27) (1 30)) R.X))
    (((Loc (1 6) (1 11)) A.B.C) ((Loc (1 37) (1 40)) Z.W)))
   (Declare ((Loc (6 19) (6 32)) foo.bar.baz))
   (Load ((Loc (4 6) (4 13)) A/b/c)))

Various mixed dep commands
  $ coqmod TestAll.v --debug
  (8:Document(4:Name9:TestAll.v)(7:Require(((3:Loc(2:461:9)(2:462:10))1:A))(((3:Loc(2:522:16)(2:522:18))2:AI))(((3:Loc(2:462:11)(2:462:12))1:B))(((3:Loc(2:522:19)(2:522:21))2:BI))(((3:Loc(2:481:1)(2:481:2))1:C))(((3:Loc(2:522:22)(2:522:24))2:CI))(((3:Loc(2:841:9)(2:842:22))13:Category.Core))(((3:Loc(2:861:9)(2:862:22))13:Category.Dual))(((3:Loc(2:881:9)(2:882:27))18:Category.Morphisms))(((3:Loc(2:812:16)(2:812:34))18:Category.Notations))(((3:Loc(2:921:9)(2:922:25))16:Category.Objects))(((3:Loc(2:901:9)(2:902:23))14:Category.Paths))(((3:Loc(2:961:9)(2:962:20))11:Category.Pi))(((3:Loc(2:941:9)(2:942:22))13:Category.Prod))(((3:Loc(2:981:9)(2:982:23))14:Category.Sigma))(((3:Loc(3:1001:9)(3:1002:24))15:Category.Strict))(((3:Loc(3:1231:9)(3:1232:29))20:Category.Subcategory))(((3:Loc(3:1021:9)(3:1022:21))12:Category.Sum))(((3:Loc(3:1041:9)(3:1042:27))18:Category.Univalent))(((3:Loc(3:1401:9)(3:1402:22))13:Coq.Init.Byte))(((3:Loc(3:1411:9)(3:1412:25))16:Coq.Init.Decimal))(((3:Loc(3:1421:9)(3:1422:29))20:Coq.Init.Hexadecimal))(((3:Loc(3:1472:16)(3:1472:29))13:Coq.Init.Ltac))(((3:Loc(3:1441:9)(3:1442:21))12:Coq.Init.Nat))(((3:Loc(3:1431:9)(3:1432:24))15:Coq.Init.Number))(((3:Loc(3:1482:16)(3:1482:32))16:Coq.Init.Tactics))(((3:Loc(3:1492:16)(3:1492:30))14:Coq.Init.Tauto))(((3:Loc(3:1462:16)(3:1462:27))11:Coq.Init.Wf))(((3:Loc(3:1382:16)(3:1382:25))9:Datatypes))(((3:Loc(3:1372:16)(3:1372:21))5:Logic))(((3:Loc(3:1362:16)(3:1362:25))9:Notations))(((3:Loc(3:1452:16)(3:1452:21))5:Peano))(((3:Loc(3:1392:16)(3:1392:22))6:Specif))(((3:Loc(2:231:6)(2:231:7))1:X))(((3:Loc(2:742:16)(2:742:19))3:baz))(((3:Loc(2:562:22)(2:562:26))4:here))(((3:Loc(2:262:21)(2:262:26))5:timed))(((3:Loc(1:61:5)(1:62:10))5:A.B.C)((3:Loc(2:112:17)(2:112:22))5:L.Y.G))(((3:Loc(1:61:5)(1:62:10))5:A.B.C)((3:Loc(2:112:13)(2:112:16))3:R.X))(((3:Loc(1:61:5)(1:62:10))5:A.B.C)((3:Loc(2:131:6)(2:131:9))3:Z.W)))(7:Declare((3:Loc(2:542:33)(2:542:36))1:a)((3:Loc(2:411:7)(2:412:16))7:bar.baz)((3:Loc(3:1542:19)(3:1542:30))9:cc_plugin)((3:Loc(3:1552:19)(3:1552:38))17:firstorder_plugin)((3:Loc(2:391:1)(2:391:6))3:foo)((3:Loc(2:311:8)(2:312:21))11:foo.bar.baz)((3:Loc(2:431:3)(2:431:8))3:tar))(4:Load((3:Loc(2:241:6)(2:242:13))5:A/b/c))(8:ExtraDep(((3:Loc(2:581:6)(2:581:9))3:foo)(3:Loc(2:582:27)(2:582:37))8:bar/file)(((3:Loc(2:592:15)(2:592:18))3:foz)(3:Loc(2:592:36)(2:592:46))8:baz/file)))
  $ coqmod TestAll.v --format=read
  Begin TestAll.v
  TestAll.v:46 Require A
  TestAll.v:52 Require AI
  TestAll.v:46 Require B
  TestAll.v:52 Require BI
  TestAll.v:48 Require C
  TestAll.v:52 Require CI
  TestAll.v:84 Require Category.Core
  TestAll.v:86 Require Category.Dual
  TestAll.v:88 Require Category.Morphisms
  TestAll.v:81 Require Category.Notations
  TestAll.v:92 Require Category.Objects
  TestAll.v:90 Require Category.Paths
  TestAll.v:96 Require Category.Pi
  TestAll.v:94 Require Category.Prod
  TestAll.v:98 Require Category.Sigma
  TestAll.v:100 Require Category.Strict
  TestAll.v:123 Require Category.Subcategory
  TestAll.v:102 Require Category.Sum
  TestAll.v:104 Require Category.Univalent
  TestAll.v:140 Require Coq.Init.Byte
  TestAll.v:141 Require Coq.Init.Decimal
  TestAll.v:142 Require Coq.Init.Hexadecimal
  TestAll.v:147 Require Coq.Init.Ltac
  TestAll.v:144 Require Coq.Init.Nat
  TestAll.v:143 Require Coq.Init.Number
  TestAll.v:148 Require Coq.Init.Tactics
  TestAll.v:149 Require Coq.Init.Tauto
  TestAll.v:146 Require Coq.Init.Wf
  TestAll.v:138 Require Datatypes
  TestAll.v:137 Require Logic
  TestAll.v:136 Require Notations
  TestAll.v:145 Require Peano
  TestAll.v:139 Require Specif
  TestAll.v:23 Require X
  TestAll.v:74 Require baz
  TestAll.v:56 Require here
  TestAll.v:26 Require timed
  TestAll.v:6 From A.B.C TestAll.v:11 Require L.Y.G
  TestAll.v:6 From A.B.C TestAll.v:11 Require R.X
  TestAll.v:6 From A.B.C TestAll.v:13 Require Z.W
  TestAll.v:54 Declare ML Module a
  TestAll.v:41 Declare ML Module bar.baz
  TestAll.v:154 Declare ML Module cc_plugin
  TestAll.v:155 Declare ML Module firstorder_plugin
  TestAll.v:39 Declare ML Module foo
  TestAll.v:31 Declare ML Module foo.bar.baz
  TestAll.v:43 Declare ML Module tar
  TestAll.v:24 Physical "A/b/c"
  TestAll.v:58 From TestAll.v:58 Require foo Extra Dependency "bar/file"
  TestAll.v:59 From TestAll.v:59 Require foz Extra Dependency "baz/file"
  End TestAll.v
  $ coqmod TestAll.v --format=sexp
  (Document
   (Name TestAll.v)
   (Require
    (((Loc (46 9) (46 10)) A))
    (((Loc (52 16) (52 18)) AI))
    (((Loc (46 11) (46 12)) B))
    (((Loc (52 19) (52 21)) BI))
    (((Loc (48 1) (48 2)) C))
    (((Loc (52 22) (52 24)) CI))
    (((Loc (84 9) (84 22)) Category.Core))
    (((Loc (86 9) (86 22)) Category.Dual))
    (((Loc (88 9) (88 27)) Category.Morphisms))
    (((Loc (81 16) (81 34)) Category.Notations))
    (((Loc (92 9) (92 25)) Category.Objects))
    (((Loc (90 9) (90 23)) Category.Paths))
    (((Loc (96 9) (96 20)) Category.Pi))
    (((Loc (94 9) (94 22)) Category.Prod))
    (((Loc (98 9) (98 23)) Category.Sigma))
    (((Loc (100 9) (100 24)) Category.Strict))
    (((Loc (123 9) (123 29)) Category.Subcategory))
    (((Loc (102 9) (102 21)) Category.Sum))
    (((Loc (104 9) (104 27)) Category.Univalent))
    (((Loc (140 9) (140 22)) Coq.Init.Byte))
    (((Loc (141 9) (141 25)) Coq.Init.Decimal))
    (((Loc (142 9) (142 29)) Coq.Init.Hexadecimal))
    (((Loc (147 16) (147 29)) Coq.Init.Ltac))
    (((Loc (144 9) (144 21)) Coq.Init.Nat))
    (((Loc (143 9) (143 24)) Coq.Init.Number))
    (((Loc (148 16) (148 32)) Coq.Init.Tactics))
    (((Loc (149 16) (149 30)) Coq.Init.Tauto))
    (((Loc (146 16) (146 27)) Coq.Init.Wf))
    (((Loc (138 16) (138 25)) Datatypes))
    (((Loc (137 16) (137 21)) Logic))
    (((Loc (136 16) (136 25)) Notations))
    (((Loc (145 16) (145 21)) Peano))
    (((Loc (139 16) (139 22)) Specif))
    (((Loc (23 6) (23 7)) X))
    (((Loc (74 16) (74 19)) baz))
    (((Loc (56 22) (56 26)) here))
    (((Loc (26 21) (26 26)) timed))
    (((Loc (6 5) (6 10)) A.B.C) ((Loc (11 17) (11 22)) L.Y.G))
    (((Loc (6 5) (6 10)) A.B.C) ((Loc (11 13) (11 16)) R.X))
    (((Loc (6 5) (6 10)) A.B.C) ((Loc (13 6) (13 9)) Z.W)))
   (Declare
    ((Loc (54 33) (54 36)) a)
    ((Loc (41 7) (41 16)) bar.baz)
    ((Loc (154 19) (154 30)) cc_plugin)
    ((Loc (155 19) (155 38)) firstorder_plugin)
    ((Loc (39 1) (39 6)) foo)
    ((Loc (31 8) (31 21)) foo.bar.baz)
    ((Loc (43 3) (43 8)) tar))
   (Load ((Loc (24 6) (24 13)) A/b/c))
   (ExtraDep
    (((Loc (58 6) (58 9)) foo) (Loc (58 27) (58 37)) bar/file)
    (((Loc (59 15) (59 18)) foz) (Loc (59 36) (59 46)) baz/file)))
