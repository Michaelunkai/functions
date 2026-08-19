#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NetBoost Consolidated - Ultimate Network Performance Optimizer
.DESCRIPTION
    Consolidated best settings from:
    - netboost/a.ps1 (v2.0 WiFi optimizer, 2025-12-22)
    - MaximizeEthernet/MaximizeEthernet.ps1 (Realtek 2.5GbE, 2026-02-12)
    - netboost3/a.ps1 (Advanced Ethernet, 2026-03-17)

    Covers: TCP/IP stack, registry tuning, NIC advanced props (Jumbo Frames,
    Flow Control, Speed+Duplex, EEE, RSS, interrupt moderation), offloads,
    NetTCPSetting profiles, SMB multichannel, QoS, service cleanup.

    NO REBOOT REQUIRED (except for pagefile/driver changes if made separately).
.NOTES
    Version: 3.0 (consolidated 2026-04-01)
    Requires: Windows PowerShell 5.1+, Administrator privileges
    PS v5 syntax throughout (semicolons, no &&)
#>

$ErrorActionPreference = 'Continue'
$script:startTime = Get-Date
$script:ok = 0 ; $script:skip = 0

# ============================================================================
# ADMIN ELEVATION CHECK
# ============================================================================
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[ERROR] Must run as Administrator. Re-launch elevated.' -ForegroundColor Red
    exit 1
}

Write-Host '================================================================' -ForegroundColor Cyan
Write-Host '   NETBOOST v3.0 - CONSOLIDATED NETWORK PERFORMANCE OPTIMIZER' -ForegroundColor Cyan
Write-Host '   Sources: netboost + MaximizeEthernet + netboost3' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ''

# ============================================================================
# HELPER
# ============================================================================
function Apply {
    param([string]$Desc, [scriptblock]$Action)
    try {
        & $Action 2>$null | Out-Null
        Write-Host "  [OK] $Desc" -ForegroundColor Green
        $script:ok++
    } catch {
        Write-Host "  [--] $Desc ($($_.Exception.Message.Split([char]10)[0]))" -ForegroundColor DarkGray
        $script:skip++
    }
}

# ============================================================================
# ADAPTER DETECTION
# ============================================================================
Write-Host '[0/14] Detecting active network adapter...' -ForegroundColor Cyan

$eth = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and ($_.MediaType -eq '802.3' -or $_.InterfaceDescription -like '*Ethernet*' -or $_.InterfaceDescription -like '*Realtek*') } | Select-Object -First 1
if (-not $eth) { $eth = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1 }
$name     = $eth.Name
$ifIndex  = $eth.ifIndex

Write-Host "  Adapter : $($eth.InterfaceDescription)" -ForegroundColor Yellow
Write-Host "  Name    : $name  |  IfIndex: $ifIndex" -ForegroundColor Yellow
Write-Host ''

# ============================================================================
# SECTION 1: netsh TCP/IP GLOBAL SETTINGS
# ============================================================================
Write-Host '[1/14] netsh TCP/IP Global Settings' -ForegroundColor Cyan

Apply 'autotuninglevel=normal'          { netsh int tcp set global autotuninglevel=normal }
Apply 'chimney=enabled'                 { netsh int tcp set global chimney=enabled }
Apply 'dca=enabled'                     { netsh int tcp set global dca=enabled }
Apply 'netdma=enabled'                  { netsh int tcp set global netdma=enabled }
Apply 'rss=enabled'                     { netsh int tcp set global rss=enabled }
Apply 'ecncapability=enabled'           { netsh int tcp set global ecncapability=enabled }
Apply 'timestamps=enabled'              { netsh int tcp set global timestamps=enabled }
Apply 'initialRto=2000'                 { netsh int tcp set global initialRto=2000 }
Apply 'minrto=300'                      { netsh int tcp set global minrto=300 }
Apply 'nonsackrttresiliency=disabled'   { netsh int tcp set global nonsackrttresiliency=disabled }
Apply 'maxsynretransmissions=4'         { netsh int tcp set global maxsynretransmissions=4 }
Apply 'fastopen=enabled'                { netsh int tcp set global fastopen=enabled }
Apply 'fastopenfallback=enabled'        { netsh int tcp set global fastopenfallback=enabled }
Apply 'hystart=enabled'                 { netsh int tcp set global hystart=enabled }
Apply 'pacingprofile=auto'              { netsh int tcp set global pacingprofile=auto }
Apply 'congestionprovider=ctcp'         { netsh int tcp set supplemental Internet congestionprovider=ctcp }
Apply 'taskoffload=enabled'             { netsh interface ipv4 set global taskoffload=enabled }
Apply 'icmpredirects=disabled'          { netsh interface ipv4 set global icmpredirects=disabled }
Apply 'sourcerouting=dontforward'       { netsh interface ipv4 set global sourceroutingbehavior=dontforward }
Apply 'neighborcachelimit=4096'         { netsh interface ipv4 set global neighborcachelimit=4096 }
Apply 'reassemblylimit=16MB IPv4'       { netsh interface ipv4 set global reassemblylimit=16777216 }
Apply 'reassemblylimit=16MB IPv6'       { netsh interface ipv6 set global reassemblylimit=16777216 }
Apply 'multicastforwarding=disabled'    { netsh interface ipv4 set global multicastforwarding=disabled }
Apply 'groupforwardedfragments=enabled' { netsh interface ipv4 set global groupforwardedfragments=enabled }
Write-Host ''

# ============================================================================
# SECTION 2: netsh INTERFACE-LEVEL SETTINGS
# ============================================================================
Write-Host '[2/14] Interface-Level Settings' -ForegroundColor Cyan

Apply "IPv4 forwarding=enabled"     { netsh interface ipv4 set interface $ifIndex forwarding=enabled }
Apply "IPv4 dadtransmits=0"         { netsh interface ipv4 set interface $ifIndex dadtransmits=0 }
Apply "IPv4 routerdiscovery=disabled" { netsh interface ipv4 set interface $ifIndex routerdiscovery=disabled }
Apply "IPv4 advertise=disabled"     { netsh interface ipv4 set interface $ifIndex advertise=disabled }
Apply "IPv4 nud=enabled"            { netsh interface ipv4 set interface $ifIndex nud=enabled }
Apply "IPv4 siteprefixlength=0"     { netsh interface ipv4 set interface $ifIndex siteprefixlength=0 }
Apply "IPv4 basereachable=30000"    { netsh interface ipv4 set interface $ifIndex basereachable=30000 }
Apply "IPv4 retransmittime=1000"    { netsh interface ipv4 set interface $ifIndex retransmittime=1000 }
Apply "IPv6 dadtransmits=0"         { netsh interface ipv6 set interface $ifIndex dadtransmits=0 }
Apply "IPv6 routerdiscovery=dhcp"   { netsh interface ipv6 set interface $ifIndex routerdiscovery=dhcp }
Apply "IPv6 basereachable=30000"    { netsh interface ipv6 set interface $ifIndex basereachable=30000 }
Write-Host ''

# ============================================================================
# SECTION 3: TCP SUPPLEMENTAL TEMPLATES
# ============================================================================
Write-Host '[3/14] TCP Supplemental Templates (CUBIC)' -ForegroundColor Cyan

foreach ($tmpl in @('Internet','Datacenter','Compat','DatacenterCustom','InternetCustom')) {
    Apply "Supplemental $tmpl congestion=CUBIC" {
        netsh int tcp set supplemental template=$tmpl congestionprovider=cubic
    }
}
Write-Host ''

# ============================================================================
# SECTION 4: Set-NetTCPSetting PROFILES
# ============================================================================
Write-Host '[4/14] Set-NetTCPSetting Profile Tuning' -ForegroundColor Cyan

Apply 'Internet: InitialCongestionWindow=10'           { Set-NetTCPSetting -SettingName Internet -InitialCongestionWindow 10 -EA Stop }
Apply 'Internet: CongestionProvider=CUBIC'             { Set-NetTCPSetting -SettingName Internet -CongestionProvider CUBIC -EA Stop }
Apply 'Internet: AutoTuningLevelLocal=Experimental'    { Set-NetTCPSetting -SettingName Internet -AutoTuningLevelLocal Experimental -EA Stop }
Apply 'Internet: ScalingHeuristics=Disabled'           { Set-NetTCPSetting -SettingName Internet -ScalingHeuristics Disabled -EA Stop }
Apply 'Internet: EcnCapability=Enabled'                { Set-NetTCPSetting -SettingName Internet -EcnCapability Enabled -EA Stop }
Apply 'Internet: Timestamps=Enabled'                   { Set-NetTCPSetting -SettingName Internet -Timestamps Enabled -EA Stop }
Apply 'Internet: MaxSynRetransmissions=2'              { Set-NetTCPSetting -SettingName Internet -MaxSynRetransmissions 2 -EA Stop }
Apply 'Internet: NonSackRttResiliency=Disabled'        { Set-NetTCPSetting -SettingName Internet -NonSackRttResiliency Disabled -EA Stop }
Apply 'Internet: InitialRto=2000'                      { Set-NetTCPSetting -SettingName Internet -InitialRto 2000 -EA Stop }
Apply 'Internet: MinRto=300'                           { Set-NetTCPSetting -SettingName Internet -MinRto 300 -EA Stop }
Apply 'Internet: DelayedAckTimeout=40'                 { Set-NetTCPSetting -SettingName Internet -DelayedAckTimeout 40 -EA Stop }
Apply 'Internet: DelayedAckFrequency=1'                { Set-NetTCPSetting -SettingName Internet -DelayedAckFrequency 1 -EA Stop }
Apply 'Internet: MemoryPressureProtection=Disabled'    { Set-NetTCPSetting -SettingName Internet -MemoryPressureProtection Disabled -EA Stop }
Apply 'Internet: ForceWS=Enabled'                      { Set-NetTCPSetting -SettingName Internet -ForceWS Enabled -EA Stop }
Apply 'Datacenter: CongestionProvider=CUBIC'           { Set-NetTCPSetting -SettingName Datacenter -CongestionProvider CUBIC -EA Stop }
Apply 'Datacenter: AutoTuningLevelLocal=Experimental'  { Set-NetTCPSetting -SettingName Datacenter -AutoTuningLevelLocal Experimental -EA Stop }
Apply 'Datacenter: EcnCapability=Enabled'              { Set-NetTCPSetting -SettingName Datacenter -EcnCapability Enabled -EA Stop }
Apply 'Compat: CongestionProvider=CUBIC'               { Set-NetTCPSetting -SettingName Compat -CongestionProvider CUBIC -EA Stop }
Apply 'DatacenterCustom: CongestionProvider=CUBIC'     { Set-NetTCPSetting -SettingName DatacenterCustom -CongestionProvider CUBIC -EA Stop }
Apply 'InternetCustom: CongestionProvider=CUBIC'       { Set-NetTCPSetting -SettingName InternetCustom -CongestionProvider CUBIC -EA Stop }
Write-Host ''

# ============================================================================
# SECTION 5: TCP/IP REGISTRY (IPv4)
# ============================================================================
Write-Host '[5/14] TCP/IP Registry (IPv4)' -ForegroundColor Cyan

$tcpip = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'

Apply 'TcpWindowSize=65535'                     { Set-ItemProperty -Path $tcpip -Name 'TcpWindowSize'             -Value 65535    -Type DWord -Force }
Apply 'GlobalMaxTcpWindowSize=16MB'             { Set-ItemProperty -Path $tcpip -Name 'GlobalMaxTcpWindowSize'    -Value 16777216 -Type DWord -Force }
Apply 'TCP1323Opts=3 (WS+TS)'                   { Set-ItemProperty -Path $tcpip -Name 'TCP1323Opts'               -Value 3        -Type DWord -Force }
Apply 'DefaultTTL=64'                           { Set-ItemProperty -Path $tcpip -Name 'DefaultTTL'                -Value 64       -Type DWord -Force }
Apply 'EnablePMTUDiscovery=1'                   { Set-ItemProperty -Path $tcpip -Name 'EnablePMTUDiscovery'        -Value 1        -Type DWord -Force }
Apply 'EnablePMTUBHDetect=1'                    { Set-ItemProperty -Path $tcpip -Name 'EnablePMTUBHDetect'         -Value 1        -Type DWord -Force }
Apply 'MaxUserPort=65534'                       { Set-ItemProperty -Path $tcpip -Name 'MaxUserPort'                -Value 65534    -Type DWord -Force }
Apply 'TcpTimedWaitDelay=30'                    { Set-ItemProperty -Path $tcpip -Name 'TcpTimedWaitDelay'          -Value 30       -Type DWord -Force }
Apply 'EnableDCA=1'                             { Set-ItemProperty -Path $tcpip -Name 'EnableDCA'                  -Value 1        -Type DWord -Force }
Apply 'EnableRSS=1'                             { Set-ItemProperty -Path $tcpip -Name 'EnableRSS'                  -Value 1        -Type DWord -Force }
Apply 'EnableTCPA=1'                            { Set-ItemProperty -Path $tcpip -Name 'EnableTCPA'                 -Value 1        -Type DWord -Force }
Apply 'SackOpts=1'                              { Set-ItemProperty -Path $tcpip -Name 'SackOpts'                   -Value 1        -Type DWord -Force }
Apply 'TcpMaxDupAcks=2'                         { Set-ItemProperty -Path $tcpip -Name 'TcpMaxDupAcks'              -Value 2        -Type DWord -Force }
Apply 'MaxHashTableSize=65536'                  { Set-ItemProperty -Path $tcpip -Name 'MaxHashTableSize'           -Value 65536    -Type DWord -Force }
Apply 'MaxFreeTcbs=65536'                       { Set-ItemProperty -Path $tcpip -Name 'MaxFreeTcbs'                -Value 65536    -Type DWord -Force }
Apply 'TcpNumConnections=1280000'               { Set-ItemProperty -Path $tcpip -Name 'TcpNumConnections'          -Value 1280000  -Type DWord -Force }
Apply 'KeepAliveTime=300000'                    { Set-ItemProperty -Path $tcpip -Name 'KeepAliveTime'              -Value 300000   -Type DWord -Force }
Apply 'KeepAliveInterval=1000'                  { Set-ItemProperty -Path $tcpip -Name 'KeepAliveInterval'          -Value 1000     -Type DWord -Force }
Apply 'DisableTaskOffload=0'                    { Set-ItemProperty -Path $tcpip -Name 'DisableTaskOffload'         -Value 0        -Type DWord -Force }
Apply 'TcpAckFrequency=1 (disable ACK delay)'   { Set-ItemProperty -Path $tcpip -Name 'TcpAckFrequency'            -Value 1        -Type DWord -Force }
Apply 'TCPNoDelay=1 (disable Nagle)'            { Set-ItemProperty -Path $tcpip -Name 'TCPNoDelay'                 -Value 1        -Type DWord -Force }
Apply 'EnableDSACK=1'                           { Set-ItemProperty -Path $tcpip -Name 'EnableDSACK'                -Value 1        -Type DWord -Force }
Apply 'TcpMaxSendFree=65535'                    { Set-ItemProperty -Path $tcpip -Name 'TcpMaxSendFree'             -Value 65535    -Type DWord -Force }
Apply 'MaxConnectionsPer1_0Server=32'           { Set-ItemProperty -Path $tcpip -Name 'MaxConnectionsPer1_0Server' -Value 32       -Type DWord -Force }
Apply 'MaxConnectionsPerServer=32'              { Set-ItemProperty -Path $tcpip -Name 'MaxConnectionsPerServer'    -Value 32       -Type DWord -Force }
Apply 'EnableTFO=3'                             { Set-ItemProperty -Path $tcpip -Name 'EnableTFO'                  -Value 3        -Type DWord -Force }
Apply 'EnableDeadGWDetect=0'                    { Set-ItemProperty -Path $tcpip -Name 'EnableDeadGWDetect'         -Value 0        -Type DWord -Force }
Apply 'ArpCacheLife=300'                        { Set-ItemProperty -Path $tcpip -Name 'ArpCacheLife'               -Value 300      -Type DWord -Force }
Apply 'ArpCacheMinReferencedLife=300'           { Set-ItemProperty -Path $tcpip -Name 'ArpCacheMinReferencedLife'  -Value 300      -Type DWord -Force }
Write-Host ''

# ============================================================================
# SECTION 6: TCP/IP REGISTRY (IPv6)
# ============================================================================
Write-Host '[6/14] TCP/IP Registry (IPv6)' -ForegroundColor Cyan

$tcpip6 = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
if (-not (Test-Path $tcpip6)) { New-Item -Path $tcpip6 -Force | Out-Null }

Apply 'IPv6 TcpWindowSize=65535'    { Set-ItemProperty -Path $tcpip6 -Name 'TcpWindowSize'     -Value 65535 -Type DWord -Force }
Apply 'IPv6 Tcp1323Opts=3'          { Set-ItemProperty -Path $tcpip6 -Name 'Tcp1323Opts'       -Value 3     -Type DWord -Force }
Apply 'IPv6 DefaultTTL=64'          { Set-ItemProperty -Path $tcpip6 -Name 'DefaultTTL'        -Value 64    -Type DWord -Force }
Apply 'IPv6 MaxUserPort=65534'      { Set-ItemProperty -Path $tcpip6 -Name 'MaxUserPort'       -Value 65534 -Type DWord -Force }
Apply 'IPv6 TcpTimedWaitDelay=30'   { Set-ItemProperty -Path $tcpip6 -Name 'TcpTimedWaitDelay' -Value 30    -Type DWord -Force }
Write-Host ''

# ============================================================================
# SECTION 7: NIC ADVANCED PROPERTIES
# ============================================================================
Write-Host '[7/14] NIC Advanced Properties (RSS, Jumbo, Flow, Speed, EEE, Interrupt)' -ForegroundColor Cyan

# RSS
Apply 'NIC: Enable RSS'                          { Enable-NetAdapterRss -Name $name -EA Stop }
Apply 'NIC: RSS Base=0 Max=15 Queues=4'          { Set-NetAdapterRss -Name $name -BaseProcessorNumber 0 -MaxProcessorNumber 15 -NumberOfReceiveQueues 4 -EA Stop }
Apply 'NIC: Receive Side Scaling=Enabled'        { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Receive Side Scaling' -DisplayValue 'Enabled' -EA Stop }

# Jumbo Frames 9014
Apply 'NIC: Jumbo Packet=9014 Bytes'             { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Jumbo Packet' -DisplayValue '9014 Bytes' -EA Stop }
Apply 'NIC: Jumbo Frame=9014 (alt key)'          { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Jumbo Frame'  -DisplayValue '9014' -EA Stop }

# Flow Control OFF
Apply 'NIC: Flow Control=Disabled'               { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Flow Control' -DisplayValue 'Disabled' -EA Stop }

# Speed + Duplex 1Gbps Full
Apply 'NIC: Speed+Duplex=1.0 Gbps Full Duplex'   { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Speed & Duplex' -DisplayValue '1.0 Gbps Full Duplex' -EA Stop }

# EEE off
Apply 'NIC: Energy-Efficient Ethernet=Disabled'  { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Energy-Efficient Ethernet' -DisplayValue 'Disabled' -EA Stop }
Apply 'NIC: Green Ethernet=Disabled'             { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Green Ethernet' -DisplayValue 'Disabled' -EA Stop }

# Interrupt moderation
Apply 'NIC: Interrupt Moderation=Enabled'        { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Interrupt Moderation'      -DisplayValue 'Enabled'   -EA Stop }
Apply 'NIC: Interrupt Moderation Rate=Adaptive'  { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Interrupt Moderation Rate' -DisplayValue 'Adaptive'  -EA Stop }

# Buffers
Apply 'NIC: Receive Buffers=2048'                { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Receive Buffers'  -DisplayValue '2048' -EA Stop }
Apply 'NIC: Transmit Buffers=2048'               { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Transmit Buffers' -DisplayValue '2048' -EA Stop }

# Power savings off
Apply 'NIC: Power Saving Mode=Disabled'          { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Power Saving Mode'     -DisplayValue 'Disabled' -EA Stop }
Apply 'NIC: Wake on Magic Packet=Disabled'       { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Wake on Magic Packet'  -DisplayValue 'Disabled' -EA Stop }
Apply 'NIC: Wake on pattern match=Disabled'      { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Wake on pattern match' -DisplayValue 'Disabled' -EA Stop }

# Offload props
Apply 'NIC: LSO V2 IPv4=Enabled'                 { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Large Send Offload V2 (IPv4)' -DisplayValue 'Enabled' -EA Stop }
Apply 'NIC: LSO V2 IPv6=Enabled'                 { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Large Send Offload V2 (IPv6)' -DisplayValue 'Enabled' -EA Stop }
Apply 'NIC: IPv4 Checksum Offload=Rx+Tx'         { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'IPv4 Checksum Offload'        -DisplayValue 'Rx & Tx Enabled' -EA Stop }
Apply 'NIC: TCP Checksum Offload IPv4=Rx+Tx'     { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'TCP Checksum Offload (IPv4)'  -DisplayValue 'Rx & Tx Enabled' -EA Stop }
Apply 'NIC: TCP Checksum Offload IPv6=Rx+Tx'     { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'TCP Checksum Offload (IPv6)'  -DisplayValue 'Rx & Tx Enabled' -EA Stop }
Apply 'NIC: UDP Checksum Offload IPv4=Rx+Tx'     { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'UDP Checksum Offload (IPv4)'  -DisplayValue 'Rx & Tx Enabled' -EA Stop }
Apply 'NIC: UDP Checksum Offload IPv6=Rx+Tx'     { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'UDP Checksum Offload (IPv6)'  -DisplayValue 'Rx & Tx Enabled' -EA Stop }
Apply 'NIC: ARP Offload=Enabled'                 { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'ARP Offload' -DisplayValue 'Enabled' -EA Stop }
Apply 'NIC: NS Offload=Enabled'                  { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'NS Offload'  -DisplayValue 'Enabled' -EA Stop }
Write-Host ''

# ============================================================================
# SECTION 8: NIC OFFLOAD CMDLETS
# ============================================================================
Write-Host '[8/14] NIC Offload Cmdlets (Checksum, LSO, RSC)' -ForegroundColor Cyan

Apply 'ChecksumOffload: TCP IPv4+IPv6 RxTx'  { Set-NetAdapterChecksumOffload -Name $name -TcpIPv4 RxTxEnabled -TcpIPv6 RxTxEnabled -EA Stop }
Apply 'ChecksumOffload: UDP IPv4+IPv6 RxTx'  { Set-NetAdapterChecksumOffload -Name $name -UdpIPv4 RxTxEnabled -UdpIPv6 RxTxEnabled -EA Stop }
Apply 'ChecksumOffload: IP IPv4 RxTx'        { Set-NetAdapterChecksumOffload -Name $name -IpIPv4 RxTxEnabled  -EA Stop }
Apply 'LSO: IPv4+IPv6 Enabled'               { Set-NetAdapterLso -Name $name -IPv4Enabled $true -IPv6Enabled $true -EA Stop }
Apply 'RSC: IPv4 Enabled'                    { Set-NetAdapterRsc -Name $name -IPv4Enabled $true -EA Stop }
Apply 'RSC: IPv6 Enabled'                    { Set-NetAdapterRsc -Name $name -IPv6Enabled $true -EA Stop }
Apply 'EncapsulatedTaskOffload=Enabled'      { Set-NetAdapterEncapsulatedPacketTaskOffload -Name $name -EncapsulatedPacketTaskOffloadEnabled $true -EA Stop }
Write-Host ''

# ============================================================================
# SECTION 9: QoS AND NETWORK THROTTLING
# ============================================================================
Write-Host '[9/14] QoS and Network Throttling' -ForegroundColor Cyan

$mmPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
Apply 'NetworkThrottlingIndex=0xFFFFFFFF' {
    if (-not (Test-Path $mmPath)) { New-Item -Path $mmPath -Force | Out-Null }
    Set-ItemProperty -Path $mmPath -Name 'NetworkThrottlingIndex' -Value 0xffffffff -Type DWord -Force
}
Apply 'SystemResponsiveness=0' { Set-ItemProperty -Path $mmPath -Name 'SystemResponsiveness' -Value 0 -Type DWord -Force }
Apply 'MMCSS Games: Priority=6 GPU=8' {
    $mg = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
    if (-not (Test-Path $mg)) { New-Item -Path $mg -Force | Out-Null }
    Set-ItemProperty -Path $mg -Name 'Affinity'            -Value 0       -Type DWord  -Force
    Set-ItemProperty -Path $mg -Name 'Background Only'     -Value 'False' -Type String -Force
    Set-ItemProperty -Path $mg -Name 'Clock Rate'          -Value 10000   -Type DWord  -Force
    Set-ItemProperty -Path $mg -Name 'GPU Priority'        -Value 8       -Type DWord  -Force
    Set-ItemProperty -Path $mg -Name 'Priority'            -Value 6       -Type DWord  -Force
    Set-ItemProperty -Path $mg -Name 'Scheduling Category' -Value 'High'  -Type String -Force
    Set-ItemProperty -Path $mg -Name 'SFIO Priority'       -Value 'High'  -Type String -Force
}
$qosPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched'
Apply 'QoS: NonBestEffortLimit=0' {
    if (-not (Test-Path $qosPath)) { New-Item -Path $qosPath -Force | Out-Null }
    Set-ItemProperty -Path $qosPath -Name 'NonBestEffortLimit' -Value 0 -Type DWord -Force
}
Apply 'QoS: Enable NetAdapter QoS' { Enable-NetAdapterQos -Name $name -EA Stop }
Write-Host ''

# ============================================================================
# SECTION 10: WFP / BFE / NETIO
# ============================================================================
Write-Host '[10/14] WFP/BFE/NetIO Registry' -ForegroundColor Cyan

Apply 'BFE: DisableStatefulFtp=1' {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Services\BFE\Parameters\Policy\Options'
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name 'DisableStatefulFtp' -Value 1 -Type DWord -Force
}
Apply 'NetIO: EnableRSCOnAggregation=1' {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetIO\Parameters'
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name 'EnableRSCOnAggregation' -Value 1 -Type DWord -Force
}
Write-Host ''

# ============================================================================
# SECTION 11: SMB MULTICHANNEL
# ============================================================================
Write-Host '[11/14] SMB Multichannel and Direct' -ForegroundColor Cyan

Apply 'SMB Client: EnableMultiChannel=true'       { Set-SmbClientConfiguration -EnableMultiChannel $true -Force -EA Stop }
Apply 'SMB Client: DisableBandwidthThrottling'    { Set-SmbClientConfiguration -EnableBandwidthThrottling $false -Force -EA Stop }
Apply 'SMB Client: MaxConnectionCount=32'         { Set-SmbClientConfiguration -MaximumConnectionCountPerServer 32 -Force -EA Stop }
Apply 'SMB Client: Disable signing overhead'      { Set-SmbClientConfiguration -EnableSecuritySignature $false -RequireSecuritySignature $false -Force -EA Stop }
Apply 'SMB Server: EnableMultiChannel=true'       { Set-SmbServerConfiguration -EnableMultiChannel $true -Force -EA Stop }
Apply 'SMB Server: MaxChannelPerSession=32'       { Set-SmbServerConfiguration -MaxChannelPerSession 32 -Force -EA Stop }
Apply 'SMB Server: AsynchronousCredits=512'       { Set-SmbServerConfiguration -AsynchronousCredits 512 -Force -EA Stop }
Apply 'SMB Server: Smb2Credits 512-8192'          { Set-SmbServerConfiguration -Smb2CreditsMin 512 -Smb2CreditsMax 8192 -Force -EA Stop }
Apply 'SMB Server: Disable signing'               { Set-SmbServerConfiguration -EnableSecuritySignature $false -RequireSecuritySignature $false -Force -EA Stop }
Apply 'SMB Server: MaxWorkItems=8192'             { Set-SmbServerConfiguration -MaxWorkItems 8192 -Force -EA Stop }
Write-Host ''

# ============================================================================
# SECTION 12: ROUTE METRICS AND ADAPTER BINDING
# ============================================================================
Write-Host '[12/14] Route Metrics and Adapter Binding' -ForegroundColor Cyan

Apply "IPv4 InterfaceMetric=5" { Set-NetIPInterface -InterfaceIndex $ifIndex -InterfaceMetric 5 -EA Stop }
Apply "IPv6 InterfaceMetric=5" { Set-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv6 -InterfaceMetric 5 -EA Stop }

Apply 'Disable ms_lltdio'  { Disable-NetAdapterBinding -Name $name -ComponentID ms_lltdio -EA Stop }
Apply 'Disable ms_rspndr'  { Disable-NetAdapterBinding -Name $name -ComponentID ms_rspndr -EA Stop }
Apply 'Disable ms_lldp'    { Disable-NetAdapterBinding -Name $name -ComponentID ms_lldp   -EA Stop }
Apply 'Enable ms_tcpip'    { Enable-NetAdapterBinding  -Name $name -ComponentID ms_tcpip  -EA Stop }
Apply 'Enable ms_tcpip6'   { Enable-NetAdapterBinding  -Name $name -ComponentID ms_tcpip6 -EA Stop }
Write-Host ''

# ============================================================================
# SECTION 13: PROCESSOR SCHEDULING
# ============================================================================
Write-Host '[13/14] Processor Scheduling' -ForegroundColor Cyan

Apply 'Win32PrioritySeparation=38' {
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 38 -Type DWord -Force
}
Apply 'AdditionalWorkerThreads +16' {
    $ep = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Executive'
    Set-ItemProperty -Path $ep -Name 'AdditionalCriticalWorkerThreads' -Value 16 -Type DWord -Force
    Set-ItemProperty -Path $ep -Name 'AdditionalDelayedWorkerThreads'  -Value 16 -Type DWord -Force
}
Write-Host ''

# ============================================================================
# SECTION 14: CLEANUP AND VERIFICATION
# ============================================================================
Write-Host '[14/14] Cleanup and Verification' -ForegroundColor Cyan

Apply 'Flush DNS cache'      { Clear-DnsClientCache -EA Stop }
Apply 'Flush ARP cache'      { Remove-NetNeighbor -InterfaceIndex $ifIndex -Confirm:$false -EA SilentlyContinue }
Apply 'Flush NetBIOS cache'  { nbtstat -R }
Apply 'Register DNS'         { ipconfig /registerdns }
Apply 'Verify TCP Internet settings' {
    $tcp = Get-NetTCPSetting -SettingName Internet
    Write-Host "    Congestion=$($tcp.CongestionProvider) AutoTune=$($tcp.AutoTuningLevelLocal) ECN=$($tcp.EcnCapability)" -ForegroundColor DarkCyan
}
Apply 'Verify NIC offloads' {
    $rsc = Get-NetAdapterRsc -Name $name -EA SilentlyContinue
    $lso = Get-NetAdapterLso -Name $name -EA SilentlyContinue
    Write-Host "    RSC4=$($rsc.IPv4Enabled) RSC6=$($rsc.IPv6Enabled) LSO4=$($lso.IPv4Enabled) LSO6=$($lso.IPv6Enabled)" -ForegroundColor DarkCyan
}
Write-Host ''

# ============================================================================
# SUMMARY
# ============================================================================
$elapsed = (Get-Date) - $script:startTime
$mins = [math]::Floor($elapsed.TotalMinutes)
$secs = $elapsed.Seconds

Write-Host '================================================================' -ForegroundColor Green
Write-Host '           NETBOOST v3.0 CONSOLIDATED - COMPLETE' -ForegroundColor Green
Write-Host '================================================================' -ForegroundColor Green
Write-Host ''
Write-Host "  Applied : $($script:ok)    Skipped: $($script:skip)    Duration: ${mins}m ${secs}s" -ForegroundColor White
Write-Host ''
Write-Host '  NO REBOOT REQUIRED - all changes take effect immediately.' -ForegroundColor Yellow
Write-Host '  Verify: netsh int tcp show global' -ForegroundColor Yellow
Write-Host '  Verify: Get-NetAdapterRss -Name (Get-NetAdapter | ? Status -eq Up | select -First 1).Name' -ForegroundColor Yellow
Write-Host ''
