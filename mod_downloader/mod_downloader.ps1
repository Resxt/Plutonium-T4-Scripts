param([switch]$ShowModList, [String[]]$DownloadMods, [switch]$DownloadAllMods, [switch]$EditConfig)

$plutonium_t4_mods_folder_path = "$env:LOCALAPPDATA\Plutonium\storage\t4\mods\"
$script_data_folder_path = "data\"
$script_config_file_path = ($script_data_folder_path+"mod_downloader_config.json")
$excluded = @(
" Up",
"Login",
" Home",
" » t4",
" » mods",
"Get list",
"HttpFileServer 2.3m",
"Name",
".extension",
"Size",
"Timestamp",
"Hits"
)





# :: Server ::

function GetAllModNames {
    $mods = ((Invoke-WebRequest -Uri ($config.mods_url+$ModName)).Links | Select-Object -ExpandProperty outerText);
    $list = New-Object Collections.Generic.List[String]
    $mods | ForEach-Object {
        if ($excluded -notcontains $_) {
            $list.Add($_.trim());
        }
    }

    return $list;
}

function GetModFileNames($ModName) {
    $mod_files = ((Invoke-WebRequest -Uri ($config.mods_url+$ModName)).Links | Select-Object -ExpandProperty outerText)
    $list = New-Object Collections.Generic.List[String]
    $mod_files | ForEach-Object {
        if ($excluded -notcontains $_) {
            $list.Add($_.trim());
        }
    }

    return $list;
}

function DownloadMod($ModName) {
    if ((Test-Path -Path $plutonium_t4_mods_folder_path$ModName) -eq $False) {
        Write-Host ">> Downloading '$ModName'"
        [void](New-Item -ItemType Directory -Force -Path $plutonium_t4_mods_folder_path$ModName)

        GetModFileNames($ModName) | ForEach-Object {
            if ($_ -ne "» $ModName") {
                Write-Host "> Downloading $_"
                Write-Host ("> Writing file to " + $plutonium_t4_mods_folder_path+$ModName+"\"+$_)
                Invoke-WebRequest -Uri ($config.mods_url+$ModName+"/"+$_) -OutFile ($plutonium_t4_mods_folder_path+$ModName+"\"+$_)
            }
        }
    }
    else {
        Write-Host ">> Skipping download of '$ModName'. Mod already exist"
    }
}





# :: Configuration ::

function CreateConfig([bool]$WriteConfig)
{
    echo ":: Creating your configuration ::`n"

    Set-Variable -Name "mods_url" -Scope Script -Value (NormalizeUrl -Url (Read-Host -Prompt "Please enter the full URL to the mods folder from the web server | Example: http://100.10.200.300:54965/t4/mods/"))

    if ($WriteConfig)
    {
        WriteConfig
    }
}

function WriteConfig
{
    $config = [PSCustomObject]@{
        mods_url = $mods_url
    }

    $config | ConvertTo-Json | Set-Content $script_config_file_path
}

function ParseConfig
{
    $config = Get-Content -Path $script_config_file_path | ConvertFrom-Json
    Set-Variable -Name "config" -Scope Script -Value $config
}

function CheckConfig
{
    if ((Test-Path $script_config_file_path) -eq $false)
    {
        CreateConfig -WriteConfig $true
    }

    ParseConfig
}

function EditConfig
{
    if ((Test-Path $script_config_file_path) -eq $true)
    {
        Remove-Item $script_config_file_path
    }

    CheckConfig
}





# :: Utilities ::

function NormalizeUrl([string]$Url)
{
    while ($Url.EndsWith('/'))
    {
        $Url = $Url.substring(0,$Url.length-1) + ''
    }

    $Url = $Url+"/"
    return $Url
}





# :: Script entry point ::

if ((Test-Path -Path $plutonium_t4_mods_folder_path) -eq $false) {
[void](New-Item -ItemType Directory -Path $plutonium_t4_mods_folder_path)
}

if ((Test-Path -Path $script_data_folder_path) -eq $false) {
[void](New-Item -ItemType Directory -Path $script_data_folder_path)
}

if ($DownloadMods) {
    CheckConfig
    $DownloadMods | ForEach-Object {
        DownloadMod($_)
    }
}
elseif ($DownloadAllMods) {
    CheckConfig
    GetAllModNames | ForEach-Object {
        DownloadMod($_)
    }
}
elseif ($ShowModList) {
    CheckConfig
    GetAllModNames | ForEach-Object {
        Write-Host $_
    }
}
elseif ($EditConfig) {
    EditConfig
}
else {
    CheckConfig
    Write-Host "The script didn't run because you either gave no option or a wrong option"
}
