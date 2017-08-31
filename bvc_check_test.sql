

alter system flush shared_pool;

drop table t;
create table t (x int);

select * from t where x = 1;
select * from t where x = 2;
select * from t where x = 3;

@bvc_check.sql