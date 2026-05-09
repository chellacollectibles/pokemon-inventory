const canvas = document.getElementById("storyCanvas");
const ctx = canvas.getContext("2d");

const storyNumber = document.getElementById("storyNumber");
const showingRange = document.getElementById("showingRange");
const totalItems = document.getElementById("totalItems");
const messageBox = document.getElementById("messageBox");

const typeFilter = document.getElementById("typeFilter");
const searchInput = document.getElementById("searchInput");
const startIndexInput = document.getElementById("startIndexInput");
const backgroundSelect = document.getElementById("backgroundSelect");
const headlineInput = document.getElementById("headlineInput");
const footerInput = document.getElementById("footerInput");

const showHeaderToggle = document.getElementById("showHeaderToggle");
const showFooterToggle = document.getElementById("showFooterToggle");
const showLogoToggle = document.getElementById("showLogoToggle");

const previousBtn = document.getElementById("previousBtn");
const nextBtn = document.getElementById("nextBtn");
const downloadBtn = document.getElementById("downloadBtn");
const openImageBtn = document.getElementById("openImageBtn");

const ITEMS_PER_STORY = 9;
const STORY_WIDTH = 1080;
const STORY_HEIGHT = 1920;

let allItems = [];
let filteredItems = [];
let currentStartIndex = 0;
let logoImage = null;
let renderToken = 0;

async function loadInventory() {
  try {
    showMessage("Loading inventory...", false);

    await loadLogo();

    const response = await fetch("inventory.csv?v=" + Date.now());

    if (!response.ok) {
      throw new Error("Could not load inventory.csv");
    }

    const csvText = await response.text();

    allItems = parseCSV(csvText)
      .map(cleanInventoryItem)
      .filter(item => item.filename);

    filteredItems = [...allItems];

    if (filteredItems.length === 0) {
      showMessage("Inventory loaded, but no usable rows were found.", true);
    } else {
      hideMessage();
    }

    applyFiltersAndRender();
  } catch (error) {
    console.error(error);
    showMessage("Inventory could not be loaded. Make sure story-builder.html is running from your website/repo, not opened directly as a local file.", true);
    drawErrorState("Could not load inventory.csv");
  }
}

async function loadLogo() {
  try {
    logoImage = await loadImage("assets/small-logo.png");
  } catch {
    try {
      logoImage = await loadImage("assets/logo.png");
    } catch {
      logoImage = null;
    }
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

  return {
    filename: item.filename || "",
    backFilename: item.back_filename || item.backfilename || "",
    type: normalizeType(item.type || ""),
    name: name,
    set: item.set || "",
    price: item.price || "",
    conditionLabel: extractStoryCondition(name, item.type || "")
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

function extractStoryCondition(name, type) {
  const typeCleaned = normalizeType(type || "");
  const cleaned = String(name || "").toLowerCase();

  if (typeCleaned === "graded") return "Graded";

  if (cleaned.includes("near mint")) return "NM";
  if (cleaned.includes("lightly played")) return "LP";
  if (cleaned.includes("moderately played")) return "MP";
  if (cleaned.includes("heavily played")) return "HP";
  if (cleaned.includes("damaged")) return "DMG";

  return "";
}

function applyFiltersAndRender() {
  const typeValue = typeFilter.value.trim().toLowerCase();
  const searchValue = searchInput.value.trim().toLowerCase();

  filteredItems = allItems.filter(item => {
    const matchesType = !typeValue || item.type === typeValue;
    const matchesSearch =
      !searchValue ||
      item.name.toLowerCase().includes(searchValue) ||
      item.set.toLowerCase().includes(searchValue) ||
      item.filename.toLowerCase().includes(searchValue);

    return matchesType && matchesSearch;
  });

  const requestedStart = Number(startIndexInput.value);
  const safeStart = Number.isFinite(requestedStart) && requestedStart > 0 ? requestedStart - 1 : 0;

  currentStartIndex = clampStartIndex(safeStart);
  startIndexInput.value = filteredItems.length === 0 ? 1 : currentStartIndex + 1;

  renderStory();
}

function clampStartIndex(index) {
  if (filteredItems.length === 0) return 0;

  const maxStart = Math.max(0, Math.floor((filteredItems.length - 1) / ITEMS_PER_STORY) * ITEMS_PER_STORY);
  return Math.min(Math.max(0, index), maxStart);
}

async function renderStory() {
  const token = ++renderToken;
  const storyItems = filteredItems.slice(currentStartIndex, currentStartIndex + ITEMS_PER_STORY);

  updateStatus();

  if (storyItems.length === 0) {
    drawErrorState("No matching inventory");
    return;
  }

  drawBackground();
  drawStoryFrame(storyItems);

  const imagePromises = storyItems.map(item =>
    loadImage(`images/${encodeURIComponent(item.filename)}`).catch(() => null)
  );
  const images = await Promise.all(imagePromises);

  if (token !== renderToken) return;

  drawBackground();
  drawStoryFrame(storyItems);

  storyItems.forEach((item, index) => {
    drawCardSlot(item, images[index], index);
  });

  drawBrandingAndText();
}

function updateStatus() {
  const total = filteredItems.length;
  const storyIndex = total === 0 ? 0 : Math.floor(currentStartIndex / ITEMS_PER_STORY) + 1;
  const storyTotal = total === 0 ? 0 : Math.ceil(total / ITEMS_PER_STORY);
  const start = total === 0 ? 0 : currentStartIndex + 1;
  const end = Math.min(currentStartIndex + ITEMS_PER_STORY, total);

  storyNumber.textContent = `${storyIndex}/${storyTotal}`;
  showingRange.textContent = total === 0 ? "0" : `${start}-${end}`;
  totalItems.textContent = total.toLocaleString();

  previousBtn.disabled = currentStartIndex <= 0;
  nextBtn.disabled = currentStartIndex + ITEMS_PER_STORY >= total;
  downloadBtn.disabled = total === 0;
  openImageBtn.disabled = total === 0;
}

function drawBackground() {
  const bg = backgroundSelect.value;

  if (bg === "light") {
    const gradient = ctx.createLinearGradient(0, 0, STORY_WIDTH, STORY_HEIGHT);
    gradient.addColorStop(0, "#f7fbff");
    gradient.addColorStop(1, "#dfe9f7");
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, STORY_WIDTH, STORY_HEIGHT);

    drawSoftCircle(110, 170, 360, "rgba(255, 223, 60, 0.22)");
    drawSoftCircle(990, 320, 420, "rgba(40, 107, 216, 0.14)");
    return;
  }

  let top = "#111318";
  let bottom = "#05070b";
  let accentOne = "rgba(255, 223, 60, 0.10)";
  let accentTwo = "rgba(40, 107, 216, 0.13)";

  if (bg === "blue") {
    top = "#07142f";
    bottom = "#020712";
    accentOne = "rgba(255, 223, 60, 0.12)";
    accentTwo = "rgba(40, 107, 216, 0.28)";
  }

  if (bg === "red") {
    top = "#19090d";
    bottom = "#050304";
    accentOne = "rgba(244, 63, 63, 0.26)";
    accentTwo = "rgba(255, 223, 60, 0.10)";
  }

  const gradient = ctx.createLinearGradient(0, 0, STORY_WIDTH, STORY_HEIGHT);
  gradient.addColorStop(0, top);
  gradient.addColorStop(1, bottom);
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, STORY_WIDTH, STORY_HEIGHT);

  drawSoftCircle(80, 220, 420, accentOne);
  drawSoftCircle(1040, 390, 520, accentTwo);
  drawSoftCircle(880, 1760, 520, "rgba(255,255,255,0.045)");
  drawNoise();
}

function drawSoftCircle(x, y, radius, color) {
  const gradient = ctx.createRadialGradient(x, y, 0, x, y, radius);
  gradient.addColorStop(0, color);
  gradient.addColorStop(1, "rgba(0,0,0,0)");
  ctx.fillStyle = gradient;
  ctx.beginPath();
  ctx.arc(x, y, radius, 0, Math.PI * 2);
  ctx.fill();
}

function drawNoise() {
  ctx.save();
  ctx.globalAlpha = 0.035;

  for (let i = 0; i < 2500; i++) {
    const x = Math.random() * STORY_WIDTH;
    const y = Math.random() * STORY_HEIGHT;
    const shade = Math.random() > 0.5 ? 255 : 0;
    ctx.fillStyle = `rgb(${shade}, ${shade}, ${shade})`;
    ctx.fillRect(x, y, 1.2, 1.2);
  }

  ctx.restore();
}

function getGridMetrics() {
  const showHeader = showHeaderToggle.checked;
  const showFooter = showFooterToggle.checked;

  const topSafe = showHeader ? 172 : 66;
  const bottomSafe = showFooter ? 128 : 58;

  const gridLeft = 26;
  const gridRight = 26;
  const gridTop = topSafe;
  const gridBottom = STORY_HEIGHT - bottomSafe;

  const gapX = 16;
  const gapY = 24;
  const slotWidth = (STORY_WIDTH - gridLeft - gridRight - gapX * 2) / 3;
  const slotHeight = (gridBottom - gridTop - gapY * 2) / 3;

  return {
    gridLeft,
    gridRight,
    gridTop,
    gridBottom,
    gapX,
    gapY,
    slotWidth,
    slotHeight
  };
}

function drawStoryFrame(storyItems) {
  const metrics = getGridMetrics();

  ctx.save();
  ctx.strokeStyle = "rgba(255,255,255,0.08)";
  ctx.lineWidth = 2;
  roundRect(ctx, 24, 28, STORY_WIDTH - 48, STORY_HEIGHT - 56, 36);
  ctx.stroke();
  ctx.restore();

  for (let i = 0; i < storyItems.length; i++) {
    const col = i % 3;
    const row = Math.floor(i / 3);
    const x = metrics.gridLeft + col * (metrics.slotWidth + metrics.gapX);
    const y = metrics.gridTop + row * (metrics.slotHeight + metrics.gapY);

    ctx.save();

    const bg = backgroundSelect.value;
    if (bg === "light") {
      ctx.fillStyle = "rgba(255,255,255,0.74)";
      ctx.strokeStyle = "rgba(7,20,47,0.08)";
    } else {
      ctx.fillStyle = "rgba(234,238,245,0.95)";
      ctx.strokeStyle = "rgba(255,255,255,0.22)";
    }

    ctx.shadowColor = "rgba(0,0,0,0.23)";
    ctx.shadowBlur = 18;
    ctx.shadowOffsetY = 10;
    roundRect(ctx, x, y, metrics.slotWidth, metrics.slotHeight, 28);
    ctx.fill();

    ctx.shadowColor = "transparent";
    ctx.lineWidth = 2;
    roundRect(ctx, x, y, metrics.slotWidth, metrics.slotHeight, 28);
    ctx.stroke();

    ctx.restore();
  }
}

function drawCardSlot(item, image, index) {
  const metrics = getGridMetrics();

  const col = index % 3;
  const row = Math.floor(index / 3);

  const slotX = metrics.gridLeft + col * (metrics.slotWidth + metrics.gapX);
  const slotY = metrics.gridTop + row * (metrics.slotHeight + metrics.gapY);

  // Slightly enlarged scan area
  const paddingX = -30;
  const paddingY = -10;

  const infoBlockHeight = item.conditionLabel ? 100 : 80;

  const imageAreaX = slotX + paddingX;
  const imageAreaY = slotY + paddingY;
  const imageAreaW = metrics.slotWidth - paddingX * 2;
  const imageAreaH = metrics.slotHeight - paddingY * 2 - infoBlockHeight;

  if (!image) {
    drawMissingImage(slotX, slotY, metrics.slotWidth, metrics.slotHeight, item.filename);
    drawPriceAndCondition(item, slotX, slotY, metrics.slotWidth, metrics.slotHeight);
    return;
  }

  const fit = containRect(
    image.naturalWidth,
    image.naturalHeight,
    imageAreaX,
    imageAreaY,
    imageAreaW,
    imageAreaH
  );

  ctx.save();
  ctx.shadowColor = "rgba(0,0,0,0.20)";
  ctx.shadowBlur = 12;
  ctx.shadowOffsetY = 8;
  ctx.drawImage(image, fit.x, fit.y, fit.w, fit.h);
  ctx.restore();

  drawPriceAndCondition(item, slotX, slotY, metrics.slotWidth, metrics.slotHeight);
}

function drawPriceAndCondition(item, slotX, slotY, slotW, slotH) {
  const priceText = formatPrice(item.price);
  const conditionText = item.conditionLabel || "";

  ctx.save();

  ctx.font = "950 56px Outfit, Inter, Arial, sans-serif";
  const priceMetrics = ctx.measureText(priceText);
  const priceBoxW = Math.max(166, priceMetrics.width + 58);
  const priceBoxH = 82;
  const conditionBoxH = conditionText ? 36 : 0;
  const gap = conditionText ? 8 : 0;
  const totalH = priceBoxH + gap + conditionBoxH;

  const priceBoxX = slotX + (slotW - priceBoxW) / 2;
  const priceBoxY = slotY + slotH - totalH - 22;

  ctx.shadowColor = "rgba(0,0,0,0.24)";
  ctx.shadowBlur = 12;
  ctx.shadowOffsetY = 7;

  const priceGradient = ctx.createLinearGradient(priceBoxX, priceBoxY, priceBoxX, priceBoxY + priceBoxH);
  priceGradient.addColorStop(0, "#ffffff");
  priceGradient.addColorStop(1, "#f2f4f8");

  ctx.fillStyle = priceGradient;
  roundRect(ctx, priceBoxX, priceBoxY, priceBoxW, priceBoxH, 10);
  ctx.fill();

  ctx.shadowColor = "transparent";

  ctx.strokeStyle = "rgba(7,20,47,0.08)";
  ctx.lineWidth = 2;
  roundRect(ctx, priceBoxX, priceBoxY, priceBoxW, priceBoxH, 10);
  ctx.stroke();

  ctx.fillStyle = "#050505";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(priceText, priceBoxX + priceBoxW / 2, priceBoxY + priceBoxH / 2 + 1);

  if (conditionText) {
    const conditionY = priceBoxY + priceBoxH + gap;
    const conditionW = Math.min(priceBoxW - 14, Math.max(94, ctx.measureText(conditionText).width + 38));
    const conditionX = slotX + (slotW - conditionW) / 2;

    const conditionGradient = ctx.createLinearGradient(conditionX, conditionY, conditionX, conditionY + conditionBoxH);
    conditionGradient.addColorStop(0, "#172a52");
    conditionGradient.addColorStop(1, "#07142f");

    ctx.fillStyle = conditionGradient;
    roundRect(ctx, conditionX, conditionY, conditionW, conditionBoxH, 999);
    ctx.fill();

    ctx.strokeStyle = "rgba(255,255,255,0.18)";
    ctx.lineWidth = 1.5;
    roundRect(ctx, conditionX, conditionY, conditionW, conditionBoxH, 999);
    ctx.stroke();

    ctx.fillStyle = "#ffffff";
    ctx.font = "950 21px Outfit, Inter, Arial, sans-serif";
    ctx.fillText(conditionText, conditionX + conditionW / 2, conditionY + conditionBoxH / 2 + 1);
  }

  ctx.restore();
}

function drawBrandingAndText() {
  const showHeader = showHeaderToggle.checked;
  const showFooter = showFooterToggle.checked;
  const showLogo = showLogoToggle.checked;

  const bgLight = backgroundSelect.value === "light";
  const mainText = bgLight ? "#07142f" : "#ffffff";

  if (showHeader) {
    const headline = headlineInput.value.trim() || "Claim Sale";

    ctx.save();

    if (showLogo && logoImage) {
      const logoW = 128;
      const ratio = logoImage.naturalHeight / logoImage.naturalWidth;
      const logoH = logoW * ratio;
      ctx.drawImage(logoImage, 52, 42, logoW, logoH);
    }

    ctx.fillStyle = mainText;
    ctx.font = "950 70px Outfit, Inter, Arial, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    fitText(ctx, headline, STORY_WIDTH / 2, 56, 690, 70);

    ctx.restore();
  }

  if (showFooter) {
    const footer = footerInput.value.trim() || "@chellacollectibles • Message to claim";

    ctx.save();

    ctx.fillStyle = bgLight ? "rgba(255,255,255,0.82)" : "rgba(255,255,255,0.10)";
    roundRect(ctx, 54, STORY_HEIGHT - 104, STORY_WIDTH - 108, 64, 999);
    ctx.fill();

    ctx.strokeStyle = bgLight ? "rgba(7,20,47,0.10)" : "rgba(255,255,255,0.12)";
    ctx.lineWidth = 2;
    roundRect(ctx, 54, STORY_HEIGHT - 104, STORY_WIDTH - 108, 64, 999);
    ctx.stroke();

    ctx.fillStyle = mainText;
    ctx.font = "900 31px Outfit, Inter, Arial, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    fitText(ctx, footer, STORY_WIDTH / 2, STORY_HEIGHT - 72, STORY_WIDTH - 170, 31);

    ctx.restore();
  }
}

function drawMissingImage(x, y, w, h, filename) {
  ctx.save();

  ctx.fillStyle = "rgba(255,255,255,0.72)";
  roundRect(ctx, x + 10, y + 10, w - 20, h - 20, 24);
  ctx.fill();

  ctx.strokeStyle = "rgba(7,20,47,0.14)";
  ctx.lineWidth = 3;
  roundRect(ctx, x + 10, y + 10, w - 20, h - 20, 24);
  ctx.stroke();

  ctx.fillStyle = "#07142f";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.font = "900 24px Inter, Arial, sans-serif";
  ctx.fillText("Image Missing", x + w / 2, y + h / 2 - 16);

  ctx.fillStyle = "rgba(7,20,47,0.66)";
  ctx.font = "700 18px Inter, Arial, sans-serif";
  fitText(ctx, filename, x + w / 2, y + h / 2 + 22, w - 44, 18);

  ctx.restore();
}

function drawErrorState(message) {
  drawBackground();

  ctx.save();
  ctx.fillStyle = backgroundSelect.value === "light" ? "#07142f" : "#ffffff";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.font = "900 58px Outfit, Inter, Arial, sans-serif";
  ctx.fillText(message, STORY_WIDTH / 2, STORY_HEIGHT / 2);
  ctx.restore();

  updateStatus();
}

function containRect(imgW, imgH, x, y, w, h) {
  const scale = Math.min(w / imgW, h / imgH);
  const drawW = imgW * scale;
  const drawH = imgH * scale;

  return {
    x: x + (w - drawW) / 2,
    y: y + (h - drawH) / 2,
    w: drawW,
    h: drawH
  };
}

function formatPrice(price) {
  const cleaned = String(price || "").trim();

  if (!cleaned) {
    return "DM";
  }

  const numeric = Number(cleaned.replace(/[$,]/g, ""));

  if (!Number.isNaN(numeric)) {
    return `$${numeric.toLocaleString()}`;
  }

  return cleaned.startsWith("$") ? cleaned : `$${cleaned}`;
}

function loadImage(src) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = reject;
    image.src = src;
  });
}

function roundRect(context, x, y, width, height, radius) {
  const r = Math.min(radius, width / 2, height / 2);

  context.beginPath();
  context.moveTo(x + r, y);
  context.arcTo(x + width, y, x + width, y + height, r);
  context.arcTo(x + width, y + height, x, y + height, r);
  context.arcTo(x, y + height, x, y, r);
  context.arcTo(x, y, x + width, y, r);
  context.closePath();
}

function fitText(context, text, x, y, maxWidth, startingSize) {
  let fontSize = startingSize;

  while (fontSize > 14) {
    const existingFont = context.font;
    const fontParts = existingFont.split(" ");
    const family = fontParts.slice(2).join(" ") || "Inter, Arial, sans-serif";
    const weight = fontParts[0] || "900";

    context.font = `${weight} ${fontSize}px ${family}`;

    if (context.measureText(text).width <= maxWidth) {
      break;
    }

    fontSize -= 2;
  }

  context.fillText(text, x, y);
}

function showMessage(message, isError) {
  messageBox.hidden = false;
  messageBox.textContent = message;
  messageBox.style.background = isError ? "#fff1f1" : "#fff4d6";
  messageBox.style.borderColor = isError ? "rgba(244, 63, 63, 0.32)" : "rgba(255, 184, 46, 0.36)";
  messageBox.style.color = isError ? "#9b1c1c" : "#755100";
}

function hideMessage() {
  messageBox.hidden = true;
  messageBox.textContent = "";
}

function goPrevious() {
  currentStartIndex = clampStartIndex(currentStartIndex - ITEMS_PER_STORY);
  startIndexInput.value = currentStartIndex + 1;
  renderStory();
}

function goNext() {
  currentStartIndex = clampStartIndex(currentStartIndex + ITEMS_PER_STORY);
  startIndexInput.value = currentStartIndex + 1;
  renderStory();
}

function downloadStory() {
  const storyIndex = filteredItems.length === 0 ? 1 : Math.floor(currentStartIndex / ITEMS_PER_STORY) + 1;
  const link = document.createElement("a");

  link.href = canvas.toDataURL("image/png");
  link.download = `chella-claim-sale-${String(storyIndex).padStart(2, "0")}.png`;

  document.body.appendChild(link);
  link.click();
  link.remove();
}

function openStoryImage() {
  const dataUrl = canvas.toDataURL("image/png");
  const opened = window.open();

  if (!opened) {
    showMessage("Popup blocked. Use Download Story PNG instead.", true);
    return;
  }

  opened.document.write(`
    <!DOCTYPE html>
    <html>
      <head>
        <title>Chella Claim Sale Image</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            background: #111;
          }
          img {
            width: min(100vw, 540px);
            height: auto;
            display: block;
          }
        </style>
      </head>
      <body>
        <img src="${dataUrl}" alt="Generated Chella Collectibles claim sale story">
      </body>
    </html>
  `);

  opened.document.close();
}

[
  typeFilter,
  searchInput,
  backgroundSelect,
  headlineInput,
  footerInput,
  showHeaderToggle,
  showFooterToggle,
  showLogoToggle
].forEach(element => {
  element.addEventListener("input", applyFiltersAndRender);
  element.addEventListener("change", applyFiltersAndRender);
});

startIndexInput.addEventListener("change", applyFiltersAndRender);
startIndexInput.addEventListener("keydown", event => {
  if (event.key === "Enter") {
    applyFiltersAndRender();
  }
});

previousBtn.addEventListener("click", goPrevious);
nextBtn.addEventListener("click", goNext);
downloadBtn.addEventListener("click", downloadStory);
openImageBtn.addEventListener("click", openStoryImage);

loadInventory();