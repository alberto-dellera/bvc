
alter system flush shared_pool;

declare
  l_stmt1 long := 'select count(*) from t where 0=0';
  l_stmt2 long := l_stmt1;
begin
  for i in 1..1000 loop
    if length (l_stmt1) < 1000 then
      l_stmt1 := l_stmt1 || ' and 0=0';
      l_stmt2 := l_stmt2 || ' and 0=0';
    else
      l_stmt1 := l_stmt1 || ' and 1=0';
      l_stmt2 := l_stmt2 || ' and 2=0';
    end if;
  end loop;
  
  execute immediate l_stmt1;
  execute immediate l_stmt2;
end;
/

@bvc_check.sql
