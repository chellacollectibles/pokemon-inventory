Chella Collectibles - Simplified eBay Exporter

WHERE THESE FILES GO
Put these files/folders in the same root folder as your website inventory.csv:

- eBay-Exporter-GUI.bat
- eBay-Exporter-GUI.ps1
- ebay_exporter.py
- ebay_export_config.json
- ebay_category_listing_template.csv
- ebay_inventory.csv
- templates/ebay_description_template.html
- output/

NORMAL WORKFLOW
1. Double-click eBay-Exporter-GUI.bat.
2. Review the "Website Items Not On eBay" tab.
3. Click "Export New Items to eBay CSV".
4. Upload output/ebay_upload_new_items.csv to eBay.

IMPORTANT BEHAVIOR CHANGE
When you export new items, those SKUs are immediately written to ebay_inventory.csv.
You do NOT need to import the eBay result report anymore.

SHIPPING RULES
- Single/raw cards with original inventory.csv price from $0.01 through $20.00 use Shipping-PWE.
- Single/raw cards over $20.00 use Shipping-Normal.
- Graded cards always use Shipping-Normal.
- Sealed products always use Shipping-Normal.

REMOVAL CHECK
Use the "eBay Items Missing From Website" tab to see items still tracked in ebay_inventory.csv
that are no longer present in inventory.csv. Select one or more rows in that tab and click
"Remove eBay Items Missing From Website" to delete those selected SKUs from ebay_inventory.csv.
This does not touch inventory.csv and does not contact eBay; it only cleans your local eBay tracker.

OUTPUT FILE
The file to upload to eBay is:
output/ebay_upload_new_items.csv
