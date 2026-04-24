const gallery = document.getElementById("gallery");
const imageCount = document.getElementById("imageCount");
const loadMoreBtn = document.getElementById("loadMoreBtn");

const lightbox = document.getElementById("lightbox");
const lightboxImage = document.getElementById("lightboxImage");
const closeLightbox = document.getElementById("closeLightbox");

let allImages = [];
let visibleCount = 0;

const batchSize = 60;

async function loadImages() {
  try {
    const response = await fetch("images.json?v=" + Date.now());

    if (!response.ok) {
      throw new Error("Could not load images.json");
    }

    allImages = await response.json();

    if (!Array.isArray(allImages) || allImages.length === 0) {
      imageCount.textContent = "No images found yet.";
      loadMoreBtn.classList.add("hidden");
      return;
    }

    imageCount.textContent = `${allImages.length.toLocaleString()} items`;
    renderNextBatch();
  } catch (error) {
    gallery.innerHTML = `
      <div class="error-message">
        Images could not be loaded. Make sure images.json exists and was generated successfully.
      </div>
    `;
    imageCount.textContent = "Unable to load inventory.";
    loadMoreBtn.classList.add("hidden");
    console.error(error);
  }
}

function renderNextBatch() {
  const nextImages = allImages.slice(visibleCount, visibleCount + batchSize);

  nextImages.forEach(fileName => {
    const card = document.createElement("article");
    card.className = "card";

    const img = document.createElement("img");
    img.src = `images/${encodeURIComponent(fileName)}`;
    img.alt = "Chella Collectibles inventory item";
    img.loading = "lazy";

    img.addEventListener("click", () => {
      lightboxImage.src = `images/${encodeURIComponent(fileName)}`;
      lightbox.classList.add("active");
      lightbox.setAttribute("aria-hidden", "false");
    });

    card.appendChild(img);
    gallery.appendChild(card);
  });

  visibleCount += nextImages.length;

  if (visibleCount >= allImages.length) {
    loadMoreBtn.classList.add("hidden");
  } else {
    loadMoreBtn.classList.remove("hidden");
    loadMoreBtn.textContent = `Load More (${allImages.length - visibleCount} remaining)`;
  }
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

function closeImage() {
  lightbox.classList.remove("active");
  lightbox.setAttribute("aria-hidden", "true");
  lightboxImage.src = "";
}

loadImages();
