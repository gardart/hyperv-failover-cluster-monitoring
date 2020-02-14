# Get Failover Cluster Status info

$ClusterName = "hvcluster"
$DocumentServer = "192.168.5.26"
$DocumentServerPort = "5551"

#region Functions
#----------------

# Send JSON data Over Tcp socket
Function Send-JsonOverTcp {
    param ( [ValidateNotNullOrEmpty()] 
    [string] $Ip, 
    [int] $Port, 
    $JsonObject) 
    $JsonString = $JsonObject -replace "`n",' ' -replace "`r",' ' -replace ' ',''
    $Socket = New-Object System.Net.Sockets.TCPClient($Ip,$Port) 
    $Stream = $Socket.GetStream() 
    $Writer = New-Object System.IO.StreamWriter($Stream)
    $Writer.WriteLine($JsonString)
    $Writer.Flush()
    $Stream.Close()
    $Socket.Close()
}

#endregion Functions

#region Modules
#----------------

Import-Module FailoverClusters

#endregion Modules

#region Variables
#----------------

$Yesterday = (get-date).AddDays(-1)
$LastHour = (get-date).AddHours(-1)

#endregion Variables

#region Gathering Cluster Information
#-----------------------------------------
 
$Tag = "foc-cluster-health"
$ClusterOwnerNode = (Get-ClusterGroup -Cluster $ClusterName -Name "Cluster Group").OwnerNode.NodeName
$ClusterInfo = Get-Cluster -Name $ClusterName | Select-Object -Property *
$ClusterEvents = Get-WinEvent system -ComputerName $ClusterOwnerNode | Where-Object {$_.TimeCreated -ge $LastHour} | Where-Object {($_.ProviderName -eq "Microsoft-Windows-FailoverClustering")}

# Get ClusterResource Data
$ClusterResourceData = Get-ClusterResource -Cluster $ClusterName

$ClusterInfoObject = New-Object PSObject -Property @{
    ClusterName             = $ClusterInfo.Name
    AutoBalancerMode        = $ClusterInfo.AutoBalancerMode     # https://docs.microsoft.com/en-us/previous-versions/windows/desktop/mscs/clusters-autobalancermode
    AutoBalancerLevel       = $ClusterInfo.AutoBalancerLevel   # https://docs.microsoft.com/en-us/previous-versions/windows/desktop/mscs/clusters-autobalancerlevel
    ClusterOwnerNode        = $ClusterOwnerNode
    ClusterEvents           = $ClusterEvents.Count
    ClusterVMRoles         = (Get-ClusterGroup -Cluster $ClusterName | ? { $_.GroupType –eq 'VirtualMachine' }).Count
    ClusterNodes            = (Get-ClusterNode -Cluster $ClusterName).Count
    ClusterCSVs             = (Get-ClusterSharedVolume -Cluster $ClusterName).Count
    OfflineVMConfig         = ($ClusterResourceData | where{($_.ResourceType -eq "Virtual Machine Configuration") -and ($_.State -ne "Online")}).Count
    Tag                     = $Tag
}

$ClusterInfoObject = $ClusterInfoObject | ConvertTo-Json
Send-JsonOverTcp $DocumentServer $DocumentServerPort "$ClusterInfoObject"

###
# Get Cluster Nodes Info
###
$Tag = "foc-nodes-status"
$ClusterNodes = Get-ClusterNode -Cluster $ClusterName | Select-Object -Property *,@{Name = 'Tag'; Expression = {$Tag}}
$ClusterNodes = $ClusterNodes | ConvertTo-Json
Send-JsonOverTcp $DocumentServer $DocumentServerPort "$ClusterNodes"

###
# Get Cluster Shared Volumes Info
###
$Tag = "foc-csv-status"
$CSVs = Get-ClusterSharedVolume -Cluster $ClusterName

foreach ($CSV in $CSVs ){
    $CSVinfos = $CSV | Select-Object -Property Name,State -ExpandProperty SharedVolumeInfo
    foreach ( $CSVinfo in $CSVinfos ){
        $CSVObject = New-Object PSObject -Property @{
            FriendlyName    = $CSVinfo.Name
            Path            = $CSVinfo.FriendlyVolumeName
            Size            = $CSVinfo.Partition.Size
            FreeSpace       = $CSVinfo.Partition.FreeSpace
            UsedSpace       = $CSVinfo.Partition.UsedSpace
            MaintenanceMode = $CSVinfo.MaintenanceMode
            FaultState      = $CSVinfo.FaultState
            State           = $CSVinfo.State
            Tag             = $Tag
        }
    }
    # Convert to JSON and send to document server (Logstash / Telegraf)
    $CSVinfo = $CSVObject | Select-Object FriendlyName, Path, State, Size, FreeSpace, UsedSpace, MaintenanceMode, FaultState, Tag | ConvertTo-Json
    Send-JsonOverTcp $DocumentServer $DocumentServerPort "$CSVinfo"
}

#endregion