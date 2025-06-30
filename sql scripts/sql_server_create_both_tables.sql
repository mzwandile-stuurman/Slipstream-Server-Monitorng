/*CREATE TABLE dbo.process_monitor (
    id INT IDENTITY(1,1) PRIMARY KEY,
    name NVARCHAR(255),
    ram BIGINT,
    cpu DECIMAL(5,2),
    timestamp DATETIME NOT NULL,
    log_date DATE NOT NULL,
    cpu_percent DECIMAL(5,2)
);*/


/*CREATE TABLE dbo.system_metrics (
    id INT IDENTITY(1,1) PRIMARY KEY,
    timestamp DATETIME NOT NULL,
    log_date DATE NOT NULL,
    cpu_count INT,
    total_physical_memory BIGINT,
    total_net_sent BIGINT,
    total_net_received BIGINT,
    total_memory_mb DECIMAL(10,2),
    free_memory_mb DECIMAL(10,2),
    used_memory_mb DECIMAL(10,2),
    ram_percent_used DECIMAL(5,2),
    machine_name NVARCHAR(100),
    cpu_name NVARCHAR(255),
    cpu_load DECIMAL(5,2),
    max_clock_mhz INT,
    current_clock_mhz INT,
    process_count INT,
    thread_count INT,
    handle_count INT,
    system_uptime_seconds BIGINT,
    signal_strength INT,
    link_speed_mbps INT,
    disk_total_gb DECIMAL(10,2),
    disk_used_gb DECIMAL(10,2),
    disk_free_gb DECIMAL(10,2)
);*/

--TRUNCATE TABLE dbo.system_metrics;
--TRUNCATE TABLE dbo.process_monitor;
--select * from dbo.process_monitor
--select * from system_metrics