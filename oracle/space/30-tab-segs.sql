create table tab_segs  as 

SELECT 'TABLE' AS seg_type,
         c.owner,
         c.table_name,
         COUNT(1) as cnt ,
         round(SUM(s.bytes) / 1024 / 1024 / 1024, 2) AS gb
    FROM candidates c
    JOIN dba_segments s ON s.owner = c.owner
                       AND s.segment_name = c.table_name
                       AND s.segment_type IN ('TABLE', 'TABLE PARTITION', 'TABLE SUBPARTITION')
   GROUP BY c.owner,
            c.table_name