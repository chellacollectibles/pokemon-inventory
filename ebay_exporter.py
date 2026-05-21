#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import html
import json
import re
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
from typing import Dict, List, Tuple


@dataclass
class InventoryItem:
    filename: str
    back_filename: str
    item_type: str
    name: str
    set_name: str
    price: str
    source_row_number: int


def normalize_header(value: str) -> str:
    return value.strip().lower().replace(" ", "").replace("_", "")


def normalize_type(value: str) -> str:
    cleaned = (value or "").strip().lower()
    if cleaned in {"single", "singles"}:
        return "single"
    if cleaned in {"graded", "graded cards", "gradedcards"}:
        return "graded"
    if cleaned in {"sealed", "sealed products", "sealedproducts"}:
        return "sealed"
    return cleaned


def money(value: str) -> Decimal | None:
    cleaned = str(value or "").replace("$", "").replace(",", "").strip()
    if not cleaned:
        return None
    try:
        return Decimal(cleaned)
    except InvalidOperation:
        return None


def load_config(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def read_inventory(path: Path) -> List[InventoryItem]:
    if not path.exists():
        raise FileNotFoundError(f"Could not find {path}. Put this tool in the same folder as inventory.csv.")

    items: List[InventoryItem] = []
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            raise ValueError("inventory.csv has no header row.")

        header_map = {normalize_header(h): h for h in reader.fieldnames}

        def get(row: dict, *names: str) -> str:
            for name in names:
                key = normalize_header(name)
                if key in header_map:
                    return (row.get(header_map[key]) or "").strip()
            return ""

        for row_number, row in enumerate(reader, start=2):
            filename = get(row, "filename")
            if not filename:
                continue

            items.append(InventoryItem(
                filename=filename,
                back_filename=get(row, "back_filename", "backfilename"),
                item_type=normalize_type(get(row, "type")),
                name=get(row, "name"),
                set_name=get(row, "set"),
                price=get(row, "price"),
                source_row_number=row_number,
            ))

    return items


def read_full_listing_template(path: Path) -> Tuple[List[str], List[str]]:
    if not path.exists():
        raise FileNotFoundError(f"Missing eBay category listing template: {path}")

    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        rows = [row for row in reader if row]

    if len(rows) < 2:
        raise ValueError("Template does not contain enough rows.")

    info_row = rows[0]
    header_row = rows[1]

    if not header_row or not header_row[0].startswith("*Action("):
        raise ValueError("Could not find full listing header row. Expected *Action(...) in row 2.")

    return info_row, header_row


def detect_raw_condition(name: str, config: dict) -> Tuple[str, str]:
    lower_name = (name or "").lower()
    for key, label in config["condition_labels"].items():
        if key in lower_name:
            return label, config["condition_abbreviations"].get(label, label)
    return "", ""


def parse_grade_info(name: str) -> Tuple[str, str]:
    text = " ".join((name or "").replace("-", " ").split())
    upper = text.upper()
    companies = ["PSA", "BGS", "CGC", "TAG", "ARS", "SGC", "AGS", "BCCG", "BVG"]

    for company in companies:
        if company not in upper:
            continue

        idx = upper.find(company)
        after = upper[idx + len(company):].strip()
        grade_match = re.search(r"\b(10|9\.5|9|8\.5|8|7\.5|7|6\.5|6|5\.5|5|4\.5|4|3\.5|3|2\.5|2|1\.5|1)\b", after)

        if grade_match:
            return company, grade_match.group(1)

        if "AUTHENTIC" in after:
            return company, "Authentic"

    return "", ""


def strip_condition_and_grade_from_name(name: str) -> str:
    value = name or ""

    for condition in ["Near Mint", "Lightly Played", "Moderately Played", "Heavily Played", "Damaged"]:
        value = re.sub(rf"\s*-\s*{re.escape(condition)}\s*$", "", value, flags=re.I)

    value = re.sub(
        r"\s*-\s*(PSA|BGS|CGC|TAG|ARS|SGC|AGS|BCCG|BVG)(?:\s+(?:AUTO|Perfect|Pristine))?\s+(?:10|9\.5|9|8\.5|8|7\.5|7|6\.5|6|5\.5|5|4\.5|4|3\.5|3|2\.5|2|1\.5|1|Authentic)\s*$",
        "",
        value,
        flags=re.I,
    )

    return " ".join(value.split())


def clean_title_text(value: str) -> str:
    value = html.unescape(value or "")
    value = value.replace("Pokémon", "Pokemon").replace("pokemon", "Pokemon")
    value = re.sub(r"\s+-\s+", " ", value)
    return " ".join(value.split()).strip()


def smart_trim_title(title: str, max_length: int) -> str:
    title = clean_title_text(title)

    if len(title) <= max_length:
        return title

    replacements = [
        (" Reverse Holofoil ", " Rev Holo "),
        (" Holofoil ", " Holo "),
        (" 1st Edition", " 1st Ed"),
        (" Moderately Played", " MP"),
        (" Lightly Played", " LP"),
        (" Heavily Played", " HP"),
        (" Near Mint", " NM"),
        (" Damaged", " DMG"),
        (" Pokemon Card", ""),
        (" Pokemon TCG", ""),
        (" Unlimited", " Unltd"),
    ]

    for old, new in replacements:
        title = clean_title_text(title.replace(old, new))
        if len(title) <= max_length:
            return title

    return title[:max_length].rstrip(" -,")


def build_title(item: InventoryItem, config: dict) -> str:
    max_length = int(config.get("title_max_length", 80))
    base_name = clean_title_text(strip_condition_and_grade_from_name(item.name))
    set_name = clean_title_text(item.set_name)

    if item.item_type == "graded":
        company, grade = parse_grade_info(item.name)
        grade_text = " ".join(part for part in [company, grade] if part)
        pieces = [base_name, set_name, grade_text, "Pokemon Card"]
    elif item.item_type == "sealed":
        pieces = [base_name, set_name, "Pokemon TCG Sealed"]
    else:
        _, abbr = detect_raw_condition(item.name, config)
        pieces = [base_name, set_name, "Pokemon Card", abbr]

    return smart_trim_title(" ".join(piece for piece in pieces if piece), max_length)


def generate_sku(item: InventoryItem, config: dict) -> str:
    prefix = config.get("sku_prefix", "CHELLA")
    stem = Path(item.filename).stem.upper()
    clean_stem = re.sub(r"[^A-Z0-9]+", "-", stem).strip("-")
    type_part = item.item_type.upper() if item.item_type else "ITEM"
    return f"{prefix}-{type_part}-{clean_stem}"


def ebay_price(value: str) -> str:
    amount = money(value)

    if amount is None or amount <= 0:
        return ""

    if amount == amount.to_integral_value():
        amount -= Decimal("0.01")
    else:
        amount = amount.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

    if amount < Decimal("0.01"):
        amount = Decimal("0.99")

    return f"{amount:.2f}"


def build_image_urls(item: InventoryItem, config: dict) -> str:
    base_url = config["site_base_image_url"].rstrip("/") + "/"
    sep = config.get("multiple_image_separator", "|")
    urls = []

    if item.filename:
        urls.append(base_url + item.filename)
    if item.back_filename:
        urls.append(base_url + item.back_filename)

    return sep.join(urls)


def category_id(item: InventoryItem, config: dict) -> str:
    if item.item_type in {"single", "graded"}:
        return config["graded_category_id"] if item.item_type == "graded" else config["single_category_id"]

    name = (item.name or "").lower()
    if "pack" in name and "box" not in name:
        return config["sealed_pack_category_id"]

    return config["sealed_box_category_id"]


def condition_id(item: InventoryItem, config: dict) -> str:
    return config["condition_ids"].get(item.item_type, "")


def raw_condition_descriptor_id(item: InventoryItem, config: dict) -> str:
    if item.item_type != "single":
        return ""
    label, _ = detect_raw_condition(item.name, config)
    return config["raw_condition_descriptor_ids"].get(label, "")


def grader_descriptor_id(item: InventoryItem, config: dict) -> str:
    if item.item_type != "graded":
        return ""
    company, _ = parse_grade_info(item.name)
    return config["professional_grader_ids"].get(company, "")


def grade_descriptor_id(item: InventoryItem, config: dict) -> str:
    if item.item_type != "graded":
        return ""
    _, grade = parse_grade_info(item.name)
    return config["grade_ids"].get(grade, "")


def condition_text_for_description(item: InventoryItem, config: dict) -> str:
    if item.item_type == "graded":
        company, grade = parse_grade_info(item.name)
        return f"Professionally graded: {company} {grade}".strip()

    if item.item_type == "sealed":
        return "Factory sealed / unopened"

    label, abbr = detect_raw_condition(item.name, config)
    ebay_label = config.get("raw_condition_descriptor_labels", {}).get(label, "")

    if label and abbr and ebay_label:
        return f"{label} ({abbr}) / eBay equivalent: {ebay_label}"

    return f"{label} ({abbr})" if label and abbr else "Condition shown in title/photos"


def render_description(item: InventoryItem, title: str, config: dict) -> str:
    template_path = Path(config["description_template"])
    template = template_path.read_text(encoding="utf-8")

    replacements = {
        "{{title}}": html.escape(title),
        "{{item_name}}": html.escape(item.name or "Not listed"),
        "{{set_name}}": html.escape(item.set_name or "Not listed"),
        "{{condition_text}}": html.escape(condition_text_for_description(item, config)),
    }

    for token, value in replacements.items():
        template = template.replace(token, value)

    return " ".join(template.split())


def extract_card_number(name: str) -> str:
    match = re.search(r"#([A-Za-z0-9/\\-\\.]+)", name or "")
    return match.group(1) if match else ""


def shipping_policy_for_item(item: InventoryItem, config: dict) -> str:
    """Return the business policy name that should be used for this item.

    Singles priced at or below the configured PWE max price use the PWE policy.
    Graded cards and sealed products always use the normal policy. The decision is
    based on the original inventory.csv price, not the .99-adjusted eBay price.
    """
    normal_policy = config.get("shipping_policy_normal") or config.get("shipping_policy", "Shipping-Normal")
    pwe_policy = config.get("shipping_policy_pwe", "Shipping-PWE")
    pwe_max = money(str(config.get("shipping_pwe_max_price", "20"))) or Decimal("20")

    if item.item_type != "single":
        return normal_policy

    amount = money(item.price)
    if amount is not None and Decimal("0") < amount <= pwe_max:
        return pwe_policy

    return normal_policy


def build_row(item: InventoryItem, config: dict, action: str, header_row: List[str]) -> Dict[str, str]:
    title = build_title(item, config)
    row: Dict[str, str] = {header: "" for header in header_row}
    action_header = header_row[0]

    row[action_header] = action
    row["CustomLabel"] = generate_sku(item, config)
    row["*Category"] = category_id(item, config)
    row["*Title"] = title
    row["*ConditionID"] = condition_id(item, config)
    row["CD:Professional Grader - (ID: 27501)"] = grader_descriptor_id(item, config)
    row["CD:Grade - (ID: 27502)"] = grade_descriptor_id(item, config)
    row["CDA:Certification Number - (ID: 27503)"] = ""
    row["CD:Card Condition - (ID: 40001)"] = raw_condition_descriptor_id(item, config)

    row["*C:Franchise"] = config.get("franchise", "Pokémon")
    row["*C:Set"] = item.set_name
    row["*C:Manufacturer"] = config.get("manufacturer", "Nintendo")
    row["C:Type"] = config.get("type_sealed" if item.item_type == "sealed" else "type_single", "Non-Sport Trading Card")
    row["C:Card Condition"] = condition_text_for_description(item, config)
    row["C:Card Name"] = clean_title_text(strip_condition_and_grade_from_name(item.name))
    row["C:Card Number"] = extract_card_number(item.name)
    row["C:Graded"] = "Yes" if item.item_type == "graded" else "No"
    row["C:Professional Grader"] = parse_grade_info(item.name)[0] if item.item_type == "graded" else ""
    row["C:Grade"] = parse_grade_info(item.name)[1] if item.item_type == "graded" else ""

    if item.item_type == "sealed":
        name = (item.name or "").lower()
        row["C:Configuration"] = "Pack" if "pack" in name and "box" not in name else "Box"

    row["PicURL"] = build_image_urls(item, config)
    row["GalleryType"] = "Gallery"
    row["*Description"] = render_description(item, title, config)
    row["*Format"] = config.get("format", "FixedPrice")
    row["*Duration"] = config.get("duration", "GTC")
    row["*StartPrice"] = ebay_price(item.price)
    row["*Quantity"] = str(config.get("quantity", 1))
    row["ImmediatePayRequired"] = "1"
    row["*Location"] = config.get("location", "New Jersey, United States")
    row["*DispatchTimeMax"] = config.get("dispatch_time_max", "3")
    row["*ReturnsAcceptedOption"] = config.get("returns_accepted_option", "ReturnsNotAccepted")
    row["ShippingProfileName"] = shipping_policy_for_item(item, config)
    row["ReturnProfileName"] = config.get("return_profile_name", "")
    row["PaymentProfileName"] = config.get("payment_profile_name", "")

    return row


def warnings_for_item(item: InventoryItem, config: dict) -> List[str]:
    warnings = []

    if not item.name:
        warnings.append("Missing name")
    if not item.price:
        warnings.append("Missing price")
    if not item.set_name:
        warnings.append("Missing set")
    if item.item_type == "single" and not raw_condition_descriptor_id(item, config):
        warnings.append("Missing raw condition descriptor")
    if item.item_type == "graded" and not grader_descriptor_id(item, config):
        warnings.append("Missing grader descriptor")
    if item.item_type == "graded" and not grade_descriptor_id(item, config):
        warnings.append("Missing grade descriptor")

    return warnings


def ebay_inventory_path(config: dict) -> Path:
    return Path(config.get("ebay_inventory_csv", "ebay_inventory.csv"))


def ensure_ebay_inventory_file(config: dict) -> None:
    path = ebay_inventory_path(config)
    if path.exists():
        return

    with path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "sku", "filename", "type", "name", "set", "price", "date_added_to_ebay", "notes"
        ])
        writer.writeheader()


def read_uploaded_skus(config: dict) -> set[str]:
    ensure_ebay_inventory_file(config)
    path = ebay_inventory_path(config)
    skus: set[str] = set()

    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            sku = (row.get("sku") or "").strip()
            if sku:
                skus.add(sku)

    return skus


def filter_new_only(items: List[InventoryItem], config: dict) -> List[InventoryItem]:
    uploaded_skus = read_uploaded_skus(config)
    return [item for item in items if generate_sku(item, config) not in uploaded_skus]


def write_pending_upload(items: List[InventoryItem], config: dict, mode: str, action: str) -> Path:
    output_folder = Path(config.get("output_folder", "output"))
    output_folder.mkdir(parents=True, exist_ok=True)
    pending_path = output_folder / f"ebay_pending_upload_{action}_{mode}.csv"

    with pending_path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "sku", "filename", "type", "name", "set", "price", "date_generated"
        ])
        writer.writeheader()
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        for item in items:
            writer.writerow({
                "sku": generate_sku(item, config),
                "filename": item.filename,
                "type": item.item_type,
                "name": item.name,
                "set": item.set_name,
                "price": item.price,
                "date_generated": now,
            })

    return pending_path


def append_items_to_ebay_inventory(items: List[InventoryItem], config: dict, note: str) -> int:
    ensure_ebay_inventory_file(config)
    existing = read_uploaded_skus(config)
    path = ebay_inventory_path(config)
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    added = 0

    with path.open("a", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "sku", "filename", "type", "name", "set", "price", "date_added_to_ebay", "notes"
        ])

        for item in items:
            sku = generate_sku(item, config)
            if sku in existing:
                continue

            writer.writerow({
                "sku": sku,
                "filename": item.filename,
                "type": item.item_type,
                "name": item.name,
                "set": item.set_name,
                "price": item.price,
                "date_added_to_ebay": now,
                "notes": note,
            })
            existing.add(sku)
            added += 1

    return added


def mark_pending_complete(config: dict) -> int:
    output_folder = Path(config.get("output_folder", "output"))
    candidates = sorted(output_folder.glob("ebay_pending_upload_Add_*.csv"), key=lambda p: p.stat().st_mtime, reverse=True)

    if not candidates:
        raise FileNotFoundError("No pending Add upload file found in output folder.")

    pending_path = candidates[0]
    ensure_ebay_inventory_file(config)
    existing = read_uploaded_skus(config)
    path = ebay_inventory_path(config)
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    added = 0

    with pending_path.open("r", encoding="utf-8-sig", newline="") as read_file, \
         path.open("a", encoding="utf-8-sig", newline="") as write_file:

        reader = csv.DictReader(read_file)
        writer = csv.DictWriter(write_file, fieldnames=[
            "sku", "filename", "type", "name", "set", "price", "date_added_to_ebay", "notes"
        ])

        for row in reader:
            sku = (row.get("sku") or "").strip()
            if not sku or sku in existing:
                continue

            writer.writerow({
                "sku": sku,
                "filename": row.get("filename", ""),
                "type": row.get("type", ""),
                "name": row.get("name", ""),
                "set": row.get("set", ""),
                "price": row.get("price", ""),
                "date_added_to_ebay": now,
                "notes": f"Marked complete from {pending_path.name}",
            })
            existing.add(sku)
            added += 1

    return added


def write_outputs(items: List[InventoryItem], config: dict, mode: str, action: str) -> None:
    output_folder = Path(config.get("output_folder", "output"))
    output_folder.mkdir(parents=True, exist_ok=True)

    info_row, header_row = read_full_listing_template(Path(config["ebay_template_csv"]))

    upload_path = output_folder / f"ebay_listing_{action}_{mode}.csv"
    review_path = output_folder / f"ebay_review_{action}_{mode}.csv"

    with upload_path.open("w", encoding="utf-8-sig", newline="") as upload_file:
        writer = csv.writer(upload_file, lineterminator="\r\n")
        writer.writerow(info_row)
        writer.writerow(header_row)

        for item in items:
            row = build_row(item, config, action, header_row)
            writer.writerow([row.get(header, "") for header in header_row])

    review_headers = [
        "source_row", "sku", "type", "category", "condition_id",
        "raw_condition_descriptor", "grader_descriptor", "grade_descriptor",
        "shipping_policy", "title", "price", "image_urls", "warnings"
    ]

    with review_path.open("w", encoding="utf-8-sig", newline="") as review_file:
        writer = csv.DictWriter(review_file, fieldnames=review_headers)
        writer.writeheader()

        for item in items:
            writer.writerow({
                "source_row": item.source_row_number,
                "sku": generate_sku(item, config),
                "type": item.item_type,
                "category": category_id(item, config),
                "condition_id": condition_id(item, config),
                "raw_condition_descriptor": raw_condition_descriptor_id(item, config),
                "grader_descriptor": grader_descriptor_id(item, config),
                "grade_descriptor": grade_descriptor_id(item, config),
                "shipping_policy": shipping_policy_for_item(item, config),
                "title": build_title(item, config),
                "price": ebay_price(item.price),
                "image_urls": build_image_urls(item, config),
                "warnings": " | ".join(warnings_for_item(item, config)),
            })

    pending_path = None
    if action == "Add":
        pending_path = write_pending_upload(items, config, mode, action)

    print(f"Created: {upload_path}")
    print(f"Created: {review_path}")
    if pending_path:
        print(f"Created: {pending_path}")


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--new-only", action="store_true", help="Only export SKUs not already listed in ebay_inventory.csv.")
    group.add_argument("--full", action="store_true", help="Export full inventory.")
    parser.add_argument("--action", default="VerifyAdd", choices=["VerifyAdd", "Add"])
    parser.add_argument("--config", default="ebay_export_config.json")
    parser.add_argument("--mark-pending-complete", action="store_true", help="Append last pending Add upload SKUs into ebay_inventory.csv.")
    parser.add_argument("--mark-full-inventory-listed", action="store_true", help="Append every current inventory SKU into ebay_inventory.csv.")
    parser.add_argument("--auto-track-exported", action="store_true", help="Immediately append exported Add SKUs into ebay_inventory.csv after creating the upload CSV.")

    args = parser.parse_args()
    config = load_config(Path(args.config))

    if args.mark_pending_complete:
        added = mark_pending_complete(config)
        print(f"Added {added} SKU(s) to {ebay_inventory_path(config)} from last pending Add upload.")
        return 0

    items = read_inventory(Path(config["input_inventory_csv"]))

    if args.mark_full_inventory_listed:
        added = append_items_to_ebay_inventory(items, config, "Manually marked full current inventory as listed")
        print(f"Added {added} SKU(s) to {ebay_inventory_path(config)}.")
        return 0

    if not items:
        raise ValueError("No usable rows found in inventory.csv")

    if args.new_only:
        export_items = filter_new_only(items, config)
        mode = "NEW_ONLY"
        skipped = len(items) - len(export_items)
        print(f"Inventory rows loaded: {len(items)}")
        print(f"Already-listed SKUs skipped: {skipped}")
        print(f"New rows selected: {len(export_items)}")
    else:
        export_items = items
        mode = "FULL"
        print(f"Inventory rows loaded: {len(items)}")
        print(f"Rows selected for FULL export: {len(export_items)}")

    print(f"Action: {args.action}")

    if not export_items:
        print("No items to export.")
        return 0

    write_outputs(export_items, config, mode, args.action)

    if args.auto_track_exported and args.action == "Add":
        added = append_items_to_ebay_inventory(export_items, config, f"Auto-tracked when export CSV was generated ({mode})")
        print(f"Auto-tracked exported SKUs in {ebay_inventory_path(config)}: {added} added.")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print()
        print("ERROR:", exc)
        print("Fix the issue above, then run again.")
        raise SystemExit(1)
