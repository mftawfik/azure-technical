Analyzing Resource Consumption on Azure Virtual Machines using Azure Monitor Insights and Logs
This guide explains how to monitor and analyze resource consumption, such as CPU and memory usage, on Azure Virtual Machines (VMs). Using Azure Monitor Insights and Log Analytics, we’ll set up detailed monitoring and use custom Kusto Query Language (KQL) queries to pinpoint high-resource usage processes.

Prerequisites
An Azure Virtual Machine: Ensure you have an active VM instance you want to monitor.
Log Analytics Workspace: This is required to store log data. You can create one in the Azure Portal.
Steps
Step 1: Enable Azure Monitor Insights for the Virtual Machine
Go to the Azure Portal.
Navigate to your VM, then select Monitoring > Insights from the sidebar.
Select Enable if Insights is not already enabled. This activates the collection of essential performance metrics like CPU, Memory, and Network usage.
Step 2: View Basic Metrics
Once Insights is enabled, navigate to Metrics under the VM’s Monitoring section.

Here, you’ll find graphs displaying basic metrics, such as:

CPU Utilization
Memory Usage
Network Activity
These metrics provide a quick overview but may lack detailed information about individual processes.

Step 3: Enable Log Analytics for Advanced Analysis
Within the VM’s Insights section, select Logs. This will open Log Analytics, allowing you to perform custom queries.
Link your VM to a Log Analytics Workspace if prompted. This is where detailed log data will be stored and analyzed.
Step 4: Write Custom KQL Queries for In-Depth Insights
Kusto Query Language (KQL) is a powerful query language for Azure Log Analytics. The following are some useful queries to analyze CPU and memory usage.

Query 1: Top Processes by CPU Usage
This query shows the top processes consuming CPU resources over a 5-minute period.

kusto
Copy code
Perf
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| summarize AvgCPU = avg(CounterValue) by InstanceName, bin(TimeGenerated, 5m)
| top 10 by AvgCPU desc
Query 2: Processes with High Memory Consumption
This query shows the amount of available memory in MB over time, with a focus on low memory availability.

kusto
Copy code
Perf
| where ObjectName == "Memory" and CounterName == "Available MBytes"
| summarize AvgMemory = avg(CounterValue) by bin(TimeGenerated, 5m)
| order by AvgMemory asc
Tip: Adjust the time intervals and add filters based on your VM’s requirements to focus on specific time frames or processes.

Step 5: Monitor Individual Processes
For even more detail, consider enabling Azure Diagnostics Extension. This will allow you to:

Collect Windows Event Logs (for Windows VMs) or Syslog (for Linux VMs).
Identify specific applications and services consuming high CPU or memory resources.
Step 6: Set Up Alerts for Resource Thresholds
Using Azure Monitor, you can set up alerts to notify you when certain thresholds are exceeded. This can include high CPU or memory usage.

Go to Alerts under Monitor in the Azure Portal.
Define the alert criteria, such as CPU utilization greater than 80%, and specify notification preferences.
Conclusion
With Azure Monitor Insights and custom KQL queries, you can gain in-depth insights into your VM's resource usage. By regularly monitoring your VM and setting up alerts, you’ll be able to address resource bottlenecks and maintain optimal performance.

Feel free to experiment with different queries and adjust as needed for your environment!
