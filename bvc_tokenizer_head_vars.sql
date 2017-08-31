-----------------------------------------------------------------------------------------
-- Bind Variables Checker: Tokenizer, and Statement Binder
-- Author:      Alberto Dell'Era
-- Copyright:   (c) 2003 - 2017 Alberto Dell'Era http://www.adellera.it
-----------------------------------------------------------------------------------------

type t_int         is table of int index by binary_integer;
type t_varchar2    is table of long index by binary_integer;
type t_varchar2_30 is table of varchar2 (30) index by binary_integer;
