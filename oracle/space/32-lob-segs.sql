create table lob_segs as 
       SELECT 'LOB' AS seg_type,
              c.owner,
              c.table_name,
       COUNT(1) as cnt ,
              round(SUM(s.bytes) / 1024 / 1024 / 1024, 2) AS gb       
       FROM candidates c
       JOIN dba_lobs l ON l.owner = c.owner
                     AND l.table_name = c.table_name
       JOIN dba_segments s ON s.owner = l.owner
                            AND s.segment_name IN (l.segment_name, l.index_name)
                            AND s.segment_type IN ('LOBSEGMENT', 'LOBINDEX', 'LOB PARTITION')
       GROUP BY c.owner,
              c.table_name
  