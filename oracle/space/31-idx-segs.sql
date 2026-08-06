create table idx_segs as 
    SELECT 'INDEX' AS seg_type,
        c.owner,
        c.table_name,
        COUNT(1) AS cnt,
        round(SUM(s.bytes) / 1024 / 1024 / 1024, 2) AS gb
    FROM candidates c
    JOIN dba_indexes i ON i.table_owner = c.owner
                        AND i.table_name = c.table_name
    JOIN dba_segments s ON s.owner = i.owner
                        AND s.segment_name = i.index_name
                        AND s.segment_type IN ('INDEX', 'INDEX PARTITION', 'INDEX SUBPARTITION')
    GROUP BY c.owner,
            c.table_name;
