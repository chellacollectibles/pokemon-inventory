const gallery = document.getElementById("gallery");
const imageCount = document.getElementById("imageCount");
const loadMoreBtn = document.getElementById("loadMoreBtn");

const nameSearch = document.getElementById("nameSearch");
const typeFilter = document.getElementById("typeFilter");
const setSearch = document.getElementById("setSearch");
const clearFiltersBtn = document.getElementById("clearFiltersBtn");

const lightbox = document.getElementById("lightbox");
const lightboxImage = document.getElementById("lightboxImage");
const closeLightbox = document.getElementById("closeLightbox");

let allItems = [];
let filteredItems = [];
let visibleCount = 0;

const batchSize = 60;

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

    filteredItems = [...allItems];

    if (!Array.isArray(allItems) || allItems.length === 0) {
      imageCount.textContent = "No inventory found yet.";
      loadMoreBtn.classList.add("hidden");
      return;
    }

    renderFreshResults();
  } catch (error) {
    gallery.innerHTML = `
      <div class="error-message">
        Inventory could not be loaded. Make sure inventory.csv exists in the main GitHub folder and includes columns for filename, type, name, set, and price.
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
  return {
    filename: item.filename || "",
    type: normalizeType(item.type || ""),
    name: item.name || "",
    set: item.set || "",
    price: item.price || ""
  };
}

function normalizeType(type) {
  const cleaned = type.trim().toLowerCase();

  if (cleaned === "singles") return "single";
  if (cleaned === "graded cards") return "graded";
  if (cleaned === "sealed products") return "sealed";

  return cleaned;
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
    card.className = "inventory-item";

    const imageWrap = document.createElement("div");
    imageWrap.className = "inventory-image-wrap";

    const img = document.createElement("img");
    img.src = `images/${encodeURIComponent(item.filename)}`;
    img.alt = buildAltText(item);
    img.loading = "lazy";

    img.addEventListener("click", () => {
      lightboxImage.src = `images/${encodeURIComponent(item.filename)}`;
      lightboxImage.alt = buildAltText(item);
      lightbox.classList.add("active");
      lightbox.setAttribute("aria-hidden", "false");
    });

    imageWrap.appendChild(img);

    const info = document.createElement("div");
    info.className = "inventory-info";

    const topLine = document.createElement("div");
    topLine.className = "inventory-info-top";

    const typeBadge = document.createElement("span");
    typeBadge.className = `type-badge ${item.type || "unknown"}`;
    typeBadge.textContent = formatType(item.type);

    const price = document.createElement("span");
    price.className = "item-price";
    price.textContent = formatPrice(item.price);

    topLine.appendChild(typeBadge);
    topLine.appendChild(price);

    const title = document.createElement("h3");
    title.textContent = item.name || "Unnamed Item";

    const set = document.createElement("p");
    set.textContent = item.set ? item.set : "Set not listed";

    info.appendChild(topLine);
    info.appendChild(title);
    info.appendChild(set);

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

  filteredItems = allItems.filter(item => {
    const matchesName = !nameQuery || item.name.toLowerCase().includes(nameQuery);
    const matchesType = !typeQuery || item.type === typeQuery;
    const matchesSet = !setQuery || item.set.toLowerCase().includes(setQuery);

    return matchesName && matchesType && matchesSet;
  });

  renderFreshResults();
}

function clearFilters() {
  nameSearch.value = "";
  typeFilter.value = "";
  setSearch.value = "";

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
}

loadMoreBtn.addEventListener("click", renderNextBatch);

closeLightbox.addEventListener("click", closeImage);

lightbox.addEventListener("click", event => {
  if (event.target === lightbox) {
    closeImage();
  }
});

document.addEventListener("keydown", event => {
  if (event.key === "Escape") {
    closeImage();
  }
});

nameSearch.addEventListener("input", applyFilters);
typeFilter.addEventListener("change", applyFilters);
setSearch.addEventListener("input", applyFilters);
clearFiltersBtn.addEventListener("click", clearFilters);

loadInventory();
