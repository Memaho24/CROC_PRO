<#
Compatibility wrapper. The implementation lives in tools\Apps.ps1.
#>
& (Join-Path $PSScriptRoot 'tools\Apps.ps1') @args
exit $LASTEXITCODE
