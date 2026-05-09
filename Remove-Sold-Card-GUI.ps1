# Chella Collectibles - Remove Sold Card GUI Tool
# Place this file in the same folder as inventory.csv
# Expected structure:
#   inventory.csv
#   images\
#   images.json optional

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$CsvPath = Join-Path $Root "inventory.csv"
$ImagesPath = Join-Path $Root "images"
$ImagesJsonPath = Join-Path $Root "images.json"

$script:Inventory = @()
$script:RemovalQueue = New-Object System.Collections.ArrayList
$script:LastMatches = @()
$script:FrontImageObject = $null
$script:BackImageObject = $null

function Get-QueueKey {
    param($Item)
    return "$($Item.filename)|$($Item.name)|$($Item.set)|$($Item.price)"
}

function Add-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    $script:LogBox.AppendText($line + [Environment]::NewLine)
    $script:LogBox.SelectionStart = $script:LogBox.Text.Length
    $script:LogBox.ScrollToCaret()
}

function Test-StartupFiles {
    if (!(Test-Path $CsvPath)) {
        [System.Windows.Forms.MessageBox]::Show("inventory.csv was not found in this folder.`n`nExpected:`n$CsvPath", "Missing inventory.csv", "OK", "Error") | Out-Null
        exit 1
    }

    if (!(Test-Path $ImagesPath)) {
        [System.Windows.Forms.MessageBox]::Show("images folder was not found in this folder.`n`nExpected:`n$ImagesPath", "Missing images folder", "OK", "Error") | Out-Null
        exit 1
    }
}

function Load-Inventory {
    try {
        $script:Inventory = @(Import-Csv $CsvPath)

        if ($null -eq $script:Inventory -or $script:Inventory.Count -eq 0) {
            throw "inventory.csv appears to be empty."
        }

        Add-Log "Loaded inventory.csv with $($script:Inventory.Count) item(s)."
        Add-Log "Using images folder: $ImagesPath"

        if (Test-Path $ImagesJsonPath) {
            Add-Log "images.json found and will be updated during final apply."
        } else {
            Add-Log "images.json not found. That is okay; it will be skipped."
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not load inventory.csv.`n`n$($_.Exception.Message)", "Load Error", "OK", "Error") | Out-Null
        exit 1
    }
}

function Clear-ImageBox {
    param([System.Windows.Forms.PictureBox]$PictureBox)

    if ($PictureBox.Image -ne $null) {
        $oldImage = $PictureBox.Image
        $PictureBox.Image = $null
        $oldImage.Dispose()
    }
}

function Load-ImageIntoBox {
    param(
        [System.Windows.Forms.PictureBox]$PictureBox,
        [string]$Filename,
        [System.Windows.Forms.Label]$StatusLabel
    )

    Clear-ImageBox -PictureBox $PictureBox

    if ([string]::IsNullOrWhiteSpace($Filename)) {
        $StatusLabel.Text = "No image"
        return
    }

    $imagePath = Join-Path $ImagesPath $Filename

    if (!(Test-Path $imagePath)) {
        $StatusLabel.Text = "Missing: $Filename"
        return
    }

    try {
        # Load through a FileStream so the file is not locked when it later gets renamed.
        $stream = [System.IO.File]::Open($imagePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $tempImage = [System.Drawing.Image]::FromStream($stream)
            $PictureBox.Image = New-Object System.Drawing.Bitmap $tempImage
            $tempImage.Dispose()
        }
        finally {
            $stream.Close()
            $stream.Dispose()
        }

        $StatusLabel.Text = $Filename
    }
    catch {
        $StatusLabel.Text = "Could not load: $Filename"
        Add-Log "Could not load image preview for $Filename - $($_.Exception.Message)" "WARNING"
    }
}

function Format-CardDetails {
    param($Item)

    if ($null -eq $Item) {
        return "No card selected."
    }

    $back = if ([string]::IsNullOrWhiteSpace($Item.back_filename)) { "None" } else { $Item.back_filename }

    return @"
Name:  $($Item.name)
Set:   $($Item.set)
Type:  $($Item.type)
Price: $($Item.price)
Front: $($Item.filename)
Back:  $back
"@
}

function Refresh-ResultsGrid {
    param([array]$Items)

    $script:ResultsGrid.Rows.Clear()
    $script:LastMatches = @($Items)

    for ($i = 0; $i -lt $script:LastMatches.Count; $i++) {
        $item = $script:LastMatches[$i]
        $key = Get-QueueKey $item
        $alreadyQueued = $false

        foreach ($queued in $script:RemovalQueue) {
            if ((Get-QueueKey $queued) -eq $key) {
                $alreadyQueued = $true
                break
            }
        }

        $status = if ($alreadyQueued) { "Queued" } else { "" }
        [void]$script:ResultsGrid.Rows.Add(($i + 1), $item.name, $item.set, $item.type, $item.price, $item.filename, $item.back_filename, $status)
    }

    $script:ResultsCountLabel.Text = "Results: $($script:LastMatches.Count)"
}

function Refresh-QueueGrid {
    $script:QueueGrid.Rows.Clear()

    for ($i = 0; $i -lt $script:RemovalQueue.Count; $i++) {
        $item = $script:RemovalQueue[$i]
        [void]$script:QueueGrid.Rows.Add(($i + 1), $item.name, $item.set, $item.type, $item.price, $item.filename, $item.back_filename)
    }

    $script:QueueCountLabel.Text = "Queued: $($script:RemovalQueue.Count)"
}

function Get-SelectedResultItem {
    if ($script:ResultsGrid.SelectedRows.Count -eq 0) {
        return $null
    }

    $index = [int]$script:ResultsGrid.SelectedRows[0].Cells[0].Value - 1
    if ($index -lt 0 -or $index -ge $script:LastMatches.Count) {
        return $null
    }

    return $script:LastMatches[$index]
}

function Get-SelectedQueueItem {
    if ($script:QueueGrid.SelectedRows.Count -eq 0) {
        return $null
    }

    $index = [int]$script:QueueGrid.SelectedRows[0].Cells[0].Value - 1
    if ($index -lt 0 -or $index -ge $script:RemovalQueue.Count) {
        return $null
    }

    return $script:RemovalQueue[$index]
}

function Show-SelectedCardPreview {
    param($Item)

    $script:DetailsBox.Text = Format-CardDetails -Item $Item

    if ($null -eq $Item) {
        Clear-ImageBox -PictureBox $script:FrontPictureBox
        Clear-ImageBox -PictureBox $script:BackPictureBox
        $script:FrontImageLabel.Text = "No front image"
        $script:BackImageLabel.Text = "No back image"
        return
    }

    Load-ImageIntoBox -PictureBox $script:FrontPictureBox -Filename $Item.filename -StatusLabel $script:FrontImageLabel
    Load-ImageIntoBox -PictureBox $script:BackPictureBox -Filename $Item.back_filename -StatusLabel $script:BackImageLabel
}

function Search-Cards {
    $search = $script:SearchBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($search)) {
        Refresh-ResultsGrid -Items @()
        Add-Log "Enter a card name to search."
        return
    }

    # Matches original script behavior: search card name only.
    $matches = @($script:Inventory | Where-Object {
        $_.name -and $_.name.ToLower().Contains($search.ToLower())
    })

    Refresh-ResultsGrid -Items $matches
    Add-Log "Search '$search' found $($matches.Count) matching item(s)."
}

function Add-SelectedResultToQueue {
    $item = Get-SelectedResultItem

    if ($null -eq $item) {
        Add-Log "Select a result first." "WARNING"
        return
    }

    $selectedKey = Get-QueueKey $item

    foreach ($queued in $script:RemovalQueue) {
        if ((Get-QueueKey $queued) -eq $selectedKey) {
            Add-Log "That item is already in the removal queue: $($item.name)" "WARNING"
            return
        }
    }

    $message = "Add this item to the removal queue?`n`n" + (Format-CardDetails -Item $item)
    $answer = [System.Windows.Forms.MessageBox]::Show($message, "Confirm Queue Add", "YesNo", "Question")

    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        [void]$script:RemovalQueue.Add($item)
        Refresh-QueueGrid
        Refresh-ResultsGrid -Items $script:LastMatches
        Add-Log "Added to removal queue: $($item.name)"
    } else {
        Add-Log "Not added: $($item.name)"
    }
}

function Remove-SelectedQueueItem {
    $item = Get-SelectedQueueItem

    if ($null -eq $item) {
        Add-Log "Select a queued item first." "WARNING"
        return
    }

    $answer = [System.Windows.Forms.MessageBox]::Show("Remove this item from the queue only?`n`n$($item.name)", "Remove From Queue", "YesNo", "Question")

    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    $removeKey = Get-QueueKey $item

    for ($i = $script:RemovalQueue.Count - 1; $i -ge 0; $i--) {
        if ((Get-QueueKey $script:RemovalQueue[$i]) -eq $removeKey) {
            $script:RemovalQueue.RemoveAt($i)
        }
    }

    Refresh-QueueGrid
    Refresh-ResultsGrid -Items $script:LastMatches
    Add-Log "Removed from queue: $($item.name)"
}

function Rename-SoldImage {
    param([string]$Filename)

    if ([string]::IsNullOrWhiteSpace($Filename)) {
        return $null
    }

    $oldPath = Join-Path $ImagesPath $Filename

    if (!(Test-Path $oldPath)) {
        Add-Log "Image not found: images\$Filename" "WARNING"
        return $null
    }

    $directory = Split-Path $oldPath -Parent
    $nameOnly = Split-Path $oldPath -Leaf

    if ($nameOnly -like "SOLD_*") {
        Add-Log "Already marked sold: images\$nameOnly" "WARNING"
        return $nameOnly
    }

    $newName = "SOLD_$nameOnly"
    $newPath = Join-Path $directory $newName

    if (Test-Path $newPath) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $extension = [System.IO.Path]::GetExtension($nameOnly)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($nameOnly)
        $newName = "SOLD_${baseName}_$timestamp$extension"
        $newPath = Join-Path $directory $newName
        Add-Log "Sold filename already existed. Using: $newName" "WARNING"
    }

    Rename-Item -Path $oldPath -NewName $newName
    Add-Log "Renamed image: images\$Filename -> images\$newName"

    return $newName
}

function Update-ImagesJson {
    param([hashtable]$RenameMap)

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
        Add-Log "Updated images.json with renamed sold image filenames."
    }
    catch {
        Add-Log "Could not update images.json. inventory.csv was still updated. $($_.Exception.Message)" "WARNING"
    }
}

function Apply-Removals {
    if ($script:RemovalQueue.Count -eq 0) {
        Add-Log "No cards queued. No changes made." "WARNING"
        return
    }

    $summary = "This will:`n`n" +
        "1. Create a backup of inventory.csv`n" +
        "2. Remove all queued items from inventory.csv`n" +
        "3. Rename each related image with SOLD_ at the front`n" +
        "4. Update images.json if possible`n`n" +
        "Queued item(s): $($script:RemovalQueue.Count)`n`n" +
        "Continue?"

    $confirm = [System.Windows.Forms.MessageBox]::Show($summary, "Final Confirm", "YesNo", "Warning")

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Add-Log "Cancelled. No changes made."
        return
    }

    try {
        # Release preview image handles before renaming files.
        Show-SelectedCardPreview -Item $null

        $backupPath = Join-Path $Root ("inventory_backup_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".csv")
        Copy-Item -Path $CsvPath -Destination $backupPath
        Add-Log "Backup created: $(Split-Path $backupPath -Leaf)"

        $renameMap = @{}

        foreach ($item in $script:RemovalQueue) {
            Add-Log "Processing: $($item.name)"

            $newFrontName = Rename-SoldImage -Filename $item.filename
            if ($newFrontName) {
                $renameMap[$item.filename] = $newFrontName
            }

            if (![string]::IsNullOrWhiteSpace($item.back_filename)) {
                $newBackName = Rename-SoldImage -Filename $item.back_filename
                if ($newBackName) {
                    $renameMap[$item.back_filename] = $newBackName
                }
            }
        }

        $queueKeys = @{}
        foreach ($item in $script:RemovalQueue) {
            $queueKeys[(Get-QueueKey $item)] = $true
        }

        $updatedInventory = @($script:Inventory | Where-Object {
            $key = Get-QueueKey $_
            -not $queueKeys.ContainsKey($key)
        })

        $updatedInventory | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Add-Log "Updated inventory.csv. Removed $($script:RemovalQueue.Count) item(s)."

        if ($renameMap.Count -gt 0) {
            Update-ImagesJson -RenameMap $renameMap
        }

        $script:RemovalQueue.Clear()
        Load-Inventory
        Refresh-QueueGrid
        Refresh-ResultsGrid -Items @()
        $script:SearchBox.Text = ""

        Add-Log "DONE. Review the changed files in GitHub Desktop, then commit and push."
        [System.Windows.Forms.MessageBox]::Show("Done. Removed queued item(s), marked images as SOLD, and created a backup.", "Finished", "OK", "Information") | Out-Null
    }
    catch {
        Add-Log "ERROR: $($_.Exception.Message)" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("An error occurred.`n`n$($_.Exception.Message)`n`nCheck the output log before continuing.", "Error", "OK", "Error") | Out-Null
    }
}

# ---------------- GUI ----------------
Test-StartupFiles

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "Chella Collectibles - Remove Sold Card"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1280, 820)
$form.MinimumSize = New-Object System.Drawing.Size(1120, 720)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Chella Collectibles - Remove Sold Card"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(14, 12)
$form.Controls.Add($titleLabel)

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = "Search by card name, preview the front/back images, queue sold cards, then apply once."
$subtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$subtitleLabel.AutoSize = $true
$subtitleLabel.Location = New-Object System.Drawing.Point(18, 46)
$form.Controls.Add($subtitleLabel)

$searchLabel = New-Object System.Windows.Forms.Label
$searchLabel.Text = "Card name search:"
$searchLabel.AutoSize = $true
$searchLabel.Location = New-Object System.Drawing.Point(18, 82)
$form.Controls.Add($searchLabel)

$script:SearchBox = New-Object System.Windows.Forms.TextBox
$script:SearchBox.Location = New-Object System.Drawing.Point(122, 78)
$script:SearchBox.Size = New-Object System.Drawing.Size(360, 24)
$form.Controls.Add($script:SearchBox)

$searchButton = New-Object System.Windows.Forms.Button
$searchButton.Text = "Search"
$searchButton.Location = New-Object System.Drawing.Point(492, 76)
$searchButton.Size = New-Object System.Drawing.Size(90, 28)
$form.Controls.Add($searchButton)

$addButton = New-Object System.Windows.Forms.Button
$addButton.Text = "Add Selected to Queue"
$addButton.Location = New-Object System.Drawing.Point(592, 76)
$addButton.Size = New-Object System.Drawing.Size(150, 28)
$form.Controls.Add($addButton)

$removeQueueButton = New-Object System.Windows.Forms.Button
$removeQueueButton.Text = "Remove Selected from Queue"
$removeQueueButton.Location = New-Object System.Drawing.Point(752, 76)
$removeQueueButton.Size = New-Object System.Drawing.Size(180, 28)
$form.Controls.Add($removeQueueButton)

$applyButton = New-Object System.Windows.Forms.Button
$applyButton.Text = "Finish and Apply"
$applyButton.Location = New-Object System.Drawing.Point(942, 76)
$applyButton.Size = New-Object System.Drawing.Size(130, 28)
$applyButton.BackColor = [System.Drawing.Color]::FromArgb(255, 236, 236)
$form.Controls.Add($applyButton)

$quitButton = New-Object System.Windows.Forms.Button
$quitButton.Text = "Quit"
$quitButton.Location = New-Object System.Drawing.Point(1082, 76)
$quitButton.Size = New-Object System.Drawing.Size(70, 28)
$form.Controls.Add($quitButton)

$script:ResultsCountLabel = New-Object System.Windows.Forms.Label
$script:ResultsCountLabel.Text = "Results: 0"
$script:ResultsCountLabel.AutoSize = $true
$script:ResultsCountLabel.Location = New-Object System.Drawing.Point(18, 116)
$form.Controls.Add($script:ResultsCountLabel)

$script:ResultsGrid = New-Object System.Windows.Forms.DataGridView
$script:ResultsGrid.Location = New-Object System.Drawing.Point(18, 138)
$script:ResultsGrid.Size = New-Object System.Drawing.Size(760, 250)
$script:ResultsGrid.Anchor = "Top,Left,Right"
$script:ResultsGrid.AllowUserToAddRows = $false
$script:ResultsGrid.AllowUserToDeleteRows = $false
$script:ResultsGrid.ReadOnly = $true
$script:ResultsGrid.SelectionMode = "FullRowSelect"
$script:ResultsGrid.MultiSelect = $false
$script:ResultsGrid.AutoSizeColumnsMode = "Fill"
$script:ResultsGrid.RowHeadersVisible = $false
[void]$script:ResultsGrid.Columns.Add("num", "#")
[void]$script:ResultsGrid.Columns.Add("name", "Name")
[void]$script:ResultsGrid.Columns.Add("set", "Set")
[void]$script:ResultsGrid.Columns.Add("type", "Type")
[void]$script:ResultsGrid.Columns.Add("price", "Price")
[void]$script:ResultsGrid.Columns.Add("front", "Front")
[void]$script:ResultsGrid.Columns.Add("back", "Back")
[void]$script:ResultsGrid.Columns.Add("status", "Status")
$script:ResultsGrid.Columns[0].FillWeight = 25
$script:ResultsGrid.Columns[1].FillWeight = 180
$script:ResultsGrid.Columns[2].FillWeight = 95
$script:ResultsGrid.Columns[3].FillWeight = 55
$script:ResultsGrid.Columns[4].FillWeight = 50
$script:ResultsGrid.Columns[5].FillWeight = 80
$script:ResultsGrid.Columns[6].FillWeight = 80
$script:ResultsGrid.Columns[7].FillWeight = 55
$form.Controls.Add($script:ResultsGrid)

$previewGroup = New-Object System.Windows.Forms.GroupBox
$previewGroup.Text = "Selected Card Preview"
$previewGroup.Location = New-Object System.Drawing.Point(792, 116)
$previewGroup.Size = New-Object System.Drawing.Size(450, 430)
$previewGroup.Anchor = "Top,Right"
$form.Controls.Add($previewGroup)

$script:DetailsBox = New-Object System.Windows.Forms.TextBox
$script:DetailsBox.Multiline = $true
$script:DetailsBox.ReadOnly = $true
$script:DetailsBox.Location = New-Object System.Drawing.Point(14, 24)
$script:DetailsBox.Size = New-Object System.Drawing.Size(420, 92)
$script:DetailsBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$script:DetailsBox.Text = "No card selected."
$previewGroup.Controls.Add($script:DetailsBox)

$frontTitle = New-Object System.Windows.Forms.Label
$frontTitle.Text = "Front"
$frontTitle.AutoSize = $true
$frontTitle.Location = New-Object System.Drawing.Point(14, 126)
$previewGroup.Controls.Add($frontTitle)

$backTitle = New-Object System.Windows.Forms.Label
$backTitle.Text = "Back"
$backTitle.AutoSize = $true
$backTitle.Location = New-Object System.Drawing.Point(232, 126)
$previewGroup.Controls.Add($backTitle)

$script:FrontPictureBox = New-Object System.Windows.Forms.PictureBox
$script:FrontPictureBox.Location = New-Object System.Drawing.Point(14, 148)
$script:FrontPictureBox.Size = New-Object System.Drawing.Size(200, 240)
$script:FrontPictureBox.BorderStyle = "FixedSingle"
$script:FrontPictureBox.SizeMode = "Zoom"
$previewGroup.Controls.Add($script:FrontPictureBox)

$script:BackPictureBox = New-Object System.Windows.Forms.PictureBox
$script:BackPictureBox.Location = New-Object System.Drawing.Point(232, 148)
$script:BackPictureBox.Size = New-Object System.Drawing.Size(200, 240)
$script:BackPictureBox.BorderStyle = "FixedSingle"
$script:BackPictureBox.SizeMode = "Zoom"
$previewGroup.Controls.Add($script:BackPictureBox)

$script:FrontImageLabel = New-Object System.Windows.Forms.Label
$script:FrontImageLabel.Text = "No front image"
$script:FrontImageLabel.AutoEllipsis = $true
$script:FrontImageLabel.Location = New-Object System.Drawing.Point(14, 396)
$script:FrontImageLabel.Size = New-Object System.Drawing.Size(200, 20)
$previewGroup.Controls.Add($script:FrontImageLabel)

$script:BackImageLabel = New-Object System.Windows.Forms.Label
$script:BackImageLabel.Text = "No back image"
$script:BackImageLabel.AutoEllipsis = $true
$script:BackImageLabel.Location = New-Object System.Drawing.Point(232, 396)
$script:BackImageLabel.Size = New-Object System.Drawing.Size(200, 20)
$previewGroup.Controls.Add($script:BackImageLabel)

$script:QueueCountLabel = New-Object System.Windows.Forms.Label
$script:QueueCountLabel.Text = "Queued: 0"
$script:QueueCountLabel.AutoSize = $true
$script:QueueCountLabel.Location = New-Object System.Drawing.Point(18, 404)
$form.Controls.Add($script:QueueCountLabel)

$script:QueueGrid = New-Object System.Windows.Forms.DataGridView
$script:QueueGrid.Location = New-Object System.Drawing.Point(18, 426)
$script:QueueGrid.Size = New-Object System.Drawing.Size(760, 120)
$script:QueueGrid.Anchor = "Top,Left,Right"
$script:QueueGrid.AllowUserToAddRows = $false
$script:QueueGrid.AllowUserToDeleteRows = $false
$script:QueueGrid.ReadOnly = $true
$script:QueueGrid.SelectionMode = "FullRowSelect"
$script:QueueGrid.MultiSelect = $false
$script:QueueGrid.AutoSizeColumnsMode = "Fill"
$script:QueueGrid.RowHeadersVisible = $false
[void]$script:QueueGrid.Columns.Add("num", "#")
[void]$script:QueueGrid.Columns.Add("name", "Name")
[void]$script:QueueGrid.Columns.Add("set", "Set")
[void]$script:QueueGrid.Columns.Add("type", "Type")
[void]$script:QueueGrid.Columns.Add("price", "Price")
[void]$script:QueueGrid.Columns.Add("front", "Front")
[void]$script:QueueGrid.Columns.Add("back", "Back")
$script:QueueGrid.Columns[0].FillWeight = 25
$script:QueueGrid.Columns[1].FillWeight = 190
$script:QueueGrid.Columns[2].FillWeight = 100
$script:QueueGrid.Columns[3].FillWeight = 55
$script:QueueGrid.Columns[4].FillWeight = 50
$script:QueueGrid.Columns[5].FillWeight = 80
$script:QueueGrid.Columns[6].FillWeight = 80
$form.Controls.Add($script:QueueGrid)

$outputLabel = New-Object System.Windows.Forms.Label
$outputLabel.Text = "Output log:"
$outputLabel.AutoSize = $true
$outputLabel.Location = New-Object System.Drawing.Point(18, 560)
$form.Controls.Add($outputLabel)

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Location = New-Object System.Drawing.Point(18, 582)
$script:LogBox.Size = New-Object System.Drawing.Size(1224, 150)
$script:LogBox.Anchor = "Left,Right,Bottom"
$script:LogBox.Multiline = $true
$script:LogBox.ScrollBars = "Vertical"
$script:LogBox.ReadOnly = $true
$script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($script:LogBox)

$noteLabel = New-Object System.Windows.Forms.Label
$noteLabel.Text = "Important: this keeps the original behavior: queued rows are removed from inventory.csv, images are renamed with SOLD_, and a CSV backup is created."
$noteLabel.AutoSize = $true
$noteLabel.Location = New-Object System.Drawing.Point(18, 744)
$noteLabel.Anchor = "Left,Bottom"
$form.Controls.Add($noteLabel)

$searchButton.Add_Click({ Search-Cards })
$script:SearchBox.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        Search-Cards
        $_.SuppressKeyPress = $true
    }
})
$addButton.Add_Click({ Add-SelectedResultToQueue })
$removeQueueButton.Add_Click({ Remove-SelectedQueueItem })
$applyButton.Add_Click({ Apply-Removals })
$quitButton.Add_Click({ $form.Close() })

$script:ResultsGrid.Add_SelectionChanged({
    $item = Get-SelectedResultItem
    if ($null -ne $item) {
        Show-SelectedCardPreview -Item $item
    }
})

$script:QueueGrid.Add_SelectionChanged({
    $item = Get-SelectedQueueItem
    if ($null -ne $item) {
        Show-SelectedCardPreview -Item $item
    }
})

$form.Add_FormClosing({
    Clear-ImageBox -PictureBox $script:FrontPictureBox
    Clear-ImageBox -PictureBox $script:BackPictureBox
})

Load-Inventory
Refresh-ResultsGrid -Items @()
Refresh-QueueGrid

[void]$form.ShowDialog()
