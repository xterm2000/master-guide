#database #trace #oracle  #operative 
```sql
begin
trace_session_prc(inp_nickname => 'NAME',inp_mode => 'ON',inp_test_subject => 'mytrace');
end;

begin
trace_session_prc(inp_nickname => 'NAME',inp_mode => 'OFF',inp_test_subject => 'mytrace');
end;

select * from trace_session t order by t.sdate desc

```

- Get trc file
- run command line tkprof on .trc file.