This is a set of scripts whose purpose is mainly to check quickly and easily whether the database clients are using bind variables or not.

### bvc_check.sql

The most convenient script is bvc_check.sql, that reads the statements text from gv$sql and then reports the ones that have the same _bound statement_ (which is simply the statement text whose literals are replaced with bind variables, normalized in lowercase, with redundant white space removed, etc).

Here's an example of the bvc_check.sql script output:

```
------------------
statements count :  0000000003
bound    : select*from t where x=:n
example 1: select * from t where x = 2
example 2: select * from t where x = 3
------------------
```

This shows that there are three statements that map to the same bound statement "select*from t where x=:n"; two examples are provided as output.

This script does not need any server-side install, which is of course a definitive plus when investigating production since normally we are not allowed to install anything there. You only need select privileges on gv$sql, gv$sqltext_with_newlines and dba_users; just run bvc_check.sql inside sqlplus and then inspect the output bvc_check.lst file.

Caveat: the full-scan of gv$sql is quite heavy on latches - this may impact the performance of a system that is already heavy contending on library cache latches, so check in production first for this kind of latch contention. It is anyway a lesser problem in recent Oracle versions.

If all you need is a simple script to check for bind variables - you can stop reading here.

### bvc_tokenizer_pkg.sql: Bound Statement calculator

The script bvc_tokenizer_pkg.sql installs the package bvc_tokenizer_pkg server-side; this package provides a stored function, bound_stmt(), which is the workhorse that calculates the bound statement. For example:

```
SQL> select bvc_tokenizer_pkg.bound_stmt ('select * from t where x = 2') as bound from dual;

BOUND
------------------------------
select*from t where x=:n
```

This stored function is similar to the Tom Kyte's function [remove_constants](http://asktom.oracle.com/pls/ask/f?p=4950:8:::::F4950_P8_DISPLAYID:1163635055580) but much more sophisticated. Check the bvc_tokenizer_pkg.sql header for more information.

This stored function allows for very intriguing analyses.

#### Flexible analysis of bind variables usage

First, obviously, we can easily make (almost)the same analysis that bvc_check.sql makes:

```
select bvc_tokenizer_pkg.bound_stmt(sql_text) bound, count(*) cnt
  from (
select distinct sql_text 
  from gv$sql 
 where parsing_user_id not in (select user_id from dba_users where username in ('SYS','SYSTEM'))
       )
 group by bvc_tokenizer_pkg.bound_stmt(sql_text)
having count(*) > 1
order by cnt desc;

BOUND                                                     CNT
-------------------------------------------------- ----------
select*from t where x=:n                                    5
select*from t where to_char(x)=:s                           4
```

The advantage over bvc_check.sql is flexibility, since we can very easily adapt the mining SQL to our needs; examples of frequently occurring scenarios are investigating only statements parsed by certain users (gv$sql.parsing_user_id), or whose executions is above a certain threshold, or joining other gv$ views to enrich the mined information.

#### Grouping execution statistics by bound statement

The bound_stmt() stored function has other uses besides checking for bind variables. The most interesting one is to properly group execution statistics for statements that are not using bind variables (which could be made for perfectly sound reasons: literals are not always evil ;). For instance, if your clients submit 20 statements that map to the same bound statement, each one consuming only 1% of a resource, it's way too easy to overlook the importance of the statement; but if you group the resource by bound statement, it is quite impossible to miss a whopping 20%.

Here is an example of this technique:

```
select bvc_tokenizer_pkg.bound_stmt(sql_text) bound, 
       sum(elapsed_time) elapsed_time
  from v$sql
 group by bvc_tokenizer_pkg.bound_stmt(sql_text)
 order by elapsed_time desc;
BOUND                                              ELAPSED_TIME
-------------------------------------------------- ------------
declare job binary_integer:=:b;next_date date:=:b;     15707151
broken boolean:=false;begin wwv_flow_mail.push_que
ue(wwv_flow_platform.get_preference(:s),wwv_flow_p
latform.get_preference(:s));:b:=next_date;if broke
n then:b:=:n;else:b:=:n;end if;end;

select table_objno,primary_instance,secondary_inst      4531685
ance,owner_instance from sys.aq$_queue_table_affin
ities a where a.owner_instance<>:b and dbms_aqadm_
syscalls.get_owner_instance(a.primary_instance,a.s
econdary_instance,a.owner_instance)=:b order by ta
ble_objno for update of a.owner_instance skip lock
ed
```

### bvc_tokenizer_pkg.sql: Statement Tokenizer

The bvc_tokenizer_pkg.sql implements also a SQL tokenizer (a routine that breaks a SQL statement into its tokens). For example:

```
SQL> exec bvc_tokenizer_pkg.debug_print_tokens ('select /*+ first_rows */ a from t where x + +1.e-123 > :ph');

  keyword "select"
     conn " "
     hint "/*+ first_rows */"
     conn " "
    ident "a"
     conn " "
  keyword "from"
     conn " "
    ident "t"
     conn " "
  keyword "where"
     conn " "
    ident "x"
     conn " + "
   number "+1.e-123"
     conn " > "
     bind ":ph"
```

This routine is used by the bound_stmt() stored function discussed above; the latter simply substitutes each number/string/bind token with a bind variable and then concatenates the tokens back.

Of course, the tokenizer routine might be easily used to implement a SQL pretty printer - something I might implement in the future.
