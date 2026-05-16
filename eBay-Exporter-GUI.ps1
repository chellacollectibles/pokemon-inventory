# Chella Collectibles - Simple eBay Exporter GUI
# Place this file in the same folder as inventory.csv.

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$CsvPath = Join-Path $Root "inventory.csv"
$EbayInventoryPath = Join-Path $Root "ebay_inventory.csv"
$ExporterPath = Join-Path $Root "ebay_exporter.py"
$OutputPath = Join-Path $Root "output"
$ArchivePath = Join-Path $OutputPath "archive"

$script:Inventory = @()
$script:EbayInventory = @()
$script:NewItems = @()
$script:LastFailures = @()

function Add-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"

    if ($script:LogBox -ne $null) {
        $script:LogBox.AppendText($line + [Environment]::NewLine)
        $script:LogBox.SelectionStart = $script:LogBox.Text.Length
        $script:LogBox.ScrollToCaret()
    }
}

function Ensure-Files {
    if (!(Test-Path $CsvPath)) {
        [System.Windows.Forms.MessageBox]::Show("inventory.csv was not found in this folder.`n`nExpected:`n$CsvPath", "Missing inventory.csv", "OK", "Error") | Out-Null
        exit 1
    }

    if (!(Test-Path $ExporterPath)) {
        [System.Windows.Forms.MessageBox]::Show("ebay_exporter.py was not found in this folder.`n`nExpected:`n$ExporterPath", "Missing exporter", "OK", "Error") | Out-Null
        exit 1
    }

    if (!(Test-Path $EbayInventoryPath)) {
        "sku,filename,type,name,set,price,date_added_to_ebay,notes" | Out-File -FilePath $EbayInventoryPath -Encoding utf8
    }

    if (!(Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath | Out-Null
    }

    if (!(Test-Path $ArchivePath)) {
        New-Item -ItemType Directory -Path $ArchivePath | Out-Null
    }
}

function Normalize-Type {
    param([string]$Type)

    $clean = ($Type + "").Trim().ToLower()

    if ($clean -eq "singles") { return "single" }
    if ($clean -eq "single") { return "single" }
    if ($clean -eq "graded cards") { return "graded" }
    if ($clean -eq "graded") { return "graded" }
    if ($clean -eq "sealed products") { return "sealed" }
    if ($clean -eq "sealed") { return "sealed" }

    return $clean
}

function Get-Sku {
    param($Item)

    $type = Normalize-Type $Item.type
    if ([string]::IsNullOrWhiteSpace($type)) { $type = "ITEM" }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($Item.filename).ToUpper()
    $cleanStem = ($stem -replace "[^A-Z0-9]+", "-").Trim("-")

    return "CHELLA-$($type.ToUpper())-$cleanStem"
}

function Load-Data {
    Ensure-Files

    try {
        $script:Inventory = @(Import-Csv $CsvPath)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not load inventory.csv.`n`n$($_.Exception.Message)", "Inventory Load Error", "OK", "Error") | Out-Null
        return
    }

    try {
        $script:EbayInventory = @(Import-Csv $EbayInventoryPath)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not load ebay_inventory.csv.`n`n$($_.Exception.Message)", "eBay Tracking Load Error", "OK", "Error") | Out-Null
        return
    }

    Refresh-NewItems
    Refresh-Stats
    Refresh-Grids
}

function Get-UploadedSkuSet {
    $set = @{}

    foreach ($row in $script:EbayInventory) {
        $sku = ($row.sku + "").Trim()
        if (![string]::IsNullOrWhiteSpace($sku)) {
            $set[$sku] = $true
        }
    }

    return $set
}

function Refresh-NewItems {
    $uploaded = Get-UploadedSkuSet

    $script:NewItems = @($script:Inventory | Where-Object {
        $sku = Get-Sku $_
        !$uploaded.ContainsKey($sku)
    })
}

function Refresh-Stats {
    $total = $script:Inventory.Count
    $tracked = $script:EbayInventory.Count
    $new = $script:NewItems.Count

    $newSingles = @($script:NewItems | Where-Object { (Normalize-Type $_.type) -eq "single" }).Count
    $newGraded = @($script:NewItems | Where-Object { (Normalize-Type $_.type) -eq "graded" }).Count
    $newSealed = @($script:NewItems | Where-Object { (Normalize-Type $_.type) -eq "sealed" }).Count

    $script:StatsLabel.Text = "Website inventory: $total    Tracked on eBay: $tracked    New to upload: $new    Singles: $newSingles    Graded: $newGraded    Sealed: $newSealed"
}

function Refresh-Grids {
    $script:NewGrid.Rows.Clear()

    foreach ($item in $script:NewItems) {
        [void]$script:NewGrid.Rows.Add((Get-Sku $item), $item.type, $item.name, $item.set, $item.price, $item.filename)
    }

    $script:FailureGrid.Rows.Clear()

    foreach ($failure in $script:LastFailures) {
        [void]$script:FailureGrid.Rows.Add($failure.LineNumber, $failure.SKU, $failure.Status, $failure.ErrorCode, $failure.ErrorMessage)
    }
}

function Get-PythonCommand {
    $pyCommand = Get-Command py -ErrorAction SilentlyContinue
    if ($null -ne $pyCommand) { return "py" }

    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $pythonCommand) { return "python" }

    return $null
}

function Run-Exporter {
    param(
        [string[]]$Arguments,
        [string]$FriendlyName
    )

    $python = Get-PythonCommand

    if ($null -eq $python) {
        [System.Windows.Forms.MessageBox]::Show("Python was not found.`n`nInstall Python from python.org and check 'Add python.exe to PATH'.", "Python Missing", "OK", "Error") | Out-Null
        Add-Log "Python was not found." "ERROR"
        return $false
    }

    $script:StatusLabel.Text = "Running: $FriendlyName..."
    $script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(40, 107, 216)
    $form.Refresh()

    Add-Log "Running: $FriendlyName"
    Add-Log "$python ebay_exporter.py $($Arguments -join ' ')"

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $python
    $processInfo.WorkingDirectory = $Root
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true
    $processInfo.Arguments = "ebay_exporter.py " + ($Arguments -join " ")

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo

    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if (![string]::IsNullOrWhiteSpace($stdout)) {
        foreach ($line in ($stdout -split "`r?`n")) {
            if (![string]::IsNullOrWhiteSpace($line)) {
                Add-Log $line
            }
        }
    }

    if (![string]::IsNullOrWhiteSpace($stderr)) {
        foreach ($line in ($stderr -split "`r?`n")) {
            if (![string]::IsNullOrWhiteSpace($line)) {
                Add-Log $line "ERROR"
            }
        }
    }

    if ($process.ExitCode -ne 0) {
        $script:StatusLabel.Text = "Failed: $FriendlyName"
        $script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 35, 35)
        [System.Windows.Forms.MessageBox]::Show("$FriendlyName failed. Check the Log tab for details.", "Exporter Failed", "OK", "Error") | Out-Null
        return $false
    }

    $script:StatusLabel.Text = "Completed: $FriendlyName"
    $script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(22, 128, 65)
    Add-Log "Completed: $FriendlyName"
    return $true
}

function Archive-IfExists {
    param([string]$PathToArchive)

    if (Test-Path $PathToArchive) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($PathToArchive)
        $ext = [System.IO.Path]::GetExtension($PathToArchive)
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $target = Join-Path $ArchivePath "$name-$stamp$ext"
        Move-Item -Path $PathToArchive -Destination $target -Force
        Add-Log "Archived old file: $target"
    }
}

function Copy-CleanOutput {
    param(
        [string]$GeneratedPath,
        [string]$CleanPath
    )

    if (!(Test-Path $GeneratedPath)) {
        Add-Log "Expected generated file not found: $GeneratedPath" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Expected generated file not found:`n$GeneratedPath", "Missing Output", "OK", "Error") | Out-Null
        return $false
    }

    Archive-IfExists -PathToArchive $CleanPath
    Copy-Item -Path $GeneratedPath -Destination $CleanPath -Force
    Add-Log "Created clean upload file: $CleanPath"
    return $true
}

function Generate-NewUpload {
    Load-Data

    if ($script:NewItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("There are no new items to upload. Everything in inventory.csv is already tracked in ebay_inventory.csv.", "No New Items", "OK", "Information") | Out-Null
        Add-Log "No new items to upload."
        return
    }

    $success = Run-Exporter -Arguments @("--new-only", "--action", "Add") -FriendlyName "Generate New Items Upload CSV"
    if (!$success) { return }

    $generated = Join-Path $OutputPath "ebay_listing_Add_NEW_ONLY.csv"
    $clean = Join-Path $OutputPath "ebay_upload_new_items.csv"

    if (Copy-CleanOutput -GeneratedPath $generated -CleanPath $clean) {
        [System.Windows.Forms.MessageBox]::Show("Upload this file to eBay:`n`n$clean`n`nAfter eBay processes it, download the result report and click Import eBay Result Report.", "Upload CSV Created", "OK", "Information") | Out-Null
        Start-Process $OutputPath
    }

    Load-Data
}

function Generate-FullUpload {
    Load-Data

    $confirm = [System.Windows.Forms.MessageBox]::Show("This creates an upload CSV for your FULL inventory.`n`nOnly use this for the first-time full upload or special cases.`n`nContinue?", "Generate Full Inventory Upload", "YesNo", "Warning")
    if ($confirm -ne "Yes") { return }

    $success = Run-Exporter -Arguments @("--full", "--action", "Add") -FriendlyName "Generate Full Inventory Upload CSV"
    if (!$success) { return }

    $generated = Join-Path $OutputPath "ebay_listing_Add_FULL.csv"
    $clean = Join-Path $OutputPath "ebay_upload_full_inventory.csv"

    if (Copy-CleanOutput -GeneratedPath $generated -CleanPath $clean) {
        [System.Windows.Forms.MessageBox]::Show("Upload this file to eBay:`n`n$clean`n`nAfter eBay processes it, download the result report and click Import eBay Result Report.", "Full Upload CSV Created", "OK", "Information") | Out-Null
        Start-Process $OutputPath
    }

    Load-Data
}

function Get-InventoryBySku {
    $map = @{}

    foreach ($item in $script:Inventory) {
        $sku = Get-Sku $item
        if (![string]::IsNullOrWhiteSpace($sku)) {
            $map[$sku] = $item
        }
    }

    return $map
}

function Import-EbayResultReport {
    Load-Data

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select eBay result report CSV"
    $dialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
    $dialog.InitialDirectory = $OutputPath

    if ($dialog.ShowDialog() -ne "OK") {
        return
    }

    $resultPath = $dialog.FileName

    try {
        $resultRows = @(Import-Csv $resultPath)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not read selected CSV.`n`n$($_.Exception.Message)", "Import Error", "OK", "Error") | Out-Null
        return
    }

    if ($resultRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("The selected result file appears to be empty.", "Empty Result", "OK", "Warning") | Out-Null
        return
    }

    $inventoryBySku = Get-InventoryBySku
    $existing = Get-UploadedSkuSet
    $successRows = New-Object System.Collections.ArrayList
    $failedRows = New-Object System.Collections.ArrayList
    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    foreach ($row in $resultRows) {
        $status = ($row.Status + "").Trim()
        $sku = ($row.CustomLabel + "").Trim()

        if ([string]::IsNullOrWhiteSpace($sku)) {
            $sku = ($row.ApplicationData + "").Trim()
        }

        if ($status -eq "Success") {
            if (![string]::IsNullOrWhiteSpace($sku) -and !$existing.ContainsKey($sku)) {
                $item = $null
                if ($inventoryBySku.ContainsKey($sku)) {
                    $item = $inventoryBySku[$sku]
                }

                [void]$successRows.Add([pscustomobject]@{
                    sku = $sku
                    filename = if ($item -ne $null) { $item.filename } else { "" }
                    type = if ($item -ne $null) { Normalize-Type $item.type } else { "" }
                    name = if ($item -ne $null) { $item.name } else { "" }
                    set = if ($item -ne $null) { $item.set } else { "" }
                    price = if ($item -ne $null) { $item.price } else { "" }
                    date_added_to_ebay = $now
                    notes = "Imported from eBay result report: $([System.IO.Path]::GetFileName($resultPath))"
                })

                $existing[$sku] = $true
            }
        }
        else {
            [void]$failedRows.Add([pscustomobject]@{
                LineNumber = $row.'Line Number'
                SKU = $sku
                Status = $status
                ErrorCode = $row.ErrorCode
                ErrorMessage = $row.ErrorMessage
            })
        }
    }

    if ($successRows.Count -gt 0) {
        $successRows | Export-Csv -Path $EbayInventoryPath -Append -NoTypeInformation -Encoding UTF8
    }

    $script:LastFailures = @($failedRows)

    $failedPath = Join-Path $OutputPath "ebay_failed_uploads.csv"
    $summaryPath = Join-Path $OutputPath "ebay_last_result_summary.csv"

    $failedRows | Export-Csv -Path $failedPath -NoTypeInformation -Encoding UTF8

    $summary = @(
        [pscustomobject]@{
            result_file = $resultPath
            imported_successes = $successRows.Count
            failures = $failedRows.Count
            imported_at = $now
        }
    )

    $summary | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding UTF8

    Add-Log "Imported result report: $resultPath"
    Add-Log "Successful SKUs added to tracking: $($successRows.Count)"
    Add-Log "Failures found: $($failedRows.Count)"

    Load-Data
    $script:LastFailures = @($failedRows)
    Refresh-Grids

    [System.Windows.Forms.MessageBox]::Show("Result import complete.`n`nSuccesses added to tracking: $($successRows.Count)`nFailures: $($failedRows.Count)`n`nFailure report:`n$failedPath", "Result Imported", "OK", "Information") | Out-Null

    if ($failedRows.Count -gt 0) {
        $tabs.SelectedTab = $failuresTab
    }
}

function Mark-FullInventoryListed {
    Load-Data

    $confirm = [System.Windows.Forms.MessageBox]::Show("This marks EVERY current inventory.csv item as already listed on eBay.`n`nOnly use this if your current website inventory is already synced/live on eBay.`n`nContinue?", "Advanced: Mark Current Inventory Listed", "YesNo", "Warning")
    if ($confirm -ne "Yes") { return }

    $existing = Get-UploadedSkuSet
    $rows = New-Object System.Collections.ArrayList
    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    foreach ($item in $script:Inventory) {
        $sku = Get-Sku $item
        if (!$existing.ContainsKey($sku)) {
            [void]$rows.Add([pscustomobject]@{
                sku = $sku
                filename = $item.filename
                type = Normalize-Type $item.type
                name = $item.name
                set = $item.set
                price = $item.price
                date_added_to_ebay = $now
                notes = "Marked current inventory listed from GUI"
            })
            $existing[$sku] = $true
        }
    }

    if ($rows.Count -gt 0) {
        $rows | Export-Csv -Path $EbayInventoryPath -Append -NoTypeInformation -Encoding UTF8
    }

    Add-Log "Marked current inventory as listed. Added $($rows.Count) SKU(s)."
    Load-Data
}

function Clear-EbayTracking {
    $confirm = [System.Windows.Forms.MessageBox]::Show("This clears ebay_inventory.csv and makes the tool think NOTHING is listed on eBay.`n`nOnly do this if you really want to reset tracking.`n`nContinue?", "Advanced: Clear eBay Tracking", "YesNo", "Warning")
    if ($confirm -ne "Yes") { return }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = Join-Path $ArchivePath "ebay_inventory-backup-$stamp.csv"
    Copy-Item -Path $EbayInventoryPath -Destination $backup -Force

    "sku,filename,type,name,set,price,date_added_to_ebay,notes" | Out-File -FilePath $EbayInventoryPath -Encoding utf8

    Add-Log "Cleared ebay_inventory.csv. Backup saved to: $backup"
    Load-Data
}

# UI
Ensure-Files

$form = New-Object System.Windows.Forms.Form
$form.Text = "Chella Collectibles - Simple eBay Exporter"
$form.Size = New-Object System.Drawing.Size(1200, 760)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(1080, 680)
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 247, 250)

# Menu
$menu = New-Object System.Windows.Forms.MenuStrip

$fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem("File")
$fileOpenOutput = New-Object System.Windows.Forms.ToolStripMenuItem("Open Output Folder")
$fileOpenInventory = New-Object System.Windows.Forms.ToolStripMenuItem("Open Website Inventory CSV")
$fileOpenTracking = New-Object System.Windows.Forms.ToolStripMenuItem("Open eBay Tracking CSV")
$fileExit = New-Object System.Windows.Forms.ToolStripMenuItem("Exit")

$fileMenu.DropDownItems.Add($fileOpenOutput) | Out-Null
$fileMenu.DropDownItems.Add($fileOpenInventory) | Out-Null
$fileMenu.DropDownItems.Add($fileOpenTracking) | Out-Null
$fileMenu.DropDownItems.Add("-") | Out-Null
$fileMenu.DropDownItems.Add($fileExit) | Out-Null

$toolsMenu = New-Object System.Windows.Forms.ToolStripMenuItem("Tools")
$toolsRefresh = New-Object System.Windows.Forms.ToolStripMenuItem("Refresh Inventory")
$toolsImportResult = New-Object System.Windows.Forms.ToolStripMenuItem("Import eBay Result Report")
$toolsMenu.DropDownItems.Add($toolsRefresh) | Out-Null
$toolsMenu.DropDownItems.Add($toolsImportResult) | Out-Null

$advancedMenu = New-Object System.Windows.Forms.ToolStripMenuItem("Advanced")
$advancedGenerateFull = New-Object System.Windows.Forms.ToolStripMenuItem("Generate Full Inventory Upload CSV")
$advancedMarkListed = New-Object System.Windows.Forms.ToolStripMenuItem("Mark Current Website Inventory As Already Listed")
$advancedClearTracking = New-Object System.Windows.Forms.ToolStripMenuItem("Clear eBay Tracking File")
$advancedMenu.DropDownItems.Add($advancedGenerateFull) | Out-Null
$advancedMenu.DropDownItems.Add($advancedMarkListed) | Out-Null
$advancedMenu.DropDownItems.Add($advancedClearTracking) | Out-Null

$menu.Items.Add($fileMenu) | Out-Null
$menu.Items.Add($toolsMenu) | Out-Null
$menu.Items.Add($advancedMenu) | Out-Null
$form.MainMenuStrip = $menu
$form.Controls.Add($menu)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Chella Collectibles eBay Exporter"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(7, 20, 47)
$title.Location = New-Object System.Drawing.Point(18, 40)
$title.Size = New-Object System.Drawing.Size(640, 38)
$form.Controls.Add($title)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = "Ready"
$script:StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(22, 128, 65)
$script:StatusLabel.Location = New-Object System.Drawing.Point(700, 48)
$script:StatusLabel.Size = New-Object System.Drawing.Size(460, 24)
$script:StatusLabel.TextAlign = "MiddleRight"
$form.Controls.Add($script:StatusLabel)

$script:StatsLabel = New-Object System.Windows.Forms.Label
$script:StatsLabel.Text = "Loading..."
$script:StatsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$script:StatsLabel.ForeColor = [System.Drawing.Color]::FromArgb(45, 58, 82)
$script:StatsLabel.Location = New-Object System.Drawing.Point(22, 82)
$script:StatsLabel.Size = New-Object System.Drawing.Size(1140, 24)
$form.Controls.Add($script:StatsLabel)

$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Location = New-Object System.Drawing.Point(18, 118)
$buttonPanel.Size = New-Object System.Drawing.Size(1148, 90)
$buttonPanel.Anchor = "Top,Left,Right"
$buttonPanel.BackColor = [System.Drawing.Color]::White
$buttonPanel.BorderStyle = "FixedSingle"
$form.Controls.Add($buttonPanel)

function New-MainButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$W = 250
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, 20)
    $btn.Size = New-Object System.Drawing.Size($W, 48)
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    return $btn
}

$refreshBtn = New-MainButton "1. Refresh Inventory" 22 210
$generateBtn = New-MainButton "2. Generate eBay Upload CSV" 252 300
$importBtn = New-MainButton "3. Import eBay Result Report" 572 300

$buttonPanel.Controls.Add($refreshBtn)
$buttonPanel.Controls.Add($generateBtn)
$buttonPanel.Controls.Add($importBtn)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(18, 224)
$tabs.Size = New-Object System.Drawing.Size(1148, 420)
$tabs.Anchor = "Top,Left,Right,Bottom"
$form.Controls.Add($tabs)

$newTab = New-Object System.Windows.Forms.TabPage
$newTab.Text = "New Items To Upload"

$failuresTab = New-Object System.Windows.Forms.TabPage
$failuresTab.Text = "Last Upload Failures"

$logTab = New-Object System.Windows.Forms.TabPage
$logTab.Text = "Log"

$tabs.TabPages.Add($newTab) | Out-Null
$tabs.TabPages.Add($failuresTab) | Out-Null
$tabs.TabPages.Add($logTab) | Out-Null

$script:NewGrid = New-Object System.Windows.Forms.DataGridView
$script:NewGrid.Dock = "Fill"
$script:NewGrid.ReadOnly = $true
$script:NewGrid.AllowUserToAddRows = $false
$script:NewGrid.SelectionMode = "FullRowSelect"
$script:NewGrid.AutoSizeColumnsMode = "Fill"
@("SKU", "Type", "Name", "Set", "Price", "Filename") | ForEach-Object {
    [void]$script:NewGrid.Columns.Add($_, $_)
}
$newTab.Controls.Add($script:NewGrid)

$script:FailureGrid = New-Object System.Windows.Forms.DataGridView
$script:FailureGrid.Dock = "Fill"
$script:FailureGrid.ReadOnly = $true
$script:FailureGrid.AllowUserToAddRows = $false
$script:FailureGrid.SelectionMode = "FullRowSelect"
$script:FailureGrid.AutoSizeColumnsMode = "Fill"
@("Line", "SKU", "Status", "Error Code", "Error Message") | ForEach-Object {
    [void]$script:FailureGrid.Columns.Add($_, $_)
}
$failuresTab.Controls.Add($script:FailureGrid)

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Dock = "Fill"
$script:LogBox.Multiline = $true
$script:LogBox.ScrollBars = "Vertical"
$script:LogBox.ReadOnly = $true
$script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$logTab.Controls.Add($script:LogBox)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = "Normal workflow: Refresh → Generate eBay Upload CSV → upload output/ebay_upload_new_items.csv → Import eBay Result Report."
$footer.Location = New-Object System.Drawing.Point(22, 660)
$footer.Size = New-Object System.Drawing.Size(1120, 28)
$footer.Anchor = "Left,Right,Bottom"
$footer.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$footer.ForeColor = [System.Drawing.Color]::FromArgb(70, 83, 109)
$form.Controls.Add($footer)

# Button events
$refreshBtn.Add_Click({
    Load-Data
    Add-Log "Refreshed inventory and tracking."
})

$generateBtn.Add_Click({
    Generate-NewUpload
    $tabs.SelectedTab = $logTab
})

$importBtn.Add_Click({
    Import-EbayResultReport
})

# Menu events
$fileOpenOutput.Add_Click({
    if (!(Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath | Out-Null }
    Start-Process $OutputPath
})

$fileOpenInventory.Add_Click({
    Start-Process $CsvPath
})

$fileOpenTracking.Add_Click({
    Start-Process $EbayInventoryPath
})

$fileExit.Add_Click({
    $form.Close()
})

$toolsRefresh.Add_Click({
    Load-Data
    Add-Log "Refreshed inventory and tracking."
})

$toolsImportResult.Add_Click({
    Import-EbayResultReport
})

$advancedGenerateFull.Add_Click({
    Generate-FullUpload
    $tabs.SelectedTab = $logTab
})

$advancedMarkListed.Add_Click({
    Mark-FullInventoryListed
})

$advancedClearTracking.Add_Click({
    Clear-EbayTracking
})

Load-Data
Add-Log "Ready. Simple eBay Exporter loaded."
[void]$form.ShowDialog()
