# Chella Collectibles - eBay Exporter GUI
# GUI wrapper for the proven eBay exporter backend.
# Place this file in the same folder as inventory.csv.

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$CsvPath = Join-Path $Root "inventory.csv"
$EbayInventoryPath = Join-Path $Root "ebay_inventory.csv"
$ExporterPath = Join-Path $Root "ebay_exporter.py"
$OutputPath = Join-Path $Root "output"

$script:Inventory = @()
$script:EbayInventory = @()
$script:NewItems = @()

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

    $script:StatsLabel.Text = "Website inventory: $total    Tracked on eBay: $tracked    New to upload: $new    New Singles: $newSingles    New Graded: $newGraded    New Sealed: $newSealed"
}

function Refresh-Grids {
    $script:NewGrid.Rows.Clear()
    foreach ($item in $script:NewItems) {
        [void]$script:NewGrid.Rows.Add((Get-Sku $item), $item.type, $item.name, $item.set, $item.price, $item.filename)
    }

    $script:TrackedGrid.Rows.Clear()
    foreach ($item in $script:EbayInventory) {
        [void]$script:TrackedGrid.Rows.Add($item.sku, $item.type, $item.name, $item.set, $item.price, $item.date_added_to_ebay)
    }
}

function Get-PythonCommand {
    $pyCommand = Get-Command py -ErrorAction SilentlyContinue
    if ($null -ne $pyCommand) {
        return "py"
    }

    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $pythonCommand) {
        return "python"
    }

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
    Load-Data
    return $true
}

function Confirm-Warning {
    param(
        [string]$Title,
        [string]$Message
    )

    $result = [System.Windows.Forms.MessageBox]::Show($Message, $Title, "YesNo", "Warning")
    return ($result -eq "Yes")
}

# UI
Ensure-Files

$form = New-Object System.Windows.Forms.Form
$form.Text = "Chella Collectibles - eBay Exporter GUI"
$form.Size = New-Object System.Drawing.Size(1240, 780)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(1100, 700)
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 247, 250)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Chella Collectibles eBay Exporter"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(7, 20, 47)
$title.Location = New-Object System.Drawing.Point(18, 14)
$title.Size = New-Object System.Drawing.Size(620, 38)
$form.Controls.Add($title)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = "Ready"
$script:StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(22, 128, 65)
$script:StatusLabel.Location = New-Object System.Drawing.Point(680, 22)
$script:StatusLabel.Size = New-Object System.Drawing.Size(520, 24)
$script:StatusLabel.TextAlign = "MiddleRight"
$form.Controls.Add($script:StatusLabel)

$script:StatsLabel = New-Object System.Windows.Forms.Label
$script:StatsLabel.Text = "Loading..."
$script:StatsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$script:StatsLabel.ForeColor = [System.Drawing.Color]::FromArgb(45, 58, 82)
$script:StatsLabel.Location = New-Object System.Drawing.Point(22, 55)
$script:StatsLabel.Size = New-Object System.Drawing.Size(1180, 24)
$form.Controls.Add($script:StatsLabel)

$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Location = New-Object System.Drawing.Point(18, 90)
$buttonPanel.Size = New-Object System.Drawing.Size(1185, 106)
$buttonPanel.Anchor = "Top,Left,Right"
$buttonPanel.BackColor = [System.Drawing.Color]::White
$buttonPanel.BorderStyle = "FixedSingle"
$form.Controls.Add($buttonPanel)

function New-Button {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 170
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($W, 36)
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    return $btn
}

$refreshBtn = New-Button "Refresh" 12 12 120
$verifyNewBtn = New-Button "Verify New Only" 144 12 150
$liveNewBtn = New-Button "Create Live New Only" 306 12 180
$markCompleteBtn = New-Button "Mark Last Upload Complete" 498 12 215
$openOutputBtn = New-Button "Open Output Folder" 725 12 165
$openTrackingBtn = New-Button "Open eBay Tracking CSV" 902 12 195

$verifyFullBtn = New-Button "Verify Full Inventory" 144 58 160
$liveFullBtn = New-Button "Create Live FULL" 316 58 170
$markFullBtn = New-Button "Mark Full Inventory Listed" 498 58 215

foreach ($button in @(
    $refreshBtn,
    $verifyNewBtn,
    $liveNewBtn,
    $markCompleteBtn,
    $openOutputBtn,
    $openTrackingBtn,
    $verifyFullBtn,
    $liveFullBtn,
    $markFullBtn
)) {
    $buttonPanel.Controls.Add($button)
}

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(18, 212)
$tabs.Size = New-Object System.Drawing.Size(1185, 445)
$tabs.Anchor = "Top,Left,Right,Bottom"
$form.Controls.Add($tabs)

$newTab = New-Object System.Windows.Forms.TabPage
$newTab.Text = "New Items To Upload"

$trackedTab = New-Object System.Windows.Forms.TabPage
$trackedTab.Text = "Tracked eBay Inventory"

$logTab = New-Object System.Windows.Forms.TabPage
$logTab.Text = "Log"

$tabs.TabPages.Add($newTab) | Out-Null
$tabs.TabPages.Add($trackedTab) | Out-Null
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

$script:TrackedGrid = New-Object System.Windows.Forms.DataGridView
$script:TrackedGrid.Dock = "Fill"
$script:TrackedGrid.ReadOnly = $true
$script:TrackedGrid.AllowUserToAddRows = $false
$script:TrackedGrid.SelectionMode = "FullRowSelect"
$script:TrackedGrid.AutoSizeColumnsMode = "Fill"
@("SKU", "Type", "Name", "Set", "Price", "Date Added") | ForEach-Object {
    [void]$script:TrackedGrid.Columns.Add($_, $_)
}
$trackedTab.Controls.Add($script:TrackedGrid)

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Dock = "Fill"
$script:LogBox.Multiline = $true
$script:LogBox.ScrollBars = "Vertical"
$script:LogBox.ReadOnly = $true
$script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$logTab.Controls.Add($script:LogBox)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = "Normal workflow: Verify New Only → upload VerifyAdd CSV → Create Live New Only → upload Add CSV → Mark Last Upload Complete."
$footer.Location = New-Object System.Drawing.Point(22, 668)
$footer.Size = New-Object System.Drawing.Size(1160, 28)
$footer.Anchor = "Left,Right,Bottom"
$footer.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$footer.ForeColor = [System.Drawing.Color]::FromArgb(70, 83, 109)
$form.Controls.Add($footer)

$refreshBtn.Add_Click({
    Load-Data
    Add-Log "Refreshed inventory and tracking."
})

$verifyNewBtn.Add_Click({
    Run-Exporter -Arguments @("--new-only", "--action", "VerifyAdd") -FriendlyName "Verify New Only" | Out-Null
    $tabs.SelectedTab = $logTab
})

$liveNewBtn.Add_Click({
    if (Confirm-Warning -Title "Create Live New Only" -Message "This creates an Add CSV for NEW ONLY items. Uploading that CSV to eBay may create live listings.`n`nContinue?") {
        Run-Exporter -Arguments @("--new-only", "--action", "Add") -FriendlyName "Create Live New Only" | Out-Null
        $tabs.SelectedTab = $logTab
    }
})

$markCompleteBtn.Add_Click({
    if (Confirm-Warning -Title "Mark Last Upload Complete" -Message "Only do this AFTER eBay confirms the Add upload succeeded.`n`nThis adds the pending upload SKUs to ebay_inventory.csv so they are skipped next time.`n`nContinue?") {
        Run-Exporter -Arguments @("--mark-pending-complete") -FriendlyName "Mark Last Upload Complete" | Out-Null
        $tabs.SelectedTab = $logTab
    }
})

$openOutputBtn.Add_Click({
    if (!(Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath | Out-Null
    }
    Start-Process $OutputPath
})

$openTrackingBtn.Add_Click({
    Start-Process $EbayInventoryPath
})

$verifyFullBtn.Add_Click({
    if (Confirm-Warning -Title "Verify Full Inventory" -Message "This verifies your FULL inventory. It should not create live listings, but it may take longer.`n`nContinue?") {
        Run-Exporter -Arguments @("--full", "--action", "VerifyAdd") -FriendlyName "Verify Full Inventory" | Out-Null
        $tabs.SelectedTab = $logTab
    }
})

$liveFullBtn.Add_Click({
    if (Confirm-Warning -Title "Create Live FULL Inventory" -Message "WARNING: This creates an Add CSV for your FULL inventory. Uploading that CSV to eBay may create live listings.`n`nOnly continue if you are absolutely ready.`n`nContinue?") {
        Run-Exporter -Arguments @("--full", "--action", "Add") -FriendlyName "Create Live FULL Inventory" | Out-Null
        $tabs.SelectedTab = $logTab
    }
})

$markFullBtn.Add_Click({
    if (Confirm-Warning -Title "Mark Full Inventory Listed" -Message "Use this once after your initial full eBay upload is confirmed live.`n`nIt adds every current inventory.csv SKU to ebay_inventory.csv.`n`nContinue?") {
        Run-Exporter -Arguments @("--mark-full-inventory-listed") -FriendlyName "Mark Full Inventory Listed" | Out-Null
        $tabs.SelectedTab = $logTab
    }
})

Load-Data
Add-Log "Ready. Loaded eBay Exporter GUI."
[void]$form.ShowDialog()
