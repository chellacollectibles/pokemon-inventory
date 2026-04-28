const gallery = document.getElementById("gallery");
const imageCount = document.getElementById("imageCount");
const loadMoreBtn = document.getElementById("loadMoreBtn");

const nameSearch = document.getElementById("nameSearch");
const typeFilter = document.getElementById("typeFilter");
const setSearch = document.getElementById("setSearch");
const priceSort = document.getElementById("priceSort");
const clearFiltersBtn = document.getElementById("clearFiltersBtn");

const lightbox = document.getElementById("lightbox");
const lightboxImage = document.getElementById("lightboxImage");
const closeLightbox = document.getElementById("closeLightbox");
const showFrontBtn = document.getElementById("showFrontBtn");
const showBackBtn = document.getElementById("showBackBtn");
const lightboxLabel = document.getElementById("lightboxLabel");

const requestListButton = document.getElementById("requestListButton");
const requestListCount = document.getElementById("requestListCount");
const requestDrawer = document.getElementById("requestDrawer");
const requestOverlay = document.getElementById("requestOverlay");
const closeRequestDrawer = document.getElementById("closeRequestDrawer");
const requestListItems = document.getElementById("requestListItems");
const requestListEmpty = document.getElementById("requestListEmpty");
const copyListBtn = document.getElementById("copyListBtn");
const emailListBtn = document.getElementById("emailListBtn");
const downloadTxtBtn = document.getElementById("downloadTxtBtn");
const copyShareLinkBtn = document.getElementById("copyShareLinkBtn");
const clearListBtn = document.getElementById("clearListBtn");
const requestToast = document.getElementById("requestToast");

let allItems = [];
let filteredItems = [];
let visibleCount = 0;
let currentLightboxItem = null;
let currentLightboxSide = "front";
let selectedFilenames = new Set();
let shouldOpenSharedList = false;

const batchSize = 24;
const requestListStorageKey = "chellaRequestListV1";
const shareLinkSeparator = "~";

async function loadInventory() {
  try {
    const response = await fetch("inventory.csv?v=" + Date.now());

    if (!response.ok) {
      throw new Error("Could not load inventory.csv");
    }

    const csvText = await response.text();

    allItems = parseCSV(csvText)
      .map(cleanInventoryItem)
      .filter(item => item.filename);

    filteredItems = sortItems([...allItems]);

    loadSavedRequestList();
    loadRequestListFromUrl();

    if (!Array.isArray(allItems) || allItems.length === 0) {
      imageCount.textContent = "No inventory found yet.";
      loadMoreBtn.classList.add("hidden");
      updateRequestListUI();
      return;
    }

    renderFreshResults();
    updateRequestListUI();

    if (shouldOpenSharedList) {
      setTimeout(() => {
        openRequestDrawer();
        showToast("Shared request list loaded.");
      }, 250);
    }
  } catch (error) {
    gallery.innerHTML = `
      <div class="error-message">
        Inventory could not be loaded. Make sure inventory.csv exists in the main GitHub folder and includes columns for filename, type, name, set, price, and optionally back_filename.
      </div>
    `;

    imageCount.textContent = "Unable to load inventory.";
    loadMoreBtn.classList.add("hidden");

    console.error(error);
  }
}

function parseCSV(csvText) {
  const rows = [];
  let currentRow = [];
  let currentValue = "";
  let insideQuotes = false;

  for (let i = 0; i < csvText.length; i++) {
    const char = csvText[i];
    const nextChar = csvText[i + 1];

    if (char === '"' && insideQuotes && nextChar === '"') {
      currentValue += '"';
      i++;
    } else if (char === '"') {
      insideQuotes = !insideQuotes;
    } else if (char === "," && !insideQuotes) {
      currentRow.push(currentValue);
      currentValue = "";
    } else if ((char === "\n" || char === "\r") && !insideQuotes) {
      if (char === "\r" && nextChar === "\n") {
        i++;
      }

      currentRow.push(currentValue);

      if (currentRow.some(value => value.trim() !== "")) {
        rows.push(currentRow);
      }

      currentRow = [];
      currentValue = "";
    } else {
      currentValue += char;
    }
  }

  currentRow.push(currentValue);

  if (currentRow.some(value => value.trim() !== "")) {
    rows.push(currentRow);
  }

  if (rows.length < 2) {
    return [];
  }

  const headers = rows[0].map(header => normalizeHeader(header));

  return rows.slice(1).map(row => {
    const item = {};

    headers.forEach((header, index) => {
      item[header] = row[index] ? row[index].trim() : "";
    });

    return item;
  });
}

function normalizeHeader(header) {
  return header
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "");
}

function cleanInventoryItem(item) {
  const name = item.name || "";
  const condition = extractCondition(name);

  return {
    filename: item.filename || "",
    backFilename: item.back_filename || item.backfilename || "",
    type: normalizeType(item.type || ""),
    name: name,
    set: item.set || "",
    price: item.price || "",
    condition: condition.label,
    conditionSlug: condition.slug
  };
}

function normalizeType(type) {
  const cleaned = type.trim().toLowerCase();

  if (cleaned === "singles") return "single";
  if (cleaned === "single") return "single";
  if (cleaned === "graded cards") return "graded";
  if (cleaned === "graded") return "graded";
  if (cleaned === "sealed products") return "sealed";
  if (cleaned === "sealed") return "sealed";

  return cleaned;
}

function extractCondition(name) {
  const cleaned = name.toLowerCase();

  if (cleaned.includes("near mint")) {
    return { label: "Near Mint", slug: "near-mint" };
  }

  if (cleaned.includes("lightly played")) {
    return { label: "Lightly Played", slug: "lightly-played" };
  }

  if (cleaned.includes("moderately played")) {
    return { label: "Moderately Played", slug: "moderately-played" };
  }

  if (cleaned.includes("heavily played")) {
    return { label: "Heavily Played", slug: "heavily-played" };
  }

  if (cleaned.includes("damaged")) {
    return { label: "Damaged", slug: "damaged" };
  }

  return { label: "", slug: "unknown" };
}

function getPriceValue(price) {
  const numeric = Number(String(price || "").replace(/[$,]/g, "").trim());
  return Number.isFinite(numeric) ? numeric : null;
}

function sortItems(items) {
  const sortValue = priceSort ? priceSort.value : "";

  if (!sortValue) {
    return [...items];
  }

  return [...items].sort((a, b) => {
    const priceA = getPriceValue(a.price);
    const priceB = getPriceValue(b.price);

    if (priceA === null && priceB === null) return 0;
    if (priceA === null) return 1;
    if (priceB === null) return -1;

    return sortValue === "high-low"
      ? priceB - priceA
      : priceA - priceB;
  });
}

function renderFreshResults() {
  visibleCount = 0;
  gallery.innerHTML = "";
  updateCount();
  renderNextBatch();
}

function renderNextBatch() {
  const nextItems = filteredItems.slice(visibleCount, visibleCount + batchSize);

  nextItems.forEach(item => {
    const card = document.createElement("article");
    card.className = `inventory-item condition-${item.conditionSlug || "unknown"}`;

    if (selectedFilenames.has(item.filename)) {
      card.classList.add("request-added");
    }

    const imageWrap = document.createElement("div");
    imageWrap.className = "inventory-image-wrap";

    const img = document.createElement("img");
    img.src = `images/${encodeURIComponent(item.filename)}`;
    img.alt = buildAltText(item);
    img.loading = "lazy";

    img.addEventListener("click", () => {
      openLightbox(item, "front");
    });

    imageWrap.appendChild(img);

    const info = document.createElement("div");
    info.className = "inventory-info";

    const topLine = document.createElement("div");
    topLine.className = "inventory-info-top";

    const badgeGroup = document.createElement("div");
    badgeGroup.className = "badge-group";

    if (item.condition) {
      const conditionBadge = document.createElement("span");
      conditionBadge.className = `condition-badge ${item.conditionSlug}`;
      conditionBadge.textContent = item.condition;
      badgeGroup.appendChild(conditionBadge);
    }

    const price = document.createElement("span");
    price.className = "item-price";
    price.textContent = formatPrice(item.price);

    topLine.appendChild(badgeGroup);
    topLine.appendChild(price);

    const title = document.createElement("h3");
    title.textContent = item.name || "Unnamed Item";

    const set = document.createElement("p");
    set.textContent = item.set ? item.set : "Set not listed";

    const requestButton = document.createElement("button");
    requestButton.className = "add-list-btn";
    requestButton.type = "button";
    requestButton.dataset.filename = item.filename;
    updateAddButtonState(requestButton, item.filename);

    requestButton.addEventListener("click", () => {
      toggleRequestItem(item.filename);
    });

    info.appendChild(topLine);
    info.appendChild(title);
    info.appendChild(set);
    info.appendChild(requestButton);

    card.appendChild(imageWrap);
    card.appendChild(info);

    gallery.appendChild(card);
  });

  visibleCount += nextItems.length;

  if (filteredItems.length === 0) {
    gallery.innerHTML = `
      <div class="empty-message">
        No items match your current search.
      </div>
    `;
    loadMoreBtn.classList.add("hidden");
    return;
  }

  if (visibleCount >= filteredItems.length) {
    loadMoreBtn.classList.add("hidden");
  } else {
    loadMoreBtn.classList.remove("hidden");
    loadMoreBtn.textContent = `Load More (${filteredItems.length - visibleCount} remaining)`;
  }
}

function applyFilters() {
  const nameQuery = nameSearch.value.trim().toLowerCase();
  const typeQuery = typeFilter.value.trim().toLowerCase();
  const setQuery = setSearch.value.trim().toLowerCase();

  const matchedItems = allItems.filter(item => {
    const matchesName = !nameQuery || item.name.toLowerCase().includes(nameQuery);
    const matchesType = !typeQuery || item.type === typeQuery;
    const matchesSet = !setQuery || item.set.toLowerCase().includes(setQuery);

    return matchesName && matchesType && matchesSet;
  });

  filteredItems = sortItems(matchedItems);

  renderFreshResults();
}

function clearFilters() {
  nameSearch.value = "";
  typeFilter.value = "";
  setSearch.value = "";
  priceSort.value = "";

  filteredItems = [...allItems];
  renderFreshResults();
}

function updateCount() {
  const total = filteredItems.length.toLocaleString();

  if (filteredItems.length === 1) {
    imageCount.textContent = "1 item";
  } else {
    imageCount.textContent = `${total} items`;
  }
}

function openLightbox(item, side) {
  currentLightboxItem = item;
  currentLightboxSide = side;
  updateLightboxImage();
  lightbox.classList.add("active");
  lightbox.setAttribute("aria-hidden", "false");
}

function updateLightboxImage() {
  if (!currentLightboxItem) return;

  const hasBack = Boolean(currentLightboxItem.backFilename);
  const imageFile =
    currentLightboxSide === "back" && hasBack
      ? currentLightboxItem.backFilename
      : currentLightboxItem.filename;

  lightboxImage.src = `images/${encodeURIComponent(imageFile)}`;
  lightboxImage.alt = `${buildAltText(currentLightboxItem)} - ${currentLightboxSide === "back" ? "Back" : "Front"}`;

  lightboxLabel.textContent = currentLightboxSide === "back" ? "Back Image" : "Front Image";

  if (hasBack) {
    showFrontBtn.classList.remove("hidden");
    showBackBtn.classList.remove("hidden");
  } else {
    showFrontBtn.classList.add("hidden");
    showBackBtn.classList.add("hidden");
  }

  showFrontBtn.classList.toggle("active", currentLightboxSide === "front");
  showBackBtn.classList.toggle("active", currentLightboxSide === "back");
}

function buildAltText(item) {
  const parts = [];

  if (item.name) parts.push(item.name);
  if (item.set) parts.push(item.set);
  if (item.type) parts.push(formatType(item.type));

  return parts.length ? parts.join(" - ") : "Chella Collectibles inventory item";
}

function formatType(type) {
  if (!type) return "Item";

  const map = {
    single: "Single",
    graded: "Graded",
    sealed: "Sealed"
  };

  return map[type] || capitalize(type);
}

function formatPrice(price) {
  const cleaned = String(price || "").trim();

  if (!cleaned) {
    return "Price on request";
  }

  const numeric = Number(cleaned.replace(/[$,]/g, ""));

  if (!Number.isNaN(numeric)) {
    return `$${numeric.toLocaleString()}`;
  }

  return cleaned.startsWith("$") ? cleaned : `$${cleaned}`;
}

function capitalize(value) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function closeImage() {
  lightbox.classList.remove("active");
  lightbox.setAttribute("aria-hidden", "true");
  lightboxImage.src = "";
  lightboxImage.alt = "";
  currentLightboxItem = null;
  currentLightboxSide = "front";
}

/* REQUEST LIST */

function loadSavedRequestList() {
  try {
    const saved = JSON.parse(localStorage.getItem(requestListStorageKey) || "[]");

    if (Array.isArray(saved)) {
      selectedFilenames = new Set(saved.filter(Boolean));
    }
  } catch (error) {
    selectedFilenames = new Set();
    console.error(error);
  }
}

function saveRequestList() {
  localStorage.setItem(
    requestListStorageKey,
    JSON.stringify(Array.from(selectedFilenames))
  );
}

function loadRequestListFromUrl() {
  const params = new URLSearchParams(window.location.search);
  const listParam = params.get("list");

  if (!listParam) {
    return;
  }

  const separator = listParam.includes(shareLinkSeparator)
    ? shareLinkSeparator
    : ",";

  const filenamesFromUrl = listParam
    .split(separator)
    .map(value => value.trim())
    .filter(Boolean);

  if (filenamesFromUrl.length === 0) {
    return;
  }

  const validFilenames = new Set(allItems.map(item => item.filename));
  let addedCount = 0;

  filenamesFromUrl.forEach(filename => {
    if (validFilenames.has(filename)) {
      selectedFilenames.add(filename);
      addedCount++;
    }
  });

  if (addedCount > 0) {
    shouldOpenSharedList = true;
    saveRequestList();
  }
}

function getSelectedItems() {
  const selected = Array.from(selectedFilenames);

  return selected
    .map(filename => allItems.find(item => item.filename === filename))
    .filter(Boolean);
}

function toggleRequestItem(filename) {
  if (selectedFilenames.has(filename)) {
    selectedFilenames.delete(filename);
    showToast("Removed from your list.");
  } else {
    selectedFilenames.add(filename);
    showToast("Added to your list.");
  }

  saveRequestList();
  updateRequestListUI();
  updateVisibleInventoryButtons();
}

function removeRequestItem(filename) {
  selectedFilenames.delete(filename);
  saveRequestList();
  updateRequestListUI();
  updateVisibleInventoryButtons();
  showToast("Removed from your list.");
}

function clearRequestList() {
  if (selectedFilenames.size === 0) {
    showToast("Your list is already empty.");
    return;
  }

  selectedFilenames.clear();
  saveRequestList();
  updateRequestListUI();
  updateVisibleInventoryButtons();
  showToast("Request list cleared.");
}

function updateVisibleInventoryButtons() {
  document.querySelectorAll(".add-list-btn").forEach(button => {
    const filename = button.dataset.filename;
    updateAddButtonState(button, filename);
  });

  document.querySelectorAll(".inventory-item").forEach(card => {
    const button = card.querySelector(".add-list-btn");
    if (!button) return;

    const filename = button.dataset.filename;
    card.classList.toggle("request-added", selectedFilenames.has(filename));
  });
}

function updateAddButtonState(button, filename) {
  const isAdded = selectedFilenames.has(filename);

  button.classList.toggle("added", isAdded);
  button.textContent = isAdded ? "Added to List" : "Add to List";
  button.setAttribute(
    "aria-label",
    isAdded ? "Remove this item from request list" : "Add this item to request list"
  );
}

function updateRequestListUI() {
  const selectedItems = getSelectedItems();
  const count = selectedItems.length;

  requestListCount.textContent = count.toString();

  if (count === 0) {
    requestListItems.innerHTML = "";
    requestListEmpty.classList.remove("hidden");
    copyListBtn.disabled = true;
    emailListBtn.disabled = true;
    downloadTxtBtn.disabled = true;
    copyShareLinkBtn.disabled = true;
    clearListBtn.disabled = true;
    return;
  }

  requestListEmpty.classList.add("hidden");
  copyListBtn.disabled = false;
  emailListBtn.disabled = false;
  downloadTxtBtn.disabled = false;
  copyShareLinkBtn.disabled = false;
  clearListBtn.disabled = false;

  requestListItems.innerHTML = "";

  selectedItems.forEach((item, index) => {
    const row = document.createElement("article");
    row.className = "request-list-item";

    const thumb = document.createElement("img");
    thumb.src = `images/${encodeURIComponent(item.filename)}`;
    thumb.alt = buildAltText(item);
    thumb.loading = "lazy";

    const details = document.createElement("div");
    details.className = "request-list-details";

    const title = document.createElement("h3");
    title.textContent = item.name || `Item ${index + 1}`;

    const meta = document.createElement("p");
    meta.textContent = `${item.set || "Set not listed"} • ${formatType(item.type)} • ${formatPrice(item.price)}`;

    const file = document.createElement("span");
    file.textContent = item.filename;

    details.appendChild(title);
    details.appendChild(meta);
    details.appendChild(file);

    const removeButton = document.createElement("button");
    removeButton.type = "button";
    removeButton.className = "request-remove-btn";
    removeButton.textContent = "Remove";
    removeButton.addEventListener("click", () => {
      removeRequestItem(item.filename);
    });

    row.appendChild(thumb);
    row.appendChild(details);
    row.appendChild(removeButton);

    requestListItems.appendChild(row);
  });
}

function buildRequestListText() {
  const selectedItems = getSelectedItems();

  if (selectedItems.length === 0) {
    return "";
  }

  const lines = [
    "Hi Chella Collectibles,",
    "",
    "I'm interested in the following items from your inventory:",
    ""
  ];

  selectedItems.forEach((item, index) => {
    lines.push(`${index + 1}. ${item.name || "Unnamed Item"}`);
    lines.push(`Set: ${item.set || "Set not listed"}`);
    lines.push(`Type: ${formatType(item.type)}`);
    lines.push(`Price: ${formatPrice(item.price)}`);

    if (item.condition) {
      lines.push(`Condition: ${item.condition}`);
    }

    lines.push(`Front Image/File: ${item.filename}`);

    if (item.backFilename) {
      lines.push(`Back Image/File: ${item.backFilename}`);
    }

    lines.push("");
  });

  lines.push("Thank you!");

  return lines.join("\n");
}

async function copyTextToClipboard(text) {
  if (!text) return false;

  if (navigator.clipboard && window.isSecureContext) {
    await navigator.clipboard.writeText(text);
    return true;
  }

  const textArea = document.createElement("textarea");
  textArea.value = text;
  textArea.style.position = "fixed";
  textArea.style.left = "-9999px";
  textArea.style.top = "-9999px";

  document.body.appendChild(textArea);
  textArea.focus();
  textArea.select();

  const successful = document.execCommand("copy");
  textArea.remove();

  return successful;
}

async function copyRequestList() {
  const text = buildRequestListText();

  if (!text) {
    showToast("Your list is empty.");
    return;
  }

  try {
    await copyTextToClipboard(text);
    showToast("Request list copied.");
  } catch (error) {
    console.error(error);
    showToast("Copy failed. Try downloading the TXT file.");
  }
}

function emailRequestList() {
  const text = buildRequestListText();

  if (!text) {
    showToast("Your list is empty.");
    return;
  }

  const subject = "Chella Collectibles Inventory Request";
  const mailtoUrl = `mailto:chellasales.business@gmail.com?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(text)}`;

  window.location.href = mailtoUrl;
}

function downloadRequestListTxt() {
  const text = buildRequestListText();

  if (!text) {
    showToast("Your list is empty.");
    return;
  }

  const blob = new Blob([text], {
    type: "text/plain;charset=utf-8"
  });

  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");

  link.href = url;
  link.download = "chella-request-list.txt";
  document.body.appendChild(link);
  link.click();

  link.remove();
  URL.revokeObjectURL(url);

  showToast("TXT downloaded.");
}

function buildShareLink() {
  const selectedItems = getSelectedItems();

  if (selectedItems.length === 0) {
    return "";
  }

  const rawList = selectedItems
    .map(item => item.filename)
    .join(shareLinkSeparator);

  const url = new URL(window.location.href);
  url.search = "";
  url.hash = "";
  url.searchParams.set("list", rawList);

  return url.toString();
}

async function copyShareLink() {
  const shareLink = buildShareLink();

  if (!shareLink) {
    showToast("Your list is empty.");
    return;
  }

  try {
    await copyTextToClipboard(shareLink);
    showToast("Share link copied.");
  } catch (error) {
    console.error(error);
    showToast("Copy failed. Try copying your list instead.");
  }
}

function openRequestDrawer() {
  updateRequestListUI();
  requestDrawer.classList.add("active");
  requestOverlay.classList.add("active");
  requestDrawer.setAttribute("aria-hidden", "false");
  requestOverlay.setAttribute("aria-hidden", "false");
}

function closeRequestListDrawer() {
  requestDrawer.classList.remove("active");
  requestOverlay.classList.remove("active");
  requestDrawer.setAttribute("aria-hidden", "true");
  requestOverlay.setAttribute("aria-hidden", "true");
}

let toastTimeout;

function showToast(message) {
  requestToast.textContent = message;
  requestToast.classList.add("active");

  clearTimeout(toastTimeout);

  toastTimeout = setTimeout(() => {
    requestToast.classList.remove("active");
  }, 2200);
}

/* EVENTS */

loadMoreBtn.addEventListener("click", renderNextBatch);

closeLightbox.addEventListener("click", closeImage);

showFrontBtn.addEventListener("click", () => {
  currentLightboxSide = "front";
  updateLightboxImage();
});

showBackBtn.addEventListener("click", () => {
  if (!currentLightboxItem || !currentLightboxItem.backFilename) return;
  currentLightboxSide = "back";
  updateLightboxImage();
});

lightbox.addEventListener("click", event => {
  if (event.target === lightbox) {
    closeImage();
  }
});

requestListButton.addEventListener("click", openRequestDrawer);
closeRequestDrawer.addEventListener("click", closeRequestListDrawer);
requestOverlay.addEventListener("click", closeRequestListDrawer);

copyListBtn.addEventListener("click", copyRequestList);
emailListBtn.addEventListener("click", emailRequestList);
downloadTxtBtn.addEventListener("click", downloadRequestListTxt);
copyShareLinkBtn.addEventListener("click", copyShareLink);
clearListBtn.addEventListener("click", clearRequestList);

document.addEventListener("keydown", event => {
  if (event.key === "Escape") {
    closeImage();
    closeRequestListDrawer();
  }

  if (!lightbox.classList.contains("active") || !currentLightboxItem) {
    return;
  }

  if (event.key === "ArrowLeft") {
    currentLightboxSide = "front";
    updateLightboxImage();
  }

  if (event.key === "ArrowRight" && currentLightboxItem.backFilename) {
    currentLightboxSide = "back";
    updateLightboxImage();
  }
});

nameSearch.addEventListener("input", applyFilters);
typeFilter.addEventListener("change", applyFilters);
setSearch.addEventListener("input", applyFilters);
priceSort.addEventListener("change", applyFilters);
clearFiltersBtn.addEventListener("click", clearFilters);

loadInventory();
