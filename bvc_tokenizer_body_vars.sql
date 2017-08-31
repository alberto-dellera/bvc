-----------------------------------------------------------------------------------------
-- Bind Variables Checker: Tokenizer, and Statement Binder
-- Author:      Alberto Dell'Era
-- Copyright:   (c) 2003 - 2017 Alberto Dell'Era http://www.adellera.it
-----------------------------------------------------------------------------------------

type t_string_index is table of varchar2(1)  index by varchar2(30);
type t_number_map   is table of varchar2(10) index by varchar2(1000);
type t_part_map     is table of varchar2(10) index by varchar2(30);

-- the strict-sense keyword ("table" is a keyword, "sysdate" is not)
g_keywords t_string_index;

-- log/nolog flag
g_log boolean default false;

