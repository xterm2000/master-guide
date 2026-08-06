#database #lock #oracle  #query 

```sql
-- check locked sessions - 
-- to kill one , just copy the "alter system ... " command from appropriate row and execute 
SELECT distinct 'alter system kill session ''' || B.sid || ',' || B.serial# || ''';',
                C.OWNER,
                C.OBJECT_NAME,
                A.OBJECT_ID,
                B.SID,
                B.serial#,
                B.USER#,
                B.USERNAME,
                (select au.user_name
                   from app_user au
                  where au.ident = b.USERNAME) as nmm,
                B.COMMAND,
                B.OSUSER,
                P.spid
  FROM SYS.DBA_OBJECTS      C,
       SYS.V_$LOCKED_OBJECT A,
       SYS.V_$SESSION       B,
       SYS.v_$PROCESS       P
 WHERE (C.OBJECT_ID = A.OBJECT_ID)
   AND (B.SID = A.SESSION_ID)
   AND (P.ADDR = B.paddr)
 --  and b.USERNAME = '206503460'
 order by b.USERNAME
--   and p.USERNAME = '' YOUR SSO / ONAIR

```

```sql
select distinct a.username,
                a.account_status,
                a.CREATED
  from dba_users      a,
       dba_role_privs b
 where a.username = b.grantee
   and b.grantee not in ('SYS',
                         'SYSTEM',
                         'OEMDBA',
                         'DTBACKUP',
                         'SYSMAN',
                         'SITESCOPE',
                         'PERFMON',
                         'LBACSYS',
                         'EMONDBO',
                         'DBSNMP',
                         'CI_USER')
   and b.granted_role <> 'DBA'
      --and a.ACCOUNT_STATUS not in  ('LOCKED')
   and a.account_status not like 'EXPIRED%LOCKED%'
   and a.username like '206420631'
 order by 1,
          2 asc;
```


```sql
select x.sid,
       x.serial#,
       x.username,
       x.sql_id,
       x.sql_child_number,
       optimizer_mode,
       hash_value,
       address,
       sql_text
  from gv$sqlarea sqlarea,
       gv$session x
 where x.sql_hash_value = sqlarea.hash_value
   and x.sql_address = sqlarea.address
   and x.username is not null;

```