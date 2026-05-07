# Chella Collectibles - Remove Sold Card Tool
# Place this file in the same folder as inventory.csv

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$CsvPath = Join-Path $Root "inventory.csv"
$ImagesPath = Join-Path $Root "images"
$ImagesJsonPath = Join-Path $Root "images.json"

$RemovalQueue = @()

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

function Get-QueueKey {
    param($Item)

    return "$($Item.filename)|$($Item.name)|$($Item.set)|$($Item.price)"
}

function Show-QueueSummary {
    if ($RemovalQueue.Count -eq 0) {
        Write-Host "Removal queue is currently empty." -ForegroundColor DarkGray
        return
    }

    Write-Host "Current removal queue: $($RemovalQueue.Count) item(s)" -ForegroundColor Cyan
    Write-Host ""

    for ($i = 0; $i -lt $RemovalQueue.Count; $i++) {
        $item = $RemovalQueue[$i]

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

function Finalize-Removals {
    param(
        [array]$Inventory
    )

    Write-Header

    if ($RemovalQueue.Count -eq 0) {
        Write-Host "No cards were queued for removal. No changes made." -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }

    Show-QueueSummary

    Write-Host "This will:" -ForegroundColor Yellow
    Write-Host "  1. Create a backup of inventory.csv"
    Write-Host "  2. Remove all queued items from inventory.csv"
    Write-Host "  3. Rename each related image with SOLD_ at the front"
    Write-Host "  4. Update images.json if possible"
    Write-Host ""
    Write-Host "To confirm, type exactly: YES" -ForegroundColor Red

    $Confirm = Read-Host "Confirm"

    if ($Confirm -ne "YES") {
        Write-Host ""
        Write-Host "Cancelled. No changes made." -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }

    $BackupPath = Join-Path $Root ("inventory_backup_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".csv")
    Copy-Item -Path $CsvPath -Destination $BackupPath

    Write-Host ""
    Write-Host "Backup created: $(Split-Path $BackupPath -Leaf)" -ForegroundColor Green
    Write-Host ""

    $RenameMap = @{}

    foreach ($item in $RemovalQueue) {
        Write-Host "Processing:" -ForegroundColor Cyan
        Write-Host "  $($item.name)" -ForegroundColor White

        $NewFrontName = Rename-SoldImage -Filename $item.filename
        if ($NewFrontName) {
            $RenameMap[$item.filename] = $NewFrontName
        }

        if (![string]::IsNullOrWhiteSpace($item.back_filename)) {
            $NewBackName = Rename-SoldImage -Filename $item.back_filename
            if ($NewBackName) {
                $RenameMap[$item.back_filename] = $NewBackName
            }
        }

        Write-Host ""
    }

    $QueueKeys = @{}
    foreach ($item in $RemovalQueue) {
        $QueueKeys[(Get-QueueKey $item)] = $true
    }

    $UpdatedInventory = @($Inventory | Where-Object {
        $key = Get-QueueKey $_
        -not $QueueKeys.ContainsKey($key)
    })

    $UpdatedInventory | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

    if ($RenameMap.Count -gt 0) {
        Update-ImagesJson -RenameMap $RenameMap
    }

    Write-Host ""
    Write-Host "DONE. Removed $($RemovalQueue.Count) item(s) from inventory.csv and marked images as SOLD." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next step: open GitHub Desktop, review the changed files, then commit and push." -ForegroundColor Cyan
    Write-Host ""

    exit 0
}

Write-Header

if (!(Test-Path $CsvPath)) {
    Stop-WithMessage "ERROR: inventory.csv was not found in this folder."
}

if (!(Test-Path $ImagesPath)) {
    Stop-WithMessage "ERROR: images folder was not found in this folder."
}

$Inventory = @(Import-Csv $CsvPath)

if ($null -eq $Inventory -or $Inventory.Count -eq 0) {
    Stop-WithMessage "ERROR: inventory.csv appears to be empty."
}

while ($true) {
    Write-Header

    if ($RemovalQueue.Count -gt 0) {
        Write-Host "Queued for removal: $($RemovalQueue.Count) item(s)" -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  Search card name  - type a card name, example: Charizard"
    Write-Host "  View queue        - type V"
    Write-Host "  Remove from queue - type R"
    Write-Host "  Finish and apply  - type D"
    Write-Host "  Quit no changes   - type Q"
    Write-Host ""

    $Search = Read-Host "Enter search or option"

    if ([string]::IsNullOrWhiteSpace($Search)) {
        continue
    }

    $Command = $Search.Trim().ToLower()

    if ($Command -eq "q") {
        Write-Host ""
        Write-Host "Cancelled. No changes made." -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }

    if ($Command -eq "d") {
        Finalize-Removals -Inventory $Inventory
    }

    if ($Command -eq "v") {
        Write-Header
        Show-QueueSummary
        Read-Host "Press Enter to continue"
        continue
    }

    if ($Command -eq "r") {
        Write-Header

        if ($RemovalQueue.Count -eq 0) {
            Write-Host "Queue is empty. Nothing to remove." -ForegroundColor Yellow
            Read-Host "Press Enter to continue"
            continue
        }

        Show-QueueSummary

        $RemoveSelection = Read-Host "Enter the queue number to remove, or press Enter to cancel"

        if ([string]::IsNullOrWhiteSpace($RemoveSelection)) {
            continue
        }

        $RemoveNumber = 0

        if (!( [int]::TryParse($RemoveSelection, [ref]$RemoveNumber) )) {
            Write-Host ""
            Write-Host "Invalid selection." -ForegroundColor Red
            Read-Host "Press Enter to continue"
            continue
        }

        if ($RemoveNumber -lt 1 -or $RemoveNumber -gt $RemovalQueue.Count) {
            Write-Host ""
            Write-Host "Selection out of range." -ForegroundColor Red
            Read-Host "Press Enter to continue"
            continue
        }

        $Removed = $RemovalQueue[$RemoveNumber - 1]
        $RemovalQueue = @($RemovalQueue | Where-Object { (Get-QueueKey $_) -ne (Get-QueueKey $Removed) })

        Write-Host ""
        Write-Host "Removed from queue:" -ForegroundColor Green
        Write-Host $Removed.name -ForegroundColor White
        Read-Host "Press Enter to continue"
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
        $AlreadyQueued = $RemovalQueue | Where-Object { (Get-QueueKey $_) -eq (Get-QueueKey $item) }

        Write-Host "[$($i + 1)]" -ForegroundColor Yellow -NoNewline
        Write-Host " $($item.name)" -ForegroundColor White

        if ($AlreadyQueued) {
            Write-Host "     STATUS: Already queued for removal" -ForegroundColor Red
        }

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

    $Selection = Read-Host "Enter number to add to removal queue, S to search again, D to finish, or Q to quit"

    if ($Selection.Trim().ToLower() -eq "q") {
        Write-Host ""
        Write-Host "Cancelled. No changes made." -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }

    if ($Selection.Trim().ToLower() -eq "s") {
        continue
    }

    if ($Selection.Trim().ToLower() -eq "d") {
        Finalize-Removals -Inventory $Inventory
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
    $SelectedKey = Get-QueueKey $SelectedItem

    $AlreadyInQueue = $RemovalQueue | Where-Object { (Get-QueueKey $_) -eq $SelectedKey }

    if ($AlreadyInQueue) {
        Write-Host ""
        Write-Host "That item is already in the removal queue." -ForegroundColor Yellow
        Read-Host "Press Enter to continue"
        continue
    }

    Write-Header
    Write-Host "Add this item to the removal queue?" -ForegroundColor Cyan
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
    $AddConfirm = Read-Host "Type Y to add this item, or anything else to cancel"

    if ($AddConfirm.Trim().ToLower() -eq "y") {
        $RemovalQueue += $SelectedItem

        Write-Host ""
        Write-Host "Added to removal queue." -ForegroundColor Green
        Write-Host ""
        Read-Host "Press Enter to continue"
    } else {
        Write-Host ""
        Write-Host "Not added." -ForegroundColor Yellow
        Read-Host "Press Enter to continue"
    }
}