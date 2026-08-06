SET DEFINE ON
-- ========= MINIMAL
-- drop table candidates 
create   -- drop 
 table candidates as 
SELECT t.owner,
       t.table_name,
       t.num_rows
  FROM all_tables t
 WHERE 1 = 1
   AND t.owner IN ('A', 'B')
   AND t.num_rows > 20000
   AND NOT regexp_like(t.table_name,'^TMP|^TBL')   
 ORDER BY t.owner    DESC,
          t.num_rows DESC NULLS LAST;
create index cand_idx  on candidates  (owner, table_name);
 