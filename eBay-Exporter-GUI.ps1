# Chella Collectibles - Simplified eBay Exporter GUI
# Place this file in the same folder as inventory.csv, ebay_exporter.py, ebay_export_config.json,
# ebay_category_listing_template.csv, ebay_inventory.csv, and the templates folder.

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$CsvPath = Join-Path $Root "inventory.csv"
$EbayInventoryPath = Join-Path $Root "ebay_inventory.csv"
$ExporterPath = Join-Path $Root "ebay_exporter.py"
$ConfigPath = Join-Path $Root "ebay_export_config.json"
$TemplatePath = Join-Path $Root "ebay_category_listing_template.csv"
$DescriptionTemplatePath = Join-Path $Root "templates\ebay_description_template.html"
$OutputPath = Join-Path $Root "output"
$ArchivePath = Join-Path $OutputPath "archive"

$script:Inventory = @()
$script:EbayInventory = @()
$script:NewItems = @()
$script:MissingFromWebsite = @()

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
    $missing = New-Object System.Collections.ArrayList

    foreach ($path in @($CsvPath, $ExporterPath, $ConfigPath, $TemplatePath, $DescriptionTemplatePath)) {
        if (!(Test-Path $path)) {
            [void]$missing.Add($path)
        }
    }

    if ($missing.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show("The exporter is missing required file(s):`n`n$($missing -join "`n")", "Missing Required Files", "OK", "Error") | Out-Null
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

    $stem = [System.IO.Path]::GetFileNameWithoutExtension(($Item.filename + "")).ToUpper()
    $cleanStem = ($stem -replace "[^A-Z0-9]+", "-").Trim("-")

    return "CHELLA-$($type.ToUpper())-$cleanStem"
}

function Get-OriginalPriceDecimal {
    param($Price)

    $clean = ($Price + "").Replace("$", "").Replace(",", "").Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { return $null }

    $value = 0.0
    if ([double]::TryParse($clean, [ref]$value)) {
        return $value
    }

    return $null
}

function Get-ShippingPolicy {
    param($Item)

    $type = Normalize-Type $Item.type
    $price = Get-OriginalPriceDecimal $Item.price

    # Business rule: only raw singles priced from $0.01 through $20.00 use PWE.
    # Graded cards, sealed items, missing prices, and singles over $20 use Shipping-Normal.
    if ($type -eq "single" -and $price -ne $null -and $price -gt 0 -and $price -le 20) {
        return "Shipping-PWE"
    }

    return "Shipping-Normal"
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

function Get-WebsiteSkuSet {
    $set = @{}

    foreach ($row in $script:Inventory) {
        $filename = ($row.filename + "").Trim()
        if (![string]::IsNullOrWhiteSpace($filename)) {
            $set[(Get-Sku $row)] = $true
        }
    }

    return $set
}

function Refresh-Comparisons {
    $uploaded = Get-UploadedSkuSet
    $websiteSkus = Get-WebsiteSkuSet

    $script:NewItems = @($script:Inventory | Where-Object {
        $filename = ($_.filename + "").Trim()
        if ([string]::IsNullOrWhiteSpace($filename)) { return $false }
        $sku = Get-Sku $_
        return !$uploaded.ContainsKey($sku)
    })

    $script:MissingFromWebsite = @($script:EbayInventory | Where-Object {
        $sku = ($_.sku + "").Trim()
        if ([string]::IsNullOrWhiteSpace($sku)) { return $false }
        return !$websiteSkus.ContainsKey($sku)
    })
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

    Refresh-Comparisons
    Refresh-Stats
    Refresh-Grids
}

function Refresh-Stats {
    $total = $script:Inventory.Count
    $tracked = $script:EbayInventory.Count
    $new = $script:NewItems.Count
    $missing = $script:MissingFromWebsite.Count

    $newPwe = @($script:NewItems | Where-Object { (Get-ShippingPolicy $_) -eq "Shipping-PWE" }).Count
    $newNormal = @($script:NewItems | Where-Object { (Get-ShippingPolicy $_) -eq "Shipping-Normal" }).Count

    $script:StatsLabel.Text = "Website inventory: $total    Tracked on eBay: $tracked    New to export: $new    PWE: $newPwe    Normal: $newNormal    eBay tracked but missing from website: $missing"
}

function Refresh-Grids {
    $script:NewGrid.Rows.Clear()

    foreach ($item in $script:NewItems) {
        [void]$script:NewGrid.Rows.Add((Get-Sku $item), (Get-ShippingPolicy $item), (Normalize-Type $item.type), $item.name, $item.set, $item.price, $item.filename)
    }

    $script:MissingGrid.Rows.Clear()

    foreach ($item in $script:MissingFromWebsite) {
        [void]$script:MissingGrid.Rows.Add($item.sku, $item.type, $item.name, $item.set, $item.price, $item.filename, $item.date_added_to_ebay)
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
            if (![string]::IsNullOrWhiteSpace($line)) { Add-Log $line }
        }
    }

    if (![string]::IsNullOrWhiteSpace($stderr)) {
        foreach ($line in ($stderr -split "`r?`n")) {
            if (![string]::IsNullOrWhiteSpace($line)) { Add-Log $line "ERROR" }
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

function Remove-ExtraExportFiles {
    param(
        [string[]]$PathsToRemove
    )

    foreach ($path in $PathsToRemove) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (Test-Path $path) {
            try {
                Remove-Item -Path $path -Force
                Add-Log "Removed extra export file: $path"
            } catch {
                Add-Log "Could not remove extra export file: $path - $($_.Exception.Message)" "WARN"
            }
        }
    }
}

function Generate-NewUpload {
    Load-Data

    if ($script:NewItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("There are no new website items to export. Everything in inventory.csv is already tracked in ebay_inventory.csv.", "No New Items", "OK", "Information") | Out-Null
        Add-Log "No new items to export."
        return
    }

    $countBefore = $script:NewItems.Count
    $success = Run-Exporter -Arguments @("--new-only", "--action", "Add", "--auto-track-exported") -FriendlyName "Export New Website Items"
    if (!$success) { return }

    $generated = Join-Path $OutputPath "ebay_listing_Add_NEW_ONLY.csv"
    $review = Join-Path $OutputPath "ebay_review_Add_NEW_ONLY.csv"
    $pending = Join-Path $OutputPath "ebay_pending_upload_Add_NEW_ONLY.csv"
    $clean = Join-Path $OutputPath "ebay_upload_new_items.csv"

    if (Copy-CleanOutput -GeneratedPath $generated -CleanPath $clean) {
        Remove-ExtraExportFiles -PathsToRemove @($generated, $review, $pending)
        [System.Windows.Forms.MessageBox]::Show("Created eBay upload CSV:`n`n$clean`n`n$countBefore item(s) were also automatically written to ebay_inventory.csv so they are now tracked as listed.", "Upload CSV Created", "OK", "Information") | Out-Null
        Start-Process $OutputPath
    }

    Load-Data
    $tabs.SelectedTab = $logTab
}


function Remove-SelectedMissingFromTracking {
    if ($script:MissingGrid.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select one or more rows in the 'eBay Items Missing From Website' tab first.", "No Items Selected", "OK", "Information") | Out-Null
        Add-Log "No missing eBay rows selected for removal."
        return
    }

    $selectedSkus = @{}
    foreach ($row in $script:MissingGrid.SelectedRows) {
        if ($row.IsNewRow) { continue }
        $sku = ($row.Cells["SKU"].Value + "").Trim()
        if (![string]::IsNullOrWhiteSpace($sku)) {
            $selectedSkus[$sku] = $true
        }
    }

    if ($selectedSkus.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No valid SKU values were selected.", "No SKUs Selected", "OK", "Information") | Out-Null
        Add-Log "Selected rows did not contain valid SKUs." "ERROR"
        return
    }

    $allRows = @(Import-Csv $EbayInventoryPath)
    $remainingRows = @($allRows | Where-Object {
        $sku = ($_.sku + "").Trim()
        return !$selectedSkus.ContainsKey($sku)
    })

    $headers = @("sku", "filename", "type", "name", "set", "price", "date_added_to_ebay", "notes")

    if ($remainingRows.Count -gt 0) {
        $remainingRows |
            Select-Object $headers |
            Export-Csv -Path $EbayInventoryPath -NoTypeInformation -Encoding UTF8
    }
    else {
        ($headers -join ",") | Out-File -FilePath $EbayInventoryPath -Encoding UTF8
    }

    $removedCount = $allRows.Count - $remainingRows.Count
    Add-Log "Removed $removedCount selected SKU(s) from ebay_inventory.csv."

    Load-Data
    $tabs.SelectedTab = $missingTab

    [System.Windows.Forms.MessageBox]::Show("Removed $removedCount selected item(s) from ebay_inventory.csv.", "eBay Tracker Updated", "OK", "Information") | Out-Null
}

# UI
Ensure-Files

$form = New-Object System.Windows.Forms.Form
$form.Text = "Chella Collectibles - eBay Exporter"
$form.Size = New-Object System.Drawing.Size(1220, 760)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(1080, 680)
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 247, 250)

# Menu
$menu = New-Object System.Windows.Forms.MenuStrip

$fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem("File")
$fileOpenOutput = New-Object System.Windows.Forms.ToolStripMenuItem("Open Output Folder")
$fileOpenInventory = New-Object System.Windows.Forms.ToolStripMenuItem("Open Website Inventory CSV")
$fileOpenTracking = New-Object System.Windows.Forms.ToolStripMenuItem("Open eBay Inventory CSV")
$fileExit = New-Object System.Windows.Forms.ToolStripMenuItem("Exit")

$fileMenu.DropDownItems.Add($fileOpenOutput) | Out-Null
$fileMenu.DropDownItems.Add($fileOpenInventory) | Out-Null
$fileMenu.DropDownItems.Add($fileOpenTracking) | Out-Null
$fileMenu.DropDownItems.Add("-") | Out-Null
$fileMenu.DropDownItems.Add($fileExit) | Out-Null

$toolsMenu = New-Object System.Windows.Forms.ToolStripMenuItem("Tools")
$toolsRefresh = New-Object System.Windows.Forms.ToolStripMenuItem("Refresh Inventory")
$toolsMenu.DropDownItems.Add($toolsRefresh) | Out-Null

$menu.Items.Add($fileMenu) | Out-Null
$menu.Items.Add($toolsMenu) | Out-Null
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
$script:StatusLabel.Size = New-Object System.Drawing.Size(480, 24)
$script:StatusLabel.TextAlign = "MiddleRight"
$form.Controls.Add($script:StatusLabel)

$script:StatsLabel = New-Object System.Windows.Forms.Label
$script:StatsLabel.Text = "Loading..."
$script:StatsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$script:StatsLabel.ForeColor = [System.Drawing.Color]::FromArgb(45, 58, 82)
$script:StatsLabel.Location = New-Object System.Drawing.Point(22, 82)
$script:StatsLabel.Size = New-Object System.Drawing.Size(1160, 24)
$form.Controls.Add($script:StatsLabel)

$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Location = New-Object System.Drawing.Point(18, 118)
$buttonPanel.Size = New-Object System.Drawing.Size(1168, 90)
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

$refreshBtn = New-MainButton "Refresh Inventory" 22 230
$generateBtn = New-MainButton "Export New Items to eBay CSV" 276 360
$openOutputBtn = New-MainButton "Open Output Folder" 660 210
$removeMissingBtn = New-MainButton "Remove eBay Items Missing From Website" 890 255

$buttonPanel.Controls.Add($refreshBtn)
$buttonPanel.Controls.Add($generateBtn)
$buttonPanel.Controls.Add($openOutputBtn)
$buttonPanel.Controls.Add($removeMissingBtn)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(18, 224)
$tabs.Size = New-Object System.Drawing.Size(1168, 420)
$tabs.Anchor = "Top,Left,Right,Bottom"
$form.Controls.Add($tabs)

$newTab = New-Object System.Windows.Forms.TabPage
$newTab.Text = "Website Items Not On eBay"

$missingTab = New-Object System.Windows.Forms.TabPage
$missingTab.Text = "eBay Items Missing From Website"

$logTab = New-Object System.Windows.Forms.TabPage
$logTab.Text = "Log"

$tabs.TabPages.Add($newTab) | Out-Null
$tabs.TabPages.Add($missingTab) | Out-Null
$tabs.TabPages.Add($logTab) | Out-Null

$script:NewGrid = New-Object System.Windows.Forms.DataGridView
$script:NewGrid.Dock = "Fill"
$script:NewGrid.ReadOnly = $true
$script:NewGrid.AllowUserToAddRows = $false
$script:NewGrid.SelectionMode = "FullRowSelect"
$script:NewGrid.AutoSizeColumnsMode = "Fill"
@("SKU", "Shipping Policy", "Type", "Name", "Set", "Price", "Filename") | ForEach-Object {
    [void]$script:NewGrid.Columns.Add($_, $_)
}
$newTab.Controls.Add($script:NewGrid)

$script:MissingGrid = New-Object System.Windows.Forms.DataGridView
$script:MissingGrid.Dock = "Fill"
$script:MissingGrid.ReadOnly = $true
$script:MissingGrid.AllowUserToAddRows = $false
$script:MissingGrid.SelectionMode = "FullRowSelect"
$script:MissingGrid.MultiSelect = $true
$script:MissingGrid.AutoSizeColumnsMode = "Fill"
@("SKU", "Type", "Name", "Set", "Price", "Filename", "Date Added To eBay") | ForEach-Object {
    [void]$script:MissingGrid.Columns.Add($_, $_)
}
$missingTab.Controls.Add($script:MissingGrid)

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Dock = "Fill"
$script:LogBox.Multiline = $true
$script:LogBox.ScrollBars = "Vertical"
$script:LogBox.ReadOnly = $true
$script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$logTab.Controls.Add($script:LogBox)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = "Workflow: Refresh → Export New Items to eBay CSV → upload output/ebay_upload_new_items.csv to eBay. Select missing website rows and click Remove to clean ebay_inventory.csv."
$footer.Location = New-Object System.Drawing.Point(22, 660)
$footer.Size = New-Object System.Drawing.Size(1150, 44)
$footer.Anchor = "Left,Right,Bottom"
$footer.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$footer.ForeColor = [System.Drawing.Color]::FromArgb(70, 83, 109)
$form.Controls.Add($footer)

# Button events
$refreshBtn.Add_Click({
    Load-Data
    Add-Log "Refreshed inventory and eBay tracking."
})

$generateBtn.Add_Click({
    Generate-NewUpload
})

$openOutputBtn.Add_Click({
    if (!(Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath | Out-Null }
    Start-Process $OutputPath
})

$removeMissingBtn.Add_Click({
    Remove-SelectedMissingFromTracking
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
    Add-Log "Refreshed inventory and eBay tracking."
})

Load-Data
Add-Log "Ready. Simplified eBay Exporter loaded."
[void]$form.ShowDialog()
