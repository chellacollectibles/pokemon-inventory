Chella Collectibles Simple eBay Exporter GUI

This is the simplified GUI.

Main screen buttons:
1. Refresh Inventory
2. Generate eBay Upload CSV
3. Import eBay Result Report

Normal future workflow:
1. Add cards to inventory.csv.
2. Open eBay-Exporter-GUI.bat.
3. Click Refresh Inventory.
4. Click Generate eBay Upload CSV.
5. Upload output/ebay_upload_new_items.csv to eBay.
6. Download eBay's result report.
7. Click Import eBay Result Report and choose the eBay result CSV.
8. Successful SKUs are added to ebay_inventory.csv.
9. Failed rows appear in the Last Upload Failures tab and are saved to output/ebay_failed_uploads.csv.

First-time full inventory upload:
1. Open eBay-Exporter-GUI.bat.
2. Go to Advanced > Generate Full Inventory Upload CSV.
3. Upload output/ebay_upload_full_inventory.csv to eBay.
4. Download eBay's result report.
5. Click Import eBay Result Report and choose the eBay result CSV.
6. The tool adds only successful SKUs to ebay_inventory.csv.
7. Fix any failed rows in inventory.csv.
8. Click Refresh Inventory.
9. Click Generate eBay Upload CSV to upload only the fixed failed/new items.

File menu:
- Open Output Folder
- Open Website Inventory CSV
- Open eBay Tracking CSV
- Exit

Advanced menu:
- Generate Full Inventory Upload CSV
- Mark Current Website Inventory As Already Listed
- Clear eBay Tracking File

For normal use, ignore Advanced unless you are doing a first-time full upload or fixing tracking.
