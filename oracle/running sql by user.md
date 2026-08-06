#query #session #sql #user 
```sql
--Know which query running for user
select x.sid
      ,x.serial#
      ,x.username
      ,x.sql_id
      ,x.sql_child_number
      ,optimizer_mode
      ,hash_value
      ,address
      ,sql_text
from   gv$sqlarea sqlarea
      ,gv$session x
where  x.sql_hash_value = sqlarea.hash_value
and    x.sql_address    = sqlarea.address
and    x.username  = '206533857';--     is not null;
```