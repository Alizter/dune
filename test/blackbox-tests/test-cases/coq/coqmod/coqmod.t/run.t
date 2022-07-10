Testing the output of coqmod

No file error
  $ coqmod
  Error: No file provided. Please provide a file.

Too many files error
  $ coqmod SomeFile.v SomeOtherFile.v
  Error: Too many files
    provided. Please provide only a single file.

Help screen
  $ coqmod --help
  coqmod - A simple module lexer for Coq
    --debug Output debugging information
    -help  Display this list of options
    --help  Display this list of options

Specification:

## Name
```lisp
  $ cat > FileName.v << EOF
  > EOF
  $ coqmod FileName.v 
  (()()()())
```
## Require
```lisp
  $ cat > Require.v << EOF
  > Require A B.
  > Require B C.
  > EOF
  $ coqmod Require.v 
  ((((((1:11:81:0)(1:11:91:0))1:A))((((1:22:212:13)(1:22:222:13))1:B))((((1:22:232:13)(1:22:242:13))1:C)))()()())
```
## From
```lisp
  $ cat > From.v << EOF
  > From A Require B C.
  > From A Require C D.
  > From R Require E.
  > EOF
  $ coqmod From.v 
  ((((((1:11:51:0)(1:11:61:0))1:A)(((1:12:151:0)(1:12:161:0))1:B))((((1:11:51:0)(1:11:61:0))1:A)(((1:12:171:0)(1:12:181:0))1:C))((((1:22:252:20)(1:22:262:20))1:A)(((1:22:372:20)(1:22:382:20))1:D))((((1:32:452:40)(1:32:462:40))1:R)(((1:32:552:40)(1:32:562:40))1:E)))()()())
```
## Declare
```lisp
  $ cat > Declare.v << EOF
  > Declare ML Module "foo" "bar.baz".
  > Declare ML Module "zoo" "foo".
  > EOF
  $ coqmod Declare.v 
  (()((((1:12:241:0)(1:12:331:0))7:bar.baz)(((1:22:592:35)(1:22:642:35))3:foo)(((1:22:532:35)(1:22:582:35))3:zoo))()())
```
## Load logical
```lisp
  $ cat > LoadLogical.v << EOF
  > Load A.
  > Load B.
  > EOF
  $ coqmod LoadLogical.v 
  ((((((1:11:51:0)(1:11:61:0))1:A))((((1:22:131:8)(1:22:141:8))1:B)))()()())
```
## Load physical
```lisp
  $ cat > LoadPhysical.v << EOF
  > Load "a/b/c".
  > Load "c/d/e".
  > EOF
  $ coqmod LoadPhysical.v 
  (()()((((1:11:51:0)(1:12:121:0))5:a/b/c)(((1:22:192:14)(1:22:262:14))5:c/d/e))())
```
## Extra Dependency
```lisp
  $ cat > ExtraDependency.v << EOF
  > From A Extra Dependency "b/c/d".
  > EOF
  $ coqmod ExtraDependency.v 
  (()()()(((((1:11:51:0)(1:11:61:0))1:A)((1:12:241:0)(1:12:311:0))5:b/c/d)))
```
End specification

Simple Require
  $ cat > B.v << EOF
  > Require Import A.B.
  > EOF
  $ coqmod B.v
  ((((((1:12:151:0)(1:12:181:0))3:A.B)))()()())
  $ coqmod  B.v
  ((((((1:12:151:0)(1:12:181:0))3:A.B)))()()())
  $ coqmod  B.v
  ((((((1:12:151:0)(1:12:181:0))3:A.B)))()()())

Empty file
  $ cat > A.v << EOF
  > EOF
  $ coqmod A.v
  (()()()())

Empty opening brace
  $ cat > EmptyBrace.v << EOF
  > {
  > EOF
  $ coqmod EmptyBrace.v
  (()()()())
  $ cat > EmptyBrace.v << EOF
  > { End.
  > EOF
  $ coqmod EmptyBrace.v
  (()()()())

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
  ((((((1:83:1072:99)(1:83:1082:99))1:A))((((2:103:1303:115)(2:103:1323:115))2:AI))((((1:83:1092:99)(1:83:1102:99))1:B))((((2:103:1333:115)(2:103:1353:115))2:BI))((((1:83:1112:99)(1:83:1122:99))1:C))((((2:103:1363:115)(2:103:1383:115))2:CI))((((1:32:472:42)(1:32:482:42))1:X))((((1:11:51:0)(1:12:101:0))5:A.B.C)(((1:12:301:0)(1:12:351:0))5:L.Y.G))((((1:11:51:0)(1:12:101:0))5:A.B.C)(((1:12:261:0)(1:12:291:0))3:R.X))((((1:11:51:0)(1:12:101:0))5:A.B.C)(((1:12:361:0)(1:12:391:0))3:Z.W)))((((1:62:832:65)(1:62:962:65))11:foo.bar.baz))((((1:42:552:50)(1:42:622:50))5:A/b/c))())
  $ coqmod example.v 
  ((((((1:83:1072:99)(1:83:1082:99))1:A))((((2:103:1303:115)(2:103:1323:115))2:AI))((((1:83:1092:99)(1:83:1102:99))1:B))((((2:103:1333:115)(2:103:1353:115))2:BI))((((1:83:1112:99)(1:83:1122:99))1:C))((((2:103:1363:115)(2:103:1383:115))2:CI))((((1:32:472:42)(1:32:482:42))1:X))((((1:11:51:0)(1:12:101:0))5:A.B.C)(((1:12:301:0)(1:12:351:0))5:L.Y.G))((((1:11:51:0)(1:12:101:0))5:A.B.C)(((1:12:261:0)(1:12:291:0))3:R.X))((((1:11:51:0)(1:12:101:0))5:A.B.C)(((1:12:361:0)(1:12:391:0))3:Z.W)))((((1:62:832:65)(1:62:962:65))11:foo.bar.baz))((((1:42:552:50)(1:42:622:50))5:A/b/c))())
  $ coqmod example.v 
  ((((((1:83:1072:99)(1:83:1082:99))1:A))((((2:103:1303:115)(2:103:1323:115))2:AI))((((1:83:1092:99)(1:83:1102:99))1:B))((((2:103:1333:115)(2:103:1353:115))2:BI))((((1:83:1112:99)(1:83:1122:99))1:C))((((2:103:1363:115)(2:103:1383:115))2:CI))((((1:32:472:42)(1:32:482:42))1:X))((((1:11:51:0)(1:12:101:0))5:A.B.C)(((1:12:301:0)(1:12:351:0))5:L.Y.G))((((1:11:51:0)(1:12:101:0))5:A.B.C)(((1:12:261:0)(1:12:291:0))3:R.X))((((1:11:51:0)(1:12:101:0))5:A.B.C)(((1:12:361:0)(1:12:391:0))3:Z.W)))((((1:62:832:65)(1:62:962:65))11:foo.bar.baz))((((1:42:552:50)(1:42:622:50))5:A/b/c))())

Various mixed dep commands
  $ coqmod TestAll.v --debug
  ((((((2:463:3783:370)(2:463:3793:370))1:A))((((2:523:4043:389)(2:523:4063:389))2:AI))((((2:463:3803:370)(2:463:3813:370))1:B))((((2:523:4073:389)(2:523:4093:389))2:BI))((((2:483:3833:383)(2:483:3843:383))1:C))((((2:523:4103:389)(2:523:4123:389))2:CI))((((2:844:13364:1328)(2:844:13494:1328))13:Category.Core))((((2:864:13924:1384)(2:864:14054:1384))13:Category.Dual))((((2:884:14524:1444)(2:884:14704:1444))18:Category.Morphisms))((((2:814:12694:1254)(2:814:12874:1254))18:Category.Notations))((((2:924:15714:1563)(2:924:15874:1563))16:Category.Objects))((((2:904:15194:1511)(2:904:15334:1511))14:Category.Paths))((((2:964:16944:1686)(2:964:17054:1686))11:Category.Pi))((((2:944:16294:1621)(2:944:16424:1621))13:Category.Prod))((((2:984:17434:1735)(2:984:17574:1735))14:Category.Sigma))((((3:1004:17954:1787)(3:1004:18104:1787))15:Category.Strict))((((3:1234:28154:2807)(3:1234:28354:2807))20:Category.Subcategory))((((3:1024:18544:1846)(3:1024:18664:1846))12:Category.Sum))((((3:1044:19224:1914)(3:1044:19404:1914))18:Category.Univalent))((((3:1404:36204:3612)(3:1404:36334:3612))13:Coq.Init.Byte))((((3:1414:36434:3635)(3:1414:36594:3635))16:Coq.Init.Decimal))((((3:1424:36694:3661)(3:1424:36894:3661))20:Coq.Init.Hexadecimal))((((3:1474:38034:3788)(3:1474:38164:3788))13:Coq.Init.Ltac))((((3:1444:37244:3716)(3:1444:37364:3716))12:Coq.Init.Nat))((((3:1434:36994:3691)(3:1434:37144:3691))15:Coq.Init.Number))((((3:1484:38334:3818)(3:1484:38494:3818))16:Coq.Init.Tactics))((((3:1494:38664:3851)(3:1494:38804:3851))14:Coq.Init.Tauto))((((3:1464:37754:3760)(3:1464:37864:3760))11:Coq.Init.Wf))((((3:1384:35784:3563)(3:1384:35874:3563))9:Datatypes))((((3:1374:35564:3541)(3:1374:35614:3541))5:Logic))((((3:1364:35304:3515)(3:1364:35394:3515))9:Notations))((((3:1454:37534:3738)(3:1454:37584:3738))5:Peano))((((3:1394:36044:3589)(3:1394:36104:3589))6:Specif))((((2:233:1703:165)(2:233:1713:165))1:X))((((2:744:10164:1001)(2:744:10194:1001))3:baz))((((2:563:4743:453)(2:563:4783:453))4:here))((((2:263:2083:188)(2:263:2133:188))5:timed))((((1:62:532:49)(1:62:582:49))5:A.B.C)(((2:112:912:75)(2:112:962:75))5:L.Y.G))((((1:62:532:49)(1:62:582:49))5:A.B.C)(((2:112:872:75)(2:112:902:75))3:R.X))((((1:62:532:49)(1:62:582:49))5:A.B.C)(((2:133:1032:98)(2:133:1062:98))3:Z.W)))((((2:543:4473:415)(2:543:4503:415))1:a)(((2:413:3483:342)(2:413:3573:342))7:bar.baz)(((3:1544:40074:3989)(3:1544:40184:3989))9:cc_plugin)(((3:1554:40384:4020)(3:1554:40574:4020))17:firstorder_plugin)(((2:393:3353:335)(2:393:3403:335))3:foo)(((2:313:2563:249)(2:313:2693:249))11:foo.bar.baz)(((2:433:3613:359)(2:433:3663:359))3:tar))((((2:243:1783:173)(2:243:1853:173))5:A/b/c))(((((2:583:4863:481)(2:583:4893:481))3:foo)((2:583:5073:481)(2:583:5173:481))8:bar/file)((((2:593:5333:519)(2:593:5363:519))3:foz)((2:593:5543:519)(2:593:5643:519))8:baz/file)))
  $ coqmod TestAll.v 
  ((((((2:463:3783:370)(2:463:3793:370))1:A))((((2:523:4043:389)(2:523:4063:389))2:AI))((((2:463:3803:370)(2:463:3813:370))1:B))((((2:523:4073:389)(2:523:4093:389))2:BI))((((2:483:3833:383)(2:483:3843:383))1:C))((((2:523:4103:389)(2:523:4123:389))2:CI))((((2:844:13364:1328)(2:844:13494:1328))13:Category.Core))((((2:864:13924:1384)(2:864:14054:1384))13:Category.Dual))((((2:884:14524:1444)(2:884:14704:1444))18:Category.Morphisms))((((2:814:12694:1254)(2:814:12874:1254))18:Category.Notations))((((2:924:15714:1563)(2:924:15874:1563))16:Category.Objects))((((2:904:15194:1511)(2:904:15334:1511))14:Category.Paths))((((2:964:16944:1686)(2:964:17054:1686))11:Category.Pi))((((2:944:16294:1621)(2:944:16424:1621))13:Category.Prod))((((2:984:17434:1735)(2:984:17574:1735))14:Category.Sigma))((((3:1004:17954:1787)(3:1004:18104:1787))15:Category.Strict))((((3:1234:28154:2807)(3:1234:28354:2807))20:Category.Subcategory))((((3:1024:18544:1846)(3:1024:18664:1846))12:Category.Sum))((((3:1044:19224:1914)(3:1044:19404:1914))18:Category.Univalent))((((3:1404:36204:3612)(3:1404:36334:3612))13:Coq.Init.Byte))((((3:1414:36434:3635)(3:1414:36594:3635))16:Coq.Init.Decimal))((((3:1424:36694:3661)(3:1424:36894:3661))20:Coq.Init.Hexadecimal))((((3:1474:38034:3788)(3:1474:38164:3788))13:Coq.Init.Ltac))((((3:1444:37244:3716)(3:1444:37364:3716))12:Coq.Init.Nat))((((3:1434:36994:3691)(3:1434:37144:3691))15:Coq.Init.Number))((((3:1484:38334:3818)(3:1484:38494:3818))16:Coq.Init.Tactics))((((3:1494:38664:3851)(3:1494:38804:3851))14:Coq.Init.Tauto))((((3:1464:37754:3760)(3:1464:37864:3760))11:Coq.Init.Wf))((((3:1384:35784:3563)(3:1384:35874:3563))9:Datatypes))((((3:1374:35564:3541)(3:1374:35614:3541))5:Logic))((((3:1364:35304:3515)(3:1364:35394:3515))9:Notations))((((3:1454:37534:3738)(3:1454:37584:3738))5:Peano))((((3:1394:36044:3589)(3:1394:36104:3589))6:Specif))((((2:233:1703:165)(2:233:1713:165))1:X))((((2:744:10164:1001)(2:744:10194:1001))3:baz))((((2:563:4743:453)(2:563:4783:453))4:here))((((2:263:2083:188)(2:263:2133:188))5:timed))((((1:62:532:49)(1:62:582:49))5:A.B.C)(((2:112:912:75)(2:112:962:75))5:L.Y.G))((((1:62:532:49)(1:62:582:49))5:A.B.C)(((2:112:872:75)(2:112:902:75))3:R.X))((((1:62:532:49)(1:62:582:49))5:A.B.C)(((2:133:1032:98)(2:133:1062:98))3:Z.W)))((((2:543:4473:415)(2:543:4503:415))1:a)(((2:413:3483:342)(2:413:3573:342))7:bar.baz)(((3:1544:40074:3989)(3:1544:40184:3989))9:cc_plugin)(((3:1554:40384:4020)(3:1554:40574:4020))17:firstorder_plugin)(((2:393:3353:335)(2:393:3403:335))3:foo)(((2:313:2563:249)(2:313:2693:249))11:foo.bar.baz)(((2:433:3613:359)(2:433:3663:359))3:tar))((((2:243:1783:173)(2:243:1853:173))5:A/b/c))(((((2:583:4863:481)(2:583:4893:481))3:foo)((2:583:5073:481)(2:583:5173:481))8:bar/file)((((2:593:5333:519)(2:593:5363:519))3:foz)((2:593:5543:519)(2:593:5643:519))8:baz/file)))
  $ coqmod TestAll.v 
  ((((((2:463:3783:370)(2:463:3793:370))1:A))((((2:523:4043:389)(2:523:4063:389))2:AI))((((2:463:3803:370)(2:463:3813:370))1:B))((((2:523:4073:389)(2:523:4093:389))2:BI))((((2:483:3833:383)(2:483:3843:383))1:C))((((2:523:4103:389)(2:523:4123:389))2:CI))((((2:844:13364:1328)(2:844:13494:1328))13:Category.Core))((((2:864:13924:1384)(2:864:14054:1384))13:Category.Dual))((((2:884:14524:1444)(2:884:14704:1444))18:Category.Morphisms))((((2:814:12694:1254)(2:814:12874:1254))18:Category.Notations))((((2:924:15714:1563)(2:924:15874:1563))16:Category.Objects))((((2:904:15194:1511)(2:904:15334:1511))14:Category.Paths))((((2:964:16944:1686)(2:964:17054:1686))11:Category.Pi))((((2:944:16294:1621)(2:944:16424:1621))13:Category.Prod))((((2:984:17434:1735)(2:984:17574:1735))14:Category.Sigma))((((3:1004:17954:1787)(3:1004:18104:1787))15:Category.Strict))((((3:1234:28154:2807)(3:1234:28354:2807))20:Category.Subcategory))((((3:1024:18544:1846)(3:1024:18664:1846))12:Category.Sum))((((3:1044:19224:1914)(3:1044:19404:1914))18:Category.Univalent))((((3:1404:36204:3612)(3:1404:36334:3612))13:Coq.Init.Byte))((((3:1414:36434:3635)(3:1414:36594:3635))16:Coq.Init.Decimal))((((3:1424:36694:3661)(3:1424:36894:3661))20:Coq.Init.Hexadecimal))((((3:1474:38034:3788)(3:1474:38164:3788))13:Coq.Init.Ltac))((((3:1444:37244:3716)(3:1444:37364:3716))12:Coq.Init.Nat))((((3:1434:36994:3691)(3:1434:37144:3691))15:Coq.Init.Number))((((3:1484:38334:3818)(3:1484:38494:3818))16:Coq.Init.Tactics))((((3:1494:38664:3851)(3:1494:38804:3851))14:Coq.Init.Tauto))((((3:1464:37754:3760)(3:1464:37864:3760))11:Coq.Init.Wf))((((3:1384:35784:3563)(3:1384:35874:3563))9:Datatypes))((((3:1374:35564:3541)(3:1374:35614:3541))5:Logic))((((3:1364:35304:3515)(3:1364:35394:3515))9:Notations))((((3:1454:37534:3738)(3:1454:37584:3738))5:Peano))((((3:1394:36044:3589)(3:1394:36104:3589))6:Specif))((((2:233:1703:165)(2:233:1713:165))1:X))((((2:744:10164:1001)(2:744:10194:1001))3:baz))((((2:563:4743:453)(2:563:4783:453))4:here))((((2:263:2083:188)(2:263:2133:188))5:timed))((((1:62:532:49)(1:62:582:49))5:A.B.C)(((2:112:912:75)(2:112:962:75))5:L.Y.G))((((1:62:532:49)(1:62:582:49))5:A.B.C)(((2:112:872:75)(2:112:902:75))3:R.X))((((1:62:532:49)(1:62:582:49))5:A.B.C)(((2:133:1032:98)(2:133:1062:98))3:Z.W)))((((2:543:4473:415)(2:543:4503:415))1:a)(((2:413:3483:342)(2:413:3573:342))7:bar.baz)(((3:1544:40074:3989)(3:1544:40184:3989))9:cc_plugin)(((3:1554:40384:4020)(3:1554:40574:4020))17:firstorder_plugin)(((2:393:3353:335)(2:393:3403:335))3:foo)(((2:313:2563:249)(2:313:2693:249))11:foo.bar.baz)(((2:433:3613:359)(2:433:3663:359))3:tar))((((2:243:1783:173)(2:243:1853:173))5:A/b/c))(((((2:583:4863:481)(2:583:4893:481))3:foo)((2:583:5073:481)(2:583:5173:481))8:bar/file)((((2:593:5333:519)(2:593:5363:519))3:foz)((2:593:5543:519)(2:593:5643:519))8:baz/file)))
