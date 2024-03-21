--------------------------------------------------------------------------------
-- Bind Variables Checker: install-free basic checking script.
-- 
-- This script will dump all the statements whose bound statement is the same,
-- that is, all statements that are using literals instead of bind variables
-- and that can potentially benefit from turning literals into bind variables.
--
-- Note: only the first (about) 32K characters of the SQL text are considered due to pl/sql
-- limitations. Any statement longer than 32K will be signaled with a warning.
-- These statements might produce false positives or false negatives, depending on
-- whether the two bounded version of the two fragments before and after the truncation point
-- are the same or not. Of course, statements longer than 32K are rare and usually
-- do not need to use bind variables.
--
-- Every statement is dumped together with the number of versions found in the library cache
-- (highest version count first) and two examples, both with their hash_value (or sql_id if available).
--
-- Run with a user with SELECT privileges on gv$sql, gv$sqltext_with_newlines and dba_users.
--
-- See bvc_tokenizer_pkg.sql for further comments and documentation
--
-- Author:      Alberto Dell'Era
-- Copyright:   (c) 2003 - 2024 Alberto Dell'Era http://www.adellera.it
--------------------------------------------------------------------------------
define BVC_CHECK_VERSION="1.2.5 21-March-2024"

set null  "" trimspool on define on escape off pages 50000 tab off arraysize 100 
set echo off verify off feedback off termout on timing off

define normalize_numbers_in_ident=N
define normalize_partition_names=N
define strip_hints=N
define deterministic=' ' 
define spool_file_name=bvc_check.lst

set serveroutput on 
set lines 300

alter session set cursor_sharing=exact;

-- set version defines, get parameters
variable v_db_major_version  number
variable V_DB_VERSION        varchar2(20 char)
variable V_DB_VERSION_COMPAT varchar2(20 char)
variable DB_NAME             varchar2(30 char)
variable INSTANCE_NAME       varchar2(30 char)
declare /* bvc_marker */
  l_dummy_bi1  binary_integer;
  l_dummy_bi2  binary_integer;
begin
  sys.dbms_utility.db_version (:V_DB_VERSION, :V_DB_VERSION_COMPAT);
  :v_db_major_version := to_number (substr (:V_DB_VERSION, 1, instr (:V_DB_VERSION, '.') - 1));
  l_dummy_bi1 := sys.dbms_utility.get_parameter_value ('db_name'      , l_dummy_bi2, :DB_NAME      );
  l_dummy_bi1 := sys.dbms_utility.get_parameter_value ('instance_name', l_dummy_bi2, :INSTANCE_NAME);
end;
/

set echo on

-- set version-dependent commenting-out defines
define COMM_IF_LT_10G="error"
define COMM_IF_GT_9I="error"
col COMM_IF_LT_10G noprint new_value COMM_IF_LT_10G
col COMM_IF_GT_9I  noprint new_value COMM_IF_GT_9I
select /* bvc_marker */
       case when :v_db_major_version < 10 then '--' else '' end COMM_IF_LT_10G,
       case when :v_db_major_version >  9 then '--' else '' end COMM_IF_GT_9I
  from dual;

set echo off

prompt Fetching statements. This might take a while, please wait ...

variable BVC_CHECK_NUM_STMTS number

spool &spool_file_name.

prompt normalize_numbers_in_ident=&&normalize_numbers_in_ident.; normalize_partition_names=&&normalize_partition_names.; strip_hints=&&strip_hints.

declare /* bvc_marker */
  @@bvc_tokenizer_head_vars.sql
  @@bvc_tokenizer_body_vars.sql
  -- stmt -> already checked
  type t_stmt_seen is table of number index by varchar2(32767); 
  l_stmt_seen t_stmt_seen;
  -- bound stmt -> counts
  type t_bound_counts is table of number index by varchar2(32767); 
  l_bound_counts t_bound_counts;
  -- bound stmt -> stmt examples
  type t_examples_elem is record (
    text long,
    parsing_user_id number,
    &COMM_IF_GT_9I.  hash_value number
    &COMM_IF_LT_10G. sql_id     v$sql.sql_id%type
  );
  type t_examples is table of t_examples_elem index by varchar2(32767); 
  l_example_1 t_examples;
  l_example_2 t_examples;
  -- counts -> bound stmt
  type t_counts_bound is table of varchar2(32767) index by varchar2(20);
  l_counts_bound t_counts_bound;
  -- limit 
  l_sql_text_max_length int := 32767; -- 20160128  
  -- misc
  l_bound     long;
  l_counts    number;
  l_num_stmts number := 0;
  l_count_ext varchar2 (20 char);
  l_db_name   varchar2 (200 char);
  l_sql_text  long;
  l_sql_text_too_long boolean;
  l_parsing_username_1 dba_users.username%type;
  l_parsing_username_2 dba_users.username%type;
  
  @@bvc_tokenizer_body.sql
  -- line-wrapper printer
  procedure check_print (p_msg varchar2)
  is
  begin
    print (p_msg);
  end;
begin
  -- initialize bvc engine
  populate_g_keywords;
  
  -- read statements text from v$sql
  for stmt in (select /*+ cursor_sharing_exact bvc_marker */ 
                      distinct inst_id, address, hash_value, sql_text, lengthb(sql_text) as sql_text_lengthb, parsing_user_id 
                      &COMM_IF_LT_10G. , sql_id
                 from sys.gv_$sql 
                where executions > 0 
                  and lengthb(sql_text) > 10
                  and sql_text not like '% bvc_marker %' 
                  and sql_text not like '%xplan_exec_marker%'
                  and not (module = 'DIO' and action = 'DIO') -- statements from diagnosing tool
                  and not (module = 'YAH' and action = 'YAH') -- statements from diagnosing tool
                  and not (module = 'TOPIPY' and action = 'TOPIPY') -- statements from diagnosing tool
                  and parsing_user_id not in (select user_id from dba_users where username in ('SYS', 'SYSTEM', 'SYSMAN', 'DBSNMP', 'CTXSYS', 'MDSYS', 'ORDSYS', 'ORACLE_OCM') )
              )
  loop
    l_sql_text_too_long := false;
    l_sql_text := null;
    
    if 1=0  /* 20160128: v$sql.sql_text contains wrong newlines, comments out statement */ and stmt.sql_text_lengthb <= 990 then -- max(lengthb(sql_text)) looks like 999, not 1000
      l_sql_text := stmt.sql_text;
    else 
      -- get full stmt text if longer than 1000 chars 
      for x in (select /*+ bvc_marker */ sql_text, lengthb(sql_text) as sql_text_lengthb   
                  from sys.gv_$sqltext_with_newlines
                 where inst_id    = stmt.inst_id
                   and address    = stmt.address
                   and hash_value = stmt.hash_value
                 order by piece)
      loop
        if nvl(lengthb(l_sql_text),0) + x.sql_text_lengthb >= l_sql_text_max_length then
          l_sql_text_too_long := true;
          exit;
        else
          l_sql_text := l_sql_text || x.sql_text; 
        end if;
      end loop;
    end if;
    
    if l_sql_text_too_long then
      check_print ('WARNING: statement with hash="'||stmt.hash_value||'" is longer than '||l_sql_text_max_length||'. '
        ||chr(10)||' Only the first '||l_sql_text_max_length||' will be considered by, with possible false positives or negatives.'
        ||chr(10)||' First few chars: "'|| substr (l_sql_text, 1, 100) ||'"');
    end if;

    if l_sql_text is not null -- it might happen for inconsistencies between gv$sql and gv$sqltext_with_newlines
        and not l_stmt_seen.exists( l_sql_text ) then 
      l_stmt_seen ( l_sql_text ) := 1;
      l_bound := bound_stmt ( l_sql_text, p_normalize_numbers_in_ident => '&&normalize_numbers_in_ident.', p_normalize_partition_names => '&&normalize_partition_names.', p_strip_hints => '&&strip_hints.' );
      if l_bound is null then -- bug
        check_print( 'bound stmt is null for hash="'||stmt.hash_value||'" - sql_text="'||l_sql_text||'"' );
      elsif l_bound = '**bound statement too long**' then 
        check_print( 'bound stmt too long for hash="'||stmt.hash_value||'" - sql_text="'||l_sql_text||'"' );
      else
        if not l_bound_counts.exists ( l_bound ) then
          l_bound_counts ( l_bound ) := 1;
          l_example_1 ( l_bound ).text := l_sql_text;
          l_example_1 ( l_bound ).parsing_user_id := stmt.parsing_user_id;
          &COMM_IF_GT_9I.  l_example_1 ( l_bound ).hash_value := stmt.hash_value;
          &COMM_IF_LT_10G. l_example_1 ( l_bound ).sql_id := stmt.sql_id;
        else
          l_counts := l_bound_counts ( l_bound );
          l_bound_counts ( l_bound ) := l_counts + 1;
          if l_counts = 1 then
            l_example_2 ( l_bound ).text := l_sql_text;
            l_example_2 ( l_bound ).parsing_user_id := stmt.parsing_user_id;
            &COMM_IF_GT_9I.  l_example_2 ( l_bound ).hash_value := stmt.hash_value;
            &COMM_IF_LT_10G. l_example_2 ( l_bound ).sql_id := stmt.sql_id;
          end if;
        end if;
      end if;
    end if;
  end loop;  
  
  -- get all stmts whose count > 1, in order of counts
  l_bound := l_bound_counts.first;
  loop
    exit when l_bound is null;
    l_counts := l_bound_counts ( l_bound );
    if l_counts >= 2 then
      l_num_stmts := l_num_stmts + 1;
      l_counts_bound ( to_char (l_counts, '0000000000') || '_' || l_num_stmts  ) := l_bound;
    end if;
    l_bound := l_bound_counts.next ( l_bound );
  end loop;
  :BVC_CHECK_NUM_STMTS := l_num_stmts;
  
  -- print statements in reverse order of counts
  select /*+ cursor_sharing_exact bvc_marker */ sys_context ('USERENV', 'DB_NAME') into l_db_name from dual;
  check_print ('-----------------------------------------------------------------------------');
  check_print ('Output of Bind Variables Checker (basic script), version &BVC_CHECK_VERSION.');
  check_print ('(c) 2003 - 2024 Alberto Dell''Era http://www.adellera.it');
  check_print ('Dumped on '||to_char(sysdate, 'yyyy/mm/dd hh24:mi:ss') || ', db_name="'||:DB_NAME||'", instance_name="'||:INSTANCE_NAME||'"');
  check_print ('-----------------------------------------------------------------------------');
  check_print ('Following '||l_num_stmts||' bound statements are not using bind variables:');
  check_print (' ');
  l_count_ext := l_counts_bound.last;
  loop
    exit when l_count_ext is null;
    l_bound := l_counts_bound (l_count_ext);
    check_print ('------------------');
    check_print ('statements count : ' || ltrim ( trim( substr (l_count_ext, 1, instr (l_count_ext, '_')-1 ) ) , '0') ); 
    &COMM_IF_GT_9I.  check_print ('example 1/2 hash values = ' || l_example_1 ( l_bound ).hash_value || ' / ' || l_example_2 ( l_bound ).hash_value);
    &COMM_IF_LT_10G. check_print ('example 1/2 sql_id = ' || l_example_1 ( l_bound ).sql_id || ' / ' || l_example_2 ( l_bound ).sql_id);
    select username into l_parsing_username_1 from dba_users where user_id = l_example_1 ( l_bound ).parsing_user_id;
    select username into l_parsing_username_2 from dba_users where user_id = l_example_2 ( l_bound ).parsing_user_id;
    check_print ('example 1/2 parsing username = ' || l_parsing_username_1  || ' / ' || l_parsing_username_2);
    check_print ('bound    : '  || l_bound);
    check_print ('example 1: ' || l_example_1 ( l_bound ).text );
    check_print ('example 2: ' || l_example_2 ( l_bound ).text );
    l_count_ext := l_counts_bound.prior ( l_count_ext );
  end loop;

end;
/

spool off

define BVC_CHECK_NUM_STMTS="*error*"
col BVC_CHECK_NUM_STMTS noprint new_value BVC_CHECK_NUM_STMTS 
select /*+ cursor_sharing_exact bvc_marker */ trim(:BVC_CHECK_NUM_STMTS) as BVC_CHECK_NUM_STMTS from dual;

prompt Fetch complete; spool file "&spool_file_name." produced with &BVC_CHECK_NUM_STMTS. statements.

