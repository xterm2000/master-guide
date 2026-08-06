#dba #database #oracle #info 
```sql

--- ORA-1652: unable to extend temp segment by 128 in tablespace TEMP

select value
  from v$parameter
 where name = 'db_block_size';

select bytes / 1024 / 1024 as mb_size,
       maxbytes / 1024 / 1024 as maxsize_set,
       x.*
  from dba_data_files x;

select file_name,
       TABLESPACE_NAME
  from DBA_TEMP_FILES;
```


```sql
SELECT A.tablespace_name tablespace,
       D.mb_total,
       SUM(A.used_blocks * D.block_size) / 1024 / 1024 mb_used,
       D.mb_total - SUM(A.used_blocks * D.block_size) / 1024 / 1024 mb_free
  FROM v$sort_segment A,
       (SELECT B.name,
               C.block_size,
               SUM(C.bytes) / 1024 / 1024 mb_total
          FROM v$tablespace B,
               v$tempfile   C
         WHERE B.ts# = C.ts#
         GROUP BY B.name,
                  C.block_size) D
 WHERE A.tablespace_name = D.name
 GROUP by A.tablespace_name,
          D.mb_total;
```


```sql
SELECT S.sid || ',' || S.serial# sid_serial,
       S.username,
       S.osuser,
       P.spid,
       S.module,
       P.program,
       SUM(T.blocks) * TBS.block_size / 1024 / 1024 mb_used,
       T.tablespace,
       COUNT(*) statements
  FROM v$sort_usage    T,
       v$session       S,
       dba_tablespaces TBS,
       v$process       P
 WHERE T.session_addr = S.saddr
   AND S.paddr = P.addr
   AND T.tablespace = TBS.tablespace_name
 GROUP BY S.sid,
          S.serial#,
          S.username,
          S.osuser,
          P.spid,
          S.module,
          P.program,
          TBS.block_size,
          T.tablespace
 ORDER BY mb_used;
```

```sql
SELECT S.sid || ',' || S.serial# sid_serial,
       S.username,
       Q.hash_value,
       Q.sql_text,
       T.blocks * TBS.block_size / 1024 / 1024 mb_used,
       T.tablespace
  FROM v$sort_usage    T,
       v$session       S,
       v$sqlarea       Q,
       dba_tablespaces TBS
 WHERE T.session_addr = S.saddr
   AND T.sqladdr = Q.address
   AND T.tablespace = TBS.tablespace_name
 ORDER BY mb_used;

```