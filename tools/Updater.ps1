<#
CyberCroc updater.
Sources:
  - GitHub (development/manual mode)
  - SMB share (legacy/local-club mode)
The updater runs outside the main process so CyberCroc.ps1 can be replaced safely.
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Apply,
    [switch]$Github,
    [string]$Repo='Memaho24/CROC_PRO',
    [string]$Branch='main',
    [string]$Source,
    [int]$WaitPid=0
)

. (Join-Path $PSScriptRoot 'Core.ps1')

function Get-CcVersion([string]$Root){
    try{
        $file=Join-Path $Root 'version.txt'
        if(Test-Path -LiteralPath $file){
            $v=(Get-Content -LiteralPath $file -Raw -ErrorAction Stop).Trim()
            if($v){return $v}
        }
    }catch{Write-CcError -FunctionName 'Get-CcVersion' -Exception $_.Exception}
    return '0.0.0'
}

function Get-CcGithubVersion([string]$Repository,[string]$Ref){
    try{
        $uri="https://raw.githubusercontent.com/$Repository/$Ref/version.txt"
        $r=Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $v=([string]$r.Content).Trim()
        if($v -and $v -match '^\d+(\.\d+){1,3}$'){return $v}
        throw "Invalid version.txt from GitHub: $v"
    }catch{
        Write-CcError -FunctionName 'Get-CcGithubVersion' -Exception $_.Exception
        return ''
    }
}

function Get-CcGithubUpdateInfo([string]$Root,[string]$Repository,[string]$Ref){
    $local=Get-CcVersion $Root
    $remote=Get-CcGithubVersion $Repository $Ref
    if([string]::IsNullOrWhiteSpace($remote)){
        return [pscustomobject]@{Available=$false;Reason='GitHub unavailable or version.txt missing';Local=$local;Remote='';Repo=$Repository;Branch=$Ref}
    }
    $cmp=Compare-CcVersion $remote $local
    return [pscustomobject]@{
        Available=($cmp -gt 0)
        Reason=$(if($cmp -gt 0){'New version available'}else{'Already current'})
        Local=$local
        Remote=$remote
        Repo=$Repository
        Branch=$Ref
    }
}

function Test-CcShare([string]$Path){
    try{return [bool](Test-Path -LiteralPath $Path -PathType Container -ErrorAction Stop)}
    catch{Write-CcError -FunctionName 'Test-CcShare' -Exception $_.Exception;return $false}
}

function Get-CcShareUpdateInfo([string]$Root,[string]$Share){
    try{
        if(-not(Test-CcShare $Share)){return [pscustomobject]@{Available=$false;Reason='SMB share unavailable';Local=Get-CcVersion $Root;Remote=''}}
        $remote=Get-CcVersion $Share
        $local=Get-CcVersion $Root
        $cmp=Compare-CcVersion $remote $local
        return [pscustomobject]@{Available=($cmp -gt 0);Reason=$(if($cmp -gt 0){'New version available'}else{'Already current'});Local=$local;Remote=$remote}
    }catch{
        Write-CcError -FunctionName 'Get-CcShareUpdateInfo' -Exception $_.Exception
        return [pscustomobject]@{Available=$false;Reason=$_.Exception.Message;Local='';Remote=''}
    }
}

function Wait-CcProcessExit([int]$ProcessId){
    if($ProcessId -le 0){return}
    try{
        $p=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if($p){
            Write-CcLog "Waiting for CyberCroc process $ProcessId to exit" 'INFO' 'Wait-CcProcessExit'
            Wait-Process -Id $ProcessId -Timeout 120 -ErrorAction SilentlyContinue|Out-Null
        }
    }catch{Write-CcLog "Wait for PID $ProcessId finished with warning: $($_.Exception.Message)" 'WARN' 'Wait-CcProcessExit'}
}

function Invoke-CcRobocopy([string]$From,[string]$To){
    & robocopy.exe $From $To /E /R:3 /W:2 /COPY:DAT /DCOPY:DAT /NFL /NDL /NJH /NJS /NP /XF 'config.ini' 'accounts.json' 'games.txt' 'steam_path.txt' /XD 'logs' 'BACKUP' 'data' 'runtime' 2>&1|Out-Null
    $rc=$LASTEXITCODE
    if($rc -ge 8){throw "Robocopy failed: $From -> $To, code $rc"}
    return $rc
}

function Invoke-CcGithubApply([string]$Root,[string]$Repository,[string]$Ref){
    $stage=$null
    $backup=$null
    $zip=$null
    try{
        $info=Get-CcGithubUpdateInfo $Root $Repository $Ref
        if(-not $info.Available){
            Write-CcLog "GitHub update skipped: $($info.Reason) local=$($info.Local) remote=$($info.Remote)" 'INFO' 'Invoke-CcGithubApply'
            return $false
        }

        Wait-CcProcessExit $WaitPid

        $stage=Join-Path $env:TEMP ('CyberCrocGithub_'+[guid]::NewGuid().ToString('N'))
        $zip=Join-Path $env:TEMP ('CyberCrocGithub_'+[guid]::NewGuid().ToString('N')+'.zip')
        $backup=Join-Path $env:TEMP ('CyberCrocBackup_'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage -Force|Out-Null
        New-Item -ItemType Directory -Path $backup -Force|Out-Null

        $zipUri="https://github.com/$Repository/archive/refs/heads/$Ref.zip"
        Write-CcLog "Downloading GitHub update $($info.Remote) from $zipUri" 'INFO' 'Invoke-CcGithubApply'
        Invoke-WebRequest -Uri $zipUri -OutFile $zip -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
        Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force

        $sourceRoot=Get-ChildItem -LiteralPath $stage -Directory -ErrorAction Stop|Select-Object -First 1
        if(-not $sourceRoot){throw 'GitHub archive is empty'}

        # Backup only application files. Local settings/data are never overwritten.
        Invoke-CcRobocopy $Root $backup|Out-Null
        Invoke-CcRobocopy $sourceRoot.FullName $Root|Out-Null

        $installed=Get-CcVersion $Root
        if((Compare-CcVersion $installed $info.Remote) -ne 0){
            throw "Update verification failed: installed=$installed expected=$($info.Remote)"
        }

        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue

        Write-CcLog "GitHub update completed: $($info.Local) -> $($info.Remote)" 'OK' 'Invoke-CcGithubApply'
        $launcher=Join-Path $Root 'launcher.vbs'
        if(Test-Path -LiteralPath $launcher){
            Start-Process -FilePath 'wscript.exe' -ArgumentList @('//B','//Nologo',$launcher) -WorkingDirectory $Root -WindowStyle Hidden|Out-Null
        }
        return $true
    }catch{
        Write-CcError -FunctionName 'Invoke-CcGithubApply' -Exception $_.Exception
        try{
            if($backup -and (Test-Path -LiteralPath $backup)){
                Invoke-CcRobocopy $backup $Root|Out-Null
                Write-CcLog 'GitHub update rollback completed.' 'WARN' 'Invoke-CcGithubApply'
            }
        }catch{Write-CcError -FunctionName 'Invoke-CcGithubRollback' -Exception $_.Exception}
        if($zip){Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue}
        if($stage){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}
        if($backup){Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue}
        return $false
    }
}

function Invoke-CcShareApply([string]$Root,[string]$Share){
    try{
        if(-not(Test-CcShare $Share)){throw "SMB share unavailable: $Share"}
        $info=Get-CcShareUpdateInfo $Root $Share
        if(-not $info.Available){
            Write-CcLog "SMB update skipped: $($info.Reason) local=$($info.Local) remote=$($info.Remote)" 'INFO' 'Invoke-CcShareApply'
            return $false
        }
        Wait-CcProcessExit $WaitPid
        $stage=Join-Path $env:TEMP ('CyberCrocShare_'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage -Force|Out-Null
        Invoke-CcRobocopy $Share $stage|Out-Null
        Invoke-CcRobocopy $stage $Root|Out-Null
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        Write-CcLog "SMB update completed: $($info.Local) -> $($info.Remote)" 'OK' 'Invoke-CcShareApply'
        $launcher=Join-Path $Root 'launcher.vbs'
        if(Test-Path -LiteralPath $launcher){Start-Process -FilePath 'wscript.exe' -ArgumentList @('//B','//Nologo',$launcher) -WorkingDirectory $Root -WindowStyle Hidden|Out-Null}
        return $true
    }catch{Write-CcError -FunctionName 'Invoke-CcShareApply' -Exception $_.Exception;return $false}
}

$root=$script:CcRoot
if($Check){
    if($Github){
        Get-CcGithubUpdateInfo $root $Repo $Branch|ConvertTo-Json -Compress
    }else{
        if(-not $Source){$cfg=Get-CcConfig;$Source=[string]$cfg['UPDATE_SHARE']}
        Get-CcShareUpdateInfo $root $Source|ConvertTo-Json -Compress
    }
    exit 0
}
if($Apply){
    $ok=$false
    if($Github){$ok=Invoke-CcGithubApply $root $Repo $Branch}
    else{
        if(-not $Source){$cfg=Get-CcConfig;$Source=[string]$cfg['UPDATE_SHARE']}
        $ok=Invoke-CcShareApply $root $Source
    }
    if($ok){exit 0}else{exit 1}
}
