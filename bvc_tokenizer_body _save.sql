-----------------------------------------------------------------------------------------
-- Bind Variables Checker: Tokenizer, and Statement Binder
-- Author:      Alberto Dell'Era
-- Copyright:   (c) 2003 - 2017 Alberto Dell'Era http://www.adellera.it
-----------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------
-- "Statement Tokenizer": a routine that takes a SQL statement and breaks 
-- it into its tokens. 
-- For example:
-- SQL> exec bvc_tokenizer_pkg.debug_print_tokens ('select /*+ first_rows */ a from t where x + +1.e-123 > :ph');
--   keyword "select"
--      conn " "
--      hint "/*+ first_rows */"
--      conn " "
--     ident "a"
--      conn " "
--   keyword "from"
--      conn " "
--     ident "t"
--      conn " "
--   keyword "where"
--      conn " "
--     ident "x"
--      conn " + "
--    number "+1.e-123"
--      conn " > "
--      bind ":ph"
-- See the package header for additional comments and details.
--
-----------------------------------------------------------------------------------------
-- "Statement Binder": a routine that takes a SQL statement and 
-- replaces all literals with bind variables, normalizing the 
-- statement as well (in lowercase, without redundant whitespace, etc).
-- For example:
-- SQL> select bvc_tokenizer_pkg.bound_stmt ('SELECT * FROM T WHERE ID = +1.2e+1 AND Y = ''PIPPO'' AND Z = :B1')  bound_stmt from dual;
-- BOUND_STMT
-- --------------------------------------------
-- select*from t where id=:n and y=:s and z=:b
-- 
-- The Statement Binder uses the Tokenizer to parse the statement, then basically "pretty prints" it.
-- See the package header for additional comments and details.
--
-- Note : about the motivation for normalizing numbers in identifiers in bound_stmt.
-- If p_normalize_numbers_in_ident is 'Y' (the default), numbers contained in identifier
-- such as object names, aliases, and bind variables names (and hints) are normalized: 
--   select * from t123 t123   where id='pippo' and (c4=1 or c4=2) and id3=:ph1
-- becomes
--   select*from t{0} t{0} where id=:s and(c{1}=:n or c{1}=:n)and id{2}=:b
-- This is to detect some coding horrors contained in mainstream "database independent"
-- libraries, that generate code such as
--  select * from t t1 where t1.x = 
--  select * from t t2 where t2.x = 
--  select * from t t3 where t3.x = 
-- Please note that equal numbers in identifier are substituted with the same number:
--  select * from t123 t123 --> select*from t{0} t{0}
--  and (c4=1 or c4=2)      --> and(c{1}=:n or c{1}=:n)
--  i.e. every occurrence of t123 is substituted with t{0}, c4 with c{1} and so on.
-- Obviously this permits to understand where the same identifier is referenced in
-- the bound-statement.
-- 
-- If p_normalize_partition_names is 'Y' (the default), partition names are normalized with "#<progressive>";
-- partitions with the same name gets the same normalizing identifier.
--
-- If p_strip_hints is 'Y' (default is 'N'), hints are removed
-- 
-- Author: Alberto Dell'Era, first version: 28th of July 2003

----------------------------------------------------------
-- set logging mode (log to dbms_output)
procedure set_log (p_value boolean default true)
is
begin
  g_log := p_value;
end set_log;

----------------------------------------------------------
-- prints in l_chunk_size chunks
procedure print (p_msg varchar2)
is
  l_chunk_size int := 240;
  l_pos int := 1;
  l_msg_length int := length (p_msg);
begin
  loop
    dbms_output.put_line (substr (p_msg, l_pos, l_chunk_size));
    l_pos := l_pos + l_chunk_size;
    exit when l_pos > l_msg_length;
  end loop;
end;

----------------------------------------------------------
procedure log (p_msg varchar2)
is
begin
  if g_log then
    print (p_msg);
  end if;
end log;

----------------------------------------------------------
-- populates the keywords map
-- generating statement:
-- select '  g_keywords('''||lower(keyword)||''') := null;' from v$reserved_words;
-- then get rid of pseudo columns such as sysdate, rowid, rownum, level, etc, and
-- frequently-used column names such as "id"
procedure populate_g_keywords
is
begin
  g_keywords('abort') := null;
  g_keywords('access') := null;
  g_keywords('accessed') := null;
  g_keywords('account') := null;
  g_keywords('activate') := null;
  g_keywords('add') := null;
  g_keywords('admin') := null;
  g_keywords('administer') := null;
  g_keywords('administrator') := null;
  g_keywords('advise') := null;
  g_keywords('after') := null;
  g_keywords('algorithm') := null;
  g_keywords('alias') := null;
  g_keywords('all') := null;
  g_keywords('all_rows') := null;
  g_keywords('allocate') := null;
  g_keywords('allow') := null;
  g_keywords('alter') := null;
  g_keywords('always') := null;
  g_keywords('analyze') := null;
  g_keywords('ancillary') := null;
  g_keywords('and') := null;
  g_keywords('any') := null;
  g_keywords('apply') := null;
  g_keywords('archive') := null;
  g_keywords('archivelog') := null;
  g_keywords('array') := null;
  g_keywords('as') := null;
  g_keywords('asc') := null;
  g_keywords('associate') := null;
  g_keywords('at') := null;
  g_keywords('attribute') := null;
  g_keywords('attributes') := null;
  g_keywords('audit') := null;
  g_keywords('authenticated') := null;
  g_keywords('authid') := null;
  g_keywords('authorization') := null;
  g_keywords('auto') := null;
  g_keywords('autoallocate') := null;
  g_keywords('autoextend') := null;
  g_keywords('automatic') := null;
  g_keywords('availability') := null;
  g_keywords('backup') := null;
  g_keywords('become') := null;
  g_keywords('before') := null;
  g_keywords('begin') := null;
  g_keywords('behalf') := null;
  g_keywords('between') := null;
  g_keywords('bfile') := null;
  g_keywords('binding') := null;
  g_keywords('bitmap') := null;
  g_keywords('bits') := null;
  g_keywords('blob') := null;
  g_keywords('block') := null;
  g_keywords('blocksize') := null;
  g_keywords('block_range') := null;
  g_keywords('body') := null;
  g_keywords('bound') := null;
  g_keywords('both') := null;
  g_keywords('broadcast') := null;
  g_keywords('buffer_pool') := null;
  g_keywords('build') := null;
  g_keywords('bulk') := null;
  g_keywords('by') := null;
  g_keywords('byte') := null;
  g_keywords('cache') := null;
  g_keywords('cache_instances') := null;
  g_keywords('call') := null;
  g_keywords('cancel') := null;
  g_keywords('cascade') := null;
  g_keywords('case') := null;
  g_keywords('cast') := null;
  g_keywords('category') := null;
  g_keywords('certificate') := null;
  g_keywords('cfile') := null;
  g_keywords('chained') := null;
  g_keywords('change') := null;
  g_keywords('char') := null;
  g_keywords('char_cs') := null;
  g_keywords('character') := null;
  g_keywords('check') := null;
  g_keywords('checkpoint') := null;
  g_keywords('child') := null;
  g_keywords('choose') := null;
  g_keywords('chunk') := null;
  g_keywords('class') := null;
  g_keywords('clear') := null;
  g_keywords('clob') := null;
  g_keywords('clone') := null;
  g_keywords('close') := null;
  g_keywords('close_cached_open_cursors') := null;
  g_keywords('cluster') := null;
  g_keywords('coalesce') := null;
  g_keywords('collect') := null;
  g_keywords('column') := null;
  g_keywords('columns') := null;
  g_keywords('column_value') := null;
  g_keywords('comment') := null;
  g_keywords('commit') := null;
  g_keywords('committed') := null;
  g_keywords('compatibility') := null;
  g_keywords('compile') := null;
  g_keywords('complete') := null;
  g_keywords('composite_limit') := null;
  g_keywords('compress') := null;
  g_keywords('compute') := null;
  g_keywords('conforming') := null;
  g_keywords('connect') := null;
  g_keywords('connect_time') := null;
  g_keywords('consider') := null;
  g_keywords('consistent') := null;
  g_keywords('constraint') := null;
  g_keywords('constraints') := null;
  g_keywords('container') := null;
  g_keywords('contents') := null;
  g_keywords('context') := null;
  g_keywords('continue') := null;
  g_keywords('controlfile') := null;
  g_keywords('convert') := null;
  g_keywords('corruption') := null;
  g_keywords('cost') := null;
  g_keywords('cpu_per_call') := null;
  g_keywords('cpu_per_session') := null;
  g_keywords('create') := null;
  g_keywords('create_stored_outlines') := null;
  g_keywords('cross') := null;
  g_keywords('cube') := null;
  g_keywords('current') := null;
  g_keywords('current_date') := null;
  g_keywords('current_schema') := null;
  g_keywords('current_time') := null;
  g_keywords('current_timestamp') := null;
  g_keywords('current_user') := null;
  g_keywords('cursor') := null;
  g_keywords('cursor_specific_segment') := null;
  g_keywords('cycle') := null;
  g_keywords('dangling') := null;
  g_keywords('data') := null;
  g_keywords('database') := null;
  g_keywords('datafile') := null;
  g_keywords('datafiles') := null;
  g_keywords('dataobjno') := null;
  g_keywords('date') := null;
  g_keywords('date_mode') := null;
  g_keywords('day') := null;
  g_keywords('dba') := null;
  g_keywords('dbtimezone') := null;
  g_keywords('ddl') := null;
  g_keywords('deallocate') := null;
  g_keywords('debug') := null;
  g_keywords('dec') := null;
  g_keywords('decimal') := null;
  g_keywords('declare') := null;
  g_keywords('default') := null;
  g_keywords('deferrable') := null;
  g_keywords('deferred') := null;
  g_keywords('defined') := null;
  g_keywords('definer') := null;
  g_keywords('degree') := null;
  g_keywords('delay') := null;
  g_keywords('delete') := null;
  g_keywords('demand') := null;
  g_keywords('dense_rank') := null;
  g_keywords('rowdependencies') := null;
  g_keywords('deref') := null;
  g_keywords('desc') := null;
  g_keywords('detached') := null;
  g_keywords('determines') := null;
  g_keywords('dictionary') := null;
  g_keywords('dimension') := null;
  g_keywords('directory') := null;
  g_keywords('disable') := null;
  g_keywords('disassociate') := null;
  g_keywords('disconnect') := null;
  g_keywords('disk') := null;
  g_keywords('diskgroup') := null;
  g_keywords('disks') := null;
  g_keywords('dismount') := null;
  g_keywords('dispatchers') := null;
  g_keywords('distinct') := null;
  g_keywords('distinguished') := null;
  g_keywords('distributed') := null;
  g_keywords('dml') := null;
  g_keywords('double') := null;
  g_keywords('drop') := null;
  g_keywords('dump') := null;
  g_keywords('dynamic') := null;
  g_keywords('each') := null;
  g_keywords('element') := null;
  g_keywords('else') := null;
  g_keywords('enable') := null;
  g_keywords('encrypted') := null;
  g_keywords('encryption') := null;
  g_keywords('end') := null;
  g_keywords('enforce') := null;
  g_keywords('entry') := null;
  g_keywords('error_on_overlap_time') := null;
  g_keywords('escape') := null;
  g_keywords('estimate') := null;
  g_keywords('events') := null;
  g_keywords('except') := null;
  g_keywords('exceptions') := null;
  g_keywords('exchange') := null;
  g_keywords('excluding') := null;
  g_keywords('exclusive') := null;
  g_keywords('execute') := null;
  g_keywords('exempt') := null;
  g_keywords('exists') := null;
  g_keywords('expire') := null;
  g_keywords('explain') := null;
  g_keywords('explosion') := null;
  g_keywords('extend') := null;
  g_keywords('extends') := null;
  g_keywords('extent') := null;
  g_keywords('extents') := null;
  g_keywords('external') := null;
  g_keywords('externally') := null;
  g_keywords('extract') := null;
  g_keywords('failed_login_attempts') := null;
  g_keywords('failgroup') := null;
  g_keywords('false') := null;
  g_keywords('fast') := null;
  g_keywords('file') := null;
  g_keywords('filter') := null;
  g_keywords('final') := null;
  g_keywords('finish') := null;
  g_keywords('first') := null;
  g_keywords('first_rows') := null;
  g_keywords('flagger') := null;
  g_keywords('flashback') := null;
  g_keywords('float') := null;
  g_keywords('flob') := null;
  g_keywords('flush') := null;
  g_keywords('following') := null;
  g_keywords('for') := null;
  g_keywords('force') := null;
  g_keywords('foreign') := null;
  g_keywords('freelist') := null;
  g_keywords('freelists') := null;
  g_keywords('freepools') := null;
  g_keywords('fresh') := null;
  g_keywords('from') := null;
  g_keywords('full') := null;
  g_keywords('function') := null;
  g_keywords('functions') := null;
  g_keywords('generated') := null;
  g_keywords('global') := null;
  g_keywords('globally') := null;
  g_keywords('global_name') := null;
  g_keywords('global_topic_enabled') := null;
  g_keywords('grant') := null;
  g_keywords('group') := null;
  g_keywords('grouping') := null;
  g_keywords('groups') := null;
  g_keywords('guaranteed') := null;
  g_keywords('guard') := null;
  g_keywords('hash') := null;
  g_keywords('hashkeys') := null;
  g_keywords('having') := null;
  g_keywords('header') := null;
  g_keywords('heap') := null;
  g_keywords('hierarchy') := null;
  g_keywords('hour') := null;
  --g_keywords('id') := null;
  g_keywords('identified') := null;
  g_keywords('identifier') := null;
  g_keywords('idgenerators') := null;
  g_keywords('idle_time') := null;
  g_keywords('if') := null;
  g_keywords('immediate') := null;
  g_keywords('in') := null;
  g_keywords('including') := null;
  g_keywords('increment') := null;
  g_keywords('incremental') := null;
  g_keywords('index') := null;
  g_keywords('indexed') := null;
  g_keywords('indexes') := null;
  g_keywords('indextype') := null;
  g_keywords('indextypes') := null;
  g_keywords('indicator') := null;
  g_keywords('initial') := null;
  g_keywords('initialized') := null;
  g_keywords('initially') := null;
  g_keywords('initrans') := null;
  g_keywords('inner') := null;
  g_keywords('insert') := null;
  g_keywords('instance') := null;
  g_keywords('instances') := null;
  g_keywords('instantiable') := null;
  g_keywords('instantly') := null;
  g_keywords('instead') := null;
  g_keywords('int') := null;
  g_keywords('integer') := null;
  g_keywords('integrity') := null;
  g_keywords('intermediate') := null;
  g_keywords('internal_use') := null;
  g_keywords('internal_convert') := null;
  g_keywords('intersect') := null;
  g_keywords('interval') := null;
  g_keywords('into') := null;
  g_keywords('invalidate') := null;
  g_keywords('in_memory_metadata') := null;
  g_keywords('is') := null;
  g_keywords('isolation') := null;
  g_keywords('isolation_level') := null;
  g_keywords('java') := null;
  g_keywords('join') := null;
  g_keywords('keep') := null;
  g_keywords('kerberos') := null;
  g_keywords('key') := null;
  g_keywords('keyfile') := null;
  g_keywords('keys') := null;
  g_keywords('keysize') := null;
  g_keywords('rekey') := null;
  g_keywords('kill') := null;
  g_keywords('<<') := null;
  g_keywords('last') := null;
  g_keywords('lateral') := null;
  g_keywords('layer') := null;
  g_keywords('ldap_registration') := null;
  g_keywords('ldap_registration_enabled') := null;
  g_keywords('ldap_reg_sync_interval') := null;
  g_keywords('leading') := null;
  g_keywords('left') := null;
  g_keywords('less') := null;
  --g_keywords('level') := null;
  g_keywords('levels') := null;
  g_keywords('library') := null;
  g_keywords('like') := null;
  g_keywords('like2') := null;
  g_keywords('like4') := null;
  g_keywords('likec') := null;
  g_keywords('limit') := null;
  g_keywords('link') := null;
  g_keywords('list') := null;
  g_keywords('lob') := null;
  g_keywords('local') := null;
  g_keywords('localtime') := null;
  --g_keywords('localtimestamp') := null;
  g_keywords('location') := null;
  g_keywords('locator') := null;
  g_keywords('lock') := null;
  g_keywords('locked') := null;
  g_keywords('log') := null;
  g_keywords('logfile') := null;
  g_keywords('logging') := null;
  g_keywords('logical') := null;
  g_keywords('logical_reads_per_call') := null;
  g_keywords('logical_reads_per_session') := null;
  g_keywords('logoff') := null;
  g_keywords('logon') := null;
  g_keywords('long') := null;
  g_keywords('manage') := null;
  g_keywords('managed') := null;
  g_keywords('management') := null;
  g_keywords('manual') := null;
  g_keywords('mapping') := null;
  g_keywords('master') := null;
  g_keywords('materialized') := null;
  g_keywords('matched') := null;
  g_keywords('max') := null;
  g_keywords('maxarchlogs') := null;
  g_keywords('maxdatafiles') := null;
  g_keywords('maxextents') := null;
  g_keywords('maximize') := null;
  g_keywords('maxinstances') := null;
  g_keywords('maxlogfiles') := null;
  g_keywords('maxloghistory') := null;
  g_keywords('maxlogmembers') := null;
  g_keywords('maxsize') := null;
  g_keywords('maxtrans') := null;
  g_keywords('maxvalue') := null;
  g_keywords('method') := null;
  g_keywords('min') := null;
  g_keywords('member') := null;
  g_keywords('memory') := null;
  g_keywords('merge') := null;
  g_keywords('migrate') := null;
  g_keywords('minimize') := null;
  g_keywords('minimum') := null;
  g_keywords('minextents') := null;
  g_keywords('minus') := null;
  g_keywords('minute') := null;
  g_keywords('minvalue') := null;
  g_keywords('mirror') := null;
  g_keywords('mlslabel') := null;
  g_keywords('mode') := null;
  g_keywords('modify') := null;
  g_keywords('monitoring') := null;
  g_keywords('month') := null;
  g_keywords('mount') := null;
  g_keywords('move') := null;
  g_keywords('movement') := null;
  g_keywords('mts_dispatchers') := null;
  g_keywords('multiset') := null;
  --g_keywords('name') := null;
  g_keywords('named') := null;
  g_keywords('national') := null;
  g_keywords('natural') := null;
  g_keywords('nchar') := null;
  g_keywords('nchar_cs') := null;
  g_keywords('nclob') := null;
  g_keywords('needed') := null;
  g_keywords('nested') := null;
  g_keywords('nested_table_id') := null;
  g_keywords('network') := null;
  g_keywords('never') := null;
  g_keywords('new') := null;
  g_keywords('next') := null;
  g_keywords('nls_calendar') := null;
  g_keywords('nls_characterset') := null;
  g_keywords('nls_comp') := null;
  g_keywords('nls_nchar_conv_excp') := null;
  g_keywords('nls_currency') := null;
  g_keywords('nls_date_format') := null;
  g_keywords('nls_date_language') := null;
  g_keywords('nls_iso_currency') := null;
  g_keywords('nls_lang') := null;
  g_keywords('nls_language') := null;
  g_keywords('nls_length_semantics') := null;
  g_keywords('nls_numeric_characters') := null;
  g_keywords('nls_sort') := null;
  g_keywords('nls_special_chars') := null;
  g_keywords('nls_territory') := null;
  --g_keywords('no') := null;
  g_keywords('noarchivelog') := null;
  g_keywords('noaudit') := null;
  g_keywords('nocache') := null;
  g_keywords('nocompress') := null;
  g_keywords('nocycle') := null;
  g_keywords('norowdependencies') := null;
  g_keywords('nodelay') := null;
  g_keywords('noforce') := null;
  g_keywords('nologging') := null;
  g_keywords('nomapping') := null;
  g_keywords('nomaxvalue') := null;
  g_keywords('nominimize') := null;
  g_keywords('nominvalue') := null;
  g_keywords('nomonitoring') := null;
  g_keywords('none') := null;
  g_keywords('noorder') := null;
  g_keywords('nooverride') := null;
  g_keywords('noparallel') := null;
  g_keywords('norely') := null;
  g_keywords('norepair') := null;
  g_keywords('noresetlogs') := null;
  g_keywords('noreverse') := null;
  g_keywords('normal') := null;
  g_keywords('nosegment') := null;
  g_keywords('nostrict') := null;
  g_keywords('nostripe') := null;
  g_keywords('nosort') := null;
  g_keywords('noswitch') := null;
  g_keywords('not') := null;
  g_keywords('nothing') := null;
  g_keywords('novalidate') := null;
  g_keywords('nowait') := null;
  --g_keywords('null') := null;
  g_keywords('nulls') := null;
  g_keywords('number') := null;
  g_keywords('numeric') := null;
  g_keywords('nvarchar2') := null;
  g_keywords('object') := null;
  g_keywords('objno') := null;
  g_keywords('objno_reuse') := null;
  g_keywords('of') := null;
  g_keywords('off') := null;
  g_keywords('offline') := null;
  --g_keywords('oid') := null;
  g_keywords('oidindex') := null;
  g_keywords('old') := null;
  g_keywords('on') := null;
  g_keywords('online') := null;
  g_keywords('only') := null;
  g_keywords('opaque') := null;
  g_keywords('opcode') := null;
  g_keywords('open') := null;
  g_keywords('operator') := null;
  g_keywords('optimal') := null;
  g_keywords('optimizer_goal') := null;
  g_keywords('option') := null;
  g_keywords('or') := null;
  g_keywords('order') := null;
  g_keywords('organization') := null;
  g_keywords('outer') := null;
  g_keywords('outline') := null;
  g_keywords('over') := null;
  g_keywords('overflow') := null;
  g_keywords('overlaps') := null;
  g_keywords('own') := null;
  g_keywords('package') := null;
  g_keywords('packages') := null;
  g_keywords('parallel') := null;
  g_keywords('parameters') := null;
  g_keywords('parent') := null;
  g_keywords('parity') := null;
  g_keywords('partially') := null;
  g_keywords('partition') := null;
  g_keywords('partitions') := null;
  g_keywords('partition_hash') := null;
  g_keywords('partition_list') := null;
  g_keywords('partition_range') := null;
  g_keywords('password') := null;
  g_keywords('password_grace_time') := null;
  g_keywords('password_life_time') := null;
  g_keywords('password_lock_time') := null;
  g_keywords('password_reuse_max') := null;
  g_keywords('password_reuse_time') := null;
  g_keywords('password_verify_function') := null;
  g_keywords('pctfree') := null;
  g_keywords('pctincrease') := null;
  g_keywords('pctthreshold') := null;
  g_keywords('pctused') := null;
  g_keywords('pctversion') := null;
  g_keywords('percent') := null;
  g_keywords('performance') := null;
  g_keywords('permanent') := null;
  g_keywords('pfile') := null;
  g_keywords('physical') := null;
  g_keywords('plan') := null;
  g_keywords('plsql_debug') := null;
  g_keywords('policy') := null;
  g_keywords('post_transaction') := null;
  g_keywords('prebuilt') := null;
  g_keywords('preceding') := null;
  g_keywords('precision') := null;
  g_keywords('prepare') := null;
  g_keywords('preserve') := null;
  g_keywords('primary') := null;
  g_keywords('prior') := null;
  g_keywords('private') := null;
  g_keywords('private_sga') := null;
  g_keywords('privilege') := null;
  g_keywords('privileges') := null;
  g_keywords('procedure') := null;
  g_keywords('profile') := null;
  g_keywords('protected') := null;
  g_keywords('protection') := null;
  g_keywords('public') := null;
  g_keywords('purge') := null;
  g_keywords('px_granule') := null;
  g_keywords('query') := null;
  g_keywords('queue') := null;
  g_keywords('quiesce') := null;
  g_keywords('quota') := null;
  g_keywords('random') := null;
  g_keywords('range') := null;
  g_keywords('rapidly') := null;
  g_keywords('raw') := null;
  g_keywords('rba') := null;
  g_keywords('read') := null;
  g_keywords('reads') := null;
  g_keywords('real') := null;
  g_keywords('rebalance') := null;
  g_keywords('rebuild') := null;
  g_keywords('records_per_block') := null;
  g_keywords('recover') := null;
  g_keywords('recoverable') := null;
  g_keywords('recovery') := null;
  g_keywords('recycle') := null;
  g_keywords('reduced') := null;
  g_keywords('ref') := null;
  g_keywords('references') := null;
  g_keywords('referencing') := null;
  g_keywords('refresh') := null;
  g_keywords('register') := null;
  g_keywords('reject') := null;
  g_keywords('relational') := null;
  g_keywords('rely') := null;
  g_keywords('rename') := null;
  g_keywords('repair') := null;
  g_keywords('replace') := null;
  g_keywords('reset') := null;
  g_keywords('resetlogs') := null;
  g_keywords('resize') := null;
  g_keywords('resolve') := null;
  g_keywords('resolver') := null;
  g_keywords('resource') := null;
  g_keywords('restrict') := null;
  g_keywords('restricted') := null;
  g_keywords('resumable') := null;
  g_keywords('resume') := null;
  g_keywords('retention') := null;
  g_keywords('return') := null;
  g_keywords('returning') := null;
  g_keywords('reuse') := null;
  g_keywords('reverse') := null;
  g_keywords('revoke') := null;
  g_keywords('rewrite') := null;
  g_keywords('right') := null;
  g_keywords('role') := null;
  g_keywords('roles') := null;
  g_keywords('rollback') := null;
  g_keywords('rollup') := null;
  g_keywords('row') := null;
  --g_keywords('rowid') := null;
  --g_keywords('rownum') := null;
  g_keywords('rows') := null;
  g_keywords('rule') := null;
  g_keywords('sample') := null;
  g_keywords('savepoint') := null;
  g_keywords('sb4') := null;
  g_keywords('scan') := null;
  g_keywords('scan_instances') := null;
  g_keywords('schema') := null;
  g_keywords('scn') := null;
  g_keywords('scope') := null;
  g_keywords('sd_all') := null;
  g_keywords('sd_inhibit') := null;
  g_keywords('sd_show') := null;
  g_keywords('second') := null;
  g_keywords('security') := null;
  g_keywords('segment') := null;
  g_keywords('seg_block') := null;
  g_keywords('seg_file') := null;
  g_keywords('select') := null;
  g_keywords('selectivity') := null;
  g_keywords('sequence') := null;
  g_keywords('sequenced') := null;
  g_keywords('serializable') := null;
  g_keywords('servererror') := null;
  g_keywords('session') := null;
  g_keywords('session_cached_cursors') := null;
  g_keywords('sessions_per_user') := null;
  g_keywords('sessiontimezone') := null;
  g_keywords('sessiontzname') := null;
  g_keywords('set') := null;
  g_keywords('sets') := null;
  g_keywords('settings') := null;
  g_keywords('share') := null;
  g_keywords('shared') := null;
  g_keywords('shared_pool') := null;
  g_keywords('shrink') := null;
  g_keywords('shutdown') := null;
  g_keywords('siblings') := null;
  --g_keywords('sid') := null;
  g_keywords('single') := null;
  g_keywords('singletask') := null;
  g_keywords('simple') := null;
  g_keywords('size') := null;
  g_keywords('skip') := null;
  g_keywords('skip_unusable_indexes') := null;
  g_keywords('smallint') := null;
  g_keywords('snapshot') := null;
  g_keywords('some') := null;
  g_keywords('sort') := null;
  g_keywords('source') := null;
  g_keywords('space') := null;
  g_keywords('specification') := null;
  g_keywords('spfile') := null;
  g_keywords('split') := null;
  g_keywords('sql_trace') := null;
  g_keywords('standby') := null;
  g_keywords('start') := null;
  g_keywords('startup') := null;
  g_keywords('statement_id') := null;
  g_keywords('statistics') := null;
  g_keywords('static') := null;
  g_keywords('stop') := null;
  g_keywords('storage') := null;
  g_keywords('store') := null;
  g_keywords('stripe') := null;
  g_keywords('strict') := null;
  g_keywords('structure') := null;
  g_keywords('subpartition') := null;
  g_keywords('subpartitions') := null;
  g_keywords('subpartition_rel') := null;
  g_keywords('substitutable') := null;
  g_keywords('successful') := null;
  g_keywords('summary') := null;
  g_keywords('suspend') := null;
  g_keywords('supplemental') := null;
  g_keywords('switch') := null;
  g_keywords('switchover') := null;
  g_keywords('sys_op_bitvec') := null;
  g_keywords('sys_op_col_present') := null;
  g_keywords('sys_op_cast') := null;
  g_keywords('sys_op_enforce_not_null$') := null;
  g_keywords('sys_op_mine_value') := null;
  g_keywords('sys_op_noexpand') := null;
  g_keywords('sys_op_ntcimg$') := null;
  g_keywords('synonym') := null;
  --g_keywords('sysdate') := null;
  g_keywords('sysdba') := null;
  g_keywords('sysoper') := null;
  g_keywords('system') := null;
  --g_keywords('systimestamp') := null;
  g_keywords('table') := null;
  g_keywords('tables') := null;
  g_keywords('tablespace') := null;
  g_keywords('tablespace_no') := null;
  g_keywords('tabno') := null;
  g_keywords('tempfile') := null;
  g_keywords('template') := null;
  g_keywords('temporary') := null;
  --g_keywords('test') := null;
  g_keywords('than') := null;
  g_keywords('the') := null;
  g_keywords('then') := null;
  g_keywords('thread') := null;
  g_keywords('through') := null;
  g_keywords('timestamp') := null;
  g_keywords('time') := null;
  g_keywords('timeout') := null;
  g_keywords('timezone_abbr') := null;
  g_keywords('timezone_hour') := null;
  g_keywords('timezone_minute') := null;
  g_keywords('timezone_region') := null;
  g_keywords('time_zone') := null;
  g_keywords('to') := null;
  g_keywords('toplevel') := null;
  g_keywords('trace') := null;
  g_keywords('tracing') := null;
  g_keywords('trailing') := null;
  g_keywords('transaction') := null;
  g_keywords('transitional') := null;
  g_keywords('treat') := null;
  g_keywords('trigger') := null;
  g_keywords('triggers') := null;
  g_keywords('true') := null;
  g_keywords('truncate') := null;
  g_keywords('tx') := null;
  g_keywords('type') := null;
  g_keywords('types') := null;
  g_keywords('tz_offset') := null;
  g_keywords('ub2') := null;
  g_keywords('uba') := null;
  --g_keywords('uid') := null;
  g_keywords('unarchived') := null;
  g_keywords('unbound') := null;
  g_keywords('unbounded') := null;
  g_keywords('under') := null;
  g_keywords('undo') := null;
  g_keywords('undrop') := null;
  g_keywords('uniform') := null;
  g_keywords('union') := null;
  g_keywords('unique') := null;
  g_keywords('unlimited') := null;
  g_keywords('unlock') := null;
  g_keywords('unpacked') := null;
  g_keywords('unprotected') := null;
  g_keywords('unquiesce') := null;
  g_keywords('unrecoverable') := null;
  g_keywords('until') := null;
  g_keywords('unusable') := null;
  g_keywords('unused') := null;
  g_keywords('upd_indexes') := null;
  g_keywords('upd_joinindex') := null;
  g_keywords('updatable') := null;
  g_keywords('update') := null;
  g_keywords('upgrade') := null;
  g_keywords('urowid') := null;
  g_keywords('usage') := null;
  g_keywords('use') := null;
  g_keywords('use_private_outlines') := null;
  g_keywords('use_stored_outlines') := null;
  g_keywords('user') := null;
  g_keywords('user_defined') := null;
  g_keywords('using') := null;
  g_keywords('validate') := null;
  g_keywords('validation') := null;
  g_keywords('value') := null;
  g_keywords('values') := null;
  g_keywords('varchar') := null;
  g_keywords('varchar2') := null;
  g_keywords('varray') := null;
  g_keywords('varying') := null;
  g_keywords('version') := null;
  g_keywords('view') := null;
  g_keywords('wait') := null;
  g_keywords('when') := null;
  g_keywords('whenever') := null;
  g_keywords('where') := null;
  g_keywords('with') := null;
  g_keywords('within') := null;
  g_keywords('without') := null;
  g_keywords('work') := null;
  g_keywords('write') := null;
  g_keywords('xmlattributes') := null;
  g_keywords('xmlcolattval') := null;
  g_keywords('xmlelement') := null;
  g_keywords('xmlforest') := null;
  g_keywords('xmltype') := null;
  g_keywords('xmlschema') := null;
  g_keywords('xid') := null;
  g_keywords('year') := null;
  g_keywords('zone') := null;
end populate_g_keywords;

----------------------------------------------------------
-- returns the least of the non-zero arguments
-- (or zero if they are all equal to zero)
function least_non_zero (
  p1 int, 
  p2 int default 0, 
  p3 int default 0, 
  p4 int default 0
)
return int
is
  l_ret int default greatest (p1,p2,p3,p4);
begin
  if p1 <> 0 and p1 < l_ret then
    l_ret := p1;
  end if;
  if p2 <> 0 and p2 < l_ret then
    l_ret := p2;
  end if;
  if p3 <> 0 and p3 < l_ret then
    l_ret := p3;
  end if;
  if p4 <> 0 and p4 < l_ret then
    l_ret := p4;
  end if;
  return l_ret; 
end;

----------------------------------------------------------
-- get the closing position of a comment,hint,quoted-ident 
-- or string literal section.
-- nb the closing pos is "one after the end":
-- aaa 'pippo' xxx
--            ^ closing pos 
function get_closing_pos (
  p_stmt_stripped varchar2,
  p_opening_pos   int,
  p_opening_token varchar2
)
return int
is
  l_closing_token varchar2(2);
  l_closing_pos int;
begin
  if p_opening_token = '/*' then
    l_closing_token := '*/';
  elsif p_opening_token = '--' then
    l_closing_token := chr(10);
  elsif p_opening_token = '"' then
    l_closing_token := '"';
  elsif p_opening_token = '''' then
    l_closing_token :=  '''';
  end if;
  
  l_closing_pos := instr (p_stmt_stripped, 
                          l_closing_token, 
                          p_opening_pos + length(p_opening_token));
                          
  -- close the section at the end of the statement if no closing position
  -- was found (possible if eg statement is truncated at 1000 chars)
  if l_closing_pos = 0 then
    return length (p_stmt_stripped) + 1;
  end if;
  
  -- handle double-quotes in string eg 'dell''era'
  if p_opening_token = '''' 
     and substr (p_stmt_stripped, l_closing_pos+1, 1) = '''' 
  then
    return get_closing_pos (p_stmt_stripped, l_closing_pos+1, p_opening_token);
  end if;
  
  -- return the "one after the end" position
  return l_closing_pos + length (l_closing_token);

end get_closing_pos;

----------------------------------------------------------
-- copies the token in p_tokens and replace it with
-- spaces in  p_stmt_stripped
procedure extract_token (
  p_stmt_stripped in out nocopy varchar2,
  p_tokens        in out nocopy t_varchar2,
  p_first         int,
  p_last          int
)
is
begin
  p_tokens (p_first) := substr (p_stmt_stripped, p_first, p_last - p_first);
  p_stmt_stripped := substr (p_stmt_stripped, 1, p_first-1)
                     || rpad (' ', p_last - p_first)
                     || substr (p_stmt_stripped, p_last ); 
end extract_token;
  
----------------------------------------------------------
-- extracts all comment,hint,quoted-ident or string literal sections.
-- comment       : /*comment*/, --comment
-- hint          : /*+hint*/, --+hint
-- quoted-ident  : "ident"
-- string literal: 'smith', 'dell''era'
procedure extract_stringlikes (
  p_stmt_stripped in out nocopy varchar2,
  p_tokens        in out nocopy t_varchar2,
  p_tokens_type   in out nocopy t_varchar2_30
)
is
  l_first_ss  int default 1;
  l_first_hh  int default 1;
  l_first_dq  int default 1;
  l_first_sq  int default 1;
  l_first_min int;
  l_closing_pos int;
  l_token_type varchar2(30);
begin
  
  loop
    -- get first stringlike opening position
    l_first_ss  := instr (p_stmt_stripped, '/*', l_first_ss);
    l_first_hh  := instr (p_stmt_stripped, '--', l_first_hh);
    l_first_dq  := instr (p_stmt_stripped, '"' , l_first_dq);
    l_first_sq  := instr (p_stmt_stripped, '''', l_first_sq);
    l_first_min := least_non_zero (l_first_ss, l_first_hh, l_first_dq, l_first_sq);
    exit when l_first_min = 0;
    
    -- get closing position and type of stringlike
    if l_first_min = l_first_ss then
      l_closing_pos := get_closing_pos (p_stmt_stripped, l_first_min, '/*');
      if substr (p_stmt_stripped, l_first_min+2, 1) = '+' then
        l_token_type  := 'hint';
      else
        l_token_type  := 'comment';
      end if;
    elsif l_first_min = l_first_hh then
      l_closing_pos := get_closing_pos (p_stmt_stripped, l_first_min, '--');
      if substr (p_stmt_stripped, l_first_min+2, 1) = '+' then
        l_token_type  := 'hint';
      else
        l_token_type  := 'comment';
      end if;
    elsif l_first_min = l_first_dq then
      l_closing_pos := get_closing_pos (p_stmt_stripped, l_first_min, '"');
      l_token_type  := 'ident';
    elsif l_first_min = l_first_sq then
      l_closing_pos := get_closing_pos (p_stmt_stripped, l_first_min, '''');
      l_token_type  := 'string';
    end if;
    
    -- extract stringlike from p_stmt_stripped, replace with blanks
    extract_token (p_stmt_stripped, p_tokens, l_first_min, l_closing_pos);
               
    p_tokens_type (l_first_min) := l_token_type;
                    
    if g_log then log (replace (p_stmt_stripped,' ','_')); end if;                
  end loop;
end extract_stringlikes;

----------------------------------------------------------
function is_alpha (p_char varchar2)
return boolean
is
begin
  if p_char >= 'a' then return p_char <= 'z'; elsif p_char < 'A' then return false; else return p_char <= 'Z'; end if;
  --ORIGINAL: return instr ('abcdefghijklmnopqrstuvwxyz', lower(p_char)) > 0;
end is_alpha;

----------------------------------------------------------
-- alpha extended: alpha or _,$,#
function is_alpha_extended (p_char varchar2)
return boolean
is
begin
  return is_alpha(p_char) or instr ('_$#', p_char) > 0;
end is_alpha_extended;

----------------------------------------------------------
function is_digit (p_char varchar2)
return boolean
is
begin
  return p_char <= '9' and p_char >= '0';
  --ORIGINAL: return instr ('0123456789', p_char) > 0;
end is_digit;

----------------------------------------------------------
function is_digit_period (p_char varchar2)
return boolean
is
begin
  if p_char > '9' then return false; else return p_char >= '0' or p_char = '.'; end if;
  -- ORIGINAL: return instr ('0123456789', p_char) > 0 or p_char = '.';
end is_digit_period;

----------------------------------------------------------
-- gets the first non-alpha(extended)numeric char position
-- the char MUST exist
function get_first_non_alphaextnum_pos (
  p_stmt_stripped varchar2,
  p_start_pos     int
)
return int
is
begin
  for i in p_start_pos .. length (p_stmt_stripped) loop
    if not (is_alpha_extended (substr (p_stmt_stripped, i, 1))
       or is_digit (substr (p_stmt_stripped, i, 1))) 
    then
      return i;
    end if;
  end loop;
  raise_application_error (-20001, 'no non-alphanum char found');
end get_first_non_alphaextnum_pos;

----------------------------------------------------------
-- gets the first alphabetic char position
-- 0 if not found
function get_first_alpha_pos (
  p_stmt_stripped varchar2,
  p_start_pos     int
)
return int
is
begin
  for i in p_start_pos .. length (p_stmt_stripped) loop
    if is_alpha (substr (p_stmt_stripped, i, 1)) 
    then
      return i;
    end if;
  end loop;
  return 0;
end;
 
----------------------------------------------------------
-- extract all bind variables placeholders
-- :x, :1, :, :    x, :ph1, :ph1:ind
-- NB binds like :"ident", :<blanks>"ident" and :<blanks>x 
-- are extracted like ":",
-- and later the <bind><ident> token pairs are 
-- merged together (reconciled)
procedure extract_bind_vars (
  p_stmt_stripped in out nocopy varchar2,
  p_tokens        in out nocopy t_varchar2,
  p_tokens_type   in out nocopy t_varchar2_30
)
is
  l_first_colon int;
  l_closing_pos int default 1;
begin
  loop
    l_first_colon := instr (p_stmt_stripped, ':', l_closing_pos);
    exit when l_first_colon = 0;
    -- if token is ":=", it is a pl/sql assignment => skip
    if substr (p_stmt_stripped, l_first_colon+1, 1) = '=' then 
      l_closing_pos := l_first_colon + 2;
    else 
      l_closing_pos := get_first_non_alphaextnum_pos (p_stmt_stripped,l_first_colon+1); 
      -- handle binds like :ph:ind
      if substr (p_stmt_stripped, l_closing_pos, 1) = ':' then
        l_closing_pos := get_first_non_alphaextnum_pos (p_stmt_stripped,l_closing_pos+1); 
      end if;
    
      extract_token (p_stmt_stripped, p_tokens, l_first_colon, l_closing_pos);
      p_tokens_type (l_first_colon) := 'bind';
    end if;
    if g_log then log (replace (p_stmt_stripped,' ','_')); end if; 
  end loop;
end extract_bind_vars;

----------------------------------------------------------
function classify_identifier (p_ident varchar2)
return varchar2
is
begin
  if g_keywords.exists (lower (p_ident)) then
    return 'keyword';
  end if;
  return 'ident';
end classify_identifier;

----------------------------------------------------------
function is_e_inside_science_notation (
  p_prev_2 varchar2,
  p_prev_1 varchar2,
  p_next_1 varchar2,
  p_next_2 varchar2
)
return boolean
is
begin
  if not ( is_digit(p_next_1) or (p_next_1 in ('+','-') and is_digit(p_next_2))) then
    return false;
  end if;
  if is_digit (p_prev_1) then
    return true;
  end if;
  return p_prev_1 = '.' and is_digit (p_prev_2);
end is_e_inside_science_notation;

----------------------------------------------------------
-- extract all identifiers (begin with alpha, continue with alphanum chars)
procedure extract_identifiers (
  p_stmt_stripped in out nocopy varchar2,
  p_tokens        in out nocopy t_varchar2,
  p_tokens_type   in out nocopy t_varchar2_30
)
is
  l_closing_pos int default 1;
  l_first_alpha int;
begin
  loop
    l_first_alpha := get_first_alpha_pos (p_stmt_stripped, l_closing_pos);
    exit when l_first_alpha = 0;
    -- skip if first_alpha is 'e' and belongs to a scientific-notation number
    if lower(substr (p_stmt_stripped,l_first_alpha,1)) = 'e'
       and l_first_alpha >= 3
       and is_e_inside_science_notation (
             substr (p_stmt_stripped,l_first_alpha-2,1), 
             substr (p_stmt_stripped,l_first_alpha-1,1),
             substr (p_stmt_stripped,l_first_alpha+1,1),
             substr (p_stmt_stripped,l_first_alpha+2,1)
           )
    then
      l_closing_pos := l_first_alpha + 1;
    else
      l_closing_pos := get_first_non_alphaextnum_pos (p_stmt_stripped,l_first_alpha+1); 
      p_tokens_type (l_first_alpha) := 
        classify_identifier (substr (p_stmt_stripped,l_first_alpha,l_closing_pos-l_first_alpha));
      extract_token (p_stmt_stripped, p_tokens, l_first_alpha, l_closing_pos);     
    end if;
    if g_log then log (replace (p_stmt_stripped,' ','_')); end if; 
  end loop;
end extract_identifiers;

----------------------------------------------------------
-- gets the first digit or period char position
-- 0 if not found
function get_first_digit_period_pos (
  p_stmt_stripped varchar2,
  p_start_pos     int
)
return int
is
begin
  for i in p_start_pos .. length (p_stmt_stripped) loop
    if is_digit_period (substr (p_stmt_stripped, i, 1))
    then
      return i;
    end if;
  end loop;
  return 0;
end get_first_digit_period_pos;

----------------------------------------------------------
-- gets the first non (digit or period) char position
-- the char MUST exist
function get_first_non_digit_period_pos (
  p_stmt_stripped varchar2,
  p_start_pos     int
)
return int
is
begin
  for i in p_start_pos .. length (p_stmt_stripped) loop
    if not is_digit_period (substr (p_stmt_stripped, i, 1))
    then
      return i;
    end if;
  end loop;
  raise_application_error (-20002, 'no non-num-period char found');
end get_first_non_digit_period_pos;

----------------------------------------------------------
-- gets the first non (digit or + or -) char position
-- the char MUST exist
function get_first_non_digit_pm_pos (
  p_stmt_stripped varchar2,
  p_start_pos     int
)
return int
is
begin
  for i in p_start_pos .. length (p_stmt_stripped) loop
    if not( is_digit (substr (p_stmt_stripped, i, 1)) 
            or substr (p_stmt_stripped, i, 1) in ('+','-'))
    then
      return i;
    end if;
  end loop;
  raise_application_error (-20003, 'no non-num-plus-minus char found');
end get_first_non_digit_pm_pos;

----------------------------------------------------------
function is_white_space (p_char varchar2)
return boolean
is
begin
  return instr (' '||chr(10)||chr(9), p_char) > 0;
end is_white_space;

----------------------------------------------------------
-- gets the previous non-whitespace char position
-- 0 if not found
function get_prev_non_white_space_pos (
  p_stmt_stripped varchar2,
  p_start_pos     int
)
return int
is
begin
  for i in reverse 1 .. p_start_pos-1  loop
    if not is_white_space (substr (p_stmt_stripped, i, 1))
    then
      return i;
    end if;
  end loop;
  return 0;
end get_prev_non_white_space_pos;

----------------------------------------------------------
function is_operator (p_char varchar2)
return boolean
is
begin
  return instr ('+-*/(=<>|,[', p_char) > 0;
end is_operator;

----------------------------------------------------------
-- returns the token covering the position p_pos
-- returns null if not found
function get_token_covering (
  p_pos    int,
  p_tokens t_varchar2
)
return int
is
  l_token int;
begin
  if p_tokens.exists (p_pos) then
    return p_pos;
  end if;
  l_token := p_tokens.prior (p_pos);
  if l_token is not null 
     and p_pos < l_token + length(p_tokens(l_token)) 
  then
    return l_token;
  end if;
  return null;
end get_token_covering;

----------------------------------------------------------
-- returns true if the char at position is inside a keyword 
function is_inside_keyword (
  p_pos         int,
  p_tokens      t_varchar2,
  p_tokens_type t_varchar2_30)
return boolean
is
  l_token_covering int;
begin
  l_token_covering := get_token_covering (p_pos, p_tokens);
  return l_token_covering is not null 
     and p_tokens_type (l_token_covering) = 'keyword';
end is_inside_keyword;

----------------------------------------------------------
-- extract all numbers
-- see the "sql reference guide" for exact syntax of numbers
procedure extract_numbers (
  p_stmt_stripped in out nocopy varchar2,
  p_tokens        in out nocopy t_varchar2,
  p_tokens_type   in out nocopy t_varchar2_30,
  p_stmt_orig     varchar2
)
is
  l_closing_pos int default 1;
  l_first int;
  l_trail_char int;
  l_trail_char2 int;
begin
  loop
    -- num must start with a digit or "." (trailing + and - are handled below)
    l_first := get_first_digit_period_pos (p_stmt_stripped, l_closing_pos);
    exit when l_first = 0;
    -- if starts with ".", following char must be a digit or "e"
    if substr (p_stmt_stripped, l_first, 1) = '.'
       and not is_digit (substr (p_stmt_stripped, l_first+1, 1)) 
       and not lower (substr (p_stmt_stripped, l_first+1, 1)) = 'e' then
      l_closing_pos := l_first+1;
    else
      -- digit or period are allowed until the end
      l_closing_pos := get_first_non_digit_period_pos (p_stmt_stripped, l_first);
      -- advance closing pos if "e" is found
      if lower (substr (p_stmt_stripped, l_closing_pos, 1)) = 'e' then
        l_closing_pos := get_first_non_digit_pm_pos (p_stmt_stripped, l_closing_pos+1);
      end if;
      -- add trailing + or - if part of number [eg + +1, / +1, ( + 1,) ]
      l_trail_char := get_prev_non_white_space_pos (p_stmt_orig, l_first);
      if l_trail_char > 0 and substr (p_stmt_orig,l_trail_char,1) in ('+','-') then
        l_trail_char2 := get_prev_non_white_space_pos (p_stmt_orig, l_trail_char);
        if l_trail_char2 > 0 and (is_operator (substr (p_stmt_orig,l_trail_char2,1)) 
                                  or is_inside_keyword (l_trail_char2, p_tokens, p_tokens_type))
        then
          l_first := l_trail_char;
        end if;
      end if;
      extract_token (p_stmt_stripped, p_tokens, l_first, l_closing_pos);
      p_tokens_type (l_first) := 'number';
    end if;
    if g_log then log (replace (p_stmt_stripped,' ','_')); end if; 
  end loop;
end extract_numbers;

----------------------------------------------------------
-- reconcile bind variables of the form
-- :[space*]ident  
-- eg ':  x',    ': "SYS_B_0"'
procedure reconcile_spaced_binds (
  p_tokens        in out nocopy t_varchar2,
  p_tokens_type   in out nocopy t_varchar2_30
)
is
  l_i int;
  l_next_i int;
begin
  l_i := p_tokens.first;
  loop
    exit when l_i is null;
    if p_tokens_type (l_i) = 'bind' and p_tokens(l_i) = ':' then
      l_next_i := p_tokens.next (l_i);
      if l_next_i is not null and p_tokens_type (l_next_i) = 'ident' then
        -- merge the two tokens
        p_tokens(l_i) := p_tokens(l_i) || lpad (' ', l_next_i - l_i - 1) || p_tokens(l_next_i);
        p_tokens.delete (l_next_i);
        p_tokens_type.delete (l_next_i);
      end if;
    end if;
    
    l_i := p_tokens.next (l_i);
  end loop;
end reconcile_spaced_binds;

----------------------------------------------------------
-- adds the "conn" tokens
procedure extract_remaining (
  p_stmt          varchar2,
  p_tokens        in out nocopy t_varchar2,
  p_tokens_type   in out nocopy t_varchar2_30
)
is
  l_i int;
  l_next_i int;
  l_next_pos int;
begin
  
  -- insert token containing beginning of statement
  if p_tokens.first > 1 then
     p_tokens(1)      := substr (p_stmt, 1, l_i-1);
     p_tokens_type(1) := 'conn';
  end if;
  -- insert fake token at the end
  p_tokens (length(p_stmt)+1) := 'fake';
  l_i := p_tokens.first;
  loop
    exit when p_tokens (l_i) = 'fake';
    -- next token must start here:
    l_next_pos := l_i + length(p_tokens(l_i));
    -- next current token starts here:
    l_next_i := p_tokens.next (l_i);
    -- insert new token if tokens are not adjacent
    if l_next_pos != l_next_i then
      p_tokens      (l_next_pos) := substr (p_stmt, l_next_pos, l_next_i - l_next_pos);
      p_tokens_type (l_next_pos) := 'conn';
    end if;    
    l_i := l_next_i;
  end loop; 
  -- remove fake token
  p_tokens.delete (length(p_stmt)+1);
end extract_remaining;

----------------------------------------------------------
-- tokenize a statement (the workhorse)
-- p_tokens: the "tokens" of the statement, ie an index-by table, indexed by the
-- position of the first character of the token in the statement, 
-- that contains the token value (eg 'select', ':b1', 'owner', ecc)
-- p_tokens_type: the token type ('keyword', 'bind', 'ident',
--                'string', 'number', 'hint','comment', 'conn')
-- 'conn' means a connecting token, eg 'where a<=b' is
-- keyword "where"
--    conn " "
--   ident "a"
--    conn "<="
--   ident "b"
procedure tokenize (
  p_stmt        varchar2,
  p_tokens      out nocopy t_varchar2,
  p_tokens_type out nocopy t_varchar2_30
)
is
  -- normalize the statement 
  -- and make it terminating with a double blank to simplify algorithm
  l_stmt_stripped long := replace (p_stmt, chr(13),' ') || '  ';
begin
  extract_stringlikes (l_stmt_stripped, p_tokens, p_tokens_type);
  extract_bind_vars   (l_stmt_stripped, p_tokens, p_tokens_type);
  extract_identifiers (l_stmt_stripped, p_tokens, p_tokens_type);
  extract_numbers     (l_stmt_stripped, p_tokens, p_tokens_type, p_stmt);
  reconcile_spaced_binds (p_tokens, p_tokens_type);
  extract_remaining   (p_stmt         , p_tokens, p_tokens_type);
end tokenize;

----------------------------------------------------------
-- print on dbms_output the extracted tokens
procedure debug_print_tokens (p_stmt varchar2)
is
  l_i int;
  l_tokens t_varchar2;
  l_tokens_type t_varchar2_30;
begin
  if g_log then log (p_stmt); end if;
  tokenize (p_stmt, l_tokens, l_tokens_type);
  l_i := l_tokens.first;
  loop
    exit when l_i is null;
    dbms_output.put_line (lpad (l_tokens_type(l_i),10) ||' "'|| l_tokens (l_i)||'"');
    l_i := l_tokens.next (l_i);
  end loop;
end debug_print_tokens;

----------------------------------------------------------
-- returns a normalized identifier. 
-- Each sequence of digits is replaced by a number;
-- the number is the same across the statemenet
-- if the sequence is the same.
-- ie if "t103" -> "t{0}", "x103" -> "x{0}"
-- non double-quoted identifiers are normalized in lowercase.
function normalize_ident (
  p_ident      varchar2, 
  p_number_map in out nocopy t_number_map,
  p_normalize_numbers_in_ident varchar2
)
return varchar2
is
  l_last_digit int default 1;
  l_out long;
  l_ident long;
  l_number long;
  c varchar2(1 char);
  l_first_digit int;
begin
  if upper(p_normalize_numbers_in_ident) = 'Y' then
    l_ident := p_ident || '!'; -- add "!" at the end to simplify algorithm
    for i in 1 .. length(l_ident) loop
      c := substr (l_ident, i, 1);
      if l_first_digit is null -- not inside a sequence of digits
      then
        if not is_digit(c) then
          l_out := l_out || c;
        else
          l_first_digit := i;
        end if;
      else -- in sequence of digits
        if not is_digit(c) then 
          -- sequence of digits is over. Add sequence to map
          l_number := substr (l_ident, l_first_digit, i - l_first_digit);
          if not p_number_map.exists(l_number) then
            p_number_map(l_number):= p_number_map.count;
          end if;
          -- return normalized sequence
          l_out := l_out || chr(123) || p_number_map(l_number) || chr(125) || c;
          l_first_digit := null;
        else
          null;
        end if;
      end if;
    end loop;
    -- remove the added "!" at the end
    l_out := substr (l_out, 1, length(l_out)-1);
  else
    l_out := p_ident;
  end if;
  
  -- return lowercase ident if not doublequoted
  if substr (l_out, 1, 1) = '"' then
    return l_out;
  else
    return lower(l_out);
  end if;
end normalize_ident;

----------------------------------------------------------
procedure check_partition_reference( p_tokens in out t_varchar2, p_tokens_type in out t_varchar2_30, p_i_part int, p_partition_ident_index out int )
is 
  l_next_1 int;
  l_next_2 int;
  l_next_3 int;
begin 

  -- check "partition pxx"
  l_next_1 := p_tokens.next ( p_i_part );
  if l_next_1 is null then return; end if;

  l_next_2 := p_tokens.next ( l_next_1 );
  if l_next_2 is null then return; end if;

  if p_tokens_type( l_next_1 ) = 'conn' and p_tokens_type( l_next_2 ) = 'ident' then 
    p_partition_ident_index := l_next_2;
    return; 
  end if; 

  -- check "partition ( pxx )"
  if p_tokens_type( l_next_1 ) != 'conn' or trim(p_tokens( l_next_1 )) != '(' then
    log( '--> '||p_tokens_type( l_next_1)||' '||trim(p_tokens( l_next_1 ))  ); 
    return;
  end if;

  if p_tokens_type( l_next_2 ) != 'ident' then 
    return;
  end if;

  l_next_3 := p_tokens.next ( l_next_2 );
  if l_next_3 is null then return; end if;

  if p_tokens_type( l_next_3 ) != 'conn' or trim(p_tokens( l_next_3 )) != ')' then 
    return;
  end if;  

  p_partition_ident_index := l_next_2;
end check_partition_reference;

----------------------------------------------------------
procedure mark_partition_idents( p_tokens in out t_varchar2, p_tokens_type in out t_varchar2_30, p_partition_idents out t_varchar2_30 )
is 
  l_i int;
  l_token long;
  l_token_type varchar2(30);
  l_partition_ident_index int;

  
begin 
  l_i := p_tokens.first;
  loop
    exit when l_i is null;

    l_token      := p_tokens      (l_i);
    l_token_type := p_tokens_type (l_i);

    log( l_token ||' '||l_token_type );

    if l_token_type = 'keyword' and lower(trim(l_token)) = 'partition' then 
      check_partition_reference( p_tokens, p_tokens_type, l_i, l_partition_ident_index );
      if l_partition_ident_index is not null then 
        p_partition_idents( l_partition_ident_index ) := 'x';
      end if;
    end if; 

    l_i := p_tokens.next (l_i);
  end loop;
end mark_partition_idents;

----------------------------------------------------------
-- same as bound_stmt, but returns also
-- 1) p_num_replaced_literals: the number of literals (numbers and strings) replaced
--    if p_num_replaced_literals=0, the original statement contained bind values only.
-- 2) p_replaced_values: the values of literals and names of bind variables replaced
-- 3) p_replaced_values_type: their types ('number','string','bind')
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
&&deterministic.
is
  l_i int;
  l_tokens t_varchar2;
  l_tokens_type t_varchar2_30;
  l_partition_idents t_varchar2_30;
  l_token long;
  l_token_type varchar2(30);
  l_o long;
  l_number_map t_number_map;
  l_part_map   t_part_map;
  l_separators varchar2(20) := '=<>!+-*/(),;|:[].@';
  l_sep varchar2 (1 char);
  l_lengthb_old int;
begin
  p_num_replaced_literals := 0;

  if p_stmt is null then
    return null;
  end if;
  
  -- tokenize 
  tokenize (p_stmt, l_tokens, l_tokens_type);

  -- normalize partitions 
  if p_normalize_partition_names = 'Y' then 
    mark_partition_idents( l_tokens, l_tokens_type, l_partition_idents );
  end if;
  
  -- rebuild the statement replacing strings and numbers with binds, ecc
  l_i := l_tokens.first;
  loop
    exit when l_i is null;
    if lengthb(l_o) > 32767 - 30 then 
      return '**bound statement too long**';
    end if;
    l_token      := l_tokens      (l_i);
    l_token_type := l_tokens_type (l_i);
    if l_token_type in ('conn','keyword') then
      l_o := l_o || lower(l_token);
    elsif l_token_type = 'hint' then
      -- strip hints or normalize
      if p_strip_hints = 'Y' then 
        l_o := l_o || ' ';
      else 
        l_o := l_o || normalize_ident (l_token, l_number_map, p_normalize_numbers_in_ident);
      end if;
    elsif l_token_type = 'comment' then
      l_o := l_o || ' ';
    elsif l_token_type = 'bind' then
      l_o := l_o || ':b';
      p_replaced_values     (p_replaced_values     .count) := l_token;
      p_replaced_values_type(p_replaced_values_type.count) := l_token_type;
    elsif l_token_type = 'number' then  
      l_o := l_o || ':n';
      p_num_replaced_literals := p_num_replaced_literals + 1;
      p_replaced_values     (p_replaced_values     .count) := l_token;
      p_replaced_values_type(p_replaced_values_type.count) := l_token_type;
    elsif l_token_type = 'string' then  
      l_o := l_o || ':s';
      p_num_replaced_literals := p_num_replaced_literals + 1;
      p_replaced_values     (p_replaced_values     .count) := l_token;
      p_replaced_values_type(p_replaced_values_type.count) := l_token_type;
    elsif l_token_type = 'ident' then
      -- substitute partition identifier or normalize  
      if l_partition_idents.exists(l_i) then 
        if not l_part_map.exists(l_token) then 
          l_part_map(l_token) := '#'||l_part_map.count;
        end if;
        l_o := l_o || l_part_map(l_token);
        p_replaced_values     (p_replaced_values     .count) := l_token;
        p_replaced_values_type(p_replaced_values_type.count) := l_token_type;
      else 
        l_o := l_o || normalize_ident (l_token, l_number_map, p_normalize_numbers_in_ident);
      end if;
    else
      raise_application_error (-20010, 'unknown token type <'||l_token_type||'> for token <'||l_token||'>');
    end if;
    
    l_i := l_tokens.next (l_i);
  end loop;    
  
  -- transform white space in blanks
  l_o := replace (l_o, chr(10), ' ');
  l_o := replace (l_o, chr(9) , ' ');
  -- remove double blanks
  loop
    l_lengthb_old := lengthb (l_o);
    l_o := replace (l_o, '  ', ' ');
    exit when lengthb (l_o) = l_lengthb_old or l_o is null;
  end loop;
  -- remove redundant white space
  for i in 1..length(l_separators) loop
    l_sep := substr (l_separators, i, 1);
    l_o := replace (l_o, l_sep||' ', l_sep);
    l_o := replace (l_o, ' '||l_sep, l_sep);
  end loop;
  return trim(l_o);
end bound_stmt_verbose;

----------------------------------------------------------
-- transforms a statement in a (normalized) bound statement:
-- 1) all literals replaced with binds (numbers -> :n, strings -> :s) 
-- 2) all bind variables replaced with a single name (:b)
-- 3) redundant white space removed ( a = b -> a=b, from   t -> from t)
-- 4) all in lowercase, but not doublequoted idents (SELECT FROM "TAB", T -> select from "TAB", t)
-- 5) comments removed (but hints preserved and normalized)
-- 6) (optionally but on by default) numbers in ident normalized:
--    select * from t t102, u t103, v t102 -> select * from t t{0}, u t{1}, v t{0} 
-- 7) (optionally but on by default) partition names normalized:
--    insert into t partition ( PA ) select * from t partition(PA) -> insert into t partition(#0) select * from t partition(#0)
function bound_stmt (
  p_stmt                       varchar2,
  p_normalize_numbers_in_ident varchar2 default 'Y',
  p_normalize_partition_names  varchar2 default 'Y',
  p_strip_hints                varchar2 default 'N'
)
return varchar2
&&deterministic.
is
  l_num_replaced_literals int;
  l_replaced_values      t_varchar2;
  l_replaced_values_type t_varchar2_30;
begin
  return bound_stmt_verbose (
    p_stmt, 
    p_normalize_numbers_in_ident,
    p_normalize_partition_names,
    p_strip_hints,
    l_num_replaced_literals,
    l_replaced_values,
    l_replaced_values_type
  );
end bound_stmt;


