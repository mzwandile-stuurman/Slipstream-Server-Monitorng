@echo off
setlocal EnableDelayedExpansion
:: This is test batch script, just to get an alternative from powershell

:: PostgreSQL connection config
set PGUSER=postgres
set PGPASSWORD=mzwandile
set PGDATABASE=system_monitoring
set PGHOST=localhost
set PGPORT=5433

:: Timestamp
for /f "tokens=1-4 delims=/ " %%a in ("%date%") do (
    set MM=%%a
    set DD=%%b
    set YYYY=%%c
)
set timestamp=%YYYY%-%MM%-%DD% %time%

:: -------- SYSTEM METRICS --------
for /f "tokens=2 delims==" %%a in ('wmic cpu get loadpercentage /value') do set cpu=%%a
for /f "tokens=2 delims==" %%a in ('wmic OS get FreePhysicalMemory /value') do set mem=%%a
echo INSERT INTO system_metrics_batch (timestamp, cpu_load, free_memory_kb) VALUES ('%timestamp%', %cpu%, %mem%); | psql

:: -------- GET PROCESS MEMORY (tasklist) --------
set "memfile=%TEMP%\proc_mem.txt"
del "%memfile%" >nul 2>&1

for /f "skip=3 tokens=1,2,3,* delims=," %%A in ('tasklist /fo csv /nh') do (
    set "proc_name=%%~A"
    set "pid=%%~B"
    set "session=%%~C"
    set "mem=%%~D"

    set "mem=!mem:,=!"
    set "mem=!mem: K=!"

    echo !pid!,"!proc_name!",!mem!>>"%memfile%"
)

:: -------- GET CPU USAGE (typeperf) --------
set "cpufile=%TEMP%\proc_cpu.csv"
del "%cpufile%" >nul 2>&1

:: Collect CPU usage for all processes (one sample)
typeperf "\Process(*)\% Processor Time" -sc 1 > "%cpufile%" 2>nul

:: Remove quotes and first two lines
findstr /v /c:"\"(PDH" /c:"\"Time" "%cpufile%" > "%cpufile%.clean"
del "%cpufile%" >nul

:: -------- JOIN AND INSERT TOP 10 --------
:: Sort by memory descending
sort /r "%memfile%" > "%memfile%.sorted"

set count=0
for /f "tokens=1,2,3 delims=," %%a in (%memfile%.sorted) do (
    if !count! lss 10 (
        set /a count+=1
        set "pid=%%a"
        set "proc_name=%%b"
        set "mem_kb=%%c"
        set "cpu_val=0"

        :: Search cleaned CPU file for matching process name
        for /f "tokens=1,* delims=," %%x in (%cpufile%.clean) do (
            echo %%x | findstr /i "\\Process(!proc_name!)\\%% Processor Time" >nul
            if !errorlevel! == 0 (
                set "cpu_line=%%y"
                set "cpu_val=!cpu_line:"=!"
                goto :found
            )
        )
        :found

        :: Strip % if exists
        set "cpu_val=!cpu_val:~0,-1!"

        :: Placeholder for network (not accessible via native batch)
        set "net_in_bytes=0"
        set "net_out_bytes=0"

        echo INSERT INTO process_metrics (timestamp, pid, process_name, working_set_kb, cpu_percent, net_in_bytes, net_out_bytes) VALUES ('%timestamp%', !pid!, '!proc_name!', !mem_kb!, !cpu_val!, !net_in_bytes!, !net_out_bytes!); | psql
    )
)

:: Cleanup
del "%memfile%" >nul
del "%memfile%.sorted" >nul
del "%cpufile%.clean" >nul
endlocal
