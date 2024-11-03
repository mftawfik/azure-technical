
# Analyzing Resource Consumption on Azure Virtual Machines using Azure Monitor Insights and Logs

This guide explains how to monitor and analyze resource consumption, such as CPU and memory usage, on Azure Virtual Machines (VMs). Using **Azure Monitor Insights** and **Log Analytics**, we’ll set up detailed monitoring and use custom Kusto Query Language (KQL) queries to pinpoint high-resource usage processes.

## Prerequisites
1. **An Azure Virtual Machine**: Ensure you have an active VM instance you want to monitor.
2. **Log Analytics Workspace**: This is required to store log data. You can create one in the **Azure Portal**.

---

## Steps

### Step 1: Enable Azure Monitor Insights for the Virtual Machine
1. Go to the **Azure Portal**.
2. Navigate to your VM, then select **Monitoring** > **Insights** from the sidebar.
3. Select **Enable** if Insights is not already enabled. This activates the collection of essential performance metrics like **CPU**, **Memory**, and **Network** usage.

### Step 2: View Basic Metrics
1. Once **Insights** is enabled, navigate to **Metrics** under the VM’s **Monitoring** section.
2. Here, you’ll find graphs displaying basic metrics, such as:
   - **CPU Utilization**
   - **Memory Usage**
   - **Network Activity**

   These metrics provide a quick overview but may lack detailed information about individual processes.

### Step 3: Enable Log Analytics for Advanced Analysis
1. Within the VM’s **Insights** section, select **Logs**. This will open **Log Analytics**, allowing you to perform custom queries.
2. Link your VM to a **Log Analytics Workspace** if prompted. This is where detailed log data will be stored and analyzed.

### Step 4: Write Custom KQL Queries for In-Depth Insights

**Kusto Query Language (KQL)** is a powerful query language for Azure Log Analytics. The following are some useful queries to analyze CPU and memory usage.

#### Query 1: Top Processes by CPU Usage
This query shows the top processes consuming CPU resources over a 5-minute period.

```
Perf
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| summarize AvgCPU = avg(CounterValue) by InstanceName, bin(TimeGenerated, 5m)
| top 10 by AvgCPU desc
```

#### Query 2: Processes with High Memory Consumption
This query shows the amount of available memory in MB over time, with a focus on low memory availability.

```
Perf
| where ObjectName == "Memory" and CounterName == "Available MBytes"
| summarize AvgMemory = avg(CounterValue) by bin(TimeGenerated, 5m)
| order by AvgMemory asc
```

> **Tip**: Adjust the time intervals and add filters based on your VM’s requirements to focus on specific time frames or processes.

### Step 5: Monitor Individual Processes with Azure Diagnostics Extension

To get a granular view of individual processes on your Azure VM, the **Azure Diagnostics Extension** can be configured to collect detailed log data, such as **Windows Event Logs** or **Syslog** for Linux VMs. This helps you track high-resource usage events, identify specific processes affecting performance, and troubleshoot issues more effectively.

#### 5.1 Enabling Azure Diagnostics Extension
1. **Navigate to the VM**:
   - Go to the **Azure Portal**.
   - Select your **VM** instance.

2. **Add the Diagnostics Extension**:
   - Under **Settings**, select **Extensions + Applications**.
   - Click **+ Add** to add a new extension.
   - Choose **Azure Diagnostics** from the list of available extensions.

3. **Configure the Diagnostics Settings**:
   - After selecting the extension, configure it to capture logs and metrics:
     - **Windows VMs**: Enable **Windows Event Logs** to capture events related to system, application, and security logs.
     - **Linux VMs**: Enable **Syslog** to capture standard system logs, typically located in `/var/log/syslog`.

4. **Customize Logs and Counters**:
   - Define specific performance counters for deeper insights:
     - **CPU Counters**: Capture counters like `% Processor Time` for each running process.
     - **Memory Counters**: Track memory metrics, such as **Process Working Set** and **Private Bytes**, for each process.
   - Enable additional counters, such as disk and network metrics, depending on the resources you want to monitor.

5. **Set Up Data Collection**:
   - Specify the **Log Analytics Workspace** where you want to send the diagnostic data.
   - Choose data retention settings if applicable, to manage how long the collected data will be stored.

#### 5.2 Advanced KQL Queries for Process-Level Analysis

Once Azure Diagnostics Extension is enabled, you’ll have access to detailed process logs in **Log Analytics**. Here are some advanced KQL queries to help you analyze individual processes:

- **Top Processes by CPU Usage Over Time**:
   This query provides insights into the processes consuming the most CPU resources over a specific time period.

   ```
   Perf
   | where ObjectName == "Process" and CounterName == "% Processor Time"
   | summarize AvgCPU = avg(CounterValue) by InstanceName, ProcessName, bin(TimeGenerated, 5m)
   | top 10 by AvgCPU desc
   ```

- **Top Processes by Memory Usage**:
   This query displays processes sorted by memory usage, allowing you to identify applications consuming large amounts of RAM.

   ```
   Perf
   | where ObjectName == "Process" and CounterName == "Working Set"
   | summarize AvgMemory = avg(CounterValue) by ProcessName, bin(TimeGenerated, 5m)
   | top 10 by AvgMemory desc
   ```

- **Tracking Specific Processes**:
   If you’re troubleshooting a particular process, you can filter the data to focus on it. Replace `ProcessName` with the exact process you want to track (e.g., `sqlservr` for SQL Server).

   ```
   Perf
   | where ObjectName == "Process" and ProcessName == "sqlservr"
   | summarize AvgCPU = avg(CounterValue), AvgMemory = avg(CounterValue) by bin(TimeGenerated, 5m)
   | order by TimeGenerated desc
   ```

#### 5.3 Analyzing Windows Event Logs or Syslog (Linux)

If you're tracking specific events or errors, Windows Event Logs (for Windows VMs) and Syslog (for Linux VMs) are essential. Here’s how to query these logs:

- **Querying Windows Event Logs**:
   Use this query to retrieve specific events from Windows logs, such as application crashes or system errors.

   ```
   Event
   | where Source == "Application Error" or Source == "System"
   | where EventLevelName == "Error" or EventLevelName == "Critical"
   | project TimeGenerated, EventLog, RenderedDescription
   | order by TimeGenerated desc
   ```

- **Querying Syslog for Linux Events**:
   This query fetches critical events from Syslog on Linux VMs. You can adjust it to filter specific event levels, such as **error** or **warning**.

   ```
   Syslog
   | where SeverityLevel <= 3  // Error or higher severity
   | project TimeGenerated, Facility, Computer, Message
   | order by TimeGenerated desc
   ```

#### 5.4 Using Alerts with Diagnostics Data
You can create **Alerts** based on specific diagnostic data, so you’re notified if certain processes exceed resource limits or if critical events occur.

1. Go to **Alerts** under **Monitor** in the Azure Portal.
2. Set up alert rules using **Log Analytics queries**. For instance:
   - Trigger an alert if a process’s CPU usage exceeds 80% consistently over 5 minutes.
   - Notify if a critical event appears in **Event Logs** or **Syslog**.

---

## Conclusion
With Azure Monitor Insights and custom KQL queries, you can gain in-depth insights into your VM's resource usage. By regularly monitoring your VM and setting up alerts, you’ll be able to address resource bottlenecks and maintain optimal performance.

Feel free to experiment with different queries and adjust as needed for your environment!
