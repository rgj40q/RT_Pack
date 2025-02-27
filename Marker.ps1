$ProgressPreference = 'SilentlyContinue'
Write-Output 'Подгружаем настройки'

try {
    . ( Join-Path $PSScriptRoot _settings.ps1 )
}
catch { Write-Host ( 'Не найден файл настроек ' + ( Join-Path $PSScriptRoot _settings.ps1 ) + ', видимо это первый запуск.' ) }

$str = 'Подгружаем функции'
if ( $use_timestamp -ne 'Y' ) { Write-Host $str } else { Write-Host ( ( Get-Date -Format 'dd-MM-yyyy HH:mm:ss' ) + ' ' + $str ) }
. ( Join-Path $PSScriptRoot _functions.ps1 )

Test-PSVersion
if ( ( Test-Version '_functions.ps1' 'Adder' ) -eq $true ) {
    Write-Log 'Запускаем новую версию  _functions.ps1'
    . ( Join-Path $PSScriptRoot '_functions.ps1' )
}
Test-Version ( $PSCommandPath | Split-Path -Leaf ) 'Marker'

$use_timestamp = Test-Setting 'use_timestamp'
$tlo_path = Test-Setting 'tlo_path' -required
$down_tag = Test-Setting 'down_tag' -required
$seed_tag = Test-Setting 'seed_tag' -required
$tg_token = Test-Setting 'tg_token'
if ( $tg_token -ne '') {
    $tg_chat = Test-Setting 'tg_chat' -required
}

if ( Test-Path ( Join-Path $PSScriptRoot 'settings.json') ) {
    $settings = Get-Content -Path ( Join-Path $PSScriptRoot 'settings.json') | ConvertFrom-Json -AsHashtable
    $standalone = $true
}
else {
    try {
        . ( Join-Path $PSScriptRoot _settings.ps1 )
        $settings = [ordered]@{}
        $settings.interface = @{}
        $settings.interface.use_timestamp = ( $use_timestamp -eq 'Y' ? 'Y' : 'N' )
        $standalone = $false
    }
    catch { Write-Host ( 'Не найден файл настроек ' + ( Join-Path $PSScriptRoot _settings.ps1 ) + ', видимо это первый запуск.' ) }
}

if ( $standalone -eq $false ) {
    $tlo_path = Test-Setting 'tlo_path' -required
    $ini_path = Join-Path $tlo_path 'data' 'config.ini'
    Write-Log 'Читаем настройки Web-TLO'
    $ini_data = Get-IniContent $ini_path
}

Get-Clients
if ( $rss_mark.ToUpper() -eq 'N' -and $rss ) { 
    if ( $rss.client ) {
        $settings.clients.Remove( $rss.client )
    }
    # else {
    #     $settings.clients.Remove( ( $settings.clients.keys | Where-Object { $settings.clients[$_].IP -eq $rss.client_IP -and $settings.clients[$_].port -eq $rss.client_port } ) )
    # }
}
Get-ClientApiVersions -clients $settings.clients
$clients_torrents = Get-ClientsTorrents -mess_sender 'Marker' -noIDs
$seed_cnt = 0
$down_cnt = 0

foreach ( $torrent in $clients_torrents ) {
    if ( $torrent.state -in ( 'downloading', 'forcedDL', 'stalledDL', $settings.clients[$torrent.client_key].stopped_state_dl ) ) {
        if ( $torrent.tags -like "*$seed_tag*" ) {
            Get-topicIDs -client $settings.clients[$torrent.client_key] -torrent_list @( $torrent )
            Write-Log "Снимаем с раздачи $($torrent.topic_id) - '$($torrent.name)' метку '$seed_tag' в клиенте $($torrent.client_key)"
            Remove-Comment -client $settings.clients[$torrent.client_key] -torrent $torrent -label $seed_tag -silent
        }
        if ( $torrent.tags -notlike "*$down_tag*" ) {
            Get-topicIDs -client $settings.clients[$torrent.client_key] -torrent_list @( $torrent )
            Write-Log "Метим раздачу $($torrent.topic_id) - '$($torrent.name)' меткой '$down_tag' в клиенте $($torrent.client_key)"
            Set-Comment -client $settings.clients[$torrent.client_key] -torrent $torrent -label $down_tag
            $torrent.state = 'OK'
        }
        $down_cnt++
    }
    elseif ( $torrent.state -in ( 'queuedUP', 'stalledUP', 'forcedUP', 'uploading', $settings.clients[$torrent.client_key].stopped_state ) ) {
        if ( $torrent.tags -like "*$down_tag*" ) {
            Get-topicIDs -client $settings.clients[$torrent.client_key] -torrent_list @( $torrent )
            Write-Log "Снимаем с раздачи $($torrent.topic_id) - '$($torrent.name)' метку '$down_tag' в клиенте $($torrent.client_key)"
            Remove-Comment -client $settings.clients[$torrent.client_key] -torrent $torrent -label $down_tag -silent
        }
        if ( $torrent.tags -notlike "*$seed_tag*" ) {
            Get-topicIDs -client $settings.clients[$torrent.client_key] -torrent_list @( $torrent )
            Write-Log "Метим раздачу $($torrent.topic_id) - '$($torrent.name)' меткой '$seed_tag' в клиенте $($torrent.client_key)"
            Set-Comment -client $settings.clients[$torrent.client_key] -torrent $torrent -label $seed_tag -silent
            $seed_cnt++            
        }
        if ( $torrent.state -eq 'forcedUP' ) {
            Get-topicIDs -client $settings.clients[$torrent.client_key] -torrent_list @( $torrent )
            Write-Log "Перевожу раздачу $($torrent.topic_id) - $($torrent.name) в статус Seeding"
            $start_keys = @($torrent.hash)
            Start-Torrents -hashes $start_keys -client $settings.clients[$torrent.client_key]
        }
    }
}
Send-TGMessage -message "Переведено в seeding: $seed_cnt`nОсталось в downloading: $down_cnt" -token $tg_token -chat_id $tg_chat -mess_sender 'Marker'
