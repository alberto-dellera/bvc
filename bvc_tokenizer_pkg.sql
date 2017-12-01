-----------------------------------------------------------------------------------------
-- Bind Variables Checker: Tokenizer, and Statement Binder
-- Author:      Alberto Dell'Era
-- Copyright:   (c) 2003 - 2017 Alberto Dell'Era http://www.adellera.it
-----------------------------------------------------------------------------------------
--
-- Header comment explaining bvc overall is in bvc_tokenizer_body.sql
--

set echo on
set serveroutput on size 1000000 format wrapped

define deterministic=' ' 

----------------------------------------------------------
--------------------- PACKAGE HEADER ---------------------
----------------------------------------------------------
create or replace package bvc_tokenizer_pkg as

  -- check (important) comments in body
  function bound_stmt (
    p_stmt                       varchar2,
    p_normalize_numbers_in_ident varchar2 default 'Y',
    p_normalize_partition_names  varchar2 default 'Y',
    p_strip_hints                varchar2 default 'N'
  )
  return varchar2
  &&deterministic.;
  
  @@bvc_tokenizer_head_vars.sql
  
  -- check (important) comments in body
  function bound_stmt_verbose (
    p_stmt                       varchar2,
    p_normalize_numbers_in_ident varchar2 default 'Y',
    p_normalize_partition_names  varchar2 default 'Y',
    p_strip_hints                varchar2 default 'N',
    p_num_replaced_literals      out int,
    p_replaced_values            out t_varchar2,
    p_replaced_values_type       out t_varchar2_30
  )
  return varchar2
  &&deterministic.;

  -- check (important) comments in body
  procedure tokenize (
    p_stmt        varchar2,
    p_tokens      out nocopy t_varchar2,
    p_tokens_type out nocopy t_varchar2_30
  );
  
  -- check (important) comments in body
  procedure set_log (p_value boolean default true);
  
  -- check (important) comments in body
  procedure debug_print_tokens (p_stmt varchar2);
  
end bvc_tokenizer_pkg;
/
show errors;

----------------------------------------------------------
---------------------- PACKAGE BODY ----------------------
----------------------------------------------------------
create or replace package body bvc_tokenizer_pkg as
  @@bvc_tokenizer_body_vars.sql
  @@bvc_tokenizer_body.sql
begin
  populate_g_keywords;
end bvc_tokenizer_pkg;
/
show errors;

-- sanity check installation
begin
  bvc_tokenizer_pkg.set_log;
  
  bvc_tokenizer_pkg.debug_print_tokens (
    replace ('/**/select /*+comment*/a,x.b,c_$#,e "ident" --+xx'||chr(10)||
              'FROM t where!a!!b!= +1.e-23 and !!!!=:ph1:ind and :1=: "ph_23" and 1. = .0 or :y = :   x',
             '!', '''')
  );  
  
  dbms_output.put_line('.');

  bvc_tokenizer_pkg.debug_print_tokens ('  where +1 = 3 and -9.1=a+1.9 and b = - 1 and c =c++1 and d=d*+1');

  dbms_output.put_line('.');

  bvc_tokenizer_pkg.debug_print_tokens ('insert into t partition ( SYS_P32596 )  select sum(x) over( partition by x) from t partition(SYS_P32596)');
  
  bvc_tokenizer_pkg.debug_print_tokens ('declare x int; begin x:=owner . name(); end;');

  bvc_tokenizer_pkg.set_log (false);
end;
/

col bound_stmt form a100

select bvc_tokenizer_pkg.bound_stmt ('select /*+hint*/ /*co*/ x , C, "AA" FROM t t103 where 1  =  ''pippo'' and  :ph3= "t103"') as bound_stmt from dual;

select bvc_tokenizer_pkg.bound_stmt ('insert into t partition ( SYS_P32596 )  select sum(x) over( partition by x) from t partition(SYS_P32596)') as bound_stmt from dual;

select bvc_tokenizer_pkg.bound_stmt ('insert into t partition ( SYS_P32596 )  select sum(x) over( partition by x) from t partition(SYS_PXXXXX)') as bound_stmt from dual;

select bvc_tokenizer_pkg.bound_stmt ('alter table t move partition SYS_P32596') as bound_stmt from dual;


/*
exec bvc_tokenizer_pkg.set_log(false);
spool x.txt
select sql_text, bvc_tokenizer_pkg.bound_stmt(sql_text, 'y') from v$sql;
spool off
*/

/*
@profreset
commit;

exec dbms_profiler.start_profiler ('tokenizer');
set timing on
declare
  l_stmt varchar2(1000);
  l_stmt2 varchar2(1000);
begin
  select sql_text into l_stmt from v$sql where length(sql_text)=(select max(length(sql_text)) from v$sql) and rownum=1;
  for i in 1..100 loop
    l_stmt2 := bvc_tokenizer_pkg.bound_stmt (l_stmt);
  end loop;
end;
/
exec dbms_profiler.stop_profiler;
*/
