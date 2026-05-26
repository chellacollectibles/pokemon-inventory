1. Click 'Refresh' and see new cards in 'New Items to Upload' tab
2. Click 'Generate eBay Upload CSV'
3. Upload the ebay_upload_new_items.csv to eBay
4. Download eBay result report
5. Click 'Import eBay Result Report' and choose the downloaded report
6. ^ This prevents duplicate items from being uploaded.


//Singles
$i = 1315
Get-ChildItem -Filter "singles_*.jpg" | Sort-Object Name | ForEach-Object {
    Rename-Item $_.FullName -NewName ("temp_{0:D4}.jpg" -f $i)
    $i++
}

Get-ChildItem -Filter "temp_*.jpg" | ForEach-Object {
    Rename-Item $_.FullName -NewName ($_.Name -replace "^temp_", "singles_")
}

//Slabs
$i = 620

Get-ChildItem -Filter "singles_*.jpg" | Sort-Object Name | ForEach-Object {
    Rename-Item $_.FullName -NewName ("temp_{0}.jpg" -f $i)
    $i++
}

Get-ChildItem -Filter "temp_*.jpg" | Sort-Object Name | ForEach-Object {
    Rename-Item $_.FullName -NewName ($_.Name -replace "^temp_", "img")
}