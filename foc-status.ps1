# Get Failover Cluster Status info

$ClusterName = "hvcluster"
$DocumentServer = "192.168.5.26"
$DocumentServerPort = "5551"

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

Import-Module FailoverClusters

###
# Get Cluster Nodes Info
###
$Tag = "foc-nodes-status"
$ClusterOwnerNode = (Get-ClusterGroup -Cluster $ClusterName -Name "Cluster Group").OwnerNode.NodeName
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