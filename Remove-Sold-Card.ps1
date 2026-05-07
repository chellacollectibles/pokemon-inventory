# Chella Collectibles - Remove Sold Card Tool
# Place this file in the same folder as inventory.csv

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$CsvPath = Join-Path $Root "inventory.csv"
$ImagesPath = Join-Path $Root "images"
$ImagesJsonPath = Join-Path $Root "images.json"

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "        Chella Collectibles - Remove Sold Card Tool" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""
}

function Stop-WithMessage {
    param([string]$Message)

    Write-Host ""
    Write-Host $Message -ForegroundColor Red
    Write-Host ""
    exit 1
}

function Rename-SoldImage {
    param(
        [string]$Filename
    )

    if ([string]::IsNullOrWhiteSpace($Filename)) {
        return $null
    }

    $OldPath = Join-Path $ImagesPath $Filename

    if (!(Test-Path $OldPath)) {
        Write-Host "WARNING: Image not found: images\$Filename" -ForegroundColor Yellow
        return $null
    }

    $Directory = Split-Path $OldPath -Parent
    $NameOnly = Split-Path $OldPath -Leaf

    if ($NameOnly -like "SOLD_*") {
        Write-Host "Already marked sold: images\$NameOnly" -ForegroundColor Yellow
        return $NameOnly
    }

    $NewName = "SOLD_$NameOnly"
    $NewPath = Join-Path $Directory $NewName

    if (Test-Path $NewPath) {
        $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $Extension = [System.IO.Path]::GetExtension($NameOnly)
        $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($NameOnly)
        $NewName = "SOLD_${BaseName}_$Timestamp$Extension"
        $NewPath = Join-Path $Directory $NewName

        Write-Host "Sold filename already existed. Using: $NewName" -ForegroundColor Yellow
    }

    Rename-Item -Path $OldPath -NewName $NewName

    Write-Host "Renamed image:" -ForegroundColor Green
    Write-Host "  images\$Filename -> images\$NewName" -ForegroundColor Gray

    return $NewName
}

function Update-ImagesJson {
    param(
        [hashtable]$RenameMap
    )

    if (!(Test-Path $ImagesJsonPath)) {
        return
    }

    try {
        $jsonContent = Get-Content $ImagesJsonPath -Raw
        $imageList = $jsonContent | ConvertFrom-Json

        if ($null -eq $imageList) {
            return
        }

        $updatedList = @()

        foreach ($image in $imageList) {
            $imageString = [string]$image

            if ($RenameMap.ContainsKey($imageString)) {
                $updatedList += $RenameMap[$imageString]
            } else {
                $updatedList += $imageString
            }
        }

        $updatedList | ConvertTo-Json | Set-Content -Path $ImagesJsonPath -Encoding UTF8

        Write-Host ""
        Write-Host "Updated images.json with renamed sold image filenames." -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host "WARNING: Could not update images.json. Your inventory.csv was still updated." -ForegroundColor Yellow
        Write-Host $_.Exception.Message -ForegroundColor DarkYellow
    }
}

Write-Header

if (!(Test-Path $CsvPath)) {
    Stop-WithMessage "ERROR: inventory.csv was not found in this folder."
}

if (!(Test-Path $ImagesPath)) {
    Stop-WithMessage "ERROR: images folder was not found in this folder."
}

$Inventory = Import-Csv $CsvPath

if ($null -eq $Inventory -or $Inventory.Count -eq 0) {
    Stop-WithMessage "ERROR: inventory.csv appears to be empty."
}

while ($true) {
    Write-Header

    $Search = Read-Host "Type the card name to search, or type Q to quit"

    if ($Search.Trim().ToLower() -eq "q") {
        Write-Host ""
        Write-Host "Cancelled. No changes made." -ForegroundColor Yellow
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($Search)) {
        Write-Host ""
        Write-Host "Please type a real search term." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        continue
    }

    $Matches = @($Inventory | Where-Object {
        $_.name -and $_.name.ToLower().Contains($Search.ToLower())
    })

    if ($Matches.Count -eq 0) {
        Write-Host ""
        Write-Host "No matches found for: $Search" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to search again"
        continue
    }

    Write-Host ""
    Write-Host "Found $($Matches.Count) matching item(s):" -ForegroundColor Cyan
    Write-Host ""

    for ($i = 0; $i -lt $Matches.Count; $i++) {
        $item = $Matches[$i]

        Write-Host "[$($i + 1)]" -ForegroundColor Yellow -NoNewline
        Write-Host " $($item.name)" -ForegroundColor White
        Write-Host "     Set:   $($item.set)" -ForegroundColor Gray
        Write-Host "     Type:  $($item.type)" -ForegroundColor Gray
        Write-Host "     Price: $($item.price)" -ForegroundColor Gray
        Write-Host "     Front: $($item.filename)" -ForegroundColor Gray

        if (![string]::IsNullOrWhiteSpace($item.back_filename)) {
            Write-Host "     Back:  $($item.back_filename)" -ForegroundColor Gray
        } else {
            Write-Host "     Back:  None" -ForegroundColor DarkGray
        }

        Write-Host ""
    }

    $Selection = Read-Host "Enter the number to remove, S to search again, or Q to quit"

    if ($Selection.Trim().ToLower() -eq "q") {
        Write-Host ""
        Write-Host "Cancelled. No changes made." -ForegroundColor Yellow
        exit 0
    }

    if ($Selection.Trim().ToLower() -eq "s") {
        continue
    }

    $SelectionNumber = 0

    if (!( [int]::TryParse($Selection, [ref]$SelectionNumber) )) {
        Write-Host ""
        Write-Host "Invalid selection." -ForegroundColor Red
        Read-Host "Press Enter to continue"
        continue
    }

    if ($SelectionNumber -lt 1 -or $SelectionNumber -gt $Matches.Count) {
        Write-Host ""
        Write-Host "Selection out of range." -ForegroundColor Red
        Read-Host "Press Enter to continue"
        continue
    }

    $SelectedItem = $Matches[$SelectionNumber - 1]

    Write-Header
    Write-Host "You selected this item:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Name:  $($SelectedItem.name)" -ForegroundColor White
    Write-Host "Set:   $($SelectedItem.set)" -ForegroundColor White
    Write-Host "Type:  $($SelectedItem.type)" -ForegroundColor White
    Write-Host "Price: $($SelectedItem.price)" -ForegroundColor White
    Write-Host "Front: $($SelectedItem.filename)" -ForegroundColor White

    if (![string]::IsNullOrWhiteSpace($SelectedItem.back_filename)) {
        Write-Host "Back:  $($SelectedItem.back_filename)" -ForegroundColor White
    } else {
        Write-Host "Back:  None" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "This will:" -ForegroundColor Yellow
    Write-Host "  1. Back up inventory.csv"
    Write-Host "  2. Remove this row from inventory.csv"
    Write-Host "  3. Rename the image file(s) with SOLD_ at the front"
    Write-Host ""
    Write-Host "To confirm, type exactly: YES" -ForegroundColor Red

    $Confirm = Read-Host "Confirm"

    if ($Confirm -ne "YES") {
        Write-Host ""
        Write-Host "Cancelled. No changes made." -ForegroundColor Yellow
        Read-Host "Press Enter to continue"
        continue
    }

    $BackupPath = Join-Path $Root ("inventory_backup_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".csv")
    Copy-Item -Path $CsvPath -Destination $BackupPath

    Write-Host ""
    Write-Host "Backup created: $(Split-Path $BackupPath -Leaf)" -ForegroundColor Green
    Write-Host ""

    $RenameMap = @{}

    $NewFrontName = Rename-SoldImage -Filename $SelectedItem.filename
    if ($NewFrontName) {
        $RenameMap[$SelectedItem.filename] = $NewFrontName
    }

    if (![string]::IsNullOrWhiteSpace($SelectedItem.back_filename)) {
        $NewBackName = Rename-SoldImage -Filename $SelectedItem.back_filename
        if ($NewBackName) {
            $RenameMap[$SelectedItem.back_filename] = $NewBackName
        }
    }

    $UpdatedInventory = @($Inventory | Where-Object {
        !(
            $_.filename -eq $SelectedItem.filename -and
            $_.name -eq $SelectedItem.name -and
            $_.set -eq $SelectedItem.set -and
            $_.price -eq $SelectedItem.price
        )
    })

    $UpdatedInventory | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

    if ($RenameMap.Count -gt 0) {
        Update-ImagesJson -RenameMap $RenameMap
    }

    Write-Host ""
    Write-Host "DONE. Item removed from inventory.csv and image file(s) marked SOLD." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next step: open GitHub Desktop, review the changed files, then commit and push." -ForegroundColor Cyan
    Write-Host ""

    exit 0
}