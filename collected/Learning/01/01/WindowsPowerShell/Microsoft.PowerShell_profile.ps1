function 10sec {
    python "F:\\backup\windowsapps\Credentials\apps\WallpaperChanger\10sec.py"
}

function compile {
    echo 'C:\Users\micha\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0\LocalCache\local-packages\Python312\Scripts\pyinstaller.exe --onefile --icon=a.ico --windowed --name=Wishlist a.py'
}

function tinder {
    cd "C:/study/shells/powershell/scripts/bots"; ./tinderbot.ps1
}

function bumble {
    cd "C:/study/shells/powershell/scripts/bots"; ./bumble.ps1
}

function screen {
    Start-Sleep -Seconds 2; python F:\\study\programming\python\apps\screenshots\d.py
}

# Import the Chocolatey Profile that contains the necessary code to enable
# tab-completions to function for `choco`.
# Be aware that if you are missing these lines from your profile, tab completion
# for `choco` will not function.
# See https://ch0.co/tab-completion for details.
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path $ChocolateyProfile) {
    Import-Module "$ChocolateyProfile"
}



function brc {
    notepad $PROFILE
}

function cc {
    Clear-Host
}

function ubu {
    wsl -d Ubuntu --cd ~

}

function stack {
    python "F:\\study\programming\python\apps\scrapers\StackOverFlow\b.py"
}

function subs {
     python F:\\study\programming\python\apps\youtube\Playlists\toplaylist\g.py
}

function kali {
    wsl -d kali-linux
}

function down {
    cd "C:\users\misha\downloads"
}

function n {
    notepad
}

function stu {
    cd "F:\\study"
}

function backup {
    cd "F:\\backup"
}

function windowsapps {
    cd "F:\\backup\windowsapps"
}


function sprox {
    ssh root@192.168.1.222
}

function sshubu {
    ssh ubuntu@192.168.1.193
}

function sshubuntu {
    $pass="123456"; $user="ubuntu"; $ip="192.168.1.193"; plink.exe -ssh $user@$ip -pw $pass -t "bash --login"
}

function bashrc {
    Copy-Item -Path "\\wsl$\Ubuntu\root\.bashrc" -Destination "\\wsl$\kali-linux\root\.bashrc" -Force; Copy-Item -Path "\\wsl$\Ubuntu\root\.bashrc" -Destination "\\wsl$\kali-linux\home\$env:UserName\.bashrc" -Force; Write-Host "Copied .bashrc to both /root/.bashrc and ~/.bashrc in Kali Linux WSL2"
}

function linkedin {
    cd F:\\backup\windowsapps\Credentials\linkedin\LinkedIn-Easy-Apply-Bot; python 5.py
}

function publicip {
    curl checkip.amazonaws.com
}

function playlist {
    python F:\\study\programming\python\apps\youtube\Playlists\SearchAnDownloadPlaylist\a.py

}

function scpstu {
    stu; cd ..; scp -r study ubuntu@192.168.1.193:/home/ubuntu
}

function c {
    cd C:\
}

function gitpush {
    cd F:\\study; git commit -m "commit"; git push origin main
}

function gitadd {
    cd F:\\study; git add .
}

function gitgo {
        cd F:\\study; git add; git commit -m "commit"; git push origin main
}

function ubuntu2 {
    cd F:\\study\shells\powershell\scripts; ./setupWSL2ubuntureplicaWithouTshutdown.ps1
}

function rmubu2 {
     wsl --unregister ubuntu2
}

function ubu2 {
    wsl -d ubuntu2
}

function update {
    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser; Import-Module PSWindowsUpdate; Get-WindowsUpdate -AcceptAll -Install
}

function vid {
   python F:\\study\programming\python\apps\VideoRecordingScreen\d.py
}

function wsls {
    wsl --shutdown
}


function shrink {
    python F:\\study\programming\python\apps\shrink\Video_Audio_Shriker\a.py
}


function shrink2 {
    python F:\\study\programming\python\apps\shrink\Video_Audio_Shriker\b.py
}


function ccwsl {
     wsl --shutdown; Optimize-VHD -Path "C:\wsl2\ubuntu2\ext4.vhdx" -Mode Full; Optimize-VHD -Path "C:\wsl2\ubuntu2\ext4.vhdx" -Mode Quick; Optimize-VHD -Path "C:\wsl2\ubuntu\ext4.vhdx" -Mode Full; Optimize-VHD -Path "C:\wsl2\ubuntu\ext4.vhdx" -Mode Quick                   
}


function text {
    python F:\\study\programming\python\apps\media2text\image2text\a.py
}

function updatepip {
     C:\Users\micha\AppData\Local\Microsoft\WindowsApps\PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0\python.exe -m pip install --upgrade pip
}

function getpip {
    $scriptsPath = (python -c "import sys, os; print(os.path.join(sys.prefix, 'Scripts'))"); Remove-Item "$scriptsPath\pip.exe" -Force -ErrorAction SilentlyContinue; "@echo off`npython -m pip %*" | Out-File -FilePath "$scriptsPath\pip.bat" -Encoding ASCII; $env:PATH = "$scriptsPath;$env:PATH"; pip --version
}

function rmkali {
    wsl --unregister kali-linux; wsl --import kali-linux C:\wsl2 F:\\backup\linux\wsl\kalifull.tar; kali
}

function rmubu {
    wsl --unregister ubuntu; wsl --import ubuntu C:\wsl2\ubuntu\ F:\\backup\linux\wsl\ubuntu.tar; ubu
}

function rmk {
        wsl --unregister kali-linux; wsl --import kali-linux C:\wsl2 F:\\backup\linux\wsl\kalifull.tar; wsl --unregister ubuntu; wsl --import ubuntu C:\wsl2\ubuntu\ F:\\backup\linux\wsl\ubuntu.tar; kali
}

function rmu {
        wsl --unregister kali-linux; wsl --import kali-linux C:\wsl2 F:\\backup\linux\wsl\kalifull.tar; wsl --unregister ubuntu; wsl --import ubuntu C:\wsl2\ubuntu\ F:\\backup\linux\wsl\ubuntu.tar; ubu
}

function refresh {
     taskkill /f /im explorer.exe;  start explorer.exe
}

function refresh2  {
    shutdown /l
}

function update {
    Install-Module PSWindowsUpdate -Force; Import-Module PSWindowsUpdate; Get-WindowsUpdate; Install-WindowsUpdate -AcceptAll -Confirm
}


function export {
   wsl --export ubuntu F:\\backup\linux\ubuntu.tar; wsl --import ubuntu C:\wsl2\ubuntu\ F:\\backup\linux\wsl\ubuntu.tar
}

function track {
    cd F:\\study\programming\python\apps\study_tracker; python 4.py
}

function venv {
    cd F:\\backup\windowsapps; python -m venv venv; .\venv\Scripts\activate
}

function venv11 {
    cd F:\\backup\windowsapps; py -3.11 -m venv venv311; .\venv311\Scripts\activate
}

function word {
    Start-Process -FilePath "F:\\Program Files\\Microsoft Office\\root\\Office16\\WINWORD.EXE"
}

function reubu2 {
     rmubu2; ubuntu2
}


function defender {
    Start-Process "windowsdefender:"
}

function wallp {
    cd F:\\study\shells\powershell\scripts; ./ChangeWallpaper.ps1
}


function cool {
    venv; cd F:\\study\programming\python\apps\cool_hardware; Start-Job -ScriptBlock { python b.py }

}

function fire {
     F:\\study\security\firewall\disable_firewall\firewall_disable.ps1
}


function autofill {
     python F:\\backup\windowsapps\Credentials\autofill\b.py
}


function editfill {
     nano F:\\backup\windowsapps\Credentials\autofill\b.py
}


function sshec2 {
    ssh -i "F:\\backup\windowsapps\Credentials\AWS\key.pem" ubuntu@54.173.176.93
}



function exubu2 {
    export; reubu2 
}



function fixwsl {
     cd F:\\study\shells\powershell\scripts; ./wsl_fixer.ps1
}


function 3way {
    Start-Process "F:\\study\platforms\windows\AutoHotkey\ThreePartSnap.ahk"
}


function webhtml {
    cd F:\\study\programming\python\apps\html\extractWebsiteHtml; python b.py
}

function scanfast {
    Start-MpScan -ScanType QuickScan
}

function scanfull {
   Start-MpScan -ScanType FullScan
}

function pya {
    python a.py
}



function upnet {
    try {
        # Reset TCP/IP stack
        netsh int ip reset

        # Release and renew IP address
        ipconfig /release
        ipconfig /renew

        # Reset Winsock catalog
        netsh winsock reset

        # Flush DNS cache
        ipconfig /flushdns
        Clear-DnsClientCache

        # Set TCP Global Parameters
        netsh int tcp set global autotuninglevel=normal
        netsh int tcp set global ecncapability=enabled
        netsh int tcp set global timestamps=disabled

        # Retrieve Wi-Fi adapter name
        $adapter = Get-NetAdapter | Where-Object {$_.Name -like "*Wi-Fi*"}
        if ($adapter) {
            # Disable Large Send Offload (LSO)
            Disable-NetAdapterLso -Name $adapter.Name -ErrorAction SilentlyContinue

            # Disable Receive Side Scaling (RSS)
            Set-NetAdapterRss -Name $adapter.Name -Enabled $false -ErrorAction SilentlyContinue

            # Enable Packet Coalescing (only if available)
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Packet Coalescing" -DisplayValue "Enabled" -ErrorAction SilentlyContinue

            # Disable Large Send Offload v2 (IPv4 & IPv6)
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Large Send Offload v2 (IPv4)" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Large Send Offload v2 (IPv6)" -DisplayValue "Disabled" -ErrorAction SilentlyContinue

            # Enable Jumbo Frames (if supported)
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Jumbo Packet" -DisplayValue "9014" -ErrorAction SilentlyContinue

            # Disable Network Throttling Index
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "NetworkThrottlingIndex" -Value 0xffffffff -ErrorAction SilentlyContinue

            # Disable TCP Task Offload
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "DisableTaskOffload" -Value 1 -ErrorAction SilentlyContinue

            # Restart Wi-Fi adapter
            Restart-NetAdapter -Name $adapter.Name
        } else {
            Write-Host "Wi-Fi adapter not found. Skipping adapter-specific settings."
        }

        # DNS Settings
        Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses ("8.8.8.8", "8.8.4.4")

        # Set High Performance Power Plan
        powercfg -setactive SCHEME_MIN

        # Set Default Gateway Metric for faster routing
        $gateway = (Get-NetIPConfiguration | Where-Object {$_.InterfaceAlias -like "Wi-Fi"}).IPv4DefaultGateway
        if ($gateway) {
            Set-NetRoute -DestinationPrefix "0.0.0.0/0" -NextHop $gateway.NextHop -RouteMetric 1
        }

        Write-Host "Network optimizations applied. You may need to restart your computer."
    } catch {
        Write-Host "An error occurred: $_"
    }
}

function sshplex {
    ssh root@192.168.1.102
}

function pipreq {
    pip install -r requirements.txt
}


function streamlit {
     C:\Users\micha\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0\LocalCache\local-packages\Python312\Scripts\streamlit  run app.py
}



function backupec2 {
    New-Item -ItemType Directory -Force -Path C:\users\misha\downloads\ec2\apps, C:\users\misha\downloads\ec2\services
    scp -i "F:\\backup\windowsapps\Credentials\AWS\key.pem" -r ubuntu@54.173.176.93:/home/ubuntu/* C:\users\misha\downloads\ec2\apps
    scp -i "F:\\backup\windowsapps\Credentials\AWS\key.pem" ubuntu@54.173.176.93:/etc/systemd/system/wishlist.service C:\users\misha\downloads\ec2\services
    scp -i "F:\\backup\windowsapps\Credentials\AWS\key.pem" ubuntu@54.173.176.93:/etc/systemd/system/stickynotes.service C:\users\misha\downloads\ec2\services
    scp -i "F:\\backup\windowsapps\Credentials\AWS\key.pem" ubuntu@54.173.176.93:/etc/systemd/system/studytracker.service C:\users\misha\downloads\ec2\services
    scp -i "F:\\backup\windowsapps\Credentials\AWS\key.pem" ubuntu@54.173.176.93:/etc/systemd/system/speach2text.service C:\users\misha\downloads\ec2\services
    scp -i "F:\\backup\windowsapps\Credentials\AWS\key.pem" ubuntu@54.173.176.93:/etc/systemd/system/flask_file_explorer.service C:\users\misha\downloads\ec2\services
    wsl -d ubuntu -e sh -c 'cd /mnt/f/Users/micha/Downloads/ec2 && docker build -t michadockermisha/backup:ec2 . && docker push michadockermisha/backup:ec2'
}

function backupec2db {
    New-Item -ItemType Directory -Force -Path C:\users\misha\downloads\ec2
    scp -i "F:\\backup\windowsapps\Credentials\AWS\key.pem" ubuntu@54.173.176.93:/home/ubuntu/study_tracker/study_tracker.db C:\users\misha\downloads\ec2
    scp -i "F:\\backup\windowsapps\Credentials\AWS\key.pem" ubuntu@54.173.176.93:/home/ubuntu/wishlist/wishlist.db C:\users\misha\downloads\ec2
    scp -i "F:\\backup\windowsapps\Credentials\AWS\key.pem" ubuntu@54.173.176.93:/home/ubuntu/stickynotes/instance/notes.db C:\users\misha\downloads\ec2
    cp F:\\study\docker\dockerfiles\buildthispath C:\Users\micha\Downloads\ec2\Dockerfile
    wsl -d ubuntu -e sh -c 'cd /mnt/f/Users/micha/Downloads/ec2 && docker build -t michadockermisha/backup:ec2db . && docker push michadockermisha/backup:ec2db'
    Remove-Item -Recurse -Force C:\users\misha\downloads\ec2
}

function awsl {
    cd F:\\study\shells\powershell\scripts; ./WSL2_Ubuntu_Automation_Setup_Alias_Export.ps1
}


function logs {
    python3 F:\\study\programming\python\apps\study_Tracker\terminal\b.py
}


function nalias {
     nano C:\Users\micha\Desktop\alias.txt
}

function restorewsl {
    docker run -it -v /f/backup/linux/wsl:/f/ michadockermisha/backup:wsl sh -c "apk add rsync &&  rsync -av /home/ubuntu.tar /f && exit"
}



function ds { docker search $args }
function dps { docker ps --size }
function dpsa { docker ps -a --size }
function dim { docker images }
function built { param($tag) docker build -t $tag . }
function dp { docker push $args }
function drun { param($name) docker run -v "C:/:/c/" -it --name $name $args }
function dr { docker exec -it $args }
function drc { docker rm -f $args }
function dri { docker rmi -f $args }
function dc { docker commit $args }
function dkill { 
    docker stop (docker ps -aq) -ErrorAction SilentlyContinue; 
    docker rm (docker ps -aq) -ErrorAction SilentlyContinue; 
    docker rmi (docker images -q) -ErrorAction SilentlyContinue; 
    docker system prune -a --volumes --force; 
    docker network prune --force 
}
function conip { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $args }
function killc { docker stop $(docker ps -q); docker rm $(docker ps -aq) }
function dcu { docker-compose up -d }
function backupwsl { 
    Set-Location -Path "F:\\backup\linux\wsl"; 
    built michadockermisha/backup:wsl; 
    docker push michadockermisha/backup:wsl 
}
function backupapps { 
    Set-Location -Path "F:\\backup\windowsapps"; 
    built michadockermisha/backup:windowsapps; 
    docker push michadockermisha/backup:windowsapps 
}

function backitup {
    try {
        # Backup Windows apps
        Set-Location -Path "F:\\backup\windowsapps"
        built michadockermisha/backup:windowsapps
        docker push michadockermisha/backup:windowsapps

        # Backup study folder
        Set-Location -Path "F:\\study"
        docker build -t michadockermisha/backup:study .
        docker push michadockermisha/backup:study

        # Backup WSL
        Set-Location -Path "F:\\backup\linux\wsl"
        built michadockermisha/backup:wsl
        docker push michadockermisha/backup:wsl

        # Stop and remove any running containers to avoid conflicts
        docker stop $(docker ps -a -q) -ErrorAction Continue
        docker rm $(docker ps -a -q) -ErrorAction Continue

        # Clean up unused images to avoid conflicts
        docker rmi $(docker images -q --filter "dangling=true") -ErrorAction Continue
    }
    catch {
        Write-Error "An error occurred during the backup process: $_"
    }
}


function restoreapps { 
    drun windowsapps michadockermisha/backup:windowsapps "sh -c 'apk add rsync && rsync -aP /home /c/backup/ && cd /c/backup/ && mv home windowsapps && exit'" 
}


function RestoreLinux {
      docker run -it -v /c/backup/linux/wsl:/c/ michadockermisha/backup:wsl sh -c "apk add rsync &&  rsync -av /home/* /c "
}



function restorebackup { 
    Set-Location -Path "C:\"; 
    mkdir backup; 
    restoreapps; 
    restorelinux 
}
function dcreds { 
    Set-Location -Path "F:\\backup\windowsapps\Credentials"; 
    built michadockermisha/backup:creds; 
    docker push michadockermisha/backup:creds 
}
function saveweb { 
    Set-Location -Path "C:\Users\micha\Videos\Webinars"; 
    drun webinars michadockermisha/backup:webinars "sh -c 'apk add rsync && rsync -av /home/* /c/Users/micha/Videos/Webinars && exit'"; 
    built michadockermisha/backup:webinars; 
    docker push michadockermisha/backup:webinars; 
    Remove-Item -Recurse .\* 
}
function gg { 
    Set-Location -Path "F:\\study"; 
    docker build -t michadockermisha/backup:study .; 
    docker push michadockermisha/backup:study 
}
function savegames { 
    Set-Location -Path "F:\\backup\gamesaves"; 
    drun gamesdata michadockermisha/backup:gamesaves "sh -c 'apk add rsync && rsync -aP /home/* /c/backup/gamesaves && exit'"; 
    built michadockermisha/backup:gamesaves; 
    docker push michadockermisha/backup:gamesaves; 
    Remove-Item -Recurse .\* 
}
function saveplex { 
    Set-Location -Path "F:\\backup\plex"; 
    drun plex michadockermisha/backup:plex "sh -c 'apk add rsync && rsync -aP /home/* /c/backup/plex && exit'"; 
    built michadockermisha/backup:plex; 
    docker push michadockermisha/backup:plex; 
    Remove-Item -Recurse .\* 
}
function drmariadb { 
    docker run -v "C:/:/c/" -it -d --name mariadb -e MYSQL_ROOT_PASSWORD=123456 -p 3307:3307 mariadb:latest; 
    Start-Sleep -Seconds 30; 
    docker exec -it mariadb mariadb -u root -p 
}
function dcode { 
    docker run -v "C:/:/c/" -e DISPLAY=$DISPLAY -v "/tmp/.X11-unix:/tmp/.X11-unix" -p 3000:3000 -it --rm --name my_container michadockermisha/backup:python "bash -c 'echo y | code --no-sandbox --user-data-dir=~/vscode-data && bash'" 
}
function mp3 { docker run --rm -v "$HOME/Downloads:/root/Downloads" dizcza/youtube-mp3 $args }
function mp4 { docker run --rm -i -e PGID=$(id -g) -e PUID=$(id -u) -v "$(pwd)":/workdir:rw mikenye/youtube-dl }
function getjenkins { 
    docker run -d -p 8080:8080 -p 50000:50000 -v jenkins_home:/var/jenkins_home --name jenkins jenkins/jenkins:lts; 
    Start-Sleep -Seconds 30; 
    docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 
}
function getkuma { 
    docker run -d --restart always -p 3001:3001 -v /var/kuma:/app/data louislam/uptime-kuma:1; 
    Start-Process chrome "http://localhost:3001" 
}
function getsplunk { 
    docker run -d --name splunk -p 8000:8000 -p 8088:8088 -p 8089:8089 -p 9997:9997 -e SPLUNK_START_ARGS="--accept-license" -e SPLUNK_PASSWORD="adminadmin" -v /home/user/splunk-data:/opt/splunk/var splunk/splunk:latest; 
    Start-Process chrome "http://localhost:8000" 
}


function bbb {
  cd F:\\study\shells\powershell\scripts; ./WSL2_Ubuntu_Automation_Setup_Alias_Export_backitup_backitup.ps1
}

function cfun {
    param(
        [string]$functionName
    )

    # Search for the function definition in the profile and display it
    Get-Content $PROFILE | Select-String -Pattern "function $functionName" -Context 0,10
}


function rmps {
    down; Remove-Item -Path "a.ps1" -Force; nano a.ps1
}

function rma {
    down; Remove-Item -Path "a.py"; nano a.py
}   


function rms {
    down; Remove-Item -Path "a.ps1"; nano a.ps1
}   



function applied {
    nano F:\\backup\windowsapps\Credentials\linkedin\LinkedIn-Easy-Apply-Bot\applied.txt 
}

function link {
    python F:\\study\programming\python\apps\bots\linkedin\linkedin150Bot.py
}


function pipit {
    pipreqs C:\Users\micha\Downloads --force --savepath C:\Users\micha\Downloads\requirements.txt; pip install -r C:\Users\micha\Downloads\requirements.txt; python C:\Users\micha\Downloads\a.py
}


function hardware {
    $system = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -Property Manufacturer, Model, Name, @{Name='TotalPhysicalMemory (GB)'; Expression={[math]::round($_.TotalPhysicalMemory / 1GB, 2)}}
    $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -Property Name, @{Name='Cores'; Expression={$_.NumberOfCores}}, @{Name='Threads'; Expression={$_.NumberOfLogicalProcessors}}, MaxClockSpeed
    $gpu = Get-CimInstance -ClassName Win32_VideoController | Select-Object -Property Name, @{Name='Memory (GB)'; Expression={[math]::round($_.AdapterRAM / 1GB, 2)}}, DriverVersion
    $ramTotal = Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
    $ramTotalGB = [math]::round($ramTotal.Sum / 1GB, 2)
    $ram = Get-CimInstance -ClassName Win32_PhysicalMemory | Select-Object -Property Manufacturer, @{Name='Capacity (GB)'; Expression={[math]::round($_.Capacity / 1GB, 2)}}, Speed
    $disk = Get-CimInstance -ClassName Win32_DiskDrive | Select-Object -Property Model, @{Name='Size (GB)'; Expression={[math]::round($_.Size / 1GB, 2)}}
    $bios = Get-CimInstance -ClassName Win32_BIOS | Select-Object -Property Manufacturer, Version, ReleaseDate
    $network = Get-CimInstance -ClassName Win32_NetworkAdapter | Where-Object {$_.NetConnectionStatus -eq 2} | Select-Object -First 1 -Property Name, MACAddress
    
    "System Information:"
    $system
    "Processor Information:"
    $cpu
    "Graphics Information:"
    $gpu
    "Total RAM (GB): $ramTotalGB"
    "RAM Information:"
    $ram
    "Disk Information:"
    $disk
    "BIOS Information:"
    $bios
    "Primary Network Adapter:"
    $network
}

function mygames {
    cd F:\\study\programming\python\apps\game_tracker; python h.py
}



function sweb {   
    cd F:\\study\shells\powershell\scripts; ./WSL2_Ubuntu_Automation_Setup_Alias_Export_backitup_saveweb.ps1
}

function InstallAndRun-DockerDesktop {
    # Install Docker Desktop
    Write-Host "Installing Docker Desktop..."
    winget install -e --id Docker.DockerDesktop --silent
    
    # Check if installation was successful
    if ($?) {
        Write-Host "Docker Desktop installed successfully."
        
        # Find Docker Desktop executable path
        $dockerPath = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
        
        if (Test-Path $dockerPath) {
            Write-Host "Starting Docker Desktop..."
            Start-Process -FilePath $dockerPath
        } else {
            Write-Error "Docker Desktop executable not found at $dockerPath"
        }
    } else {
        Write-Error "Failed to install Docker Desktop"
    }
}


function slink {
    cd F:\\backup\windowsapps\Credentials\linkedin\LinkedIn-Easy-Apply-Bot
}

function wslgg {
     cd F:\\study\Shells\powershell\scripts; ./WSL2_Ubuntu_Automation_Setup_Alias_Export_gg.ps1
}


function telebot {
    pip install telethon tqdm; cd F:\\backup\windowsapps\Credentials\telegram\bot; python download_videos_from_telegram_group4.py
}


function refresh3 {    
    Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | Stop-Process -Force
}



function rjoy {
    taskkill /F /IM joytokey.exe;
    cd "C:\Program Files (x86)\JoyToKey";
    powershell Start-Process "joytokey.exe" -Verb RunAs
}



function cbackup {
    cleanapps; cleanwsl
}

function pipit {
    pip install pipreqs
    pipreqs . --force --savepath requirements.txt
    pip install -r requirements.txt
    python app.py
}


function pipit2 {
    pip install pipreqs
    pipreqs . --force --savepath requirements.txt
    pip install -r requirements.txt
    python a.py
}

function ex {
    exit
}

function nwsl {
    # Set variables for backup and import paths
    $BackupPath = "F:\\backup\linux\wsl\ubuntu.tar"
    $InstallPath = "C:\wsl2\ubuntu\"

    # Export the current WSL distribution
    Write-Host "Exporting Ubuntu... This may take a few minutes."
    wsl --export ubuntu $BackupPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to export Ubuntu. Exiting."
        return
    }
    Write-Host "Export completed successfully."

    # Unregister the WSL distribution
    Write-Host "Unregistering Ubuntu..."
    wsl --unregister ubuntu
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to unregister Ubuntu. Exiting."
        return
    }
    Write-Host "Ubuntu unregistered successfully."

    # Import the WSL distribution to a new path
    Write-Host "Importing Ubuntu... This may take a few minutes."
    wsl --import ubuntu $InstallPath $BackupPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to import Ubuntu. Exiting."
        return
    }
    Write-Host "Import completed successfully."

    # Unregister any secondary distribution (e.g., ubuntu2)
    if (wsl -l -v | Select-String "ubuntu2") {
        Write-Host "Unregistering ubuntu2..."
        wsl --unregister ubuntu2
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to unregister ubuntu2. Exiting."
            return
        }
        Write-Host "ubuntu2 unregistered successfully."
    } else {
        Write-Host "No secondary distribution (ubuntu2) found."
    }

    # Start the distribution
    Write-Host "Starting Ubuntu..."
    wsl -d ubuntu
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to start Ubuntu. Exiting."
        return
    }
    Write-Host "Ubuntu started successfully."
}



function rmqb {
    Stop-Process -Name "qbittorrent" -Force -ErrorAction SilentlyContinue; Get-WmiObject -Query "SELECT * FROM Win32_Product WHERE Name = 'qBittorrent'" | ForEach-Object { $_.Uninstall() }; Remove-Item -Path "$env:LOCALAPPDATA\qBittorrent","$env:APPDATA\qBittorrent","C:\Program Files\qBittorrent","C:\Program Files (x86)\qBittorrent" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -Path "HKCU:\Software\qBittorrent","HKLM:\SOFTWARE\qBittorrent","HKLM:\SOFTWARE\WOW6432Node\qBittorrent" -Recurse -Force -ErrorAction SilentlyContinue
}



function qb {
    F:\\backup\windowsapps\install\qbittorrent_4.6.0_x64_setup.exe
}


function cchrome {
    Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue; Remove-Item -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cookies" -Force -ErrorAction SilentlyContinue; Start-Process "chrome.exe"
}


function logs2 {
    cd F:\\study\Shells\powershell\scripts; ./automate_adding_latest_created_file_to_logs.ps1
}


function doc {
    cd C:\Users\micha\Documents
}

function mas {
    cd F:\\backup\windowsapps\install\Microsoft-Activation-Scripts-master\MAS\All-In-One-Version; .\MAS_AIO.cmd
}

function maleware {
    Invoke-WebRequest -Uri "https://downloads.malwarebytes.com/file/mb3" -OutFile "$env:TEMP\mb3-setup.exe"; Start-Process "$env:TEMP\mb3-setup.exe" -ArgumentList "/quiet" -Wait
}

function dislock {
    powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0; powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0; powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0; powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0; powercfg -SetActive SCHEME_CURRENT; Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\' -Name ScreenSaveActive -Value 0
}

function rmg {
    # Requires admin privileges
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This script requires administrator privileges. Please run PowerShell as Administrator."
        return
    }

    Write-Host "Starting complete removal of NVIDIA GeForce Experience..." -ForegroundColor Yellow

    # Stop related processes
    $processesToKill = @(
        "NVIDIA GeForce Experience",
        "NVIDIA Share",
        "NVIDIA Web Helper",
        "NVDisplay.Container",
        "NvTelemetryContainer"
    )

    foreach ($process in $processesToKill) {
        Get-Process | Where-Object {$_.ProcessName -like "*$process*"} | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Host "Attempting to stop process: $process" -ForegroundColor Cyan
    }

    # Uninstall using WMI
    Write-Host "Uninstalling GeForce Experience using WMI..." -ForegroundColor Yellow
    try {
        Get-WmiObject -Class Win32_Product | 
            Where-Object {$_.Name -like "*NVIDIA GeForce Experience*"} | 
            ForEach-Object {
                Write-Host "Uninstalling: $($_.Name)" -ForegroundColor Cyan
                $_.Uninstall()
            }
    }
    catch {
        Write-Host "WMI uninstall method failed, trying alternative removal methods..." -ForegroundColor Red
    }

    # Additional uninstall using Get-Package
    Write-Host "Checking for remaining packages..." -ForegroundColor Yellow
    Get-Package -Name "*NVIDIA GeForce Experience*" -ErrorAction SilentlyContinue | 
        Uninstall-Package -Force -ErrorAction SilentlyContinue

    # Registry cleanup
    Write-Host "Cleaning registry entries..." -ForegroundColor Yellow
    $registryPaths = @(
        "HKLM:\SOFTWARE\NVIDIA Corporation\Global\GFExperience",
        "HKLM:\SOFTWARE\NVIDIA Corporation\NVIDIA GeForce Experience",
        "HKCU:\SOFTWARE\NVIDIA Corporation\Global\GFExperience",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NVIDIA GeForce Experience"
    )

    foreach ($path in $registryPaths) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Removed registry path: $path" -ForegroundColor Cyan
        }
    }

    # File system cleanup
    Write-Host "Removing leftover files..." -ForegroundColor Yellow
    $pathsToRemove = @(
        "${env:ProgramFiles}\NVIDIA Corporation\NVIDIA GeForce Experience",
        "${env:ProgramFiles(x86)}\NVIDIA Corporation\NVIDIA GeForce Experience",
        "${env:ProgramData}\NVIDIA Corporation\GeForce Experience",
        "${env:APPDATA}\NVIDIA\GeForceExperience",
        "${env:LOCALAPPDATA}\NVIDIA\GeForceExperience",
        "${env:ProgramData}\NVIDIA Corporation\Installer2"
    )

    foreach ($path in $pathsToRemove) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Removed directory: $path" -ForegroundColor Cyan
        }
    }

    # Clean temporary files
    Write-Host "Cleaning temporary files..." -ForegroundColor Yellow
    Remove-Item -Path "$env:TEMP\NVIDIA*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:TEMP\GFExperience*" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "`nNVIDIA GeForce Experience removal complete!" -ForegroundColor Green
    Write-Host "Please restart your computer to complete the cleanup process." -ForegroundColor Yellow
}


function getorch {
    param (
        [string]$PythonPath = "python",
        [string]$CudaVersion = "cu111"
    )

    $pipInstallCommand = "$PythonPath -m pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/$CudaVersion"
    Invoke-Expression $pipInstallCommand

    $pythonCheckCommand = "$PythonPath -c `"import torch; print(torch.__version__)`""
    Invoke-Expression $pythonCheckCommand
}


function rmp {
    Remove-Item -Path "C:\Users\micha\Pictures\*" -Recurse -Force
}


function click {
    & "C:\Program Files\AutoHotkey\AutoHotkey.exe" "F:\\study\platforms\windows\AutoHotkey\MouseCopyPaste.ahk"
}


function bin {
    Clear-RecycleBin -Force
}


function nps {
    down; nano a.ps1
}

function ld {
    Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods | 
        Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{Brightness=30; Timeout=1}
}

function lu {
    Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods | 
        Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{Brightness=100; Timeout=1}
}

function pagefile {
    Start-Process -FilePath "SystemPropertiesPerformance.exe" -ArgumentList "/pagefile"
}

function sjob {
    Get-Job -State Running | Stop-Job
}

function rjob {
    Get-Job -State Running
}

function splex {
    ssh root@192.168.1.101
}

function short {
    Get-ChildItem 'F:\games' -Recurse -Filter '*.exe' | 
    Where-Object { $_.BaseName -and $_.BaseName -notmatch 'UnityCrashHandler64|QuickSFV|dxwebsetup|uninstall|unins000' } | 
    ForEach-Object { 
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut("$env:USERPROFILE\Desktop\$($_.BaseName).lnk")
        $s.TargetPath = $_.FullName
        $s.Save()
    }
}




function upnet2 {
    [CmdletBinding()]
    param()

    try {
        Write-Host "Starting network optimization process..." -ForegroundColor Cyan

        # Ensure the script is running with administrative privileges
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            Write-Error "You must run this script as an administrator."
            return
        }

        # Reset TCP/IP stack
        Write-Host "Resetting TCP/IP stack..." -ForegroundColor Green
        netsh int ip reset
        Write-Host "TCP/IP stack reset successfully." -ForegroundColor Yellow

        # Release and renew IP address
        Write-Host "Releasing IP address..." -ForegroundColor Green
        ipconfig /release
        Write-Host "IP address released." -ForegroundColor Yellow

        Write-Host "Renewing IP address..." -ForegroundColor Green
        ipconfig /renew
        Write-Host "IP address renewed." -ForegroundColor Yellow

        # Flush DNS cache
        Write-Host "Flushing DNS cache..." -ForegroundColor Green
        ipconfig /flushdns
        Write-Host "DNS cache flushed." -ForegroundColor Yellow

        # Reset Winsock catalog
        Write-Host "Resetting Winsock catalog..." -ForegroundColor Green
        netsh winsock reset
        Write-Host "Winsock catalog reset successfully." -ForegroundColor Yellow

        # Clear ARP cache
        Write-Host "Clearing ARP cache..." -ForegroundColor Green
        netsh interface ip delete arpcache
        Write-Host "ARP cache cleared." -ForegroundColor Yellow

        # Reset routing table
        Write-Host "Resetting routing table..." -ForegroundColor Green
        route -f
        Write-Host "Routing table reset." -ForegroundColor Yellow

        # Adjust TCP settings
        Write-Host "Configuring TCP settings..." -ForegroundColor Green

        # Disable Auto-Tuning
        netsh interface tcp set global autotuninglevel=disabled
        Write-Host "Windows Auto-Tuning disabled." -ForegroundColor Yellow

        # Disable Scaling Heuristics
        netsh interface tcp set heuristics=disabled
        Write-Host "Windows Scaling Heuristics disabled." -ForegroundColor Yellow

        # Set Congestion Provider to CTCP (Correct Command)
        netsh int tcp set supplemental congestionprovider=ctcp
        Write-Host "Congestion Provider set to CTCP." -ForegroundColor Yellow

        # Enable ECN Capability
        netsh int tcp set global ecncapability=enabled
        Write-Host "ECN Capability enabled." -ForegroundColor Yellow

        # Set MTU size to 1500 for active adapters
        Write-Host "Setting MTU size to 1500 for active adapters..." -ForegroundColor Green
        $activeAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.NdisPhysicalMedium -ne "Native802_11" }
        foreach ($adapter in $activeAdapters) {
            try {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "MTU" -DisplayValue "1500" -ErrorAction Stop
                Write-Host "MTU set to 1500 on adapter: $($adapter.Name)" -ForegroundColor Yellow
            } catch {
                Write-Warning "Failed to set MTU on adapter: $($adapter.Name). It may not support this property."
            }
        }

        # Restart network adapters
        Write-Host "Restarting network adapters..." -ForegroundColor Green
        foreach ($adapter in $activeAdapters) {
            try {
                Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 2
                Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Write-Host "Restarted adapter: $($adapter.Name)" -ForegroundColor Yellow
            } catch {
                Write-Warning "Failed to restart adapter: $($adapter.Name)."
            }
        }

        # Remove proxy settings
        Write-Host "Removing proxy settings..." -ForegroundColor Green
        netsh winhttp reset proxy
        Write-Host "Proxy settings removed." -ForegroundColor Yellow

        # Disable Large Send Offload where applicable
        Write-Host "Disabling Large Send Offload on applicable adapters..." -ForegroundColor Green
        foreach ($adapter in $activeAdapters) {
            $properties = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue
            if ($properties) {
                foreach ($property in $properties) {
                    if ($property.DisplayName -like "*Large Send Offload*") {
                        try {
                            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $property.DisplayName -DisplayValue "Disabled" -ErrorAction Stop
                            Write-Host "Disabled $($property.DisplayName) on adapter: $($adapter.Name)" -ForegroundColor Yellow
                        } catch {
                            Write-Warning "Failed to disable $($property.DisplayName) on adapter: $($adapter.Name)."
                        }
                    }
                }
            }
        }

        # Restart essential network services
        Write-Host "Restarting essential network services..." -ForegroundColor Green
        $servicesToRestart = @("Dhcp", "Dnscache", "NlaSvc", "netprofm", "WlanSvc", "dot3svc")
        foreach ($service in $servicesToRestart) {
            try {
                if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
                    Restart-Service -Name $service -Force -ErrorAction Stop
                    Write-Host "Service '$service' restarted successfully." -ForegroundColor Yellow
                } else {
                    Write-Warning "Service '$service' does not exist."
                }
            } catch {
                Write-Warning "Failed to restart service '$service'. It might be dependent on other services or require a reboot."
            }
        }

        # Remove lingering network connections
        Write-Host "Removing lingering network connections..." -ForegroundColor Green
        net use * /delete /yes 2>$null
        Write-Host "Lingering network connections removed." -ForegroundColor Yellow

        # Update Group Policy settings
        Write-Host "Updating Group Policy settings..." -ForegroundColor Green
        gpupdate /force
        Write-Host "Group Policy settings updated." -ForegroundColor Yellow

        # Re-register DNS
        Write-Host "Re-registering DNS..." -ForegroundColor Green
        ipconfig /registerdns
        Write-Host "DNS re-registration initiated." -ForegroundColor Yellow

        # Synchronize time settings
        Write-Host "Synchronizing time settings..." -ForegroundColor Green
        try {
            w32tm /resync
            Write-Host "Time synchronization successful." -ForegroundColor Yellow
        } catch {
            Write-Warning "Time synchronization failed. Ensure the Windows Time service is running."
        }

        # Set DNS servers to Google DNS for active adapters
        Write-Host "Setting DNS servers to Google DNS for active adapters..." -ForegroundColor Green
        foreach ($adapter in $activeAdapters) {
            try {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses ("8.8.8.8","8.8.4.4") -ErrorAction Stop
                Write-Host "DNS servers set to Google DNS on adapter: $($adapter.Name)" -ForegroundColor Yellow
            } catch {
                Write-Warning "Failed to set DNS servers on adapter: $($adapter.Name)."
            }
        }

        # Reset advanced firewall settings
        Write-Host "Resetting advanced firewall settings..." -ForegroundColor Green
        netsh advfirewall reset
        Write-Host "Advanced firewall settings reset." -ForegroundColor Yellow

        # Enable QoS Packet Scheduler where applicable
        Write-Host "Enabling QoS Packet Scheduler on applicable adapters..." -ForegroundColor Green
        foreach ($adapter in $activeAdapters) {
            try {
                # Check if QoS Packet Scheduler is available
                $qosProperty = Get-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "QoS Packet Scheduler" -ErrorAction SilentlyContinue
                if ($qosProperty) {
                    Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "QoS Packet Scheduler" -DisplayValue "Enabled" -ErrorAction Stop
                    Write-Host "QoS Packet Scheduler enabled on adapter: $($adapter.Name)" -ForegroundColor Yellow
                } else {
                    Write-Warning "QoS Packet Scheduler not found on adapter: $($adapter.Name)."
                }
            } catch {
                Write-Warning "Failed to enable QoS Packet Scheduler on adapter: $($adapter.Name)."
            }
        }

        # Optimize network adapter power management settings
        Write-Host "Optimizing network adapter power management settings..." -ForegroundColor Green
        foreach ($adapter in $activeAdapters) {
            try {
                Set-NetAdapterPowerManagement -Name $adapter.Name -NoPowerSaving -ErrorAction Stop
                Write-Host "Power management optimized on adapter: $($adapter.Name)" -ForegroundColor Yellow
            } catch {
                Write-Warning "Failed to optimize power management on adapter: $($adapter.Name)."
            }
        }

        # Optimize network adapter advanced settings
        Write-Host "Optimizing network adapter advanced settings..." -ForegroundColor Green
        foreach ($adapter in $activeAdapters) {
            $properties = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue
            if ($properties) {
                foreach ($property in $properties) {
                    switch ($property.DisplayName) {
                        "Receive Side Scaling" {
                            try {
                                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Receive Side Scaling" -DisplayValue "Enabled" -ErrorAction Stop
                                Write-Host "Receive Side Scaling enabled on adapter: $($adapter.Name)" -ForegroundColor Yellow
                            } catch {
                                Write-Warning "Failed to enable Receive Side Scaling on adapter: $($adapter.Name)."
                            }
                        }
                        "Interrupt Moderation" {
                            try {
                                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Interrupt Moderation" -DisplayValue "Enabled" -ErrorAction Stop
                                Write-Host "Interrupt Moderation enabled on adapter: $($adapter.Name)" -ForegroundColor Yellow
                            } catch {
                                Write-Warning "Failed to enable Interrupt Moderation on adapter: $($adapter.Name)."
                            }
                        }
                        default {}
                    }
                }
            }
        }

        # Display network statistics
        Write-Host "Displaying network statistics..." -ForegroundColor Green
        netstat -e
        Write-Host "Network statistics displayed." -ForegroundColor Yellow

        Write-Host "Network optimization complete. A system reboot is recommended to apply all changes." -ForegroundColor Cyan

    } catch {
        Write-Error "An unexpected error occurred: $_"
    }
}


function myapps {
    cd F:\\backup\windowsapps\installed\myapps\compiled_python
}


function rmp {
    Remove-Item -Path "C:\Users\micha\Pictures\*" -Force
}

function rmps {
    rmp; screen
}

function fix {
     sfc /scannow; DISM /Online /Cleanup-Image /CheckHealth; DISM /Online /Cleanup-Image /ScanHealth; /DISM /Online /Cleanup-Image /RestoreHealth; update
}

function lid {
    powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0; powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0; powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0; powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0; powercfg -SetActive SCHEME_CURRENT; Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\' -Name ScreenSaveActive -Value 0
}

function getparsec {
     down;  wget https://builds.parsec.app/package/parsec-windows.exe; ./parsec-windows.exe; Remove-Item -Path "C:\Users\micha\Downloads\parsec-windows.exe"
}

function getmodel {
    Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model
}

function reboot {
    Restart-Computer -Force -Confirm:$false

}

function rere {
    update; upnet; upnet2; upnet3;upnet4; reboot
}

function res() {
    # Download and extract NirCmd utility
    Invoke-WebRequest -Uri "https://www.nirsoft.net/utils/nircmd.zip" -OutFile "$env:USERPROFILE\nircmd.zip";
    Expand-Archive -Path "$env:USERPROFILE\nircmd.zip" -DestinationPath "$env:USERPROFILE\nircmd" -Force;
    Remove-Item "$env:USERPROFILE\nircmd.zip";

    # Add NirCmd to the PATH environment variable
    $env:Path += ";$env:USERPROFILE\nircmd";

    # Set resolution and scale
    nircmd.exe setdisplay 2560 1600 32;
    nircmd.exe setdisplayscaling 200;
}



function timer {
    cd F:\\study\programming\python\apps\watch\Stopwatch; python3 a.py
}

function scan {
    scanfast; scanfull
}

function dsubs {
    & "F:\backup\windowsapps\installed\Chrome\Application\chrome.exe" "https://www.youtube.com/playlist?list=PLtD44E7z8BkOlrJEKBc3aY8GseAmhTsf2"
; cd F:\\study\programming\python\apps\youtube\Playlists\deleteVideosFromOldestPublished; python d.py
}

function subs {
    cd F:\\study\programming\python\apps\youtube\Playlists\substoplaylist; python i.py
}


function cnwsl {
    ccwsl; nwsl
}

function scpmyg {
    Remove-Item -Force -Path "F:\\study\programming\python\apps\pyqt5menus\GamesDockerMenu\Gui\games_data.json"
Copy-Item -Path "F:\\study\programming\python\apps\pyqt5menus\GamesDockerMenu\nogui\games_data.json" -Destination "F:\\study\programming\python\apps\pyqt5menus\GamesDockerMenu\Gui\"
scp F:\\study\programming\python\apps\pyqt5menus\GamesDockerMenu\nogui\games_data.json ubuntu@192.168.1.193:/home/ubuntu
}


function keyubu {
    ssh-keygen -t rsa -b 2048; cat ~/.ssh/id_rsa.pub | ssh ubuntu@192.168.1.193 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
}

function keyprox {
    ssh-keygen -t rsa -b 2048; cat ~/.ssh/id_rsa.pub | ssh root@192.168.1.222 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
}

function sub {
    ssh -t ubuntu@192.168.1.193 "bash -i -c 's'"
}


function exai {
    set OPENAI_API_KEY=sk-svcacct-TiI2B_7zM1_B8PISYuPQhZTzNAtJRGvhEAtmDqCGE9VtuxGvMJBYnus_nbuoeT3BlbkFJUupZffoO1GXpkhv-o1PlCY1vrqoRdmuFSIqPt2opMT-AB1MdxfO63z6RIhX7wA
}




function updates {
    wsl --distribution ubuntu --user root -- bash -c "apt update && apt upgrade -y"; wsl --distribution ubuntu2 --user root -- bash -c "apt update && apt upgrade -y"; update
}


function ws {
    param (
        [string]$Command
    )
    wsl --distribution ubuntu --user root -- bash -lic "$Command"
}



function ws2 {
    param (
        [string]$Command
    )
    wsl --distribution ubuntu --user root -- bash -lic "$Command";     wsl --distribution ubuntu2 --user root -- bash -lic "$Command"

}


function wsls1 {
    wsl --terminate ubuntu 
}


function wsls2 {
    wsl --terminate ubuntu2 
}



function rwsl {
     wsls1; wsl --unregister ubuntu; wsl --import ubuntu C:\wsl2\ubuntu\ F:\\backup\linux\wsl\ubuntu.tar;  ws subit; wsl -d Ubuntu --cd ~
 }



function venvit {
    venv; down; pya
}

function venvit2 {
   venv; down; cd a; pya
}

function subit {
    ws subit
}


# Function to backup, remove, and recreate WSL instance
function nn {
    ws sbrc
    # Set variables for paths
    $BackupPath = "F:\\backup\linux\wsl\ubuntu.tar"
    $InstallPath = "C:\wsl2\ubuntu\"

    # Ensure backup directory exists
    $BackupDir = Split-Path $BackupPath -Parent
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force
    }

    # First export current state if it exists
    Write-Host "Attempting to backup current Ubuntu installation..."
    try {
        wsl --export ubuntu $BackupPath
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Note: No existing Ubuntu installation to export or export failed."
        } else {
            Write-Host "Successfully backed up Ubuntu installation."
        }
    } catch {
        Write-Host "Note: Unable to export. This is normal if no Ubuntu installation exists."
    }

    # Remove existing WSL instance
    Write-Host "Removing existing Ubuntu installation..."
    wsl --unregister ubuntu

    # Create installation directory if it doesn't exist
    if (-not (Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force
    }

    # Import the Ubuntu instance
    Write-Host "Importing Ubuntu from backup..."
    wsl --import ubuntu $InstallPath $BackupPath

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to import Ubuntu. Please check your backup file and paths."
        return
    }

    # Run additional commands (adapted from your original rmwsl function)
    try {
        rmubu2
        ubuntu2
        ws subit
        ubu
    } catch {
        Write-Host "Warning: One or more additional commands failed to execute: $_"
    }

    Write-Host "WSL environment restart completed."
}

# Alias for easier calling
Set-Alias -Name rmwsl -Value Restart-WSLEnvironment


function ccc {
    # Start the WinOptimize application with elevated permissions
    Start-Process -FilePath "F:\\backup\windowsapps\installed\myapps\compiled_python\windowsoptimize\D\dist\WinOptimize" -Verb RunAs

    # Open all shortcuts in the specified directory except for "IObit Unlocker"
    Get-ChildItem -Path "C:\Users\micha\Desktop\maintaince" -Filter "*.lnk" |
        Where-Object { $_.Name -notmatch "IObit Unlocker" } |
        ForEach-Object {
            $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($_.FullName)
            Start-Process -FilePath $shortcut.TargetPath -Verb RunAs
        }

    # Download and install Malwarebytes silently
    Invoke-WebRequest -Uri "https://downloads.malwarebytes.com/file/mb3" -OutFile "$env:TEMP\mb3-setup.exe"
    Start-Process -FilePath "$env:TEMP\mb3-setup.exe" -ArgumentList "/quiet" -Wait

    # Define and execute the Update function to install and apply updates
    function Update {
        Install-Module -Name PSWindowsUpdate -Force
        Import-Module PSWindowsUpdate
        Get-WindowsUpdate
        Install-WindowsUpdate -AcceptAll -Confirm:$false
    }
    Update

    # Perform a quick scan and a full scan using Windows Defender
    Start-MpScan -ScanType QuickScan
    Start-MpScan -ScanType FullScan
}


function getge {
    rmg; getgeforce
}


function display {
    cd F:\\study\shells\powershell\scripts; ./WinDisplaySettings.ps1
}



function cccc {
    # Close WinOptimize if it's running
    Get-Process -Name "WinOptimize" -ErrorAction SilentlyContinue | Stop-Process -Force

    # Get all shortcuts in the maintenance directory except IObit Unlocker
    $shortcuts = Get-ChildItem -Path "C:\Users\micha\Desktop\maintaince" -Filter "*.lnk" | 
                Where-Object { $_.Name -notmatch "IObit Unlocker" }

    # Create shell object to read shortcuts
    $shell = New-Object -ComObject WScript.Shell

    # Close each application launched from the shortcuts
    foreach ($shortcut in $shortcuts) {
        $shortcutPath = $shell.CreateShortcut($shortcut.FullName)
        $targetExe = [System.IO.Path]::GetFileNameWithoutExtension($shortcutPath.TargetPath)
        
        # Try to gracefully close the application
        Get-Process -Name $targetExe -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $_.CloseMainWindow() | Out-Null
                # If the process doesn't close after 5 seconds, force close it
                Start-Sleep -Seconds 5
                if (!$_.HasExited) {
                    $_ | Stop-Process -Force
                }
            }
            catch {
                # If graceful close fails, force close the process
                $_ | Stop-Process -Force
            }
        }
    }

    # Clean up COM object
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
    Remove-Variable shell
}

function de1 {
    cd F:\\study\shells\powershell\scripts; ./desktop1.ps1
}


function de2 {
    cd F:\\study\shells\powershell\scripts; ./desktop2.ps1
}

function refire {
    F:\\study\security\firewall\disable_firewall\enableFW.ps1
}

function fxs {
    Start-Process -FilePath "C:\Program Files\FxSound LLC\FxSound\fxsound.exe"
}


function wsgg {
    ws gg; rwsl
}

function bst {
    Start-Process -FilePath "python" -ArgumentList "F:\\study\programming\python\apps\volume\booster\a.py" -WindowStyle Hidden
}


function latest {
    (Get-ChildItem -File | Sort-Object {[System.Math]::Max(($_.LastWriteTime).Ticks, ($_.CreationTime).Ticks)} -Descending | Select-Object -First 1).FullName
}



function clap {
    Start-Job -ScriptBlock {
        python "F:\\study\programming\python\apps\SoundRecognition\DoubleClap2switchDesktops\a.py"
    }
}



function mac {
    Get-NetAdapter | Select-Object -Property Name, MacAddress
}

function bios {
    shutdown /r /fw /f /t 0
}


function add_keys {
    # Generate SSH key
    ssh-keygen -t rsa -b 2048
    
    # Add key to the first server
    cat ~/.ssh/id_rsa.pub | ssh ubuntu@192.168.1.193 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
    
    # Add key to the second server
    cat ~/.ssh/id_rsa.pub | ssh root@192.168.1.222 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
    
    # Add key to the third server
    cat ~/.ssh/id_rsa.pub | ssh root@192.168.1.101 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
}


function ggrwsl {
    ws gg; rwsl
}


function ss {
    # Enable Hibernate (if not already enabled)
    powercfg /hibernate on

    # Disable the requirement to enter a password after waking up
    powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0
    powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0
    powercfg /apply

    # Set the system to hibernate immediately
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    rundll32.exe powrprof.dll,SetSuspendState Hibernate

    # Disable wake from all devices except the keyboard
    $devices = Get-WmiObject -Query "SELECT * FROM Win32_PnPEntity WHERE Description LIKE '%Keyboard%'"

    # Iterate through all devices to configure wake-up capabilities
    foreach ($device in $devices) {
        $deviceID = $device.DeviceID -replace "\\", "\\\\" # Escape backslashes for PowerShell compatibility
        $powerManagement = Get-WmiObject -Query "SELECT * FROM Win32_DeviceSettings WHERE InstanceID='$deviceID'" `
            -ErrorAction SilentlyContinue
        if ($powerManagement -ne $null) {
            # Allow only the keyboard to wake the system
            powercfg -deviceenablewake $device.Name
        }
    }

    # Disable wake-up for all other devices
    $allDevices = powercfg -devicequery wake_armed
    foreach ($dev in $allDevices) {
        if ($dev -notlike "*Keyboard*") {
            powercfg -devicedisablewake $dev
        }
    }

    # Ensure system locks before hibernation is disabled
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v InactivityTimeoutSecs /t REG_DWORD /d 0 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System" /v AllowDomainPINLogon /t REG_DWORD /d 1 /f

    # Ensure user session resumes directly after wake-up
    rundll32.exe powrprof.dll,SetSuspendState Hibernate
}

function ggss {
    ws bigitgo; rewsl; ss
}


function path {
    python F:\\study\programming\python\apps\Downloads\FullLinkDownloadFileFromUrl\a.py
}


function audio {
    # Import the AudioDeviceCmdlets module, forcefully to ensure it's loaded
    Import-Module AudioDeviceCmdlets -Force

    # Attempt to retrieve the playback device named 'Speakers (Realtek(R) Audio)'
    # Adjust the matching pattern as needed for flexibility
    $desiredDevice = Get-AudioDevice -Playback | Where-Object { $_.Name -like '*Realtek*' } | Select-Object -First 1

    if ($desiredDevice) {
        try {
            # Attempt to set the audio device using its ID
            Set-AudioDevice -Id $desiredDevice.Id
            Write-Host "Switched audio output to: $($desiredDevice.Name)" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to set audio device. Error: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "Could not find a playback device containing 'Realtek' in its name." -ForegroundColor Yellow
        Write-Host "Available playback devices:" -ForegroundColor Cyan
        try {
            # List all available playback devices
            Get-AudioDevice -Playback | ForEach-Object { Write-Host " - $($_.Name)" }
        }
        catch {
            Write-Host "Failed to retrieve playback devices. Error: $_" -ForegroundColor Red
        }
    }
}


function html2db {
    python F:\\study\programming\python\apps\convert\HTML2SQliteDB\a.py
}


function rmal {
    F:\\study\shells\powershell\scripts\purgemalwarebytes.ps1
}



function summ {
    # Navigate to the backup directory and ensure the virtual environment is set up
    Set-Location -Path "F:\\backup\windowsapps"
    if (-Not (Test-Path ".\venv")) {
        python -m venv venv
    }
    .\venv\Scripts\Activate.ps1

    # Change to the specific project directory
    Set-Location -Path "F:\\study\programming\python\apps\youtube\youtube_summarizer\C"

    # Set the OpenAI API Key
    $Env:OPENAI_API_KEY = "sk-svcacct-TiI2B_7zM1_B8PISYuPQhZTzNAtJRGvhEAtmDqCGE9VtuxGvMJBYnus_nbuoeT3BlbkFJUupZffoO1GXpkhv-o1PlCY1vrqoRdmuFSIqPt2opMT-AB1MdxfO63z6RIhX7wA"

    # Run Streamlit using the absolute path
    F:\\backup\windowsapps\venv\Scripts\streamlit.exe run a.py
}


function paste {
    F:\\study\platforms\windows\AutoHotkey\RightNmiddleMousePasteRightClickCopy.ahk
}

function dislog {
    $User=(Get-WmiObject -Class Win32_ComputerSystem).UserName;$Pwd="123456";$Reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon";Set-ItemProperty -Path $Reg -Name "AutoAdminLogon" -Value "1";Set-ItemProperty -Path $Reg -Name "DefaultUserName" -Value $User;Set-ItemProperty -Path $Reg -Name "DefaultPassword" -Value $Pwd
}


function crere {
    vssadmin delete shadows /all /quiet; Checkpoint-Computer -Description "My Custom Restore Point" -RestorePointType "MODIFY_SETTINGS"; Get-ComputerRestorePoint | Format-Table -Property CreationTime, Description, SequenceNumber, EventType -AutoSize
}


function restore {
    (Get-ComputerRestorePoint | Sort-Object SequenceNumber -Descending | Select-Object -First 1).SequenceNumber | ForEach-Object { Restore-Computer -RestorePoint $_ }
}

function rmnps {
    ws 'rmn a.ps1'; ./a.ps1
}

function gspeedtest {
    F:\\study\shells\powershell\scripts\install_speedtest.ps1
}


function formatf {
    Format-Volume -DriveLetter F -FileSystem NTFS -NewFileSystemLabel "F" -Confirm:$false
}

function backsys {
    # Format the F drive
    Format-Volume -DriveLetter F -FileSystem NTFS -NewFileSystemLabel "F" -Confirm:$false

    $reflectPath = "F:\\backup\windowsapps\installed\reflect\reflect\Reflect.exe"
    $xmlFile = "F:\\backup\windowsapps\installed\reflect\Reflect\Backup.xml"
    $logFile = "F:\\backup\windowsapps\installed\reflect\Reflect\backup_log.txt"
    $logDir = Split-Path $logFile

    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }

    Write-Host "Starting backup in the background..." -ForegroundColor Yellow

    # Start the backup in a background job so the shell remains interactive
    Start-Job -ScriptBlock {
        param($reflectPath, $xmlFile, $logFile)
        & $reflectPath -e -full $xmlFile -log > $logFile 2>&1
    } -ArgumentList $reflectPath, $xmlFile, $logFile

    Write-Host "Backup has been initiated. Use Get-Job and Receive-Job to track progress. Returning to shell now..." -ForegroundColor Green
}


function gs1 {
    cctemp; crere; backsys
}

function gs2 {
    Start-Sleep -Seconds 1800; ggss
}


function autocomplete {
    Install-Module -Name PSReadLine -Force -SkipPublisherCheck ; Import-Module PSReadLine ; Set-PSReadLineOption -PredictionSource History ; Set-PSReadLineOption -PredictionViewStyle ListView
}


function ytmp {
   python F:\\study\programming\python\apps\youtube\DownloadAsMP3\b.py
}

function newprofile {
    New-Item -Path $profile -ItemType File -Force; notepad $profile
}

function short2 {
    $sourcePath = "F:\backup\windowsapps\installed"
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    
    # Get all .lnk files recursively
    Get-ChildItem -Path $sourcePath -Recurse -Filter "*.lnk" | ForEach-Object {
        $shortcut = $_
        $shell = New-Object -ComObject WScript.Shell
        $shortcutObj = $shell.CreateShortcut($shortcut.FullName)
        
        # Filter out uninstall-related shortcuts
        $isUninstallRelated = $shortcut.Name -match "(uninstall|remove|uninst)" -or
                             $shortcutObj.TargetPath -match "(uninstall|remove|uninst)" -or
                             $shortcutObj.Arguments -match "(uninstall|remove|uninst|/u)"
        
        # Check if shortcut has an icon
        $hasIcon = ![string]::IsNullOrEmpty($shortcutObj.IconLocation) -or
                   (Test-Path $shortcutObj.TargetPath -ErrorAction SilentlyContinue)
        
        # Check if target is an executable
        $isExecutable = $shortcutObj.TargetPath -match "\.(exe|com|bat|cmd|msi)$"
        
        # Only copy if it meets all criteria
        if (-not $isUninstallRelated -and $hasIcon -and $isExecutable) {
            try {
                Copy-Item $shortcut.FullName -Destination $desktopPath -Force
                Write-Host "Copied: $($shortcut.Name)" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to copy $($shortcut.Name): $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped: $($shortcut.Name) (filtered out)" -ForegroundColor Yellow
        }
        
        # Clean up COM object
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shortcutObj) | Out-Null
    }
    
    # Clean up COM object
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
}

function sss {
    param (
        [int]$seconds
    )

    # Command to send rtcwake with the specified seconds
    $command = "ssh root@192.168.1.222 `"nohup sudo rtcwake -m mem -s $seconds >/dev/null 2>&1 &`""
    Invoke-Expression $command
}

function rmdock {
    Write-Host "Starting Docker Desktop removal..." -ForegroundColor Cyan

    # Stop Docker Desktop processes if running
    Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue

    # Uninstall Docker Desktop using WMI
    Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Docker Desktop*" } | ForEach-Object {
        try {
            $_.Uninstall()
            Write-Host "Uninstalled: $($_.Name)" -ForegroundColor Green
        } catch {
            Write-Host "Failed to uninstall $($_.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Remove Docker files and directories
    $paths = @(
        "C:\Program Files\Docker",
        "$env:ProgramData\Docker",
        "$env:UserProfile\.docker"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) {
            try {
                Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
                Write-Host "Removed directory: $path" -ForegroundColor Green
            } catch {
                Write-Host "Failed to remove directory ${path}: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Directory not found: $path" -ForegroundColor Cyan
        }
    }

    # Clean Docker registry entries
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE",
        "HKLM:\SOFTWARE\WOW6432Node"
    )
    foreach ($regPath in $registryPaths) {
        if (Test-Path $regPath) {
            Get-ChildItem -Path $regPath -Recurse -ErrorAction SilentlyContinue | Where-Object {
                $_.PSPath -match "Docker"
            } | ForEach-Object {
                try {
                    Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Host "Removed registry entry: $($_.PSPath)" -ForegroundColor Green
                } catch {
                    Write-Host "Failed to remove registry entry $($_.PSPath): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "Registry path not found or inaccessible: $regPath" -ForegroundColor Cyan
        }
    }

    Write-Host "Docker Desktop removal completed!" -ForegroundColor Cyan
}



function gdock {
    rmdock;
    # Define the installer path
    $InstallerPath = "F:\\backup\windowsapps\install\docker-desktop-installer.exe"

    function Remove-Docker {
        Write-Host "AGGRESSIVELY removing ALL Docker components..." -ForegroundColor Red
        
        # Kill ALL related processes with extreme prejudice
        @("docker", "com.docker", "Docker Desktop", "Docker Desktop.exe", "DockerCli", "DockerDesktop", "dockerd") | ForEach-Object {
            Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }

        # Force remove services
        @("com.docker.service", "DockerDesktopVM", "com.docker.backend") | ForEach-Object {
            $service = Get-Service -Name $_ -ErrorAction SilentlyContinue
            if ($service) {
                cmd /c sc stop $_ 2>$null
                cmd /c sc delete $_ 2>$null
            }
        }

        # Aggressive Registry Cleanup
        $registryPaths = @(
            "HKLM:\SOFTWARE\Docker Inc.",
            "HKLM:\SOFTWARE\WOW6432Node\Docker Inc.",
            "HKCU:\SOFTWARE\Docker Desktop",
            "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\Docker"
        )
        foreach ($path in $registryPaths) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Uninstall using every possible method
        Write-Host "Running multiple uninstall methods..." -ForegroundColor Yellow
        
        # Method 1: Direct uninstaller
        Start-Process -FilePath $InstallerPath -ArgumentList "uninstall" -Wait -NoNewWindow
        
        # Method 2: MSI uninstall
        Get-WmiObject -Class Win32_Product | Where-Object { 
            $_.Name -like "*Docker*" 
        } | ForEach-Object {
            $_.Uninstall()
        }

        # Method 3: Registry uninstall strings
        @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        ) | ForEach-Object {
            Get-ItemProperty -Path $_ | Where-Object { 
                $_.DisplayName -like "*Docker*" 
            } | ForEach-Object {
                cmd /c $_.UninstallString /quiet 2>$null
            }
        }

        # Nuke ALL Docker directories
        $paths = @(
            "$Env:ProgramFiles\Docker",
            "${Env:ProgramFiles(x86)}\Docker",
            "$Env:ProgramData\Docker",
            "$Env:ProgramData\DockerDesktop",
            "$Env:AppData\Docker",
            "$Env:LocalAppData\Docker",
            "$Env:UserProfile\.docker",
            "$Env:LocalAppData\Docker Desktop",
            "$Env:LocalAppData\Programs\Docker",
            "$Env:LocalAppData\Programs\Docker Desktop"
        )

        foreach ($path in $paths) {
            if (Test-Path -Path $path) {
                Write-Host "Forcefully removing $path..." -ForegroundColor Yellow
                # Try both methods of removal
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                cmd /c rmdir /s /q "$path" 2>$null
            }
        }

        # Remove Docker Desktop VM
        if (Get-Command "Hyper-V\Get-VM" -ErrorAction SilentlyContinue) {
            Get-VM | Where-Object { $_.Name -like "*docker*" } | Remove-VM -Force -ErrorAction SilentlyContinue
        }

        # Reset WSL components
        wsl --shutdown
        Write-Host "Resetting WSL components..." -ForegroundColor Yellow

        # Clean Windows Features
        Write-Host "Resetting Windows Features..." -ForegroundColor Yellow
        $features = @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform", "Containers-DisposableClientVM")
        foreach ($feature in $features) {
            Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction SilentlyContinue | Out-Null
        }

        Write-Host "Docker forcefully purged from system!" -ForegroundColor Green
    }

    # Main installation logic
    if (Test-Path -Path $InstallerPath) {
        # Force kill everything Docker-related first
        Remove-Docker

        Write-Host "Waiting for system to stabilize..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10

        # Install fresh copy
        Write-Host "FORCING new Docker Desktop installation..." -ForegroundColor Green
        
        # Try multiple installation methods
        Write-Host "Attempting primary installation method..." -ForegroundColor Yellow
        Start-Process -FilePath $InstallerPath -ArgumentList "install --quiet" -Wait -NoNewWindow

        # Verify installation
        $DockerDesktopPath = "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
        if (Test-Path -Path $DockerDesktopPath) {
            Write-Host "Docker Desktop installed successfully!" -ForegroundColor Green
            Write-Host "Launching Docker Desktop..." -ForegroundColor Green
            Start-Process -FilePath $DockerDesktopPath
        } else {
            Write-Host "Primary installation might have failed. Attempting backup installation method..." -ForegroundColor Yellow
            Start-Process -FilePath $InstallerPath -ArgumentList "install" -Wait -NoNewWindow -RedirectStandardError ".\docker_install_error.log"
            
            if (Test-Path -Path $DockerDesktopPath) {
                Write-Host "Docker Desktop installed successfully on second attempt!" -ForegroundColor Green
                Start-Process -FilePath $DockerDesktopPath
            } else {
                Write-Host "Installation failed! Please check docker_install_error.log for details." -ForegroundColor Red
            }
        }
    } else {
        Write-Host "ERROR: Installer not found at $InstallerPath" -ForegroundColor Red
        Write-Host "Please verify the installer path and try again." -ForegroundColor Red
    }
}


function vcx {
     choco install vcxsrv -y --force; ws gx11
}


function cpit {
    Remove-Item "F:\study" -Recurse -Force -ErrorAction SilentlyContinue ; 
Remove-Item "F:\backup" -Recurse -Force -ErrorAction SilentlyContinue ; 
Robocopy "F:\\study" "F:\study" /MIR /MT:32 /R:1 /W:1 ; 
Robocopy "F:\\backup" "F:\backup" /MIR /MT:32 /R:1 /W:1
}



function dush {
    Get-ChildItem -Recurse | Measure-Object -Property Length -Sum | ForEach-Object { "{0:N2} MB" -f ($_.Sum / 1MB) }
}



function gh {
    F:\\backup\windowsapps\installed\ghelper\GHelper.exe
}

function Safe {
    param (
        [string]$SourceStudy = "F:\\study",
        [string]$SourceBackup = "F:\\backup",
        [string]$TargetDrive = "F:"
    )

    # Function to get total used space on the drive in GB
    function Get-UsedSpace {
        param (
            [string]$DriveLetter
        )
        $driveInfo = Get-PSDrive -Name $DriveLetter
        if ($driveInfo) {
            $usedSpace = $driveInfo.Used / 1GB
            [math]::Round($usedSpace, 2)
        } else {
            0
        }
    }

    # Start time tracking
    $start = Get-Date

    # Define target paths
    $TargetStudy = Join-Path -Path $TargetDrive -ChildPath "study"
    $TargetBackup = Join-Path -Path $TargetDrive -ChildPath "backup"

    # Sync function with used space monitoring
    function Sync-WithSpaceMonitoring {
        param (
            [string]$SourcePath,
            [string]$TargetPath
        )

        Write-Host "Synchronizing $SourcePath with $TargetPath..." -ForegroundColor Yellow
        if (Test-Path $SourcePath) {
            # Start a background job to monitor used space on the target drive
            $monitorJob = Start-Job -ScriptBlock {
                while ($true) {
                    $usedSpace = Get-UsedSpace -DriveLetter $Using:TargetDrive
                    Write-Host "Total used space on $Using:TargetDrive: $usedSpace GB" -ForegroundColor Cyan
                    Start-Sleep -Seconds 10
                }
            }

            # Run robocopy to sync files
            robocopy $SourcePath $TargetPath /MIR /E /R:2 /W:2 /NFL /NDL /NP /MT
            $exitCode = $LASTEXITCODE

            # Stop the monitoring job once sync completes
            Stop-Job -Job $monitorJob
            Remove-Job -Job $monitorJob

            # Check robocopy result
            if ($exitCode -lt 8) {
                Write-Host "Synchronized $SourcePath with $TargetPath successfully." -ForegroundColor Green
            } else {
                Write-Host "Error synchronizing $SourcePath with $TargetPath." -ForegroundColor Red
            }
        } else {
            Write-Host "Source folder $SourcePath does not exist. Skipping synchronization." -ForegroundColor Red
        }
    }

    # Sync study folder
    Sync-WithSpaceMonitoring -SourcePath $SourceStudy -TargetPath $TargetStudy

    # Sync backup folder
    Sync-WithSpaceMonitoring -SourcePath $SourceBackup -TargetPath $TargetBackup

    # End time tracking
    $end = Get-Date
    $duration = $end - $start
    Write-Host "Operation completed in $duration." -ForegroundColor Green
}


function rebrc {
    if (!(Test-Path $profile)) { New-Item -ItemType File -Path $profile -Force }; Get-Content 'F:\backup\windowsapps\install\profile.txt' | Set-Content $profile; . $profile
}



function sfil {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$searchTerm
    )

    # Recursively search for files whose names contain the search term
    Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$searchTerm*" } |
        ForEach-Object {
            $winPath = $_.FullName
            
            # Convert Windows path to WSL2 path format
            $driveLetter = $winPath.Substring(0,1).ToLower()
            $pathWithoutDrive = $winPath.Substring(2) -replace '\\','/'
            $wslPath = "/mnt/$driveLetter$pathWithoutDrive"
            
            # Output both Windows PowerShell and WSL2 formatted paths
            Write-Output "PowerShell Path: $winPath"
            Write-Output "WSL2 Path: $wslPath"
            Write-Output ""
        }
}



function btf {
    ws "getf && rsync -aHAXW --delete --progress /mnt/f/backup/ /mnt/f/backup/"      
}

function gs3 {
    update; cctemp; btf; ggss2
}


function gsteam {
    Start-Process "F:\\backup\windowsapps\install\SteamSetup.exe" -ArgumentList "/SILENT /DIR=F:\\backup\windowsapps\installed\steam"
}

function rmgamebar {
Get-AppxPackage *Microsoft.XboxGamingOverlay* | Remove-AppxPackage
}


function ggss2 {
    ws bigitgo; rewsl; sss 21600; ss
}


function parsec {
    cd F:\\backup\windowsapps\Credentials\ahk; ./parsec.ahk
}




function nnn {
    rws; ws 'clean'; ccwsl; nn
}



function rws {
    wsls1; wsl --unregister ubuntu; wsl --import ubuntu C:\wsl2\ubuntu\ F:\\backup\linux\wsl\ubuntu.tar
}



# Convenience alias (matches your old pattern)
Set-Alias -Name rmwsl -Value nnn



function mm {
    ws sbrc
    # Set variables for paths
    $BackupPath = "F:\\backup\linux\wsl\ubuntu.tar"
    $InstallPath = "C:\wsl2\ubuntu\"

    # Ensure backup directory exists
    $BackupDir = Split-Path $BackupPath -Parent
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force
    }

    # First export current state if it exists
    Write-Host "Attempting to backup current Ubuntu installation..."
    try {
        wsl --export ubuntu $BackupPath
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Note: No existing Ubuntu installation to export or export failed."
        } else {
            Write-Host "Successfully backed up Ubuntu installation."
        }
    } catch {
        Write-Host "Note: Unable to export. This is normal if no Ubuntu installation exists."
    }

    # Remove existing WSL instance
    Write-Host "Removing existing Ubuntu installation..."
    wsl --unregister ubuntu

    # Create installation directory if it doesn't exist
    if (-not (Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force
    }

    # Import the Ubuntu instance
    Write-Host "Importing Ubuntu from backup..."
    wsl --import ubuntu $InstallPath $BackupPath

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to import Ubuntu. Please check your backup file and paths."
        return
    }

    # Run additional commands (adapted from your original rmwsl function)
    try {
        rmubu2
        ubuntu2
        ws subit
    } catch {
        Write-Host "Warning: One or more additional commands failed to execute: $_"
    }

    Write-Host "WSL environment restart completed."
}

function profile {
    $source = $PROFILE
    $destination = "F:\\backup\windowsapps\profile\profile.txt"

    if (-Not (Test-Path $source)) {
        Write-Error "Source profile file does not exist: $source"
        return
    }

    # Create the destination directory if it does not exist
    $destDir = Split-Path $destination -Parent
    if (-Not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # Compare files if the destination exists
    if (Test-Path $destination) {
        $sourceHash = (Get-FileHash -Path $source -Algorithm SHA256).Hash
        $destHash   = (Get-FileHash -Path $destination -Algorithm SHA256).Hash

        if ($sourceHash -eq $destHash) {
            Write-Output "Files are identical; no update needed."
            return
        }
    }

    # Copy the file if it doesn't exist at the destination or if the content is different
    Copy-Item -Path $source -Destination $destination -Force
    Write-Output "Profile has been successfully synced to the backup location."
}

function top {
    param(
        [string]$Path = "."
    )

    Get-ChildItem -Path $Path | 
    ForEach-Object {
        $size = 0
        if ($_.PSIsContainer) {
            $size = (Get-ChildItem -Path $_.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        }
        else {
            $size = $_.Length
        }

        [PSCustomObject]@{
            Name = $_.Name
            SizeMB = [Math]::Round($size / 1MB, 2)
            SizeGB = [Math]::Round($size / 1GB, 2)
            Type = if ($_.PSIsContainer) {"Folder"} else {"File"}
        }
    } | Sort-Object -Property SizeMB -Descending | Format-Table -AutoSize
}


function desk {
    cd F:\\study\Platforms\windows\autohotkey; ./switchBetweenDesktop1And2.ahk
}


function fixtime {
    Set-Date -Date ([System.DateTime]::UtcNow)
}


function g1337x {
    python -m pip install --user git+https://github.com/NicKoehler/1337x
}

function trim { 
    cd F:\\study\shells\powershell\scripts; ./TrimFreeRam.ps1
}


function myg {
    cd  'F:\\study\programming\python\apps\pyqt5menus\GamesDockerMenu\gui' ; python i.py
}


function ccleaner {
    & "C:\Program Files\CCleaner\CCleaner64.exe"
}


function bcu {
    & "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\BCUninstaller\BCUninstaller.lnk"
}


function drim {
    desk; trim
}


function getssh {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0; Set-Service -Name sshd -StartupType Automatic; Start-Service sshd; if (-not (Get-NetFirewallRule -Name 'sshd' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -Name 'sshd' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 }    
}



function qaccess {
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\f01b4d95cf55d32a.automaticDestinations-ms" -Force; Start-Sleep -Seconds 1; $folders=@("F:\\backup\windowsapps","F:\\backup\windowsapps\installed","F:\\backup\windowsapps\install","F:\\backup\windowsapps\profile","C:\Users\micha\Videos","C:\games","F:\\study","F:\\backup","C:\Users\micha"); $shell=New-Object -ComObject Shell.Application; foreach($f in $folders){ $ns=$shell.Namespace($f); if($ns){ $ns.Self.InvokeVerb("pintohome") } }
}





function cleanup {
maleware; up; nvidia; clean; update; cctemp; rmal
}


function wish {
    cd F:\\study\programming\python\apps\wishlist\Back2localDataBase; py d.py
}




function draft {
    cd F:\\backup\windowsapps\Credentials\youtube\draft; python publishdraft.py
}


function rmn {
    param(
        [string]$filename
    )
    
    # Remove the file, forcing removal even if it's read-only
    Remove-Item -Path $filename -Force
    
    # Open the file in nano editor
    nano $filename
}



function kil {
     cd F:\\study\programming\python\apps\taskiller;  py e.py
}



function sand {
     cd F:\\study\Platforms\windows\sandbox; ./LaunchSandboxWithFolders3.ps1
}


function rewemod {
    cd F:\\study\hosting\games\wemod; ./ReinstalWemod.ps1
}


function wemod {
     cd F:\\backup\windowsapps\Credentials\ahk; ./wemod.ahk
}


function desc {
    cd F:\\study\programming\python\apps\youtube\upload\ChangeDescriptionOFvideos; pya
}


function SafeBoot {
    param (
        [Parameter(Mandatory=$false)]
        [ValidateSet("Minimal", "Network", "AlternateShell")]
        [string]$Mode = "Minimal",
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        
        [Parameter(Mandatory=$false)]
        [int]$Timeout = 10
    )
    
    # Requires admin privileges
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "ERROR: This function requires Administrator privileges. Please restart PowerShell as Administrator."
        return
    }
    
    try {
        # Verify bcdedit is available
        $bcdeditTest = bcdedit /enum | Out-String
        if (-not $?) {
            Write-Error "ERROR: Cannot access bcdedit. Make sure you're running as Administrator."
            return
        }
        
        # Configure boot settings with explicit output for debugging
        Write-Host "Configuring Safe Mode boot entry..." -ForegroundColor Cyan
        
        # Set up safe boot parameters
        switch ($Mode) {
            "Minimal" {
                $result = bcdedit /set '{current}' safeboot minimal
                Write-Host "bcdedit output: $result"
                Write-Host "Configured for Safe Mode (Minimal)" -ForegroundColor Green
            }
            "Network" {
                $result = bcdedit /set '{current}' safeboot network
                Write-Host "bcdedit output: $result"
                Write-Host "Configured for Safe Mode with Networking" -ForegroundColor Green
            }
            "AlternateShell" {
                $result1 = bcdedit /set '{current}' safeboot minimal
                $result2 = bcdedit /set '{current}' safebootalternateshell yes
                Write-Host "bcdedit output: $result1, $result2"
                Write-Host "Configured for Safe Mode with Command Prompt" -ForegroundColor Green
            }
        }
        
        # Verify the settings were applied
        Write-Host "Verifying boot configuration..." -ForegroundColor Cyan
        $verifyConfig = bcdedit /enum | Out-String
        
        if ($verifyConfig -match "safeboot\s+(\w+)") {
            Write-Host "Safe Boot configuration verified: $($Matches[1])" -ForegroundColor Green
            
            # Prompt for reboot
            if ($Force) {
                # Force restart without confirmation
                Write-Host "System will restart in $Timeout seconds..." -ForegroundColor Yellow
                Write-Host "WARNING: Your computer will boot into Safe Mode on the next restart." -ForegroundColor Red
                Start-Sleep -Seconds $Timeout
                shutdown.exe /r /t 0 /f
            } else {
                $confirm = Read-Host "System will restart into Safe Mode. Continue? (Y/N)"
                if ($confirm -eq "Y" -or $confirm -eq "y") {
                    Write-Host "Restarting system in 5 seconds..." -ForegroundColor Yellow
                    Write-Host "WARNING: Your computer will boot into Safe Mode on the next restart." -ForegroundColor Red
                    Start-Sleep -Seconds 5
                    shutdown.exe /r /t 0
                } else {
                    # Revert safe boot settings if user cancels
                    Write-Host "Reverting Safe Mode boot configuration..." -ForegroundColor Cyan
                    bcdedit /deletevalue '{current}' safeboot | Out-Null
                    bcdedit /deletevalue '{current}' safebootalternateshell 2>$null | Out-Null
                    Write-Host "Safe Mode boot configuration has been canceled and reverted." -ForegroundColor Yellow
                }
            }
        } else {
            Write-Error "ERROR: Failed to verify Safe Mode configuration. Safe Mode might not be properly configured."
            return
        }
    } catch {
        Write-Error "ERROR: An error occurred: $_"
        # Attempt to revert changes on error
        Write-Host "Attempting to revert boot configuration..." -ForegroundColor Yellow
        bcdedit /deletevalue '{current}' safeboot 2>$null | Out-Null
        bcdedit /deletevalue '{current}' safebootalternateshell 2>$null | Out-Null
    }
}

# Add a function to return to normal boot mode
function DisableSafeBoot {
    # Requires admin privileges
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "ERROR: This function requires Administrator privileges. Please restart PowerShell as Administrator."
        return
    }
    
    try {
        Write-Host "Removing Safe Mode boot configuration..." -ForegroundColor Cyan
        $result1 = bcdedit /deletevalue '{current}' safeboot
        $result2 = bcdedit /deletevalue '{current}' safebootalternateshell 2>$null
        
        Write-Host "Operation results: $result1, $result2"
        Write-Host "Safe Mode boot configuration has been removed. System will boot normally on next restart." -ForegroundColor Green
        
        $confirm = Read-Host "Do you want to restart the computer now? (Y/N)"
        if ($confirm -eq "Y" -or $confirm -eq "y") {
            Write-Host "Restarting system in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            shutdown.exe /r /t 0
        }
    } catch {
        Write-Error "ERROR: An error occurred: $_"
    }
}



function nvidia {
     Get-WmiObject Win32_Product | Where-Object { $_.Name -like "*NVIDIA*" } | ForEach-Object { $_.Uninstall() } ; Get-Package -Name "*NVIDIA*" -ErrorAction SilentlyContinue | Uninstall-Package -Force ; Remove-Item "C:\Program Files\NVIDIA Corporation" -Recurse -Force -ErrorAction SilentlyContinue ; Remove-Item "C:\Program Files (x86)\NVIDIA Corporation" -Recurse -Force -ErrorAction SilentlyContinue ; reg delete "HKLM\Software\NVIDIA Corporation" /f ; reg delete "HKCU\Software\NVIDIA Corporation" /f ; Start-Sleep -Seconds 3 ; Stop-Process -Name "nv*" -Force -ErrorAction SilentlyContinue; & "F:\\backup\windowsapps\install\nvidia\NVIDIA_app_v11.0.1.189.exe"
}



function cctemp {
    param (
        [switch]$Force
    )

    # Define temp locations
    $tempPaths = @(
        "$env:TEMP",
        "$env:TMP",
        "$env:SystemRoot\Temp",
        "C:\Windows\Temp",
        "C:\Users\*\AppData\Local\Temp",
        "C:\Users\*\AppData\Local\Microsoft\Windows\INetCache\IE\*",
        "C:\Users\*\AppData\Local\CrashDumps",
        "C:\Users\*\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
        "C:\Users\*\AppData\Local\Google\Chrome\User Data\Default\Cache",
        "C:\Users\*\AppData\Local\Mozilla\Firefox\Profiles\*.default-release\cache2",
        "C:\Windows\Prefetch",
        "C:\Windows\SoftwareDistribution\Download"
    )

    # Collect all files in temp locations
    $filesToDelete = @()
    foreach ($path in $tempPaths) {
        $filesToDelete += Get-ChildItem -Path $path -Force -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -eq $false }
    }

    # Collect all empty directories
    $dirsToDelete = @()
    foreach ($path in $tempPaths) {
        $dirsToDelete += Get-ChildItem -Path $path -Force -Recurse -Directory -ErrorAction SilentlyContinue | Sort-Object FullName -Descending
    }

    # Remove files
    foreach ($file in $filesToDelete) {
        try {
            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            Write-Host "Deleted: $($file.FullName)"
        } catch {
            Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Remove empty directories
    foreach ($dir in $dirsToDelete) {
        try {
            Remove-Item -Path $dir.FullName -Force -Recurse -ErrorAction Stop
            Write-Host "Deleted empty directory: $($dir.FullName)"
        } catch {
            Write-Host "Failed to delete directory: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "Temp file cleanup completed." -ForegroundColor Green
}


function compress {
    param(
        [string]$foldername
    )
    & "C:\Program Files\7-Zip\7z.exe" a -t7z -m0=lzma2 -mx=9 -mmt=on "$foldername.7z" "$foldername\"
}



# PSReadLine configuration for command suggestions
try { if (Get-Command Set-PSReadLineOption -ParameterName PredictionSource -ErrorAction SilentlyContinue) { Set-PSReadLineOption -PredictionSource History; Set-PSReadLineOption -PredictionViewStyle ListView } else { Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete; Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward; Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward } } catch { Write-Host 'Error configuring PSReadLine: ' }


function uninstall {
    start-process "C:\Users\Public\Desktop\IObit Uninstaller.lnk"
}


function discord {
     update; winget uninstall AutoHotkey.AutoHotkey --silent --accept-source-agreements; winget install XPDC2RH70K22MN --accept-package-agreements --accept-source-agreements; winget upgrade XPDC2RH70K22MN --silent --accept-package-agreements --accept-source-agreements; cd F:\\backup\windowsapps\Credentials\ahk; ./discord.ahk
}




function uac {
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 0 /f
}


function reuac {
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 5 /f
}



function ahk2exe {
 & "F:\\study\Platforms\windows\exe\Ahk2Exe.exe"
}





function Refresh4 {
    # Restart services that are set to start automatically
    Write-Host "Restarting services..."
    $services = Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -eq 'Running' }
    foreach ($service in $services) {
        Write-Host "Restarting service: $($service.Name)"
        Restart-Service -Name $service.Name -Force
    }

    # Launch startup applications from the Startup folder
    Write-Host "Launching startup applications from the Startup folder..."
    $startupFolder = [Environment]::GetFolderPath('Startup')
    if (Test-Path $startupFolder) {
        $startupItems = Get-ChildItem -Path $startupFolder -Filter *.lnk
        foreach ($item in $startupItems) {
            Write-Host "Launching: $($item.FullName)"
            Start-Process -FilePath $item.FullName
        }
    }

    # Launch startup applications from the Run registry keys
    Write-Host "Launching startup applications from the Run registry keys..."
    $runKeys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($runKey in $runKeys) {
        if (Test-Path $runKey) {
            $runItems = Get-ItemProperty -Path $runKey
            foreach ($item in $runItems.PSObject.Properties) {
                if ($item.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")) {
                    Write-Host "Launching: $($item.Value)"
                    Start-Process -FilePath $item.Value
                }
            }
        }
    }

    # Clear temporary files and caches
    Write-Host "Clearing temporary files and caches..."
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:LOCALAPPDATA\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "Refresh4 completed. System should feel refreshed!"
}

function smyg {
    cd F:\\study\programming\python\apps\pyqt5menus\GamesDockerMenu\gui
}


function scp2ubu2($folderName) {
    if ([string]::IsNullOrEmpty($folderName)) {
        Write-Host "Usage: scp2ubu2 <folder_name>"
        return
    }

    $srcPath = $folderName
    $dstUser = "ubuntu"
    $dstIP = "192.168.1.193"
    $dstPath = "/home/ubuntu"

    $scpCommand = "scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o Compression=no -o Ciphers=aes128-gcm@openssh.com -o MACs=umac-128-etm@openssh.com -o IPQoS=throughput `"$srcPath`" ${dstUser}@${dstIP}:`"$dstPath`""

    Invoke-Expression $scpCommand
}

function rcopy($sourceFolder) {
    $folderName = Split-Path $sourceFolder -Leaf
    $destination = "\\192.168.1.193\shared\$folderName"
    robocopy $sourceFolder $destination /E /Z /MT:128 /R:0 /W:0 /NFL /NDL /NP
}


function msys {
    & "C:\msys64\msys2_shell.cmd" -mingw64
}


function compc {
     choco install mingw -y; $env:Path += ";C:\ProgramData\mingw64\mingw64\bin"; g++ main.cpp -o main.exe; ./main.exe
}


function sss2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$WakeTime
    )

    # Construct the remote command.
    # The remote command should look like:
    #   nohup sudo rtcwake -m mem -t $(date -d 'HH:MM' +%s) >/dev/null 2>&1 &
    #
    # We use single quotes for the PowerShell string and concatenate in $WakeTime.
    $remoteCommand = 'nohup sudo rtcwake -m mem -t $(date -d ''' + $WakeTime + ''' +%s) >/dev/null 2>&1 &'

    # Execute the SSH command using the constructed remote command.
    ssh root@192.168.1.222 $remoteCommand
}



function upnet3 {
    [CmdletBinding()]
    param()

    try {
        Write-Host "Starting advanced WiFi optimization..." -ForegroundColor Cyan

        # Check for administrative privileges
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            Write-Error "You must run this script as an administrator."
            return
        }

        # Flush DNS cache
        Write-Host "Flushing DNS cache..." -ForegroundColor Yellow
        ipconfig /flushdns

        # Identify the active WiFi adapter
        Write-Host "Setting DNS to Google DNS for active WiFi adapter..." -ForegroundColor Yellow
        $adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and ($_.Name -like "*Wi-Fi*" -or $_.InterfaceDescription -like "*Wireless*")}
        if ($adapter) {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses ("8.8.8.8", "8.8.4.4")
        } else {
            Write-Warning "No active WiFi adapter found."
        }

        # Set TCP Auto-Tuning to normal
        Write-Host "Setting TCP Auto-Tuning to normal..." -ForegroundColor Yellow
        netsh interface tcp set global autotuninglevel=normal

        # Enable RSS on WiFi adapter
        if ($adapter) {
            Write-Host "Enabling RSS on WiFi adapter..." -ForegroundColor Yellow
            Set-NetAdapterRss -Name $adapter.Name -Enabled $true -ErrorAction SilentlyContinue
        }

        # Disable Large Send Offload on WiFi adapter
        if ($adapter) {
            Write-Host "Disabling Large Send Offload on WiFi adapter..." -ForegroundColor Yellow
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Large Send Offload V2 (IPv4)" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Large Send Offload V2 (IPv6)" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        }

        # Set WiFi adapter power saving to maximum performance
        Write-Host "Setting WiFi adapter power saving to maximum performance..." -ForegroundColor Yellow
        powercfg /setacvalueindex scheme_current 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0
        powercfg /setdcvalueindex scheme_current 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0
        powercfg /setactive scheme_current

        Write-Host "Advanced WiFi optimization completed." -ForegroundColor Green
    } catch {
        Write-Error "An error occurred: $_"
    }
}

function upnet3 {
    [CmdletBinding()]
    param()

    try {
        Write-Host "Starting comprehensive WiFi optimization..." -ForegroundColor Cyan

        # Admin check
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "Please run as administrator!"
        }

        # Advanced WiFi optimizations
        netsh wlan set autoconfig enabled=yes interface="Wi-Fi"
        netsh int tcp set supplemental Internet congestionprovider=ctcp
        netsh int tcp set heuristics disabled
        netsh int tcp set global initialRto=2000
        netsh int tcp set global timestamps=disabled
        netsh int tcp set global nonsackrttresiliency=disabled
        netsh int tcp set global rsc=enabled
        netsh int tcp set global ecncapability=disabled
        netsh int tcp set global dca=enabled
        netsh int tcp set global netdma=enabled
        netsh int tcp set global timestamps=disabled

        # Power management optimizations
        powershell -Command "Get-NetAdapter -Name 'Wi-Fi' | Set-NetAdapterPowerManagement -SelectiveSuspend Disabled"
        powercfg -change -monitor-timeout-ac 0
        powercfg -change -monitor-timeout-dc 0
        powercfg /setacvalueindex scheme_current sub_processor PROCTHROTTLEMAX 100
        powercfg /setdcvalueindex scheme_current sub_processor PROCTHROTTLEMAX 100

        # Advanced network settings
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "DefaultTTL" -Value 64
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "TCPNoDelay" -Value 1
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "Tcp1323Opts" -Value 1
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 0xffffffff
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 0

        # QoS and bandwidth optimization
        netsh int tcp set global autotuninglevel=normal
        netsh int tcp set global chimney=enabled
        netsh int ip set global taskoffload=enabled
        netsh int ip set global neighborcachelimit=4096
        netsh int tcp set global windowsscaling=enabled

        # WiFi-specific optimizations
        netsh wlan set autoconfig enabled=yes interface="Wi-Fi"
        netsh wlan set allowexplicitcreds allow=yes
        netsh wlan set hostednetwork mode=allow
        
        # Clear DNS and network caches
        ipconfig /flushdns
        ipconfig /registerdns
        nbtstat -R
        nbtstat -RR
        arp -d *
        route -f

        # Set optimal MTU
        $adapter = Get-NetAdapter | Where-Object {$_.Name -eq "Wi-Fi"}
        Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -NlMtuBytes 1500

        # Disable IPv6 temporary addresses
        Set-NetIPv6Protocol -RandomizeIdentifiers Disabled
        
        # Optimize receive window auto-tuning
        netsh int tcp set global autotuninglevel=normal
        
        # Reset network stack thoroughly
        netsh int ip reset C:\resetlog.txt
        netsh int ipv6 reset C:\resetlogv6.txt
        
        # Optimize network bindings
        Get-NetAdapter | Set-NetAdapterBinding -ComponentID 'ms_tcpip6' -Enabled $false
        Get-NetAdapter | Set-NetAdapterBinding -ComponentID 'ms_msclient' -Enabled $false
        
        # Set network adapter properties
        Set-NetAdapterAdvancedProperty -Name "Wi-Fi" -DisplayName "Packet Coalescing" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "Wi-Fi" -DisplayName "Power Saving Mode" -DisplayValue "Disabled" -ErrorAction SilentlyContinue

        Write-Host "All WiFi optimizations completed! Please restart your computer." -ForegroundColor Green
    }
    catch {
        Write-Error "An error occurred: $_"
    }
}


function upnet4 {
    [CmdletBinding()]
    param()

    try {
        Write-Host "Starting ultra comprehensive WiFi optimization (upnet4)..." -ForegroundColor Cyan

        # Check for administrative privileges
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "Please run this script as an administrator!"
        }

        # Dynamically find the Wi-Fi adapter by matching common names or descriptions.
        $wifiAdapter = Get-NetAdapter | Where-Object { 
            $_.InterfaceDescription -match "Wireless" -or 
            $_.Name -match "Wi[- ]?Fi" 
        } | Select-Object -First 1

        # Fallback search if not found above
        if (-not $wifiAdapter) {
            Write-Host "Wi-Fi adapter not found by name. Trying fallback search using '802.11'..." -ForegroundColor Yellow
            $wifiAdapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "802.11" } | Select-Object -First 1
        }

        if (-not $wifiAdapter) {
            Write-Error "Wi-Fi adapter not found. Exiting function."
            return
        }

        Write-Host "Using Wi-Fi adapter: $($wifiAdapter.Name)" -ForegroundColor Green

        # 1. Disable Large Send Offload (IPv4 and IPv6)
        Write-Host "Disabling Large Send Offload (IPv4 and IPv6)..." -ForegroundColor Yellow
        Set-NetAdapterAdvancedProperty -Name $wifiAdapter.Name -DisplayName "Large Send Offload V2 (IPv4)" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $wifiAdapter.Name -DisplayName "Large Send Offload V2 (IPv6)" -DisplayValue "Disabled" -ErrorAction SilentlyContinue

        # 2. Set Roaming Aggressiveness to Highest
        Write-Host "Setting Roaming Aggressiveness to Highest..." -ForegroundColor Yellow
        Set-NetAdapterAdvancedProperty -Name $wifiAdapter.Name -DisplayName "Roaming Aggressiveness" -DisplayValue "Highest" -ErrorAction SilentlyContinue

        # 3. Configure TCP ACK settings
        Write-Host "Configuring TCP ACK settings..." -ForegroundColor Yellow
        New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "TCPAckFrequency" -PropertyType DWord -Value 1 -Force | Out-Null

        # 4. Enable TCP Fast Open (if supported)
        Write-Host "Enabling TCP Fast Open (if supported)..." -ForegroundColor Yellow
        netsh int tcp set global fastopen=enabled 2>$null

        # 5. Disable Interrupt Moderation
        Write-Host "Disabling Interrupt Moderation..." -ForegroundColor Yellow
        Set-NetAdapterAdvancedProperty -Name $wifiAdapter.Name -DisplayName "Interrupt Moderation" -DisplayValue "Disabled" -ErrorAction SilentlyContinue

        # 6. Disable Energy Efficient Ethernet (EEE)
        Write-Host "Disabling Energy Efficient Ethernet (EEE)..." -ForegroundColor Yellow
        Set-NetAdapterAdvancedProperty -Name $wifiAdapter.Name -DisplayName "Energy Efficient Ethernet" -DisplayValue "Disabled" -ErrorAction SilentlyContinue

        # 7. Disable Task Offload via registry tweak
        Write-Host "Applying registry tweak: Disable Task Offload..." -ForegroundColor Yellow
        New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "DisableTaskOffload" -PropertyType DWord -Value 1 -Force | Out-Null

        # 8. Disable Receive Side Scaling (RSS)
        Write-Host "Disabling Receive Side Scaling (RSS)..." -ForegroundColor Yellow
        Set-NetAdapterAdvancedProperty -Name $wifiAdapter.Name -DisplayName "Receive Side Scaling" -DisplayValue "Disabled" -ErrorAction SilentlyContinue

        # 9. Disable TCP and UDP Checksum Offload
        Write-Host "Disabling TCP and UDP Checksum Offload..." -ForegroundColor Yellow
        Set-NetAdapterAdvancedProperty -Name $wifiAdapter.Name -DisplayName "TCP Checksum Offload" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $wifiAdapter.Name -DisplayName "UDP Checksum Offload" -DisplayValue "Disabled" -ErrorAction SilentlyContinue

        # 10. Disable Power Saving Mode on the adapter (if parameter available)
        Write-Host "Disabling Power Saving Mode on the adapter..." -ForegroundColor Yellow
        try {
            Set-NetAdapterPowerManagement -Name $wifiAdapter.Name -AllowComputerToTurnOffDevice $false -ErrorAction Stop
        }
        catch {
            Write-Host "Skipping Set-NetAdapterPowerManagement tweak: parameter not available." -ForegroundColor Yellow
        }

        # 11. Set Transmit Power to Highest
        Write-Host "Setting Transmit Power to Highest..." -ForegroundColor Yellow
        Set-NetAdapterAdvancedProperty -Name $wifiAdapter.Name -DisplayName "Transmit Power" -DisplayValue "Highest" -ErrorAction SilentlyContinue

        # 12. Force wireless mode to 802.11n (if supported)
        Write-Host "Forcing wireless mode to 802.11n (if supported)..." -ForegroundColor Yellow
        Set-NetAdapterAdvancedProperty -Name $wifiAdapter.Name -DisplayName "Wireless Mode" -DisplayValue "802.11n" -ErrorAction SilentlyContinue

        # 13. Additional tweak: Disable 802.11 Power Save
        Write-Host "Disabling 802.11 Power Save..." -ForegroundColor Yellow
        netsh wlan set profileparameter name=$wifiAdapter.Name powerManagement=disabled 2>$null

        # 14. Additional tweak: Set Preferred Band to 5GHz (if supported)
        Write-Host "Setting Preferred Band to 5GHz (if supported)..." -ForegroundColor Yellow
        Set-NetAdapterAdvancedProperty -Name $wifiAdapter.Name -DisplayName "Preferred Band" -DisplayValue "5 GHz" -ErrorAction SilentlyContinue

        # Restart the Wi-Fi adapter to apply changes
        Write-Host "Restarting the Wi-Fi adapter to apply changes..." -ForegroundColor Yellow
        Disable-NetAdapter -Name $wifiAdapter.Name -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Enable-NetAdapter -Name $wifiAdapter.Name -Confirm:$false -ErrorAction SilentlyContinue

        Write-Host "Displaying current Wi-Fi adapter status:" -ForegroundColor Cyan
        netsh wlan show interfaces

        Write-Host "Ultra comprehensive WiFi optimization (upnet4) completed! A system restart is recommended." -ForegroundColor Green
    }
    catch {
        Write-Error "An error occurred in upnet4: $_"
    }
}


function ee {
     explorer.exe .
}



function startup {
    #--- Define Paths and Working Directories ---
    # First group (Run these first)
    $qbExe = "F:\\backup\windowsapps\installed\qbittorrent\qbittorrent.exe"
    $qbWD = "F:\\backup\windowsapps\installed\qbittorrent"

    # SwitchBetweenDesktop
    $switchDesktopExe = "F:\\study\Platforms\windows\exe\switchBetweenDesktop1And2.exe"
    $switchDesktopWD = "F:\\study\Platforms\windows\exe"

    # Switch2OBS
    $switch2OBSExe = "F:\\study\Platforms\windows\exe\Switch2OBS.exe"
    $switch2OBSWD = "F:\\study\Platforms\windows\exe"

    # Final group
    $obsExe = "C:\Program Files\obs-studio\bin\64bit\obs64.exe"
    $obsWD = "C:\Program Files\obs-studio\bin\64bit"

    $trimExe = "F:\\study\Platforms\windows\exe\TrimFreeRam.exe"
    $trimWD = "F:\\study\Platforms\windows\exe"

    $ahkSwitchExe = "F:\\study\Platforms\windows\autohotkey\switchBetweenDesktop1And2.exe"
    $ahkSwitchWD = "F:\\study\Platforms\windows\autohotkey"
    
    # New GameMod AHK script
    $gameModAhkExe = "F:\\study\Platforms\windows\autohotkey\GameMod.ahk"
    $gameModAhkWD = "F:\\study\Platforms\windows\autohotkey"

    #--- Create Logon Trigger ---
    $trigger = New-ScheduledTaskTrigger -AtLogOn

    #--- Create Principal to run as current user with highest privileges ---
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest

    #--- Settings to ensure minimized startup (fixed ExecutionTimeLimit) ---
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -RunOnlyIfNetworkAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)

    #--- FIRST GROUP: qBittorrent ---
    $actionQB = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Process -FilePath '$qbExe' -WorkingDirectory '$qbWD' -WindowStyle Minimized`"" -WorkingDirectory $qbWD
    Register-ScheduledTask -TaskName "Start_01_qBittorrent" -Action $actionQB -Trigger $trigger -Principal $principal -Settings $settings -Force

    $actionSwitchDesktop = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Process -FilePath '$switchDesktopExe' -WorkingDirectory '$switchDesktopWD' -WindowStyle Minimized`"" -WorkingDirectory $switchDesktopWD
    Register-ScheduledTask -TaskName "Start_02_SwitchDesktop" -Action $actionSwitchDesktop -Trigger $trigger -Principal $principal -Settings $settings -Force

    $actionSwitch2OBS = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Process -FilePath '$switch2OBSExe' -WorkingDirectory '$switch2OBSWD' -WindowStyle Minimized`"" -WorkingDirectory $switch2OBSWD
    Register-ScheduledTask -TaskName "Start_03_Switch2OBS" -Action $actionSwitch2OBS -Trigger $trigger -Principal $principal -Settings $settings -Force

    #--- FINAL GROUP: OBS, TrimFreeRam, AHKSwitchDesktop, GameMod.ahk ---
    $actionOBS = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Process -FilePath '$obsExe' -WorkingDirectory '$obsWD' -WindowStyle Minimized`"" -WorkingDirectory $obsWD
    Register-ScheduledTask -TaskName "Start_04_OBS_Studio" -Action $actionOBS -Trigger $trigger -Principal $principal -Settings $settings -Force

    $actionTrim = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Process -FilePath '$trimExe' -WorkingDirectory '$trimWD' -WindowStyle Minimized`"" -WorkingDirectory $trimWD
    Register-ScheduledTask -TaskName "Start_05_TrimFreeRam" -Action $actionTrim -Trigger $trigger -Principal $principal -Settings $settings -Force

    $actionAHKSwitch = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Process -FilePath '$ahkSwitchExe' -WorkingDirectory '$ahkSwitchWD' -WindowStyle Minimized`"" -WorkingDirectory $ahkSwitchWD
    Register-ScheduledTask -TaskName "Start_06_AHKSwitchDesktop" -Action $actionAHKSwitch -Trigger $trigger -Principal $principal -Settings $settings -Force
    
    # Add GameMod.ahk to startup
    $actionGameModAhk = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Process -FilePath '$gameModAhkExe' -WorkingDirectory '$gameModAhkWD' -WindowStyle Minimized`"" -WorkingDirectory $gameModAhkWD
    Register-ScheduledTask -TaskName "Start_07_GameModAhk" -Action $actionGameModAhk -Trigger $trigger -Principal $principal -Settings $settings -Force

    Write-Output "All startup tasks have been registered to run minimized in the background."
    Write-Output "Execution order: qBittorrent ? SwitchDesktop ? Switch2OBS ? OBS ? TrimFreeRam ? AHKSwitchDesktop ? GameMod.ahk"
}

function sstartup {
    Write-Output "Starting comprehensive startup cleanup..."

    # 1. Disable PS1 tasks in Task Scheduler
    Get-ScheduledTask | Where-Object {$_.TaskName -like "*PS1*" -or $_.Actions.Execute -like "*.ps1" -or $_.Actions.Arguments -like "*.ps1*"} | ForEach-Object {
        try {
            Disable-ScheduledTask -TaskName $_.TaskName -ErrorAction Stop
            Write-Output "Disabled PS1 scheduled task: $($_.TaskName)"
        }
        catch {
            Write-Output "Unable to disable PS1 task: $($_.TaskName) - $($_.Exception.Message)"
        }
    }

    # 2. Disable AHK tasks in Task Scheduler
    Get-ScheduledTask | Where-Object {$_.TaskName -like "*AHK*" -or $_.Actions.Execute -like "*.ahk" -or $_.Actions.Arguments -like "*.ahk*"} | ForEach-Object {
        try {
            Disable-ScheduledTask -TaskName $_.TaskName -ErrorAction Stop
            Write-Output "Disabled AHK scheduled task: $($_.TaskName)"
        }
        catch {
            Write-Output "Unable to disable AHK task: $($_.TaskName) - $($_.Exception.Message)"
        }
    }

    # 3. Remove PS1 and AHK files from Windows Startup folder (Current User)
    $userStartupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    Get-ChildItem -Path $userStartupFolder -Include "*.ps1","*.ahk","*.lnk" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Extension -eq ".lnk") {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($_.FullName)
            $target = $shortcut.TargetPath
            if ($target -like "*.ps1" -or $target -like "*.ahk" -or $shortcut.Arguments -like "*.ps1*" -or $shortcut.Arguments -like "*.ahk*") {
                try {
                    Rename-Item -Path $_.FullName -NewName "$($_.Name).disabled" -Force
                    Write-Output "Disabled startup shortcut to PS1/AHK: $($_.Name)"
                }
                catch {
                    Write-Output "Unable to disable shortcut: $($_.Name) - $($_.Exception.Message)"
                }
            }
        }
        else {
            try {
                Rename-Item -Path $_.FullName -NewName "$($_.Name).disabled" -Force
                Write-Output "Disabled startup PS1/AHK file: $($_.Name)"
            }
            catch {
                Write-Output "Unable to disable file: $($_.Name) - $($_.Exception.Message)"
            }
        }
    }

    # 4. Remove PS1 and AHK files from Windows Startup folder (All Users)
    $allUsersStartupFolder = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    Get-ChildItem -Path $allUsersStartupFolder -Include "*.ps1","*.ahk","*.lnk" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Extension -eq ".lnk") {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($_.FullName)
            $target = $shortcut.TargetPath
            if ($target -like "*.ps1" -or $target -like "*.ahk" -or $shortcut.Arguments -like "*.ps1*" -or $shortcut.Arguments -like "*.ahk*") {
                try {
                    Rename-Item -Path $_.FullName -NewName "$($_.Name).disabled" -Force
                    Write-Output "Disabled all-users startup shortcut to PS1/AHK: $($_.Name)"
                }
                catch {
                    Write-Output "Unable to disable shortcut: $($_.Name) - $($_.Exception.Message)"
                }
            }
        }
        else {
            try {
                Rename-Item -Path $_.FullName -NewName "$($_.Name).disabled" -Force
                Write-Output "Disabled all-users startup PS1/AHK file: $($_.Name)"
            }
            catch {
                Write-Output "Unable to disable file: $($_.Name) - $($_.Exception.Message)"
            }
        }
    }

    # 5. Disable registry run entries for PS1 and AHK files
    $registryPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    )

    foreach ($path in $registryPaths) {
        if (Test-Path $path) {
            $regValues = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            foreach ($prop in $regValues.PSObject.Properties) {
                if ($prop.Name -like "PS*") { continue }
                if ($prop.Value -like "*.ps1*" -or $prop.Value -like "*.ahk*") {
                    try {
                        New-ItemProperty -Path $path -Name "$($prop.Name)_disabled" -Value $prop.Value -PropertyType String -Force | Out-Null
                        Remove-ItemProperty -Path $path -Name $prop.Name -Force
                        Write-Output "Disabled registry startup entry: $($prop.Name) in $path"
                    }
                    catch {
                        Write-Output "Unable to disable registry entry: $($prop.Name) - $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    # 6. Disable custom scheduled tasks
    $taskNames = @(
        "Start_14_CheatEngine",
        "Start_13_WeMod",
        "Start_12_AHKSwitchDesktop",
        "Start_11_ProcessLasso",
        "Start_10_TrimFreeRam",
        "Start_09_JoyToKey",
        "Start_08_OBS_Studio",
        "Start_08_GameModAhk",
        "Start_07_Switch2OBS",
        "Start_07_AHKSwitchDesktop",
        "Start_07_GameModAhk",
        "Start_06_SwitchDesktop",
        "Start_06_TrimFreeRam",
        "Start_06_AHKSwitchDesktop",
        "Start_05_SuperF4",
        "Start_05_JoyToKey",
        "Start_05_TrimFreeRam",
        "Start_04_Chrome",
        "Start_04_OBS_Studio",
        "Start_03_ghelper",
        "Start_03_Switch2OBS",
        "Start_02_qBittorrent",
        "Start_02_SwitchDesktop",
        "Start_01_Todoist",
        "Start_01_qBittorrent"
    )

    foreach ($taskName in $taskNames) {
        try {
            Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop
            Write-Output "Disabled custom task: $taskName"
        }
        catch {
            Write-Output "Task $taskName not found or already disabled."
        }
    }

    # 7. Disable old-format tasks
    $oldTaskNames = @(
        "Start_CheatEngine",
        "Start_WeMod",
        "Start_AHKSwitchDesktop",
        "Start_ProcessLasso",
        "Start_TrimFreeRam",
        "Start_JoyToKey",
        "Start_OBS_Studio",
        "Start_Switch2OBS",
        "Start_SwitchDesktop",
        "Start_SuperF4",
        "Start_Chrome",
        "Start_ghelper",
        "Start_qBittorrent",
        "Start_Todoist",
        "Start_GameModAhk"
    )

    foreach ($taskName in $oldTaskNames) {
        try {
            Disable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
            Write-Output "Disabled old-format task: $taskName"
        }
        catch {
            # Silently continue if old tasks don't exist
        }
    }

    Write-Output "All startup tasks and scripts have been disabled."
    Write-Output "PowerShell scripts (.ps1) and AutoHotkey scripts (.ahk) have been thoroughly disabled from auto-starting."
}

function winget {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        $Args
    )
    & "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1.25.390.0_x64__8wekyb3d8bbwe\winget.exe" @Args
}




function nets {
    cd F:\\study\programming\python\apps\networkbooster\windows11; py b.py
}


function wall {
    cd F:\\study\programming\python\apps\wallpapers\changeWallPaperAutomatically\gamesonly; py a.py
}


function rmdocker {
    # Stop Docker-related processes
    Write-Host "Stopping Docker-related processes..."
    Stop-Process -Name "Docker*", "com.docker.*", "wsl" -Force -ErrorAction SilentlyContinue

    # Uninstall Docker Desktop via Win32_Product (if installed)
    Write-Host "Uninstalling Docker Desktop..."
    Get-CimInstance -ClassName Win32_Product -Filter "Name LIKE 'Docker Desktop%'" | Invoke-CimMethod -MethodName Uninstall

    # Define all files/folders to purge
    $itemsToRemove = @(
        # Existing paths
        "C:\Users\micha\AppData\Local\Docker\wsl\disk\docker_data.vhdx",
        "C:\Program Files\Docker\Docker\resources\com.docker.backend.exe",
        "C:\Program Files\Docker\Docker\resources\com.docker.build.exe",
        "C:\Program Files\Docker\Docker\resources\com.docker.dev-envs.exe",
        "C:\Program Files\WSL\wslsettings\Assets\SettingsOOBEDockerDesktopIntegration.png",
        "C:\Program Files\WindowsApps\MicrosoftCorporationII.WindowsSubsystemForLinux_2.4.11.0_x64__8wekyb3d8bbwe\Images\SettingsOOBEDockerDesktopIntegration.png",
        "C:\Users\micha\AppData\Local\Docker\log\host\com.docker.backend.exe.log",
        "C:\Program Files\Send Anywhere\resources\app.asar.unpacked\node_modules\sqlite3\tools\docker\architecture\linux-arm64\Dockerfile",
        "C:\Program Files\Send Anywhere\resources\app.asar.unpacked\node_modules\sqlite3\tools\docker\architecture\linux-arm\Dockerfile",
        "C:\Program Files\Git\usr\share\vim\vim91\syntax\dockerfile.vim",
        "C:\Program Files\Send Anywhere\resources\app.asar.unpacked\node_modules\sqlite3\Dockerfile",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Docker Desktop.lnk",
        "C:\Users\micha\Desktop\Docker Desktop.lnk",
        "C:\Users\micha\AppData\Local\Programs\Microsoft VS Code\resources\app\extensions\docker\syntaxes\docker.tmLanguage.json",
        "C:\Users\micha\Desktop\DockerDesktop.lnk",
        "C:\Program Files\WSL\wslsettings\Views\OOBE\DockerDesktopIntegrationPage.xbf",
        "C:\Program Files\WSL\wslsettings\Assets\SettingsOOBEDockerIcon.png",
        "C:\Program Files\WindowsApps\MicrosoftCorporationII.WindowsSubsystemForLinux_2.4.11.0_x64__8wekyb3d8bbwe\Images\SettingsOOBEDockerIcon.png",
        "C:\Program Files\Git\usr\share\vim\vim91\ftplugin\dockerfile.vim",
        "C:\Program Files\Send Anywhere\resources\app.asar.unpacked\node_modules\sqlite3\.dockerignore",
        "C:\Users\micha\AppData\Local\Programs\Microsoft VS Code\resources\app\node_modules\is-docker",
        "C:\Users\micha\.vscode\extensions\ms-python.vscode-pylance-2025.3.2\dist\typesh ed-fallback\stubs\dockerfile-parse\dockerfile_parse",
        "C:\Users\micha\.vscode\extensions\ms-python.vscode-pylance-2025.3.2\dist\typeshed-fallback\stubs\dockerfile-parse",
        "C:\Users\micha\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\docker-desktop",
        "C:\Users\micha\AppData\Roaming\Docker Desktop",
        "C:\Users\micha\AppData\Local\Programs\Microsoft VS Code\resources\app\extensions\docker",
        "C:\Users\micha\AppData\Local\Docker",
        "C:\Users\micha\.vscode\extensions\ms-python.vscode-pylance-2025.3.2\dist\typeshed-fallback\stubs\docker\docker",
        "C:\Users\micha\.vscode\extensions\ms-python.vscode-pylance-2025.3.2\dist\typeshed-fallback\stubs\docker",
        "C:\Program Files\Send Anywhere\resources\app.asar.unpacked\node_modules\sqlite3\tools\docker",
        "C:\Program Files\Docker\Docker",
        "C:\Program Files\Docker",
        "C:\Users\micha\.docker",
        # New folders to purge
        "C:\Users\micha\AppData\Local\Temp\DockerDesktop",
        "C:\ProgramData\DockerDesktop",
        "C:\Users\micha\AppData\Roaming\Docker"
    )

    # Loop through each item and attempt removal
    Write-Host "Removing Docker files and directories..."
    foreach ($item in $itemsToRemove) {
        try {
            if (Test-Path $item) {
                Remove-Item $item -Force -Recurse -ErrorAction Stop
                Write-Host "Removed: $item"
            } else {
                Write-Host "Not found: $item"
            }
        }
        catch {
            Write-Host "Failed to remove '$item': $($_.Exception.Message)"
        }
    }

    # Unregister the Docker Desktop WSL2 distribution
    Write-Host "Unregistering Docker Desktop WSL2 distribution..."
    wsl --unregister docker-desktop

    Write-Host "Docker removal process complete."
}



function specs {
    Write-Host "Collecting selected laptop hardware specifications..." -ForegroundColor Green
    Write-Host "=====================================================" -ForegroundColor Green

    # Get OS information (Exact OS name and architecture)
    $os = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object Caption, OSArchitecture
    Write-Host "`n--- Operating System ---" -ForegroundColor Cyan
    Write-Host ("OS: " + $os.Caption)
    Write-Host ("Architecture: " + $os.OSArchitecture)

    # Get full product model from the computer system
    $system = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object Manufacturer, Model
    Write-Host "`n--- Computer System ---" -ForegroundColor Cyan
    Write-Host ("Manufacturer: " + $system.Manufacturer)
    Write-Host ("Full Product Model: " + $system.Model)

    # Get GPU information (Name of video controller)
    $gpu = Get-CimInstance -ClassName Win32_VideoController | Select-Object -First 1 Name
    Write-Host "`n--- Graphics Processing Unit ---" -ForegroundColor Cyan
    Write-Host ("GPU: " + $gpu.Name)

    # Get CPU information (Exact CPU name, cores, and logical processors)
    $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1 Name, NumberOfCores, NumberOfLogicalProcessors
    Write-Host "`n--- Central Processing Unit ---" -ForegroundColor Cyan
    Write-Host ("CPU: " + $cpu.Name)
    Write-Host ("Cores: " + $cpu.NumberOfCores + " | Logical Processors: " + $cpu.NumberOfLogicalProcessors)

    # Get RAM information (Total Physical Memory in GB)
    $totalRAM = [Math]::Round($system.TotalPhysicalMemory / 1GB, 2)
    Write-Host "`n--- Memory ---" -ForegroundColor Cyan
    Write-Host ("Installed RAM: " + $totalRAM + " GB")

    # Get Storage information (Disk drive type and capacity)
    Write-Host "`n--- Storage ---" -ForegroundColor Cyan
    $drives = Get-CimInstance -ClassName Win32_DiskDrive | Select-Object Model, InterfaceType, Size
    foreach ($drive in $drives) {
        $sizeGB = [Math]::Round($drive.Size / 1GB, 2)
        Write-Host ("Drive: " + $drive.Model)
        Write-Host ("Type: " + $drive.InterfaceType + " | Capacity: " + $sizeGB + " GB")
    }

    # Get Motherboard information
    $board = Get-CimInstance -ClassName Win32_BaseBoard | Select-Object Manufacturer, Product, SerialNumber
    Write-Host "`n--- Motherboard ---" -ForegroundColor Cyan
    Write-Host ("Manufacturer: " + $board.Manufacturer)
    Write-Host ("Product: " + $board.Product)
    Write-Host ("Serial Number: " + $board.SerialNumber)

    # Get BIOS serial number (if different from the motherboard)
    $bios = Get-CimInstance -ClassName Win32_BIOS | Select-Object -First 1 SerialNumber
    Write-Host "`n--- System Serial Number ---" -ForegroundColor Cyan
    Write-Host ("BIOS Serial Number: " + $bios.SerialNumber)

    # Determine BIOS update support URL based on motherboard manufacturer.
    Write-Host "`n--- BIOS Update ---" -ForegroundColor Cyan
    $manufacturer = $board.Manufacturer
    $biosUpdateURL = switch -Wildcard ($manufacturer) {
        "*Dell*"         { "https://www.dell.com/support/home/en-us/drivers" ; break }
        "*HP*"           { "https://support.hp.com/us-en/drivers" ; break }
        "*Lenovo*"       { "https://pcsupport.lenovo.com/us/en/solutions/ht502081" ; break }
        "*ASUS*"         { "https://www.asus.com/support/" ; break }
        "*MSI*"          { "https://www.msi.com/support/download" ; break }
        Default          { "https://www.google.com/search?q=" + $manufacturer + "+BIOS+update" }
    }
    Write-Host "To update your BIOS drivers, run the one-liner command below:"
    Write-Host "Start-Process '$biosUpdateURL'"
}



function py {
    if ($args.Count -eq 0) {
        Write-Host "No Python file specified"
        return
    }
    & "C:\Program Files\Python313\python.exe" @args
}


function python {
    if ($args.Count -eq 0) {
        Write-Host "No Python file specified"
        return
    }
    & "C:\Program Files\Python313\python.exe" @args
}



function steam {
    Set-Location "F:\backup\windowsapps\Credentials\ahk"
    .\steam.ahk
    Start-Sleep -Seconds 20
    ws gmail2
}


function game {
    cd F:\study\programming\python\apps\media\games\GameSearchData; py i.py
}



function purge {
    param(
        [Parameter(Mandatory = $true)]
        [string]$folderPath
    )
    # Change the directory to the app folder
    Set-Location "F:\study\programming\python\apps\FolderPurger"

    # Execute the Python script with the provided folder path
    python d.py "$folderPath"
}


function qaccess {
    # Remove all QuickAccess pinned items.
    # Removing every file in AutomaticDestinations will clear QuickAccess.
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*" -Force -Recurse
    Start-Sleep -Seconds 1

    # Define the list of folders that we want to add to QuickAccess.
    $folders = @(
        "F:\backup\windowsapps",
        "F:\backup\windowsapps\installed",
        "F:\backup\windowsapps\install",
        "F:\backup\windowsapps\profile",
        "C:\Users\micha\Videos",
        "C:\games",
        "F:\study",
        "F:\backup",
        "C:\Users\micha"
    )

    # Create a Shell.Application COM object for pinning folders.
    $shell = New-Object -ComObject Shell.Application

    foreach ($folder in $folders) {
        # If the folder is on the C: drive but is not an exception (does not contain "micha" and isn't exactly "C:\games"), change its drive to F:
        if ($folder -like "C:\*") {
            if (($folder -notlike "*micha*") -and ($folder -ne "C:\games")) {
                $folder = $folder -replace "^C:", "F:"
            }
        }
        
        # Attempt to get the folder namespace. If found, pin it to QuickAccess.
        $ns = $shell.Namespace($folder)
        if ($ns) {
            $ns.Self.InvokeVerb("pintohome")
        }
        else {
            Write-Host "Folder not found or inaccessible: $folder"
        }
    }
}

function short3 {
    $basePath = "F:\backup\windowsapps\installed"
    $shell = New-Object -ComObject WScript.Shell
    $processedFolders = @{}
    $totalFolders = 0
    $shortcutsCreated = 0
    $shortcutsSkipped = 0
    $shortcutsRemoved = 0

    # Function to find the main executable in a folder
    function Find-MainExecutable {
        param (
            [string]$folderPath
        )
        
        # Look for executables directly in this folder
        $exeFiles = Get-ChildItem -Path $folderPath -Filter "*.exe" -File -ErrorAction SilentlyContinue
        
        # First priority: Look for exe files with names matching the parent folder name
        $folderName = Split-Path -Path $folderPath -Leaf
        $matchingExe = $exeFiles | Where-Object { 
            $exeName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            return $exeName -eq $folderName -or 
                   $exeName -eq "$folderName-win64" -or 
                   $exeName -eq "$folderName-win32" -or
                   $exeName -eq "app" -or
                   $exeName -eq "launcher" -or
                   $exeName -eq "main"
        } | Select-Object -First 1
        
        if ($matchingExe) {
            return $matchingExe.FullName
        }
        
        # Second priority: Look for exe files in specific subfolders
        $commonSubfolders = @("bin", "app", "program", "dist", "build", "release")
        foreach ($subFolder in $commonSubfolders) {
            $subFolderPath = Join-Path -Path $folderPath -ChildPath $subFolder
            if (Test-Path -Path $subFolderPath -PathType Container) {
                $subFolderExes = Get-ChildItem -Path $subFolderPath -Filter "*.exe" -File -ErrorAction SilentlyContinue
                $subFolderMatchingExe = $subFolderExes | Where-Object { 
                    $exeName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                    return $exeName -eq $folderName -or 
                           $exeName -eq "$folderName-win64" -or 
                           $exeName -eq "$folderName-win32" -or
                           $exeName -eq "app" -or
                           $exeName -eq "launcher" -or
                           $exeName -eq "main"
                } | Select-Object -First 1
                
                if ($subFolderMatchingExe) {
                    return $subFolderMatchingExe.FullName
                }
            }
        }
        
        # Third priority: Simply take the largest exe file (assuming it's the main application)
        if ($exeFiles.Count -gt 0) {
            return ($exeFiles | Sort-Object Length -Descending | Select-Object -First 1).FullName
        }
        
        # If no exe found directly, try to find the biggest one recursively
        $allExeFiles = Get-ChildItem -Path $folderPath -Filter "*.exe" -File -Recurse -ErrorAction SilentlyContinue
        if ($allExeFiles.Count -gt 0) {
            return ($allExeFiles | Sort-Object Length -Descending | Select-Object -First 1).FullName
        }
        
        return $null
    }

    # Function to manage shortcuts in a folder - ensure only one exists
    function Manage-Shortcuts {
        param (
            [string]$folderPath,
            [string]$mainExePath = $null
        )

        $existingShortcuts = Get-ChildItem -Path $folderPath -Filter "*.lnk" -File -ErrorAction SilentlyContinue
        
        # Case 1: No shortcuts exist, create one if executable is found
        if ($existingShortcuts.Count -eq 0) {
            if ($mainExePath) {
                $shortcutPath = Join-Path -Path $folderPath -ChildPath "$([System.IO.Path]::GetFileNameWithoutExtension($mainExePath)).lnk"
                
                try {
                    $shortcut = $shell.CreateShortcut($shortcutPath)
                    $shortcut.TargetPath = $mainExePath
                    $shortcut.WorkingDirectory = [System.IO.Path]::GetDirectoryName($mainExePath)
                    $shortcut.Save()
                    Write-Host "Created shortcut for $mainExePath in $folderPath" -ForegroundColor Green
                    $script:shortcutsCreated++
                }
                catch {
                    $errorMsg = $_.Exception.Message
                    Write-Host "Error creating shortcut in $folderPath`: $errorMsg" -ForegroundColor Red
                }
            }
            else {
                Write-Host "No suitable executable found in $folderPath" -ForegroundColor Yellow
            }
            return
        }
        
        # Case 2: Multiple shortcuts exist, keep only the best one
        if ($existingShortcuts.Count -gt 1) {
            Write-Host "Found $($existingShortcuts.Count) shortcuts in $folderPath, cleaning up..." -ForegroundColor Yellow
            
            # Identify the best shortcut to keep
            $bestShortcut = $null
            $bestScore = -1
            
            foreach ($lnk in $existingShortcuts) {
                try {
                    $shortcut = $shell.CreateShortcut($lnk.FullName)
                    $targetPath = $shortcut.TargetPath
                    
                    # Skip invalid shortcuts
                    if (-not (Test-Path -Path $targetPath -ErrorAction SilentlyContinue)) {
                        continue
                    }
                    
                    # Score this shortcut (higher is better)
                    $score = 0
                    
                    # Prefer executables with same name as the folder
                    $folderName = Split-Path -Path $folderPath -Leaf
                    $exeName = [System.IO.Path]::GetFileNameWithoutExtension($targetPath)
                    
                    if ($exeName -eq $folderName) { $score += 10 }
                    if ($exeName -like "$folderName*") { $score += 5 }
                    if ($exeName -eq "app" -or $exeName -eq "main" -or $exeName -eq "launcher") { $score += 3 }
                    
                    # Prefer executables in the same directory or direct subdirectories
                    if ($targetPath.StartsWith($folderPath)) {
                        $relativePath = $targetPath.Substring($folderPath.Length).Trim('\')
                        $pathDepth = ($relativePath.Split('\').Count - 1)
                        $score += (5 - [Math]::Min(5, $pathDepth))
                    }
                    
                    # Consider file size (larger often means main app)
                    $fileInfo = Get-Item -Path $targetPath -ErrorAction SilentlyContinue
                    if ($fileInfo) {
                        # Add 0-3 points based on size (larger files get more points)
                        $sizeMB = $fileInfo.Length / 1MB
                        if ($sizeMB -gt 50) { $score += 3 }
                        elseif ($sizeMB -gt 10) { $score += 2 }
                        elseif ($sizeMB -gt 1) { $score += 1 }
                    }
                    
                    if ($score -gt $bestScore) {
                        $bestScore = $score
                        $bestShortcut = $lnk
                    }
                }
                catch {
                    # Skip problematic shortcuts
                    continue
                }
            }
            
            # Keep the best shortcut, delete the rest
            if ($bestShortcut) {
                foreach ($lnk in $existingShortcuts) {
                    if ($lnk.FullName -ne $bestShortcut.FullName) {
                        Remove-Item -Path $lnk.FullName -Force -ErrorAction SilentlyContinue
                        Write-Host "Removed extra shortcut: $($lnk.Name)" -ForegroundColor DarkYellow
                        $script:shortcutsRemoved++
                    }
                    else {
                        Write-Host "Keeping shortcut: $($lnk.Name)" -ForegroundColor Cyan
                    }
                }
            }
            elseif ($mainExePath) {
                # If no valid shortcuts were found, create a new one
                # Remove all existing invalid shortcuts
                foreach ($lnk in $existingShortcuts) {
                    Remove-Item -Path $lnk.FullName -Force -ErrorAction SilentlyContinue
                    $script:shortcutsRemoved++
                }
                
                # Create a new valid shortcut
                $shortcutPath = Join-Path -Path $folderPath -ChildPath "$([System.IO.Path]::GetFileNameWithoutExtension($mainExePath)).lnk"
                try {
                    $shortcut = $shell.CreateShortcut($shortcutPath)
                    $shortcut.TargetPath = $mainExePath
                    $shortcut.WorkingDirectory = [System.IO.Path]::GetDirectoryName($mainExePath)
                    $shortcut.Save()
                    Write-Host "Created new shortcut for $mainExePath after removing invalid ones" -ForegroundColor Green
                    $script:shortcutsCreated++
                }
                catch {
                    $errorMsg = $_.Exception.Message
                    Write-Host "Error creating replacement shortcut in $folderPath`: $errorMsg" -ForegroundColor Red
                }
            }
        }
        # Case 3: Exactly one shortcut exists, verify it's valid
        else {
            $existingShortcut = $existingShortcuts[0]
            try {
                $shortcut = $shell.CreateShortcut($existingShortcut.FullName)
                $targetPath = $shortcut.TargetPath
                
                if (-not (Test-Path -Path $targetPath -ErrorAction SilentlyContinue) -and $mainExePath) {
                    # Replace invalid shortcut with a valid one
                    Remove-Item -Path $existingShortcut.FullName -Force -ErrorAction SilentlyContinue
                    $script:shortcutsRemoved++
                    
                    $shortcutPath = Join-Path -Path $folderPath -ChildPath "$([System.IO.Path]::GetFileNameWithoutExtension($mainExePath)).lnk"
                    $shortcut = $shell.CreateShortcut($shortcutPath)
                    $shortcut.TargetPath = $mainExePath
                    $shortcut.WorkingDirectory = [System.IO.Path]::GetDirectoryName($mainExePath)
                    $shortcut.Save()
                    Write-Host "Replaced invalid shortcut with one for $mainExePath" -ForegroundColor Green
                    $script:shortcutsCreated++
                }
                else {
                    Write-Host "Folder $folderPath already has a valid shortcut, keeping it" -ForegroundColor Cyan
                    $script:shortcutsSkipped++
                }
            }
            catch {
                $errorMsg = $_.Exception.Message
                Write-Host "Error verifying existing shortcut in $folderPath`: $errorMsg" -ForegroundColor Red
            }
        }
    }

    # Process all folders recursively
    function Process-Folders {
        param (
            [string]$currentPath
        )
        
        $folders = Get-ChildItem -Path $currentPath -Directory -ErrorAction SilentlyContinue
        
        foreach ($folder in $folders) {
            # Skip if this folder has already been processed
            if ($processedFolders.ContainsKey($folder.FullName)) {
                continue
            }
            
            $processedFolders[$folder.FullName] = $true
            $script:totalFolders++
            
            # Find the main executable
            $mainExe = Find-MainExecutable -folderPath $folder.FullName
            
            # Manage shortcuts - ensure only one exists
            Manage-Shortcuts -folderPath $folder.FullName -mainExePath $mainExe
            
            # Process subfolders
            Process-Folders -currentPath $folder.FullName
        }
    }

    # Main execution
    Write-Host "Starting to process folders in $basePath..." -ForegroundColor Magenta
    Process-Folders -currentPath $basePath
    
    # Release COM object
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    
    # Summary
    Write-Host "`nProcess completed!" -ForegroundColor Green
    Write-Host "Total folders processed: $totalFolders" -ForegroundColor White
    Write-Host "Shortcuts created: $shortcutsCreated" -ForegroundColor Green
    Write-Host "Folders skipped (already had valid shortcuts): $shortcutsSkipped" -ForegroundColor Cyan
    Write-Host "Extra shortcuts removed: $shortcutsRemoved" -ForegroundColor Yellow
}


function short2 {
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $cleanupPath = Join-Path -Path $desktopPath -ChildPath 'cleanup'
    $shell = New-Object -ComObject WScript.Shell
    
    # Track all unique target paths to prevent duplicates
    $processedTargets = @{}
    $processedNames = @{}
    
    # First, check existing shortcuts in the cleanup folder
    if (Test-Path -Path $cleanupPath) {
        Get-ChildItem -Path $cleanupPath -Filter "*.lnk" | ForEach-Object {
            try {
                $existingShortcut = $shell.CreateShortcut($_.FullName)
                $targetPath = $existingShortcut.TargetPath
                $arguments = $existingShortcut.Arguments
                $uniqueKey = "$targetPath|$arguments"
                
                # Add to processed lists
                $processedTargets[$uniqueKey] = $true
                $processedNames[$_.Name] = $true
                
                Write-Host "Found existing shortcut in cleanup folder: $($_.Name) - will not create on desktop"
            }
            catch {
                Write-Host "Error reading cleanup shortcut: $($_.FullName) - $_"
            }
        }
    }
    
    # Get all shortcuts in the source directory
    Get-ChildItem -Path "F:\backup\windowsapps\installed" -Recurse -Filter "*.lnk" | Where-Object {
        # Exclude shortcuts within zip files
        $_.FullName -notmatch '\.zip\\'
    } | ForEach-Object {
        try {
            # Get the target path and arguments of the shortcut
            $shortcut = $shell.CreateShortcut($_.FullName)
            $targetPath = $shortcut.TargetPath
            $arguments = $shortcut.Arguments
            $shortcutName = $_.Name
            $uniqueKey = "$targetPath|$arguments"
            
            # Check if the target path exists and we haven't processed this target yet
            if ([string]::IsNullOrEmpty($targetPath)) {
                Write-Host "Skipping empty shortcut: $($_.FullName)"
            }
            elseif (Test-Path -Path $targetPath) {
                # Skip if we've already processed this target path
                if ($processedTargets.ContainsKey($uniqueKey)) {
                    Write-Host "Skipping duplicate shortcut: $shortcutName (Target already processed or in cleanup folder)"
                }
                # Skip if a shortcut with this name already exists
                elseif ($processedNames.ContainsKey($shortcutName)) {
                    Write-Host "Skipping shortcut with duplicate name: $shortcutName"
                }
                else {
                    # Create new shortcut directly on desktop
                    $destPath = Join-Path -Path $desktopPath -ChildPath $shortcutName
                    $newShortcut = $shell.CreateShortcut($destPath)
                    $newShortcut.TargetPath = $targetPath
                    $newShortcut.Arguments = $arguments
                    $newShortcut.WorkingDirectory = $shortcut.WorkingDirectory
                    $newShortcut.Description = $shortcut.Description
                    $newShortcut.IconLocation = $shortcut.IconLocation
                    $newShortcut.Save()
                    
                    # Track this target and name as processed
                    $processedTargets[$uniqueKey] = $true
                    $processedNames[$shortcutName] = $true
                    
                    Write-Host "Created shortcut: $shortcutName on desktop"
                }
            }
            else {
                Write-Host "Skipping broken shortcut: $shortcutName (Target: $targetPath does not exist)"
            }
        }
        catch {
            Write-Host "Error processing shortcut: $($_.FullName) - $_"
        }
    }
    
    # Release COM object
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    
    # Refresh desktop
    try {
        $shellApp = New-Object -ComObject Shell.Application
        $shellApp.RefreshDesktop()
        Write-Host "Desktop refreshed successfully"
    }
    catch {
        Write-Host "Could not refresh desktop: $_"
        # Alternative refresh method
        $wshell = New-Object -ComObject wscript.shell
        $wshell.SendKeys("{F5}")
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wshell) | Out-Null
    }
    
    # Release shell application COM object
    if ($null -ne $shellApp) {
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shellApp) | Out-Null
    }
}


function rmod {
    Stop-Process -Name "WeMod" -Force; Start-Process -FilePath "C:\Users\micha\AppData\Local\WeMod\WeMod.exe"
}


function robs {
     taskkill /F /IM obs64.exe; cd F:\backup\windowsapps\installed\obs-studio\bin\64bit; powershell Start-Process "obs64.exe" -Verb RunAs
}


function rjoy {
    # Terminate any running instance of JoyToKey
    taskkill /F /IM JoyToKey.exe;
    
    # Change to the directory where JoyToKey is installed
    cd "F:\backup\windowsapps\installed\JoyToKey";
    
    # Start JoyToKey as administrator
    powershell Start-Process "JoyToKey.exe" -Verb RunAs
}

function rg {
    robs; rjoy; rmod; rlas; rche
}

function rr2 {
    desk; rlas; rche; superf4; rmod
}

function rr {
        desk; rlas; superf4; rmod
}


function rlas {
    Stop-Process -Name "processlasso" -Force
    Start-Process -FilePath "F:\backup\windowsapps\installed\Process Lasso\ProcessLasso.exe"
}


function doom {
    Start-Process -FilePath "C:\games\doomethernal\DOOM Eternal\DOOMEternalx64vk.exe"
}


function bully {
       Start-Process -FilePath "C:\games\Bully\Bully Scholarship Edition With Fixes Only\Bully.exe"
}

function rgg {
    bully; rg
}

function tmnt {
    start-process -FilePath "C:\games\TMNTSplinteredFate\TMNTSF.exe"
}

function ashen {
     Start-Process -FilePath "C:\games\Ashen\Ashen.exe"
}

function getdirectx {
    & "F:\backup\windowsapps\install\DircetX\dxwebsetup.exe"
}

function clean2 {
    # Verify we're running in Safe Mode
    if (-not ((Get-WmiObject Win32_ComputerSystem).BootupState -match "SafeBoot")) {
        Write-Warning "This function should only be run in Safe Boot mode!"
        $continue = Read-Host "Continue anyway? (y/n)"
        if ($continue -ne "y") { return }
    }
    
    Write-Host "Starting Windows 11 deep optimization in Safe Boot mode..." -ForegroundColor Cyan
    
    # Registry optimizations specific for Safe Mode
    Write-Host "Applying registry optimizations..." -ForegroundColor Yellow
    
    # Disable startup delay
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" -Name "StartupDelayInMSec" -Value 0 -Type DWord -Force
    
    # Prioritize foreground applications
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ForegroundLockTimeout" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value 100 -Type DWord -Force
    
    # Optimize visual effects for performance
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Value ([byte[]](0x90, 0x12, 0x01, 0x80)) -Type Binary -Force
    
    # Optimize file system
    Write-Host "Running deep file system optimization..." -ForegroundColor Yellow
    
    # Run CHKDSK with advanced params (that are better to run in safe mode)
    if (-not (Test-Path "$env:SystemDrive\chkdsk_pending.txt")) {
        Write-Host "Scheduling CHKDSK with advanced parameters..." -ForegroundColor Yellow
        & chkdsk $env:SystemDrive /f /r /x /b /scan /perf | Out-File "$env:SystemDrive\chkdsk_results.txt"
    }
    
    # Advanced defragmentation only possible in Safe Mode
    Write-Host "Running advanced defragmentation..." -ForegroundColor Yellow
    & defrag $env:SystemDrive /h /u /v /g | Out-File "$env:SystemDrive\defrag_results.txt"
    
    # System file validation with offline image repair
    Write-Host "Performing deep system file repair..." -ForegroundColor Yellow
    & sfc /scannow /offbootdir=$env:SystemDrive /offwindir=$env:SystemDrive\Windows | Out-File "$env:SystemDrive\sfc_results.txt" -Append
    
    # More thorough DISM cleanup than in normal mode
    Write-Host "Performing advanced DISM operations..." -ForegroundColor Yellow
    & DISM.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-File "$env:SystemDrive\dism_cleanup.txt" -Append
    & DISM.exe /Online /Cleanup-Image /SPSuperseded /hidesp | Out-File "$env:SystemDrive\dism_sp.txt" -Append
    
    # Reset Windows Update components (more aggressive in safe mode)
    Write-Host "Resetting Windows Update components..." -ForegroundColor Yellow
    Stop-Service -Name wuauserv, cryptSvc, bits, msiserver -Force
    Remove-Item -Path "$env:SystemRoot\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:SystemRoot\System32\catroot2\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service -Name wuauserv, cryptSvc, bits, msiserver
    
    # Driver store cleanup
    Write-Host "Cleaning up driver store..." -ForegroundColor Yellow
    & pnputil.exe /enum-drivers | Out-File "$env:SystemDrive\drivers_before.txt"
    & pnputil.exe /delete-driver-package /uninstall /force | Out-File "$env:SystemDrive\driver_cleanup.txt"
    
    # Registry hive cleanup and compaction (safe in safe mode)
    Write-Host "Optimizing registry..." -ForegroundColor Yellow
    $regFiles = @(
        "$env:SystemRoot\System32\config\SOFTWARE",
        "$env:SystemRoot\System32\config\SYSTEM"
    )
    foreach ($file in $regFiles) {
        if (Test-Path -Path $file) {
            $backupFile = "$file.bak"
            Copy-Item -Path $file -Destination $backupFile -Force
            Write-Host "Backed up registry hive: $file"
        }
    }
    
    # Run advanced Windows Store reset
    Write-Host "Resetting Windows Store..." -ForegroundColor Yellow
    Get-AppXPackage -AllUsers -Name Microsoft.WindowsStore | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"} | Out-File "$env:SystemDrive\store_reset.txt"
    
    # Reset virtual memory settings to optimal
    Write-Host "Optimizing virtual memory..." -ForegroundColor Yellow
    $computersys = Get-WmiObject Win32_ComputerSystem
    $TotalRam = [Math]::Round($computersys.TotalPhysicalMemory / 1GB, 0)
    $InitialSize = $TotalRam * 1024 * 1.5
    $MaximumSize = $TotalRam * 1024 * 3
    $pagefile = Get-WmiObject -Query "SELECT * FROM Win32_PageFileSetting WHERE Name='C:\\pagefile.sys'"
    if ($pagefile) {
        $pagefile.InitialSize = $InitialSize
        $pagefile.MaximumSize = $MaximumSize
        $pagefile.Put() | Out-Null
    } else {
        $pagefile = Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{Name="C:\pagefile.sys"; InitialSize = $InitialSize; MaximumSize = $MaximumSize}
    }
    
    # Set power configuration to high performance
    Write-Host "Setting power plan to Ultimate Performance..." -ForegroundColor Yellow
    powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
    powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61
    
    # Clean up Component Store more aggressively (safe in safe mode)
    Write-Host "Deep cleaning Component Store..." -ForegroundColor Yellow
    & DISM.exe /Online /Cleanup-Image /AnalyzeComponentStore | Out-File "$env:SystemDrive\component_store_before.txt"
    & DISM.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-File "$env:SystemDrive\component_store_after.txt"
    
    # Optimize Service Startup Types
    Write-Host "Optimizing service configurations..." -ForegroundColor Yellow
    $servicesToDisable = @(
        "DiagTrack", # Connected User Experiences and Telemetry
        "dmwappushservice", # WAP Push Message Routing Service
        "MapsBroker", # Downloaded Maps Manager
        "lfsvc", # Geolocation Service
        "SharedAccess", # Internet Connection Sharing
        "lltdsvc", # Link-Layer Topology Discovery Mapper
        "wlidsvc", # Microsoft Account Sign-in Assistant
        "NgcSvc", # Microsoft Passport
        "NgcCtnrSvc", # Microsoft Passport Container
        "PhoneSvc", # Phone Service
        "PcaSvc", # Program Compatibility Assistant
        "RemoteRegistry", # Remote Registry
        "RetailDemo", # Retail Demo Service
        "SysMain", # Superfetch
        "WerSvc", # Windows Error Reporting Service
        "XblAuthManager", # Xbox Live Auth Manager
        "XblGameSave", # Xbox Live Game Save
        "XboxNetApiSvc" # Xbox Live Networking Service
    )
    
    foreach ($service in $servicesToDisable) {
        try {
            Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            Write-Host "Disabled service: $service"
        } catch {
            Write-Warning "Could not disable service: $service"
        }
    }
    
    # Clear shadow copies that may be corrupted
    Write-Host "Clearing shadow copies..." -ForegroundColor Yellow
    vssadmin delete shadows /all /quiet
    
    # Reset base installation to recover from component store corruption
    Write-Host "Resetting Windows installation base..." -ForegroundColor Yellow
    & DISM.exe /Online /Cleanup-Image /RestoreHealth /Source:WIM:D:\Sources\Install.wim:1 /LimitAccess

    # Clean font cache which can cause UI slowdowns
    Write-Host "Cleaning font cache..." -ForegroundColor Yellow
    Stop-Service "FontCache" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache\*" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache-System\*" -Force -Recurse -ErrorAction SilentlyContinue
    Start-Service "FontCache" -ErrorAction SilentlyContinue
    
    # Reset network stack completely (safer in safe mode)
    Write-Host "Resetting network stack completely..." -ForegroundColor Yellow
    ipconfig /flushdns
    netsh winsock reset
    netsh int ip reset
    netsh advfirewall reset
    
    # Fix file system permission issues
    Write-Host "Repairing file permissions..." -ForegroundColor Yellow
    icacls C:\ /reset /T /C /L | Out-File "$env:SystemDrive\permissions_repair.txt"
    
    Write-Host "Windows 11 deep optimization in Safe Boot mode completed!" -ForegroundColor Green
    Write-Host "Please restart your computer normally to complete the optimization process." -ForegroundColor Yellow
}


function getdocker {
    [CmdletBinding()]
    param (
        [switch]$Force
    )

    try {
        # Check if running as Administrator
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            throw "This function requires PowerShell to run as Administrator."
        }

        # Check if winget is installed
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw "winget is not installed. Please install winget from the Microsoft Store or GitHub."
        }

        # Check internet connectivity
        if (-not (Test-Connection -ComputerName www.docker.com -Count 1 -Quiet)) {
            throw "No internet connection detected. Please ensure you are connected to the internet."
        }

        # Check system requirements for Docker Desktop
        $osInfo = Get-CimInstance Win32_OperatingSystem
        $osVersion = [Version]$osInfo.Version
        $isProOrEnterprise = $osInfo.Caption -match "Pro|Enterprise"
        if (-not ($osInfo.Caption -match "Windows (10|11)" -and $isProOrEnterprise -and $osVersion -ge [Version]"10.0.19041")) {
            throw "Docker Desktop requires Windows 10/11 Pro or Enterprise (version 2004 or later)."
        }

        # Check available disk space (minimum 20GB recommended)
        $drive = (Get-Location).Drive.Name
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive`:'"
        if ($disk.FreeSpace -lt 20GB) {
            throw "Insufficient disk space. Docker Desktop requires at least 20GB of free space."
        }

        # Check Hyper-V and Virtual Machine Platform
        $hyperV = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
        $vmPlatform = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
        if ($hyperV.State -ne "Enabled" -or $vmPlatform.State -ne "Enabled") {
            Write-Host "Enabling Hyper-V and Virtual Machine Platform..."
            try {
                Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart -ErrorAction Stop | Out-Null
                Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart -ErrorAction Stop | Out-Null
                Write-Host "Hyper-V and Virtual Machine Platform enabled. Please restart your computer and rerun this function."
                return
            }
            catch {
                throw "Failed to enable Hyper-V or Virtual Machine Platform: $_"
            }
        }

        # Check if WSL2 is installed and enabled
        $wslStatus = wsl --status 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Installing WSL2..."
            try {
                dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
                dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
                wsl --install --no-distribution
                Write-Host "WSL2 installation initiated. Please restart your computer and rerun this function."
                return
            }
            catch {
                throw "Failed to install WSL2: $_"
            }
        }

        # Check if Docker is already installed
        if ((Get-Command docker -ErrorAction SilentlyContinue) -and (-not $Force)) {
            Write-Host "Docker is already installed. Use -Force to reinstall."
            return
        }

        # Clean up existing Docker installations and winget cache
        Write-Host "Cleaning up existing Docker installations and winget cache..."
        Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
        $dockerPath = Join-Path $env:ProgramFiles "Docker"
        if (Test-Path $dockerPath) {
            Remove-Item -Path $dockerPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        $wingetCache = Join-Path $env:LocalAppData "Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalCache"
        if (Test-Path $wingetCache) {
            Remove-Item -Path $wingetCache -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Install Docker Desktop with retry mechanism
        Write-Host "Installing Docker Desktop via winget..."
        $maxRetries = 3
        $retryCount = 0
        $success = $false
        $installArgs = @(
            "install",
            "--exact",
            "--id", "Docker.DockerDesktop",
            "--source", "winget",
            "--accept-package-agreements",
            "--accept-source-agreements",
            "--silent",
            "--disable-interactivity",
            "--no-upgrade"
        )
        if ($Force) { $installArgs += "--force" }

        $logFile = "$env:TEMP\winget_docker_install.log"
        while (-not $success -and $retryCount -lt $maxRetries) {
            try {
                $installResult = winget @installArgs 2>&1 | Out-File $logFile -Append
                if ($LASTEXITCODE -eq 0) {
                    $success = $true
                }
                else {
                    $retryCount++
                    Write-Warning "Installation attempt $retryCount failed with exit code $LASTEXITCODE. Retrying..."
                    Start-Sleep -Seconds 5
                }
            }
            catch {
                $retryCount++
                Write-Warning "Installation attempt $retryCount failed: $_"
                Start-Sleep -Seconds 5
            }
        }

        if (-not $success) {
            $errorMessage = switch ($LASTEXITCODE) {
                -1978335226 { "Installer failed (possible corruption, network issue, or security software interference)." }
                -1978335231 { "Installer hash verification failed." }
                default { "Unknown error (exit code: $LASTEXITCODE)." }
            }
            Write-Warning "winget installation failed. Attempting manual download..."

            # Fallback to manual download
            $installerUrl = "https://desktop.docker.com/win/stable/Docker%20Desktop%20Installer.exe"
            $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"
            Write-Host "Downloading Docker Desktop installer..."
            try {
                Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -ErrorAction Stop
                if ((Get-Item $installerPath).Length -lt 500MB) {
                    throw "Downloaded installer is too small, likely corrupted."
                }
                Write-Host "Starting manual installation..."
                Start-Process -FilePath $installerPath -ArgumentList "install --quiet --accept-license" -Wait -ErrorAction Stop
                $success = $true
            }
            catch {
                throw "Manual installation failed: $_`nwinget error: $errorMessage`nLog: $logFile"
            }
        }

        # Verify Docker Desktop installation
        $dockerExePath = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
        if (-not (Test-Path $dockerExePath)) {
            throw "Docker Desktop executable not found at $dockerExePath"
        }

        # Start Docker Desktop
        Write-Host "Starting Docker Desktop..."
        Start-Process -FilePath $dockerExePath -ErrorAction Stop

        # Wait for Docker to initialize
        Write-Host "Waiting for Docker to initialize..."
        $timeout = 60
        $dockerRunning = $false
        for ($i = 0; $i -lt $timeout; $i++) {
            try {
                docker info --format '{{.ServerVersion}}' | Out-Null
                if ($?) {
                    $dockerRunning = $true
                    break
                }
            }
            catch {
                Start-Sleep -Seconds 1
            }
        }

        if ($dockerRunning) {
            Write-Host "Docker Desktop installed and running successfully."
        }
        else {
            throw "Docker service failed to start within $timeout seconds. Check Docker Desktop for details."
        }
    }
    catch {
        Write-Error "Failed to install Docker Desktop: $_"
        Write-Host "Troubleshooting steps:"
        Write-Host "- Check the log file at $logFile for details."
        Write-Host "- Ensure no antivirus or firewall is blocking the installer."
        Write-Host "- Verify internet connectivity and try again."
        Write-Host "- Manually install from https://www.docker.com/products/docker-desktop/"
    }
    finally {
        # Clean up temporary installer if it exists
        if (Test-Path $installerPath -ErrorAction SilentlyContinue) {
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        }
    }
}




function unlock {
    REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f;
    REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUsername /t REG_SZ /d "$env:USERNAME" /f;
    REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d "13571357" /f;
    REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v ForceAutoLogon /t REG_SZ /d 1 /f;
    
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v DisablePasswordChange /t REG_DWORD /d 1 /f;
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v DisableLockWorkstation /t REG_DWORD /d 1 /f;
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v InactivityTimeoutSecs /t REG_DWORD /d 0 /f;
    
    powercfg -change -standby-timeout-ac 0;
    powercfg -change -monitor-timeout-ac 0;
    powercfg -change -disk-timeout-ac 0;
    
    REG ADD "HKCU\Control Panel\Desktop" /v ScreenSaveActive /t REG_SZ /d 0 /f;
    REG ADD "HKCU\Software\Policies\Microsoft\Windows\System" /v AllowDomainPINLogon /t REG_DWORD /d 0 /f;
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v AllowDomainPINLogon /t REG_DWORD /d 0 /f;
    
    REG DELETE "HKLM\SOFTWARE\Microsoft\PolicyManager\default\Settings\AllowSignInOptions" /f 2>$null;
    REG DELETE "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\UserTile" /f 2>$null;
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 0 -PropertyType DWord -Force; New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 0 -PropertyType DWord -Force
}


function getcho {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        refreshenv
    }

    choco install nano git -y --force

    # Refresh environment variables for current session
    $envPath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $gitPath = "C:\Program Files\Git\cmd"

    if ($env:PATH -notlike "*$gitPath*") {
        $env:PATH += ";$gitPath"
    }
}




function get7z {
    & "F:\backup\windowsapps\install\7z2409-x64.exe"
}



function getarm {
    & "F:\backup\windowsapps\install\Asus\ArmouryCrateInstaller_3.3.1.0\ArmouryCrateInstaller.exe"
}



function getvc {
    & "F:\backup\windowsapps\install\VCredist\install_all.bat"; & "F:\backup\windowsapps\install\VCredist\aio-runtimes_v2.5.0.exe" 
}



function getf4 {
    $super4fExe = "F:\backup\windowsapps\installed\SuperF4\SuperF4.exe"
    $super4fWD = "F:\backup\windowsapps\installed\SuperF4"

    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -RunOnlyIfNetworkAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Process -FilePath '$super4fExe' -WorkingDirectory '$super4fWD' -WindowStyle Minimized`"" -WorkingDirectory $super4fWD

    Register-ScheduledTask -TaskName "Start_SuperF4" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force

    Write-Output "Startup task for SuperF4 has been registered."
}



function fixtaskbar {
    Stop-Process -Name explorer -Force; Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache*.db","$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache*.db","$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue; ie4uinit.exe -show; Start-Process explorer.exe
}



function sfol {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$searchTerm
    )

    # Recursively search for directories whose names contain the search term
    Get-ChildItem -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$searchTerm*" } |
        ForEach-Object {
            $winPath = $_.FullName

            # Convert Windows path to WSL2 path format:
            # Replace backslashes with forward slashes
            $wslPath = $winPath -replace '\\','/'

            # If the path starts with a drive letter (e.g., "C:"), convert it to /mnt/f format
            if ($wslPath -match '^([A-Za-z]):') {
                $driveLetter = $matches[1].ToLower()
                $wslPath = "/mnt/$driveLetter" + $wslPath.Substring(2)
            }

            Write-Output "PowerShell Path: $winPath"
            Write-Output "WSL2 Path: $wslPath"
        }
}




function vsc {
    Write-Host "Starting VS Code setup process..." -ForegroundColor Cyan

    # Step 1: Uninstall existing VS Code
    Write-Host "Uninstalling Visual Studio Code..."
    try {
        winget uninstall -e --id Microsoft.VisualStudioCode --silent --force | Out-Null
        Write-Host "VS Code uninstalled successfully." -ForegroundColor Green
    }
    catch {
        Write-Warning "No existing VS Code installation found or error during uninstallation: $_"
        Write-Host "Continuing with cleanup..." -ForegroundColor Yellow
    }

    # Step 2: Clean up residual directories
    Write-Host "Removing leftover VS Code directories..."
    $pathsToRemove = @(
        "$env:USERPROFILE\.vscode",
        "$env:APPDATA\Code",
        "$env:APPDATA\Code - Insiders",
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code",
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders",
        "$env:USERPROFILE\AppData\Roaming\Code",
        "$env:USERPROFILE\AppData\Local\Code"
    )

    foreach ($path in $pathsToRemove) {
        if (Test-Path $path) {
            try {
                Remove-Item -Recurse -Force $path -ErrorAction Stop
                Write-Host "Removed: $path" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to remove $path : $_"
            }
        }
    }

    # Step 3: Verify and create custom installation directory
    $installPath = "F:\backup\windowsapps\installed\vscode"
    Write-Host "Verifying installation directory: $installPath..."
    if (-not (Test-Path $installPath)) {
        try {
            New-Item -ItemType Directory -Path $installPath -Force | Out-Null
            Write-Host "Created directory: $installPath" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to create directory $installPath : $_"
            return
        }
    }

    # Step 4: Install VS Code to custom directory
    Write-Host "Installing Visual Studio Code to $installPath..."
    try {
        winget install -e --id Microsoft.VisualStudioCode --silent --location $installPath --override '/VERYSILENT /mergetasks=!runcode /DIR="$installPath"' --accept-package-agreements --accept-source-agreements | Out-Null
        Write-Host "VS Code installed successfully to $installPath." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install VS Code: $_"
        Write-Host "Check the installer log at: $env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir\"
        return
    }

    # Step 5: Wait for VS Code CLI to be available
    Write-Host "Waiting for VS Code CLI to be available..."
    $codeCliPath = Join-Path $installPath "bin\code.cmd"
    $timeout = 60
    $elapsed = 0
    while (-not (Test-Path $codeCliPath) -and $elapsed -lt $timeout) {
        Start-Sleep -Seconds 1
        $elapsed++
    }

    if (-not (Test-Path $codeCliPath)) {
        Write-Error "VS Code CLI not found at $codeCliPath after waiting for $timeout seconds. Ensure VS Code is installed correctly."
        return
    }

    # Step 6: Install extensions
    Write-Host "Installing VS Code extensions..."
    $extensions = @(
        "ms-vscode-remote.remote-wsl",
        "ms-python.python",
        "ms-python.vscode-pylance",
        "ms-vscode.cpptools",
        "ms-vscode.cmake-tools",
        "supermaven.supermaven",
        "ms-azuretools.vscode-docker",
        "danielsanmedium.dscodegpt",
        "visualstudioexptteam.vscodeintellicode",
        "codium.codium"
    )

    foreach ($extension in $extensions) {
        try {
            Write-Host "Installing extension: $extension..."
            & $codeCliPath --install-extension $extension --force | Out-Null
            Write-Host "Installed: $extension" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to install extension $extension : $_"
        }
    }

    Write-Host "VS Code setup completed successfully in $installPath!" -ForegroundColor Green
}


function rche {
    Stop-Process -Name "cheatengine-x86_64" -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath 'F:\backup\windowsapps\installed\Cheat Engine 7.5\Cheat Engine.exe'
}


function superf4 {
    #--- Define the path and working directory for SuperF4 ---
    $exePath = "F:\backup\windowsapps\installed\SuperF4\SuperF4.exe"
    $exeWD = "F:\backup\windowsapps\installed\SuperF4"

    #--- Create Logon Trigger ---
    $trigger = New-ScheduledTaskTrigger -AtLogOn

    #--- Create Principal with current user, interactive logon, highest privileges ---
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest

    #--- Settings: No time limit, allow on battery, run when available ---
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -RunOnlyIfNetworkAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)

    #--- Action: Launch SuperF4 hidden, minimized ---
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Process -FilePath '$exePath' -WorkingDirectory '$exeWD' -WindowStyle Minimized`"" -WorkingDirectory $exeWD

    #--- Register the task ---
    Register-ScheduledTask -TaskName "Start_SuperF4" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force

    #--- Run the app immediately ---
    Start-Process -FilePath $exePath -WorkingDirectory $exeWD -WindowStyle Minimized

    Write-Output "? SuperF4 has been added to startup and launched immediately."
}


function clean {
    sizes; adw; & "F:\study\shells\powershell\scripts\RegistryCleaner\a.ps1"; & "C:\users\misha\desktop\cleanup\CCleaner.lnk" -ArgumentList "/AUTO"; & "C:\users\misha\desktop\cleanup\CleanMem - Shortcut.lnk" -ArgumentList "/auto"; & "C:\users\misha\desktop\cleanup\KerishDoctor.exe.lnk" -ArgumentList "/auto"; Start-Process "C:\users\misha\desktop\cleanup\Kerish Doctor 2022.lnk" -ArgumentList "/auto"; & "C:\users\misha\desktop\cleanup\Patch My PC Home Updater.lnk" -ArgumentList "/silent"; & "C:\users\misha\desktop\cleanup\Revo Registry Cleaner.exe - Shortcut.lnk" -ArgumentList "/silent"; & "C:\users\misha\desktop\cleanup\bleachbit.exe - Shortcut.lnk" -ArgumentList "--clean system.*"
    Write-Host "Starting deep system cleanup..." -ForegroundColor Cyan
    ws 'rmp'
    cctemp
    Remove-Item -Path $env:TEMP\*, "$env:WINDIR\Temp\*", "$env:WINDIR\Prefetch\*", "C:\Users\*\AppData\Local\Temp\*" -Force -Recurse -ErrorAction SilentlyContinue
    cleanmgr /sageset:1
    cleanmgr /sagerun:1
    cleanmgr /lowdisk
    PowerShell -Command "Clear-RecycleBin -Force"

    Repair-WindowsImage -Online -ScanHealth
    Repair-WindowsImage -Online -RestoreHealth
    sfc /scannow
    DISM.exe /Online /Cleanup-Image /CheckHealth
    DISM.exe /Online /Cleanup-Image /RestoreHealth
    dism /online /cleanup-image /startcomponentcleanup
    dism /online /Cleanup-Image /AnalyzeComponentStore
    dism /online /Cleanup-Image /StartComponentCleanup /ResetBase

    netsh int ip reset
    ipconfig /release
    ipconfig /renew
    netsh winsock reset
    ipconfig /flushdns

    net start wuauserv
    Install-Module -Name PSWindowsUpdate -Force -AllowClobber -Scope CurrentUser
    Get-WindowsUpdate -Install -AcceptAll -Verbose
    Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Force -Recurse

    defrag C: /U /V
    defrag /c /o
    Optimize-Volume -DriveLetter C -ReTrim -Confirm:$false -Verbose
    fsutil behavior set memoryusage 2
    compact.exe /CompactOS:always
    echo Y | chkdsk /f /r
    vssadmin delete shadows /for=C: /all /quiet
    vssadmin delete shadows /for=C: /oldest
    schtasks /Run /TN "\Microsoft\Windows\DiskCleanup\SilentCleanup"

    wevtutil cl Application
    wevtutil cl Security
    wevtutil cl System
    wevtutil cl Setup
    wevtutil cl ForwardedEvents

    del /q/f/s "C:\Windows\Logs\CBS\*"
    del /q/f/s "C:\Windows\Logs\DISM\*"
    del /q/f/s "C:\Windows\Logs\WindowsUpdate\*"
    del /q/f/s "C:\Windows\Prefetch\*"
    del /f /s /q "$env:LocalAppData\Microsoft\Windows\Explorer\thumbcache_*"
    del /q/f/s "C:\ProgramData\Microsoft\Windows\WER\*"
    del /q/f/s "$env:USERPROFILE\AppData\Local\Microsoft\Windows\Temporary Internet Files\*"
    del /q/f/s "C:\Windows\Logs\WMI\*.log"
    del /q/f/s "C:\Windows\SoftwareDistribution\DeliveryOptimization\*"
    del /q/f/s "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\Cache\*"
    del /q/f/s "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\Downloads\*"
    del /q/f/s "C:\ProgramData\Microsoft\Windows Defender\Scans\History\*"
    del /q/f/s "$env:USERPROFILE\AppData\Local\Microsoft\OneDrive\logs\*"
    del /q/f/s "$env:USERPROFILE\AppData\Local\Microsoft\Office\16.0\OfficeFileCache\*"
    del /q/f/s "C:\ProgramData\Microsoft\Windows\WER\ReportQueue\*"

    Get-AppxPackage -allusers Microsoft.WindowsStore | ForEach-Object {
        Add-AppxPackage -register "$($_.InstallLocation)\appxmanifest.xml" -DisableDevelopmentMode
    }

    Remove-Item -Path "C:\Windows\Installer\$PatchCache$\*" -Force -Recurse -ErrorAction SilentlyContinue
    forfiles /p "C:\Windows\Temp" /s /m *.* /d -7 /c "cmd /c del @path"

    netsh int tcp set global autotuninglevel=normal
    netsh int tcp set global autotuninglevel=highlyrestricted
    netsh int tcp set global dca=enabled
    netsh int tcp set global ecncapability=enabled

    # Additional performance boost commands
    bcdedit /set useplatformclock true; bcdedit /set disabledynamictick yes; bcdedit /set useplatformtick yes; powercfg -h off; powercfg -setactive SCHEME_MIN; powercfg /change monitor-timeout-ac 0; powercfg /change standby-timeout-ac 0; powercfg /change hibernate-timeout-ac 0; powercfg -attributes SUB_PROCESSOR PROCTHROTTLEMAX -ATTRIB_HIDE; powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100; powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100; sc config SysMain start= disabled; sc stop SysMain; sc config DiagTrack start= disabled; sc stop DiagTrack; Disable-MMAgent -ApplicationPreLaunch; Disable-MMAgent -PageCombining; Disable-MMAgent -MemoryCompression; Disable-MMAgent -OperationAPI; Disable-MMAgent -ApplicationPreLaunch; reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v ClearPageFileAtShutdown /t REG_DWORD /d 1 /f; reg add "HKCU\Control Panel\Mouse" /v MouseHoverTime /t REG_SZ /d 10 /f; reg add "HKCU\Control Panel\Desktop" /v HungAppTimeout /t REG_SZ /d 1000 /f; reg add "HKCU\Control Panel\Desktop" /v WaitToKillAppTimeout /t REG_SZ /d 2000 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Control" /v WaitToKillServiceTimeout /t REG_SZ /d 2000 /f; reg add "HKCU\Control Panel\Desktop" /v AutoEndTasks /t REG_SZ /d 1 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsDisable8dot3NameCreation /t REG_DWORD /d 1 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsMemoryUsage /t REG_DWORD /d 2 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnableSuperfetch /t REG_DWORD /d 0 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnablePrefetcher /t REG_DWORD /d 0 /f; reg add "HKLM\SOFTWARE\Microsoft\Dfrg\BootOptimizeFunction" /v Enable /t REG_SZ /d N /f; reg add "HKLM\SYSTEM\CurrentControlSet\Services\Ndu" /v Start /t REG_DWORD /d 4 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v Tcp1323Opts /t REG_DWORD /d 1 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v SackOpts /t REG_DWORD /d 1 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v DefaultTTL /t REG_DWORD /d 64 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v EnablePMTUDiscovery /t REG_DWORD /d 1 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v EnableTCPA /t REG_DWORD /d 0 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v EnableRSS /t REG_DWORD /d 1 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v EnableTCPChimney /t REG_DWORD /d 0 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v MTU /t REG_DWORD /d 1500 /f; reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v EnableDCA /t REG_DWORD /d 1 /f; takeown /f %TEMP% /r /d y; echo PERFORMANCE BOOST COMPLETE

    Write-Host "System cleanup completed!" -ForegroundColor Green
}



function ytp {
    param (
        [string]$url
    )
    yt-dlp `
        --force-ipv4 `
        --sleep-interval 3 `
        --max-sleep-interval 6 `
        --retries 10 `
        -f "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]" `
        -o "%(playlist_index)03d - %(title).120s.%(ext)s" `
        $url
}


function sg {
      Start-Process "F:\backup\windowsapps\installed\ludusavi\ludusavi.exe"
      Start-Process "F:\backup\windowsapps\installed\gameSaveManager\gs_mngr_3.exe"
      start-process "F:\backup\windowsapps\installed\savestate\SaveState.exe"
      Start-Sleep -Seconds 120; ws 'gg && sprofile && savegames'
  }


function ssg {
    Start-Process "F:\backup\windowsapps\installed\gameSaveManager\gs_mngr_3.exe"
Start-Sleep -Seconds 120; ws 'gg && sprofile && savegames'
}


function FixWinStore {
    Write-Host "`n=== Repairing Microsoft Store ===`n" -ForegroundColor Cyan
    try {
        Stop-Service -Name 'BITS','wuauserv' -Force -ErrorAction Stop
        Get-AppxPackage -AllUsers -Name Microsoft.WindowsStore | Remove-AppxPackage -ErrorAction SilentlyContinue
        Start-Process 'wsreset.exe' -Wait             # no /silent switch; wait until it closes
        Get-ChildItem 'C:\Program Files\WindowsApps' -Filter '*WindowsStore*' -Directory |
            ForEach-Object {
                Add-AppxPackage -DisableDevelopmentMode -Register "$($_.FullName)\AppXManifest.xml" -Verbose
            }
    }
    finally {
        Start-Service -Name 'BITS','wuauserv'
    }

    Write-Host "`n? Microsoft Store reinstalled - reboot Windows to finish.`n" -ForegroundColor Green
}


function disadmin {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 0
}


function win {
    param(
        [int]$TimeoutSeconds = 1200
    )

    $scriptCandidates = @(
        "F:\study\Dev_Toolchain\dev-toolchain\programming\python\apps\windowsoptimize\g.py",
        "F:\study\Dev_Toolchain\programming\python\apps\windowsoptimize\b\g.py",
        "F:\study\programming\python\apps\windowsoptimize\b\g.py",
        "F:\study\Learning\01\01\Dev_Toolchain\programming\python\apps\windowsoptimize\g.py"
    )

    $scriptPath = $scriptCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $scriptPath) {
        throw "win: windows optimizer script not found in expected locations."
    }

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        $pythonCmd = Get-Command py -ErrorAction SilentlyContinue
    }
    if (-not $pythonCmd) {
        throw "win: Python launcher not found (python/py)."
    }

    $proc = Start-Process -FilePath $pythonCmd.Source -ArgumentList @($scriptPath) -PassThru -WindowStyle Hidden
    $timeoutMs = [Math]::Max($TimeoutSeconds, 1) * 1000

    if (-not $proc.WaitForExit($timeoutMs)) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw "win: optimizer timed out after $TimeoutSeconds seconds and was terminated."
    }

    if ($proc.ExitCode -ne 0) {
        throw "win: optimizer failed with exit code $($proc.ExitCode)."
    }
}



function ytp2 {
    param (
        [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
        [string[]]$Urls
    )

    cd F:\yt
    cpsec
    cd F:\yt

    $urlArgs = $Urls -join ' '
    python3 F:\study\programming\python\apps\youtube\DownloadVideo\DownloadAndUpload\a.py $urlArgs
}




function gcl {
    param(
        [Parameter(Mandatory = $true, ValueFromRemainingArguments)]
        [string[]] $Url
    )

    Start-Process -FilePath "F:\backup\windowsapps\installed\Chrome\Application\chrome.exe" `
                  -ArgumentList  $Url
}


function ytapi {
    gcl "https://console.cloud.google.com/apis/credentials?inv=1&invt=AbxMGA&project=autosubs-454121"
}




function up {
    ccpatch; Start-Process cleanmgr.exe; Start-Process "ms-settings:storagesense"; Start-Process "$env:SystemRoot\System32\dfrgui.exe"; cd C:\Users\micha\desktop\cleanup; $shortcuts = Get-ChildItem -Filter *.lnk; $shortcuts | ForEach-Object { Start-Process $_.FullName }; Write-Host "Total processes started: $($shortcuts.Count)";  irm "https://christitus.com/win" | iex
}



function cpsec {
     ws 'down && cpsec'
}



function ytp3 {
    cd F:\yt; python3 a.py
}



function ccpatch {
    Start-Process -FilePath "F:\backup\windowsapps\install\Cracked\CCleaner Professional Plus 6.34 Multilingual\CCleaner_Patch22.exe"
}



function ext {
     py F:\study\programming\python\apps\extracting\unzipAllInDownloads\c.py
}


function ext2 {
     py F:\study\programming\python\apps\extracting\unzipAllInDownloads\a.py
}




function wmpatch {
     Start-Process -FilePath "F:\backup\windowsapps\install\wemod\wemodPatcher\WeModPatcher.bat"
}

function walls {
    # ----- CONSTANTS ---------------------------------------------------------
    $taskName   = 'AutoWallpaperGames'
    $workingDir = 'F:\study\programming\python\apps\wallpapers\changeWallPaperAutomatically\gamesonly'
    $scriptArg  = 'a.py'

    # Locate python3.exe explicitly
    try {
        $pythonExe = (Get-Command python3.exe -ErrorAction Stop).Source
    } catch {
        Write-Error "?  python3.exe not found in PATH. Add it or install Python 3, then re-run."
        return
    }

    # Remove any stale task
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    # Build the new Scheduled Task
    $action   = New-ScheduledTaskAction  -Execute $pythonExe `
                                         -Argument $scriptArg `
                                         -WorkingDirectory $workingDir
    $trigger  = New-ScheduledTaskTrigger -AtLogOn          # current user
    $settings = New-ScheduledTaskSettingsSet `
                   -AllowStartIfOnBatteries `
                   -DontStopOnIdleEnd `
                   -Compatibility Win10   # works fine on Windows 11

    Register-ScheduledTask -TaskName  $taskName `
                           -Action    $action `
                           -Trigger   $trigger `
                           -Settings  $settings `
                           -Description 'Changes wallpaper (games only) at every user log-on.' `
                           -RunLevel  LeastPrivilege | Out-Null

    Write-Host "?  '$taskName' scheduled with $pythonExe. Sign out/in or reboot to test." -ForegroundColor Green
}

function wallst {
    $taskName = 'AutoWallpaperGames'
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "?  '$taskName' disabled and removed." -ForegroundColor Yellow
    } else {
        Write-Host "??   No scheduled task named '$taskName' found." -ForegroundColor Cyan
    }
}


function sizes {
    ws sizes
}

 


function sus {
    param([string]$proc)
    & "F:\backup\windowsapps\installed\PSTools\pssuspend.exe" $proc
}

function res {
    param([string]$proc)
    & "F:\backup\windowsapps\installed\PSTools\pssuspend.exe" -r $proc
}

function sused {
    & "F:\backup\windowsapps\installed\PSTools\pssuspend.exe" eldenring.exe
}

function resed {
    & "F:\backup\windowsapps\installed\PSTools\pssuspend.exe" -r eldenring.exe
}


function comps {
    Install-Module -Name PS2EXE -Scope CurrentUser -Force; Import-Module PS2EXE;  Invoke-ps2exe -InputFile a.ps1 -OutputFile a.exe  
}

function rmd {
    Add-Type -AssemblyName System.Windows.Forms
    $proc = Start-Process "F:\study\automation\bots\MacroCreator\rmod\rmod.exe" -PassThru
    Start-Sleep -Seconds 2
    [System.Windows.Forms.SendKeys]::SendWait("1")
}



function setup {
    ext; cd F:\study\shells\powershell\scripts\RunAllInstallersInDownloadsFolder; ./a.ps1
}



function close {
    closeahk; cd F:\study\shells\powershell\scripts\CloseApps; ./a.ps1;  & "F:\study\Platforms\windows\autohotkey\SuspendAndResumeApp\a.ahk"; desk
}





function pp {
    Start-Process "F:\study\Platforms\windows\autohotkey\profile.ahk"
    Start-Sleep -Milliseconds 500
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait("1")
}




function ddu {
    & "F:\study\Platforms\windows\autohotkey\DDUNormalModWithoutRestart.ahk"
    Start-Sleep -Milliseconds 500
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait("1")
}





function up2 {
    Start-Process "F:\backup\windowsapps\installed\Driver Booster\DriverBooster.lnk"
    Start-Process "C:\Users\micha\Desktop\cleanup\Red Button.lnk"
    Start-Process "C:\Users\micha\Desktop\cleanup\KVRT.exe.lnk"
}


function liners {
    Get-Process | Where-Object { $_.Path -like "*.ahk" } | ForEach-Object { Stop-Process -Id $_.Id -Force }; Start-Process "F:\study\Platforms\windows\autohotkey\Liners3n4.ahk"; Start-Process "https://chatgpt.com/g/g-p-6760cb5963188191af3ea15a32ef4a22-continue/project"; wsl -d Ubuntu --cd ~
}



function closeahk {
    Get-Process | ForEach-Object {
        try {
            if ($_.Name -like "*autohotkey*" -or ($_.Path -and $_.Path -like "*.ahk")) {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    # Extra safety net for known names
    Stop-Process -Name "AutoHotkey" -Force -ErrorAction SilentlyContinue
}





function stopstart {
    <#
    .SYNOPSIS
        Removes applications from Windows startup that were added by the onstart function.
    
    .DESCRIPTION
        This function removes registry entries for specified applications from Windows startup.
        If no parameters are provided, it lists all current startup items and allows selection.
    
    .PARAMETER AppNames
        Optional. Names or paths of applications to remove from startup.
        If providing a full path, the function will extract just the application name.
        If no names are provided, the function will list all startup items for selection.
    
    .PARAMETER All
        Switch to remove all entries from the startup registry.
    
    .EXAMPLE
        stopstart "GHelper" "AnotherApp"
        
    .EXAMPLE
        stopstart "F:\backup\windowsapps\installed\ghelper\GHelper.exe"
        
    .EXAMPLE
        stopstart -All
        
    .EXAMPLE
        stopstart
        # Lists all startup items and prompts for selection
    #>
    [CmdletBinding(DefaultParameterSetName='Names')]
    param (
        [Parameter(ParameterSetName='Names', Position=0, ValueFromRemainingArguments=$true)]
        [string[]]$AppNames,
        
        [Parameter(ParameterSetName='All')]
        [switch]$All
    )
    
    # Registry path for startup programs
    $registryPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    
    # Function to get clean app name from a full path or app name
    function Get-CleanAppName {
        param ([string]$AppNameOrPath)
        
        if ($AppNameOrPath -like "*.exe*" -or $AppNameOrPath -match "\\") {
            # It's likely a path, extract filename without extension
            return [System.IO.Path]::GetFileNameWithoutExtension($AppNameOrPath)
        }
        else {
            # It's likely just a name
            return $AppNameOrPath
        }
    }
    
    # Get current startup items
    $startupItems = Get-ItemProperty -Path $registryPath
    if (-not $startupItems) {
        Write-Host "No startup items found." -ForegroundColor Yellow
        return
    }
    
    $startupNames = $startupItems.PSObject.Properties | 
                    Where-Object { $_.Name -ne "PSPath" -and $_.Name -ne "PSParentPath" -and 
                                  $_.Name -ne "PSChildName" -and $_.Name -ne "PSDrive" -and 
                                  $_.Name -ne "PSProvider" } |
                    Select-Object -ExpandProperty Name
    
    # If no parameters provided, show interactive selection
    if (-not $AppNames -and -not $All) {
        if ($startupNames.Count -eq 0) {
            Write-Host "No startup items found." -ForegroundColor Yellow
            return
        }
        
        Write-Host "Current startup items:" -ForegroundColor Cyan
        for ($i=0; $i -lt $startupNames.Count; $i++) {
            $name = $startupNames[$i]
            $value = $startupItems.$name
            Write-Host "[$i] $name - $value" -ForegroundColor White
        }
        
        Write-Host "Enter the numbers of items to remove (comma separated), 'all' for all items, or 'q' to quit:" -ForegroundColor Cyan
        $selection = Read-Host
        
        if ($selection -eq "q") {
            return
        }
        elseif ($selection -eq "all") {
            $All = $true
        }
        else {
            $selectedIndices = $selection -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
            $AppNames = $selectedIndices | ForEach-Object { $startupNames[$_] }
        }
    }
    
    # Process based on parameter set
    if ($All) {
        # Remove all entries
        foreach ($name in $startupNames) {
            try {
                Remove-ItemProperty -Path $registryPath -Name $name -ErrorAction Stop
                Write-Host "? Removed '$name' from startup." -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to remove '$name' from startup: $_"
            }
        }
    }
    else {
        # Process each specified app
        foreach ($appInput in $AppNames) {
            $appName = Get-CleanAppName -AppNameOrPath $appInput
            
            # Check if this app exists in startup
            if ($startupNames -contains $appName) {
                try {
                    Remove-ItemProperty -Path $registryPath -Name $appName -ErrorAction Stop
                    Write-Host "? Removed '$appName' from startup." -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to remove '$appName' from startup: $_"
                }
            }
            else {
                Write-Warning "App '$appName' not found in startup items."
            }
        }
    }
}




function susp {
    & "F:\study\Platforms\windows\autohotkey\SuspendAndResumeApp\a.ahk"
}


function ps2ahk {
    param([string]$ps1Path)
    
    if (-not (Test-Path $ps1Path)) {
        Write-Host "? PS1 file does not exist: $ps1Path" -ForegroundColor Red
        return
    }

    $ahkPath = [System.IO.Path]::ChangeExtension($ps1Path, ".ahk")
    $escapedPS1 = $ps1Path -replace '\\', '\\\\'
    $content = "Run, powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$escapedPS1`""
    
    $content | Out-File -FilePath $ahkPath -Encoding ASCII
    Write-Host "? AHK created: $ahkPath" -ForegroundColor Green
}



function ahk2ps {
    param([string]$ahkPath)

    if (-not (Test-Path $ahkPath)) {
        Write-Host "? AHK file does not exist: $ahkPath" -ForegroundColor Red
        return
    }

    $ps1Path = [System.IO.Path]::ChangeExtension($ahkPath, ".ps1")
    $ahkContent = Get-Content $ahkPath | Where-Object { $_ -match '^Run,' }

    if (-not $ahkContent) {
        Write-Host "? No 'Run,' line found in the AHK file." -ForegroundColor Red
        return
    }

    $commandLine = $ahkContent -replace '^Run,\s*', ''
    $commandLine = $commandLine -replace '`"', '"'  # Unescape quotes if present

    $ps1Content = "Start-Process $commandLine"
    $ps1Content | Out-File -FilePath $ps1Path -Encoding UTF8

    Write-Host "? PS1 created: $ps1Path" -ForegroundColor Green
}



function getdotnet {
    Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart
    dism /online /enable-feature /featurename:NetFx3 /all /norestart

    Invoke-WebRequest https://dot.net/v1/dotnet-install.ps1 -OutFile dotnet-install.ps1

    foreach ($v in 1..5) {
        try {
            ./dotnet-install.ps1 -Version "$v.0.0" -InstallDir "C:\dotnet\$v" -Architecture x64 -NoPath
        } catch {
            Write-Host "? Failed to install .NET SDK $v.0.0"
        }
    }

    $packages = @(
        "Microsoft.NetFramework.4.8.SDK",
        "Microsoft.NetFramework.4.8.TargetingPack",
        "Microsoft.DotNet.SDK.6",
        "Microsoft.DotNet.SDK.7",
        "Microsoft.DotNet.SDK.8",
        "Microsoft.DotNet.Runtime.6",
        "Microsoft.DotNet.Runtime.7",
        "Microsoft.DotNet.Runtime.8",
        "Microsoft.WindowsDesktop.Runtime.6",
        "Microsoft.WindowsDesktop.Runtime.7",
        "Microsoft.WindowsDesktop.Runtime.8",
        "Microsoft.AspNetCore.6",
        "Microsoft.AspNetCore.7",
        "Microsoft.AspNetCore.8",
        "Microsoft.VisualStudio.2022.BuildTools",
        "Microsoft.VCRedist.2015+.x64",
        "Microsoft.VCRedist.2013.x64",
        "Microsoft.VCRedist.2012.x64",
        "Microsoft.VCRedist.2010.x64",
        "Microsoft.VCRedist.2008.x64",
        "Microsoft.VCRedist.2005.x64",
        "Microsoft.DirectX",
        "OpenAL.OpenAL",
        "Microsoft.Xna.Framework.4.0",
        "physx",
        "VulkanSDK"
    )

    foreach ($pkg in $packages) {
        try {
            winget install $pkg --accept-package-agreements --accept-source-agreements
        } catch {
            Write-Host "? Failed to install $pkg"
        }
    }

    dotnet --list-sdks
    dotnet --list-runtimes
}



function nvc {
    & "F:\backup\windowsapps\installed\NVCleanstall\NVCleanstall.exe"
}


function nnvc {
    Start-Process "F:\study\Platforms\windows\autohotkey\NVCeanInstall.ahk"
    Start-Sleep -Milliseconds 700
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait("1")
}



function adw {
    & "F:\backup\windowsapps\installed\adw\adwcleaner.exe" /eula /clean /noreboot; for ($i=0; $i -lt 10; $i++) { Start-Sleep -Seconds 2; $log = Get-ChildItem -Path "$env:HOMEDRIVE\AdwCleaner\Logs" -Filter "*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($log -and (Test-Path $log.FullName)) { Get-Content $log.FullName; break } }
}








function installall {
    [CmdletBinding()]
    param (
        [string]$SourceDirectory = "C:\users\misha\downloads\a",
        [string]$GameDestination = "F:\games",
        [int]$MaxConcurrentInstalls = 5
    )

    # Create games destination if it doesn't exist
    if (-not (Test-Path -Path $GameDestination)) {
        New-Item -Path $GameDestination -ItemType Directory -Force | Out-Null
        Write-Host "Created games destination directory: $GameDestination" -ForegroundColor Green
    }

    # Find all setup files recursively (common installer extensions)
    $setupFiles = Get-ChildItem -Path $SourceDirectory -Recurse -Include "*.exe", "*.msi" | 
                 Where-Object { $_.Name -match "setup|install|launcher" -or $_.Name -match "^(setup|install)\.exe$" }

    if ($setupFiles.Count -eq 0) {
        Write-Host "No setup files found in $SourceDirectory" -ForegroundColor Yellow
        return
    }

    Write-Host "Found $($setupFiles.Count) setup files to install" -ForegroundColor Cyan

    # Initialize variables to track running installations
    $runningJobs = @{}
    $completedFiles = 0

    # Process all setup files
    foreach ($setupFile in $setupFiles) {
        # Wait if we've reached max concurrent installs
        while ($runningJobs.Count -ge $MaxConcurrentInstalls) {
            $completedJobs = $runningJobs.Keys | Where-Object { $runningJobs[$_].State -ne 'Running' }
            
            if ($completedJobs.Count -gt 0) {
                foreach ($jobId in $completedJobs) {
                    $job = $runningJobs[$jobId]
                    $setupName = $job.Name
                    
                    # Process completed job
                    Write-Host "Installation completed: $setupName" -ForegroundColor Green
                    $completedFiles++
                    
                    # Clean up job
                    Remove-Job -Job $job -Force
                    $runningJobs.Remove($jobId)
                }
            }
            else {
                # Wait a moment before checking again
                Start-Sleep -Seconds 2
            }
        }

        # Extract game name from setup file
        $gameName = [System.IO.Path]::GetFileNameWithoutExtension($setupFile.Name) -replace "(setup|install|launcher)", "" -replace "[-_\.]", " "
        $gameName = $gameName.Trim()
        
        # If name is empty or too generic, use parent folder name
        if ([string]::IsNullOrWhiteSpace($gameName) -or $gameName.Length -lt 3) {
            $gameName = $setupFile.Directory.Name
        }
        
        # Create destination folder for this game
        $gameFolder = Join-Path -Path $GameDestination -ChildPath $gameName
        if (-not (Test-Path -Path $gameFolder)) {
            New-Item -Path $gameFolder -ItemType Directory -Force | Out-Null
        }

        # Start the installation as a background job
        Write-Host "Starting installation for: $gameName" -ForegroundColor Cyan
        
        $scriptBlock = {
            param ($setupPath, $destFolder)
            
            # Determine if exe or msi
            $extension = [System.IO.Path]::GetExtension($setupPath).ToLower()
            
            if ($extension -eq '.msi') {
                # For MSI files, use msiexec with silent options and target directory
                $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$setupPath`"", "/qb", "TARGETDIR=`"$destFolder`"", "INSTALLDIR=`"$destFolder`"", "/norestart" -PassThru -Wait
            }
            else {
                # For EXE files, use AutoIt to handle dialogs and uncheck boxes
                $autoItScript = @"
#include <AutoItConstants.au3>
#include <MsgBoxConstants.au3>

; Start the installer
Run("$setupPath")

; Wait for the installer window
WinWait("Setup", "", 60)

; Keep clicking Next and unchecking boxes
While 1
    ; Look for checkboxes and uncheck them
    Local $hWnd = WinGetHandle("[ACTIVE]")
    Local $checkboxes = ControlListView($hWnd, "", "Button")
    If Not @error Then
        For $i = 1 To $checkboxes[0][0]
            If BitAND(ControlCommand($hWnd, "", $checkboxes[$i][1], "IsChecked", ""), 1) Then
                ControlCommand($hWnd, "", $checkboxes[$i][1], "Check", 0)
            EndIf
        Next
    EndIf

    ; Try to input installation path if relevant fields exist
    Local $editControls = ControlListView($hWnd, "", "Edit")
    If Not @error Then
        For $i = 1 To $editControls[0][0]
            Local $controlText = ControlGetText($hWnd, "", $editControls[$i][1])
            If StringInStr($controlText, ":\") Or StringInStr($controlText, "Program Files") Then
                ControlSetText($hWnd, "", $editControls[$i][1], "$destFolder")
            EndIf
        Next
    EndIf

    ; Click Next/Install/Finish buttons
    If ControlClick($hWnd, "", "Button[contains(@text, 'Next')]") Then
        Sleep(500)
    ElseIf ControlClick($hWnd, "", "Button[contains(@text, 'Install')]") Then
        Sleep(500)
    ElseIf ControlClick($hWnd, "", "Button[contains(@text, 'Finish')]") Then
        ExitLoop
    ElseIf WinExists("Installation Complete") Then
        ControlClick("Installation Complete", "", "Button[contains(@text, 'Finish')]")
        ExitLoop
    Else
        ; If no buttons were found, wait a bit and try again
        Sleep(1000)
        
        ; Check if installation is still running
        If Not WinExists($hWnd) Then
            ExitLoop
        EndIf
    EndIf
WEnd
"@

                # Note: In a real environment, you would need AutoIt installed
                # This is a simplified example - in practice, you might need to:
                # 1. Save the AutoIt script to a temporary file
                # 2. Run it with AutoIt executable
                # For now, we'll fall back to a simple silent install approach:
                
                # Common silent install parameters for various installers
                $silentArgs = "/S /SILENT /VERYSILENT /quiet /qn /NORESTART /DIR=`"$destFolder`" INSTALLDIR=`"$destFolder`" TARGETDIR=`"$destFolder`""
                $process = Start-Process -FilePath $setupPath -ArgumentList $silentArgs -PassThru -Wait
            }
            
            return $process.ExitCode
        }

        # Start job for this installation
        $jobName = "Install_$gameName"
        $job = Start-Job -Name $jobName -ScriptBlock $scriptBlock -ArgumentList $setupFile.FullName, $gameFolder
        $runningJobs.Add($job.Id, $job)
    }

    # Wait for remaining jobs to complete
    while ($runningJobs.Count -gt 0) {
        $completedJobs = $runningJobs.Keys | Where-Object { $runningJobs[$_].State -ne 'Running' }
        
        if ($completedJobs.Count -gt 0) {
            foreach ($jobId in $completedJobs) {
                $job = $runningJobs[$jobId]
                $setupName = $job.Name
                
                # Process completed job
                Write-Host "Installation completed: $setupName" -ForegroundColor Green
                $completedFiles++
                
                # Clean up job
                Remove-Job -Job $job -Force
                $runningJobs.Remove($jobId)
            }
        }
        else {
            # Wait a moment before checking again
            Start-Sleep -Seconds 2
        }
    }

    Write-Host "All installations completed! Total files processed: $completedFiles" -ForegroundColor Green
}

function runall {
    $exeFiles = Get-ChildItem -Path "F:\games" -Recurse -Filter *.exe -File | Where-Object {
        $_.Name -notmatch '(?i)^unins\d*\.exe$' -and
        $_.Name -notmatch '(?i)^uninstall.*\.exe$' -and
        $_.Name -notmatch '(?i)vc_redist|vcredist|quicksfv|dxwebsetup|crashreportclient|crash'
    }

    foreach ($exe in $exeFiles) {
        try {
            Write-Host "`n[RUNNING] $($exe.FullName)"
            $process = Start-Process -FilePath $exe.FullName -PassThru

            Start-Sleep -Seconds 10

            if (!$process.HasExited) {
                Write-Host "[CLOSING] $($exe.Name)"
                Stop-Process -Id $process.Id -Force
            } else {
                Write-Host "[EXITED EARLY] $($exe.Name)"
            }
        } catch {
            Write-Warning "[ERROR] Failed to handle $($exe.FullName): $_"
        }
    }

    Write-Host "`n[DONE] All filtered executables processed."
}




function onstart {
    <#
    .SYNOPSIS
        Registers one or more applications or scripts to run at Windows startup.

    .DESCRIPTION
        Adds entries to the Windows registry (Current User) for startup execution.
        Special handling for .ahk files using AHK v2 at your specified path.

    .PARAMETER FilePaths
        One or more full file paths to .exe, .bat, or .ahk scripts.

    .EXAMPLE
        onstart "C:\scripts\auto.ahk" "D:\games\modhelper.exe"
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$FilePaths
    )

    $registryPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    $ahkPath = "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe"

    foreach ($path in $FilePaths) {
        if (-not (Test-Path $path)) {
            Write-Warning "? Path not found: $path - Skipping."
            continue
        }

        $ext = [System.IO.Path]::GetExtension($path).ToLower()
        $appName = [System.IO.Path]::GetFileNameWithoutExtension($path)

        switch ($ext) {
            ".ahk" {
                if (-not (Test-Path $ahkPath)) {
                    Write-Warning "?? AHK not found at '$ahkPath' - skipping $path"
                    continue
                }
                $cmd = "`"$ahkPath`" `"$path`""
            }
            default {
                $cmd = "`"$path`""
            }
        }

        try {
            New-ItemProperty -Path $registryPath -Name $appName -Value $cmd -PropertyType String -Force | Out-Null
            Write-Host "? '$appName' added to startup." -ForegroundColor Green
        }
        catch {
            Write-Error "? Failed to add '$appName' to startup: $_"
        }
    }
}





function gchome {
    $chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$prefsPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Preferences"
$prefs = Get-Content -Path $prefsPath -Raw | ConvertFrom-Json
$prefs.homepage = "https://chatgpt.com/"
$prefs.homepage_is_newtabpage = $false
if ($prefs.session -eq $null) { $prefs | Add-Member -Type NoteProperty -Name "session" -Value @{} }
if ($prefs.session.startup_urls -eq $null) { $prefs.session | Add-Member -Type NoteProperty -Name "startup_urls" -Value @() }
$prefs.session.startup_urls = @("https://chatgpt.com/")
$prefs.session.restore_on_startup = 4
$prefs | ConvertTo-Json -Depth 100 | Set-Content -Path $prefsPath
Write-Host "Chrome homepage set to https://chatgpt.com/"
}


function macro {
    & "F:\study\Platforms\windows\autohotkey\MacroCreator.ahk"
}



function nnvidia {
    Start-Process "F:\study\Platforms\windows\autohotkey\nvidiaReinstallDriversAndApp.ahk"; Start-Sleep -Seconds 2; Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait("1")
}



function nnv {
    nnvc; Start-Sleep -Seconds 1400; nnvidia; Start-Sleep -Seconds 60
}


function dboost {
    & "F:\backup\windowsapps\installed\Driver Booster\12.4.0\DriverBooster.exe"
}



function dbo {
     Start-Process "F:\study\Platforms\windows\autohotkey\driverbooster.ahk"; Start-Sleep -Seconds 2; Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait("1")
}


function nnvd {
    ddu; Start-Sleep -Seconds 200; nnv ; dbo
}



function susel {
   & "F:\study\shells\powershell\scripts\suspendElden.ps1"
}


function elden {
    close; superf4; start-process "C:\Users\micha\Desktop\eldenring - Shortcut.lnk"; Start-Sleep -Seconds 10; rmod
}


function elden2 {
    & "F:\study\programming\python\apps\media\games\LaunchGameWithTools\WemodLassosSf4DeskN3SGtools\eldenring\20may2025\EldenRing.ahk"; Start-Sleep -Seconds 2; Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait("1")

}

function elden3 {
      & "F:\study\programming\python\apps\media\games\LaunchGameWithTools\WemodLassosSf4DeskN3SGtools\eldenring\20may2025\elden3.ahk"; Start-Sleep -Seconds 2; Add-Type -AssemblyName System.Windows.Forms;
[System.Windows.Forms.SendKeys]::SendWait("1")
  }



function elden4 {
    &  "F:\study\programming\python\apps\media\games\LaunchGameWithTools\WemodLassosSf4DeskN3SGtools\eldenring\20may2025\4mapWEMOD.ahk"; Start-Sleep -Seconds 2; Add-Type -AssemblyName System.Windows.Forms;
[System.Windows.Forms.SendKeys]::SendWait("1")
}


function elden5 {
    &  "F:\study\programming\python\apps\media\games\LaunchGameWithTools\WemodLassosSf4DeskN3SGtools\eldenring\20may2025\5suspendElden.ahk"; Start-Sleep -Seconds 2; Add-Type -AssemblyName System.Windows.Forms;
[System.Windows.Forms.SendKeys]::SendWait("1")
}


function elel {
    elden2; Start-Sleep -Seconds 65; elden3; Start-Sleep -Seconds 15; elden4; Start-Sleep -Seconds 15; elden5
}


function time {
    param (
        [ScriptBlock]$Command
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $Command
    $sw.Stop()
    Write-Host "Finished in $($sw.Elapsed.TotalSeconds) seconds"
}



function maxpower {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c; powercfg /change monitor-timeout-ac 0; powercfg /change monitor-timeout-dc 0; powercfg /change standby-timeout-ac 0; powercfg /change standby-timeout-dc 0; powercfg /change hibernate-timeout-ac 0; powercfg /change hibernate-timeout-dc 0; powercfg /change processor-state-min 100
}


function minpower {
    powercfg /setactive a1841308-3541-4fab-bc81-f71556f20b4a; powercfg /change monitor-timeout-ac 0; powercfg /change monitor-timeout-dc 0; powercfg /change standby-timeout-ac 0; powercfg /change standby-timeout-dc 0; powercfg /change hibernate-timeout-ac 0; powercfg /change hibernate-timeout-dc 0; powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 60; powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 60; powercfg /setactive SCHEME_CURRENT
}


function killt {
    Get-Process | Where-Object { $_.MainWindowTitle -match 'Windows Terminal|PowerShell|Command Prompt|cmd|wsl' } | ForEach-Object { Stop-Process -Id $_.Id -Force }
}





function ffhome {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [string]$Homepage = "https://filecr.com/en/",
        
        [Parameter(Mandatory=$false)]
        [string]$FirefoxPath = "F:\backup\windowsapps\installed\Mozilla Firefox\firefox.exe"
    )

    # Get all Firefox profiles
    $profilesPath = "$env:APPDATA\Mozilla\Firefox\Profiles"
    $profiles = Get-ChildItem -Path $profilesPath -Directory -ErrorAction SilentlyContinue | 
                Where-Object { $_.Name -like "*.default*" -or $_.Name -like "*.default-release*" }
    
    if (-not $profiles) {
        Write-Host "Firefox profiles not found. Make sure Firefox has been run at least once." -ForegroundColor Red
        return
    }
    
    $successCount = 0
    
    foreach ($profile in $profiles) {
        $prefsPath = Join-Path -Path $profile.FullName -ChildPath "prefs.js"
        
        if (Test-Path -Path $prefsPath) {
            try {
                # Read the content of prefs.js
                $prefsContent = Get-Content -Path $prefsPath -Raw -ErrorAction Stop
                
                # Remove any existing homepage preference
                $newContent = $prefsContent -replace 'user_pref\("browser\.startup\.homepage",.*?\);(\r\n|\r|\n)?', ''
                
                # Add the new homepage preference at the end
                $newContent = $newContent.TrimEnd() + "`nuser_pref(`"browser.startup.homepage`", `"$Homepage`");"
                
                # Write the updated content back to prefs.js
                Set-Content -Path $prefsPath -Value $newContent -ErrorAction Stop
                
                Write-Host "Homepage set to $Homepage in profile: $($profile.FullName)" -ForegroundColor Green
                $successCount++
            }
            catch {
                Write-Host "Error updating profile $($profile.FullName): $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "prefs.js not found in profile: $($profile.FullName)" -ForegroundColor Yellow
        }
    }
    
    if ($successCount -gt 0) {
        Write-Host "Successfully updated $successCount Firefox profile(s)." -ForegroundColor Green
    }
    else {
        Write-Host "No Firefox profiles were successfully updated." -ForegroundColor Red
    }
    
    # Check if Firefox is running
    $firefoxProcess = Get-Process -Name firefox -ErrorAction SilentlyContinue
    if ($firefoxProcess) {
        Write-Host "Note: You may need to restart Firefox for changes to take effect." -ForegroundColor Yellow
    }
}

# Create an alias for backward compatibility
# Set-Alias -Name ffhome -Value Set-FirefoxHomepage

# Example usage:
# ffhome
# Or with custom homepage:
# ffhome -Homepage "https://example.com"



function Copy {
    param([Parameter(ValueFromRemainingArguments=$true)] $Command)

    $output = Invoke-Expression ($Command -join ' ')
    $output | Set-Clipboard
    Write-Host "Output of '$Command' copied to clipboard."
}



function Copy {
    param([Parameter(ValueFromRemainingArguments=$true)] $Command)

    $output = Invoke-Expression ($Command -join ' ')
    $output | Set-Clipboard
    Write-Host "Output of '$Command' copied to clipboard."
}

function Copy {
    param (
        [string[]]$InputObject
    )

    $InputObject -join "`n" | Set-Clipboard
    Write-Host "Copied to clipboard."
}

## --- put the two functions in your profile -------------------------------

function CopyClip {
    <#
        .SYNOPSIS
            Send any text to the Windows clipboard.
        .PARAMETER Text
            String (or array of strings) to copy.
    #>
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Text
    )

    $Text -join "`n" | Set-Clipboard
    Write-Host "? Copied to clipboard."
}

function cco {
    <#
        .SYNOPSIS
            Copy the contents of a file (like a Unix `cat` pipe) to the clipboard.
        .EXAMPLE
            cco "F:\path\to\script.ahk"
    #>
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        try {
            Get-Content -LiteralPath $Path -Raw -ErrorAction Stop |
                CopyClip
        }
        catch {
            Write-Warning "? Failed to read file: $($_.Exception.Message)"
        }
    }
    else {
        Write-Warning "? File not found: $Path"
    }
}



function rmwinold {
    takeown /f "C:\Windows.old" /r /d y; icacls "C:\Windows.old" /grant administrators:F /t; Remove-Item -Path "C:\Windows.old" -Recurse -Force; rd /s /q "C:\Windows.old";  cleanmgr /sageset:65535; DISM /online /Cleanup-Image /StartComponentCleanup /ResetBase
}



function vsc {
    # Hard-coded winget path
    $wingetCmd = "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1.25.389.0_x64__8wekyb3d8bbwe\winget.exe"
    if (-not (Test-Path $wingetCmd -PathType Leaf)) {
        Write-Error "winget.exe not found at '$wingetCmd'."
        return
    }

    # 1) If installed, uninstall; otherwise skip
    Write-Host "`n=== Checking for existing VS Code install ===" -ForegroundColor Cyan
    $listOutput = & $wingetCmd list --id Microsoft.VisualStudioCode --disable-interactivity 2>$null
    if ($listOutput -match "Microsoft\.VisualStudioCode") {
        Write-Host "VS Code is installed ? uninstalling..." -ForegroundColor Cyan
        & $wingetCmd uninstall --exact --id Microsoft.VisualStudioCode --silent --disable-interactivity
    } else {
        Write-Host "VS Code not found ? skipping uninstall." -ForegroundColor Yellow
    }

    # 2) Remove leftovers
    Write-Host "`n=== Removing leftover VS Code directories ===" -ForegroundColor Cyan
    $paths = @(
        "$env:USERPROFILE\.vscode",
        "$env:APPDATA\Code",
        "$env:APPDATA\Code - Insiders",
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code",
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders",
        "$env:USERPROFILE\AppData\Roaming\Code",
        "$env:USERPROFILE\AppData\Local\Code"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            try {
                Remove-Item -Path $p -Recurse -Force -Confirm:$false -ErrorAction Stop
                Write-Host ("* Deleted {0}" -f $p) -ForegroundColor DarkGray
            } catch {
                Write-Warning ("Failed to delete '{0}': {1}" -f $p, $_.Exception.Message)
            }
        }
    }

    # 3) Install (or reinstall) VS Code
    Write-Host "`n=== Installing Visual Studio Code ===" -ForegroundColor Cyan
    try {
        & $wingetCmd install --exact --id Microsoft.VisualStudioCode --force --silent `
            --accept-source-agreements --disable-interactivity
    } catch {
        Write-Error ("Install error: {0}" -f $_.Exception.Message)
        return
    }

    # 4) Wait up to 60s for the CLI to appear
    $codeCmd = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"
    $timeout = 60; $elapsed = 0
    while (-not (Test-Path $codeCmd) -and $elapsed -lt $timeout) {
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    if (-not (Test-Path $codeCmd)) {
        Write-Error ("VS Code CLI not found at {0} after {1}s." -f $codeCmd, $timeout)
        return
    }

    # 5) Install extensions
    Write-Host "`n=== Installing VS Code Extensions ===" -ForegroundColor Cyan
    $extensions = @(
        "ms-vscode-remote.remote-wsl",
        "ms-python.python",
        "ms-python.vscode-pylance",
        "ms-vscode.cpptools",
        "ms-vscode.cmake-tools"
    )
    foreach ($ext in $extensions) {
        try {
            & $codeCmd --install-extension $ext --force | Out-Null
            Write-Host ("* Installed {0}" -f $ext) -ForegroundColor DarkGreen
        } catch {
            Write-Warning ("Ext install failed '{0}': {1}" -f $ext, $_.Exception.Message)
        }
    }

    # 6) Launch VS Code
    Write-Host "`n=== Launching Visual Studio Code ===" -ForegroundColor Cyan
    $codeExe = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"
    if (Test-Path $codeExe) {
        Start-Process $codeExe
    } else {
        Write-Warning ("Code.exe not found at {0}. Launch manually." -f $codeExe)
    }

    Write-Host "`n? All done: VS Code reinstalled, extensions applied, and launched." -ForegroundColor Green
}



function driverdu {
     & "F:\backup\windowsapps\installed\Display Driver Uninstaller\Display Driver Uninstaller.exe"
}


function bbel {
     robocopy "$env:APPDATA\EldenRing" "F:\backup\gamesaves\EldenRing" /E /XO /NFL /NDL /NJH /NJS /NP; ws savegames
}
function winget { & "C:\Program Files\WindowsApps\microsoft.desktopappinstaller_1.25.389.0_x64__8wekyb3d8bbwe\winget.exe" @args }



function fixwinget {
    (Get-ChildItem "C:\Program Files\WindowsApps" -Filter "*winget.exe" -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName | ForEach-Object { 'function winget { & "' + $_ + '" @args }' } | Add-Content $PROFILE; . $PROFILE
}function winget { & "C:\Program Files\WindowsApps\microsoft.desktopappinstaller_1.25.389.0_x64__8wekyb3d8bbwe\winget.exe" @args }


function startit {
    onstart "F:\backup\windowsapps\installed\ghelper\GHelper.exe"
    onstart "F:\study\Platforms\windows\autohotkey\SuspendAndResumeApp\a.ahk"
    onstart "F:\\study\Platforms\windows\autohotkey\switchBetweenDesktop1And2.ahk"
}


function terminaladmin {
    $settings = Get-Content "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" | ConvertFrom-Json; $settings.profiles.defaults | Add-Member -NotePropertyName "elevate" -NotePropertyValue $true -Force; $settings | ConvertTo-Json -Depth 10 | Set-Content "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
}function winget { & "C:\Program Files\WindowsApps\microsoft.desktopappinstaller_1.25.389.0_x64__8wekyb3d8bbwe\winget.exe" @args }


function taskbar {
    Write-Output "Resetting taskbar and repinning apps..."

    # Remove pinned items (Favorites) from Taskband
    Try {
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -Name Favorites -ErrorAction SilentlyContinue
        reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" /v Favorites /f | Out-Null
    } Catch {}

    # Kill Explorer to apply changes
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

    # Clear icon cache
    Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache*" -Force -ErrorAction SilentlyContinue

    # Restart Explorer
    Start-Process explorer
    Start-Sleep -Seconds 2

    # Resolve latest Windows Terminal path
    $term = (Get-ChildItem "C:\Program Files\WindowsApps\" -Directory -Filter "Microsoft.WindowsTerminal*" |
             Sort-Object LastWriteTime -Descending |
             Select-Object -First 1).FullName + "\WindowsTerminal.exe"

    # Path to syspin tool
    $syspin = 'F:\backup\windowsapps\installed\syspin\syspin.exe'

    # List of apps to pin (shortcuts or executables)
    $appsToPin = @(
        'F:\backup\windowsapps\installed\Everything\Everything.lnk',
        'C:\Users\micha\AppData\Local\Programs\Microsoft VS Code\Code.exe',
        $term,
        'F:\backup\windowsapps\installed\Chrome\Application\chrome.exe',
        'F:\backup\windowsapps\installed\Mozilla Firefox\firefox.exe',
        'C:\Program Files\WindowsApps\5319275A.WhatsAppDesktop_2.2518.3.0_x64__cv1g1gvanyjgm\WhatsApp.exe',
        'C:\Program Files\WindowsApps\SAMSUNGELECTRONICSCoLtd.SamsungNotes_4.3.242.0_x64__wyx1vj98g3asy\SamsungNotes.exe',
        'F:\backup\windowsapps\installed\todoist\Todoist.exe',
        'F:\backup\windowsapps\installed\myapps\compiled_python\myg\dist\GameDockerMenu.exe',
        'F:\backup\windowsapps\installed\MacroCreator\MacroCreator.exe'
    )

    # Pin each app using syspin (5386 = Pin to Taskbar)
    foreach ($app in $appsToPin) {
        if (Test-Path $app) {
            & $syspin $app c:5386
        } else {
            Write-Warning "App not found: $app"
        }
    }

    Write-Output "All specified applications have been processed for taskbar pinning."
}







function rewsl {
    Write-Host "Starting full WSL2 setup..." -ForegroundColor Green

    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "Please run PowerShell as Administrator."
        return
    }

    $wslBasePath = "C:\wsl2"
    $ubuntuPath1 = "$wslBasePath\ubuntu"
    $ubuntuPath2 = "$wslBasePath\ubuntu2"
    $backupPath = "F:\backup\linux\wsl\ubuntu.tar"

    foreach ($distro in @("ubuntu", "ubuntu2")) {
        if ((wsl --list --quiet 2>$null) -contains $distro) {
            wsl --terminate $distro 2>$null
            wsl --unregister $distro 2>$null
        }
    }

    foreach ($path in @($ubuntuPath1, $ubuntuPath2)) {
        if (Test-Path "$path\ext4.vhdx") {
            Remove-Item "$path\ext4.vhdx" -Force -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    $features = @(
        "Microsoft-Windows-Subsystem-Linux",
        "VirtualMachinePlatform",
        "Microsoft-Hyper-V-All",
        "Containers-DisposableClientVM"
    )
    $restartNeeded = $false
    $enabled = @()

    foreach ($f in $features) {
        $status = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
        if ($status -and $status.State -ne "Enabled") {
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction SilentlyContinue
            if ($result.RestartNeeded) { $restartNeeded = $true }
            $enabled += $f
        }
    }

    foreach ($svc in @("vmms", "vmcompute")) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -ne "Running") {
            try { Start-Service -Name $svc } catch {}
        }
    }

    $hv = (Get-ComputerInfo).HyperVRequirementVirtualizationFirmwareEnabled
    if ($hv -eq $false) {
        Write-Warning "Enable virtualization in BIOS/UEFI."
        return
    }

    if ($restartNeeded) {
        Write-Warning "Restart required after enabling features: $($enabled -join ', ')"
        return
    }

    wsl --update 2>$null
    wsl --set-default-version 2

    if (-not (Test-Path $backupPath)) {
        Write-Warning "Missing backup: $backupPath"
        return
    }

    try {
        wsl --import ubuntu $ubuntuPath1 $backupPath
        wsl --import ubuntu2 $ubuntuPath2 $backupPath
    } catch {
        Write-Error "Failed to import one or both distros: $_"
        return
    }

    Set-Content "$env:USERPROFILE\.wslconfig" @"
[wsl2]
memory=4GB
processors=2
swap=2GB
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
networkingMode=mirrored
dnsTunneling=true
firewall=true
autoProxy=true
"@ -Force

    wsl --set-default ubuntu
    wsl --list --verbose

    Write-Host "Entering Ubuntu now..." -ForegroundColor Cyan
    wsl -d ubuntu
}












function rrewsl {
    Write-Host "Starting full WSL2 setup..." -ForegroundColor Green

    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "Please run PowerShell as Administrator."
        return
    }

    $wslBasePath = "C:\wsl2"
    $ubuntuPath1 = "$wslBasePath\ubuntu"
    $ubuntuPath2 = "$wslBasePath\ubuntu2"
    $backupPath = "F:\backup\linux\wsl\ubuntu.tar"

    foreach ($distro in @("ubuntu", "ubuntu2")) {
        if ((wsl --list --quiet 2>$null) -contains $distro) {
            wsl --terminate $distro 2>$null
            wsl --unregister $distro 2>$null
        }
    }

    foreach ($path in @($ubuntuPath1, $ubuntuPath2)) {
        if (Test-Path "$path\ext4.vhdx") {
            Remove-Item "$path\ext4.vhdx" -Force -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    $features = @(
        "Microsoft-Windows-Subsystem-Linux",
        "VirtualMachinePlatform",
        "Microsoft-Hyper-V-All",
        "Containers-DisposableClientVM"
    )
    $restartNeeded = $false
    $enabled = @()

    foreach ($f in $features) {
        $status = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
        if ($status -and $status.State -ne "Enabled") {
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction SilentlyContinue
            if ($result.RestartNeeded) { $restartNeeded = $true }
            $enabled += $f
        }
    }

    foreach ($svc in @("vmms", "vmcompute")) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -ne "Running") {
            try { Start-Service -Name $svc } catch {}
        }
    }

    $hv = (Get-ComputerInfo).HyperVRequirementVirtualizationFirmwareEnabled
    if ($hv -eq $false) {
        Write-Warning "Enable virtualization in BIOS/UEFI."
        return
    }

    if ($restartNeeded) {
        Write-Warning "Restart required after enabling features: $($enabled -join ', ')"
        return
    }

    wsl --update 2>$null
    wsl --set-default-version 2

    if (-not (Test-Path $backupPath)) {
        Write-Warning "Missing backup: $backupPath"
        return
    }

    try {
        wsl --import ubuntu $ubuntuPath1 $backupPath
        wsl --import ubuntu2 $ubuntuPath2 $backupPath
    } catch {
        Write-Error "Failed to import one or both distros: $_"
        return
    }

    Set-Content "$env:USERPROFILE\.wslconfig" @"
[wsl2]
memory=4GB
processors=2
swap=2GB
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
networkingMode=mirrored
dnsTunneling=true
firewall=true
autoProxy=true
"@ -Force

    wsl --set-default ubuntu
    wsl --list --verbose

    Write-Host "WSL setup completed. You can start Ubuntu manually via 'wsl -d ubuntu'" -ForegroundColor Cyan
}



function 3ubu {
    Write-Host "Starting WSL2 setup for ubuntu, ubuntu2, and ubuntu3..." -ForegroundColor Green

    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "Please run PowerShell as Administrator."
        return
    }

    $wslBasePath = "C:\wsl2"
    $backupPath = "F:\backup\linux\wsl\ubuntu.tar"
    $distros = @(
        @{ Name = "ubuntu"; Path = "$wslBasePath\ubuntu" },
        @{ Name = "ubuntu2"; Path = "$wslBasePath\ubuntu2" },
        @{ Name = "ubuntu3"; Path = "$wslBasePath\ubuntu3" }
    )

    # Unregister existing distros and delete VHDXs
    foreach ($d in $distros) {
        $name = $d.Name
        $path = $d.Path
        if ((wsl --list --quiet 2>$null) -contains $name) {
            wsl --terminate $name 2>$null
            wsl --unregister $name 2>$null
        }
        if (Test-Path "$path\ext4.vhdx") {
            Remove-Item "$path\ext4.vhdx" -Force -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    # Ensure WSL-related features are enabled
    $features = @(
        "Microsoft-Windows-Subsystem-Linux",
        "VirtualMachinePlatform",
        "Microsoft-Hyper-V-All",
        "Containers-DisposableClientVM"
    )
    $restartNeeded = $false
    $enabled = @()

    foreach ($f in $features) {
        $status = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
        if ($status -and $status.State -ne "Enabled") {
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction SilentlyContinue
            if ($result.RestartNeeded) { $restartNeeded = $true }
            $enabled += $f
        }
    }

    foreach ($svc in @("vmms", "vmcompute")) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -ne "Running") {
            try { Start-Service -Name $svc } catch {}
        }
    }

    $hv = (Get-ComputerInfo).HyperVRequirementVirtualizationFirmwareEnabled
    if ($hv -eq $false) {
        Write-Warning "Hardware virtualization is not enabled in BIOS/UEFI. Please enable VT-x / AMD-V."
        return
    }

    if ($restartNeeded) {
        Write-Warning "Restart required after enabling features: $($enabled -join ', ')"
        return
    }

    wsl --update 2>$null
    wsl --set-default-version 2

    if (-not (Test-Path $backupPath)) {
        Write-Warning "Missing backup: $backupPath"
        return
    }

    # Import all three Ubuntu distros
    foreach ($d in $distros) {
        try {
            wsl --import $d.Name $d.Path $backupPath
            Write-Host "Imported: $($d.Name)" -ForegroundColor Green
        } catch {
            Write-Error "Failed to import $($d.Name): $_"
        }
    }

    # .wslconfig setup
    Set-Content "$env:USERPROFILE\.wslconfig" @"
[wsl2]
memory=4GB
processors=2
swap=2GB
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
networkingMode=mirrored
dnsTunneling=true
firewall=true
autoProxy=true
"@ -Force

    wsl --set-default ubuntu
    wsl --list --verbose

    Write-Host "Setup complete. You can now run 'wsl -d ubuntu', 'ubuntu2', or 'ubuntu3' manually." -ForegroundColor Cyan
}


function ddefender {
    c; Get-Process | Where-Object { $_.Path -like 'F:\backup\windowsapps\install\Cracked\dcontrol*' -and $_.Path } | Stop-Process -Force; Remove-Item -Path 'F:\backup\windowsapps\install\Cracked\dcontrol\24122024' -Recurse -Force -Confirm:$false; cd F:\study\Platforms\windows\autohotkey\DisDefender; ./a.ahk; ./b.ahk; start-sleep 2; ./c.ahk; start-sleep 7; & 'C:\Program Files\7-Zip\7z.exe' x -p"sordum" "F:\backup\windowsapps\install\Cracked\dcontrol.rar" -o"F:\backup\windowsapps\install\Cracked\dcontrol" -y; Set-Location "F:\backup\windowsapps\install\Cracked\dcontrol\24122024"; Start-Process -FilePath "F:\backup\windowsapps\install\Cracked\dcontrol\24122024\dControl.exe" -ArgumentList "/D" -WindowStyle Hidden; start-sleep 20; Start-Process -FilePath "F:\backup\windowsapps\install\Cracked\dcontrol\24122024\dControl.exe" -ArgumentList "/D" -WindowStyle Hidden; start-sleep 15; c; Get-Process | Where-Object { $_.Path -like 'F:\backup\windowsapps\install\Cracked\dcontrol*' -and $_.Path } | Stop-Process -Force; Remove-Item -Path 'F:\backup\windowsapps\install\Cracked\dcontrol\24122024' -Recurse -Force -Confirm:$false; & 'C:\Program Files\7-Zip\7z.exe' x -p"sordum" "F:\backup\windowsapps\install\Cracked\dcontrol.rar" -o"F:\backup\windowsapps\install\Cracked\dcontrol" -y; Set-Location "F:\backup\windowsapps\install\Cracked\dcontrol\24122024"; Start-Process -FilePath "F:\backup\windowsapps\install\Cracked\dcontrol\24122024\dControl.exe" -ArgumentList "/D" -WindowStyle Hidden; start-sleep 10; c; Get-Process | Where-Object { $_.Path -like 'F:\backup\windowsapps\install\Cracked\dcontrol*' -and $_.Path } | Stop-Process -Force; Remove-Item -Path 'F:\backup\windowsapps\install\Cracked\dcontrol\24122024' -Recurse -Force -Confirm:$false
}



function ubu3 {
     wsl -d ubuntu3
}


function n1 {
     & "C:\Program Files\WindowsApps\nvidiacorp.nvidiacontrolpanel_8.1.967.0_x64__56jybvy8sckqj\nvcplui.exe"

}


function swemod {
    Start-Process "F:\backup\windowsapps\install\wemod\WeMod-Setup.exe" -Wait; Start-Sleep -Seconds 2; Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait("{TAB}{ENTER}"); Start-Process "C:\Users\micha\AppData\Local\WeMod\WeMod.exe"; Start-Sleep 3; Get-Process WeMod -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Process "F:\backup\windowsapps\install\wemod\wemodPatcher\WeModPatcher.bat"
}


function winget { & "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1.25.390.0_x64__8wekyb3d8bbwe\winget.exe" @args }



function rrel {
    Copy-Item -Path 'F:\backup\gamesaves\Elden Ring\drive-C\Users\micha\AppData\Roaming\EldenRing\76561197960267366\*' -Destination "$env:APPDATA\EldenRing\76561197960267366\" -Recurse -Force
}
function winget { & "C:\Program Files\WindowsApps\microsoft.desktopappinstaller_1.21.10120.0_x64__8wekyb3d8bbwe\winget.exe" @args }
function winget { & "C:\Program Files\WindowsApps\microsoft.desktopappinstaller_1.21.10120.0_x64__8wekyb3d8bbwe\winget.exe" @args }



function armourycrate {
    & "C:\Program Files\WindowsApps\B9ECED6F.ArmouryCrate_6.1.18.0_x64__qmba6cd70vzyy\ArmouryCrate.exe"
}



function nvidiaprofile {
    & "F:\backup\windowsapps\installed\nvidiaProfileInspector\nvidiaProfileInspector.exe"
}
function winget { & "C:\Program Files\WindowsApps\microsoft.desktopappinstaller_1.25.390.0_x64__8wekyb3d8bbwe\winget.exe" @args }



function getahk {
    Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -like "*AutoHotkey*"} | ForEach-Object {$_.Uninstall()} ; Get-ChildItem "${env:ProgramFiles}\AutoHotkey*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force ; Get-ChildItem "${env:ProgramFiles(x86)}\AutoHotkey*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force ; Get-ChildItem "$env:TEMP\ahk*" -ErrorAction SilentlyContinue | Remove-Item -Force ; Start-Process "F:\backup\windowsapps\install\AutoHotkey_2.0.19_setup.exe" -ArgumentList "/silent" -Wait
}


# --- helper used by every function ------------------------------------------
function Set-WslMemory {
    param(
        [Parameter(Mandatory)][ValidatePattern('^\d+GB$')]$SizeGB
    )

    $cfg = "C:\Users\micha\.wslconfig"
    # 1) wipe the file (or ignore if it doesn't exist)
    Remove-Item $cfg -Force -ErrorAction SilentlyContinue

    # 2) add fresh content
    "`r`n[wsl2]`r`nmemory=$SizeGB`r`nswap=$SizeGB" |
        Set-Content $cfg -Force -Encoding ASCII

    # 3) restart WSL using the same privileges the shell already has
    wsl --shutdown
    wsl -d Ubuntu
}

# --- one wrapper per preset --------------------------------------------------
function w1gb  { Set-WslMemory '1GB'  }
function w2gb  { Set-WslMemory '2GB'  }
function w3gb  { Set-WslMemory '3GB'  }
function w4gb  { Set-WslMemory '4GB'  }
function w5gb  { Set-WslMemory '5GB'  }
function w6gb  { Set-WslMemory '6GB'  }
function w7gb  { Set-WslMemory '7GB'  }
function w8gb  { Set-WslMemory '8GB'  }
function w9gb  { Set-WslMemory '9GB'  }
function w10gb { Set-WslMemory '10GB' }
function w11gb { Set-WslMemory '11GB' }
function w12gb { Set-WslMemory '12GB' }
function w13gb { Set-WslMemory '13GB' }
function w14gb { Set-WslMemory '14GB' }


function startahk {
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'SwitchDesktopAHK' -Value '"F:\study\Platforms\windows\autohotkey\switchBetweenDesktop1And2.ahk"' ; Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'SuspendResumeAHK' -Value '"F:\study\Platforms\windows\autohotkey\SuspendAndResumeApp\a.ahk"'
}

function rmahk {
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'SwitchDesktopAHK' -ErrorAction SilentlyContinue ; Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'SuspendResumeAHK' -ErrorAction SilentlyContinue
}


function speedtest {
    if (!(Get-Command speedtest -ErrorAction SilentlyContinue)) { Invoke-WebRequest -Uri "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip" -OutFile "$env:TEMP\speedtest.zip"; Expand-Archive "$env:TEMP\speedtest.zip" -DestinationPath "$env:TEMP\speedtest" -Force; $env:Path += ";$env:TEMP\speedtest" } ; & "$env:TEMP\speedtest\speedtest.exe" --accept-license --accept-gdpr -f json | ConvertFrom-Json | ForEach-Object { "Ping: $($_.ping.latency) ms`nDownload: $([math]::Round($_.download.bandwidth/125000,2)) Mbps`nUpload: $([math]::Round($_.upload.bandwidth/125000,2)) Mbps" }
}
