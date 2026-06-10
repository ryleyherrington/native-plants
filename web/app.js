const DATA_URL = "data/plants.json";
const IMAGE_DIR = "images/";
const SECTION_ORDER = [
  "Large trees",
  "Small trees",
  "Large shrubs",
  "Small and medium shrubs",
  "Perennials, annuals and ferns"
];
const BLOOM_SEASONS = ["Spring", "Summer", "Fall", "Winter"];
const FAVORITES_KEY = "native-plants-web-favorites";

const state = {
  plants: [],
  layout: "grid",
  searchText: "",
  mobileFiltersOpen: false,
  selectedSections: new Set(),
  selectedDifficulties: new Set(),
  selectedBloomTimes: new Set(),
  selectedTraits: new Set(),
  collapsedSections: new Set(),
  favorites: new Set(loadJSON(FAVORITES_KEY, [])),
  selectedPlantId: null
};

const els = {
  filterPanel: document.querySelector(".filter-panel"),
  mobileFilterToggle: document.getElementById("mobileFilterToggle"),
  searchInput: document.getElementById("searchInput"),
  viewButtons: Array.from(document.querySelectorAll(".view-button")),
  clearFilters: document.getElementById("clearFilters"),
  filterGroups: document.getElementById("filterGroups"),
  activeFilters: document.getElementById("activeFilters"),
  sectionStack: document.getElementById("sectionStack"),
  emptyState: document.getElementById("emptyState"),
  visibleCount: document.getElementById("visibleCount"),
  visibleLabel: document.getElementById("visibleLabel"),
  dialog: document.getElementById("plantDialog"),
  closeDialog: document.getElementById("closeDialog"),
  dialogImage: document.getElementById("dialogImage"),
  dialogSection: document.getElementById("dialogSection"),
  dialogTitle: document.getElementById("dialogTitle"),
  dialogScientific: document.getElementById("dialogScientific"),
  dialogFavorite: document.getElementById("dialogFavorite"),
  dialogHabit: document.getElementById("dialogHabit"),
  dialogSize: document.getElementById("dialogSize"),
  dialogDifficulty: document.getElementById("dialogDifficulty"),
  dialogBloom: document.getElementById("dialogBloom"),
  dialogNotes: document.getElementById("dialogNotes"),
  dialogTraits: document.getElementById("dialogTraits"),
  dialogIcons: document.getElementById("dialogIcons"),
  dialogSource: document.getElementById("dialogSource")
};

init();

async function init() {
  applyInitialTheme();
  bindEvents();

  try {
    const plants = await loadPlants();
    state.plants = plants.map(preparePlant);
    renderFilters();
    render();
  } catch (error) {
    els.sectionStack.innerHTML = "";
    els.emptyState.hidden = false;
    els.emptyState.querySelector("h2").textContent = "Plant data did not load";
    els.emptyState.querySelector("p").textContent = error.message;
  }
}

async function loadPlants() {
  try {
    const response = await fetch(DATA_URL);
    if (!response.ok) {
      throw new Error(`Plant data failed to load: ${response.status}`);
    }
    return response.json();
  } catch (error) {
    if (Array.isArray(window.NATIVE_PLANTS_DATA)) {
      return window.NATIVE_PLANTS_DATA;
    }

    if (window.location.protocol === "file:") {
      throw new Error("The browser blocked local file access. Serve this folder over localhost or open the hosted site.");
    }

    throw new Error(`Could not load ${DATA_URL}. Confirm the data file is deployed next to the catalog.`);
  }
}

function bindEvents() {
  els.mobileFilterToggle.addEventListener("click", () => {
    state.mobileFiltersOpen = !state.mobileFiltersOpen;
    render();
  });
  els.searchInput.addEventListener("input", event => {
    state.searchText = event.target.value;
    render();
  });

  els.viewButtons.forEach(button => {
    button.addEventListener("click", () => {
      state.layout = button.dataset.layout;
      render();
    });
  });

  els.clearFilters.addEventListener("click", () => {
    state.selectedSections.clear();
    state.selectedDifficulties.clear();
    state.selectedBloomTimes.clear();
    state.selectedTraits.clear();
    state.searchText = "";
    els.searchInput.value = "";
    renderFilters();
    render();
  });

  els.sectionStack.addEventListener("click", event => {
    const favoriteButton = event.target.closest("[data-favorite-id]");
    if (favoriteButton) {
      event.stopPropagation();
      toggleFavorite(favoriteButton.dataset.favoriteId);
      return;
    }

    const sectionButton = event.target.closest("[data-section-toggle]");
    if (sectionButton) {
      const section = sectionButton.dataset.sectionToggle;
      if (state.collapsedSections.has(section)) {
        state.collapsedSections.delete(section);
      } else {
        state.collapsedSections.add(section);
      }
      render();
      return;
    }

    const plantButton = event.target.closest("[data-plant-id]");
    if (plantButton) {
      openPlant(plantButton.dataset.plantId);
    }
  });

  els.closeDialog.addEventListener("click", () => els.dialog.close());
  els.dialog.addEventListener("click", event => {
    if (event.target === els.dialog) {
      els.dialog.close();
    }
  });
  els.dialogFavorite.addEventListener("click", () => {
    if (state.selectedPlantId) {
      toggleFavorite(state.selectedPlantId);
      updateDialogFavorite();
    }
  });
}

function preparePlant(plant) {
  const bloomSeasons = bloomSeasonsFromNotes(plant.notes);
  const bloomDescription = bloomSeasons.join(", ");
  const searchableText = folded([
    plant.name,
    plant.scientificName,
    plant.section,
    plant.habit,
    plant.size,
    plant.difficulty,
    plant.notes,
    bloomDescription,
    ...plant.traits
  ].join(" "));

  return {
    ...plant,
    bloomSeasons,
    bloomDescription,
    searchableText
  };
}

function renderFilters() {
  const groups = [
    {
      id: "sections",
      title: "Section",
      values: orderedSections(),
      selected: state.selectedSections
    },
    {
      id: "difficulties",
      title: "Ease",
      values: uniqueValues(state.plants.map(plant => plant.difficulty)),
      selected: state.selectedDifficulties
    },
    {
      id: "bloom",
      title: "Bloom",
      values: BLOOM_SEASONS.filter(season => state.plants.some(plant => plant.bloomSeasons.includes(season))),
      selected: state.selectedBloomTimes
    },
    {
      id: "traits",
      title: "Traits",
      values: uniqueValues(state.plants.flatMap(plant => plant.traits)),
      selected: state.selectedTraits
    }
  ];

  els.filterGroups.innerHTML = groups.map(group => `
    <section class="filter-group" data-filter="${group.id}">
      <div class="filter-group-title">${escapeHTML(group.title)}</div>
      <div class="filter-chip-list">
        ${group.values.map(value => filterChip(group.id, value, group.selected.has(value))).join("")}
      </div>
    </section>
  `).join("");

  els.filterGroups.querySelectorAll("[data-filter-value]").forEach(button => {
    button.addEventListener("click", () => {
      const set = filterSetFor(button.dataset.filterGroup);
      const value = button.dataset.filterValue;
      if (set.has(value)) {
        set.delete(value);
      } else {
        set.add(value);
      }
      renderFilters();
      render();
    });
  });
}

function render() {
  const visiblePlants = state.plants.filter(matchesActiveFilters);
  const activeCount = activeFilterCount();
  const hasSearch = state.searchText.trim() !== "";
  const favoritePlants = visiblePlants.filter(plant => state.favorites.has(plant.id));
  const favoriteIds = new Set(favoritePlants.map(plant => plant.id));
  const groups = [];

  if (favoritePlants.length > 0) {
    groups.push(["Favorites", favoritePlants]);
  }

  orderedSections().forEach(section => {
    const plants = visiblePlants.filter(plant => plant.section === section && !favoriteIds.has(plant.id));
    if (plants.length > 0) {
      groups.push([section, plants]);
    }
  });

  els.visibleCount.textContent = visiblePlants.length.toString();
  els.visibleLabel.textContent = visiblePlants.length === 1 ? "plant" : "plants";
  els.clearFilters.disabled = activeCount === 0 && !hasSearch;
  els.filterPanel.classList.toggle("mobile-filters-open", state.mobileFiltersOpen);
  els.filterPanel.classList.toggle("has-active-filters", activeCount > 0);
  els.filterPanel.classList.toggle("has-search", hasSearch);
  els.mobileFilterToggle.textContent = state.mobileFiltersOpen
    ? "Hide filters"
    : activeCount > 0
      ? `Filters (${activeCount})`
      : "Filters";
  els.mobileFilterToggle.setAttribute("aria-expanded", String(state.mobileFiltersOpen));
  els.activeFilters.innerHTML = activeFilterPills();
  els.emptyState.hidden = visiblePlants.length > 0;
  els.viewButtons.forEach(button => {
    const isActive = button.dataset.layout === state.layout;
    button.classList.toggle("is-active", isActive);
    button.setAttribute("aria-pressed", String(isActive));
  });

  els.sectionStack.innerHTML = groups.map(([section, plants]) => plantSection(section, plants)).join("");
}

function plantSection(section, plants) {
  const isCollapsed = state.collapsedSections.has(section);
  return `
    <section class="plant-section">
      <button class="section-toggle" type="button" data-section-toggle="${escapeAttr(section)}">
        <strong>${escapeHTML(section)}</strong>
        <span class="section-count">${plants.length}</span>
        <span class="section-chevron" aria-hidden="true">${isCollapsed ? ">" : "v"}</span>
      </button>
      ${isCollapsed ? "" : `<div class="${state.layout === "grid" ? "plant-grid" : "plant-list"}">${plants.map(plantCard).join("")}</div>`}
    </section>
  `;
}

function plantCard(plant) {
  return state.layout === "grid" ? gridCard(plant) : listRow(plant);
}

function gridCard(plant) {
  const isFavorite = state.favorites.has(plant.id);
  return `
    <article class="plant-card">
      <button class="favorite-button ${isFavorite ? "is-favorite" : ""}" type="button" data-favorite-id="${escapeAttr(plant.id)}" aria-label="${isFavorite ? "Remove favorite" : "Favorite"} ${escapeAttr(plant.name)}">${isFavorite ? "&#9733;" : "&#9734;"}</button>
      <button class="plant-card-main" type="button" data-plant-id="${escapeAttr(plant.id)}">
        <img class="plant-photo" src="${IMAGE_DIR}${escapeAttr(plant.imageName)}" alt="${escapeAttr(plant.name)}" loading="lazy">
        <div class="plant-card-content">
          ${plantTitle(plant)}
          <p class="size-line">${escapeHTML(plant.size)}</p>
          <div class="badge-row">${difficultyBadge(plant)}${bloomBadge(plant)}</div>
          ${iconStrip(plant)}
        </div>
      </button>
    </article>
  `;
}

function listRow(plant) {
  const isFavorite = state.favorites.has(plant.id);
  return `
    <article class="plant-row">
      <button class="favorite-button ${isFavorite ? "is-favorite" : ""}" type="button" data-favorite-id="${escapeAttr(plant.id)}" aria-label="${isFavorite ? "Remove favorite" : "Favorite"} ${escapeAttr(plant.name)}">${isFavorite ? "&#9733;" : "&#9734;"}</button>
      <button class="plant-row-main" type="button" data-plant-id="${escapeAttr(plant.id)}">
        <img class="plant-photo" src="${IMAGE_DIR}${escapeAttr(plant.imageName)}" alt="${escapeAttr(plant.name)}" loading="lazy">
        <div class="plant-row-content">
          ${plantTitle(plant)}
          <p class="habit-line">${escapeHTML(plant.habit)}</p>
          <p class="size-line">${escapeHTML(plant.size)}</p>
          <div class="badge-row">${difficultyBadge(plant)}${bloomBadge(plant)}</div>
          ${iconStrip(plant)}
        </div>
      </button>
    </article>
  `;
}

function plantTitle(plant) {
  return `
    <div class="plant-name-line">
      <h3 class="plant-name">${escapeHTML(plant.name)}</h3>
      <p class="scientific">${escapeHTML(plant.scientificName)}</p>
    </div>
  `;
}

function difficultyBadge(plant) {
  const isModerate = folded(plant.difficulty).includes("moderately");
  return `<span class="difficulty-badge ${isModerate ? "moderate" : "easy"}">${escapeHTML(plant.difficulty)}</span>`;
}

function bloomBadge(plant) {
  if (!plant.bloomDescription) {
    return "";
  }
  return `<span class="bloom-badge">${escapeHTML(plant.bloomDescription)}</span>`;
}

function iconStrip(plant) {
  return `<img class="icon-strip" src="${IMAGE_DIR}${escapeAttr(plant.iconStripName)}" alt="" loading="lazy">`;
}

function filterChip(group, value, isSelected) {
  return `
    <button class="filter-chip ${isSelected ? "is-selected" : ""}" type="button" data-filter-group="${group}" data-filter-value="${escapeAttr(value)}" aria-pressed="${isSelected}">
      ${escapeHTML(value)}
    </button>
  `;
}

function activeFilterPills() {
  const labels = [
    ...Array.from(state.selectedSections),
    ...Array.from(state.selectedDifficulties),
    ...Array.from(state.selectedBloomTimes),
    ...Array.from(state.selectedTraits)
  ];

  if (state.searchText.trim()) {
    labels.unshift(`Search: ${state.searchText.trim()}`);
  }

  return labels.map(label => `<span class="active-filter">${escapeHTML(label)}</span>`).join("");
}

function matchesActiveFilters(plant) {
  const query = folded(state.searchText.trim());
  const queryMatches = query === "" || plant.searchableText.includes(query);
  const sectionMatches = state.selectedSections.size === 0 || state.selectedSections.has(plant.section);
  const difficultyMatches = state.selectedDifficulties.size === 0 || state.selectedDifficulties.has(plant.difficulty);
  const bloomMatches = state.selectedBloomTimes.size === 0 || !isDisjoint(state.selectedBloomTimes, plant.bloomSeasons);
  const traitMatches = state.selectedTraits.size === 0 || !isDisjoint(state.selectedTraits, plant.traits);
  return queryMatches && sectionMatches && difficultyMatches && bloomMatches && traitMatches;
}

function openPlant(plantId) {
  const plant = state.plants.find(item => item.id === plantId);
  if (!plant) {
    return;
  }

  state.selectedPlantId = plant.id;
  els.dialogImage.src = `${IMAGE_DIR}${plant.imageName}`;
  els.dialogImage.alt = plant.name;
  els.dialogSection.textContent = plant.section;
  els.dialogTitle.textContent = plant.name;
  els.dialogScientific.textContent = plant.scientificName;
  els.dialogHabit.textContent = plant.habit;
  els.dialogSize.textContent = plant.size;
  els.dialogDifficulty.textContent = plant.difficulty;
  els.dialogBloom.textContent = plant.bloomDescription || "Not listed";
  els.dialogNotes.textContent = plant.notes;
  els.dialogTraits.innerHTML = plant.traits.map(trait => `<span class="trait-pill">${escapeHTML(trait)}</span>`).join("");
  els.dialogIcons.src = `${IMAGE_DIR}${plant.iconStripName}`;
  els.dialogIcons.alt = `${plant.name} plant cue icons`;
  els.dialogSource.textContent = `Source page ${plant.sourcePage}`;
  updateDialogFavorite();

  if (!els.dialog.open) {
    els.dialog.showModal();
  }
}

function updateDialogFavorite() {
  const plant = state.plants.find(item => item.id === state.selectedPlantId);
  if (!plant) {
    return;
  }
  const isFavorite = state.favorites.has(plant.id);
  els.dialogFavorite.textContent = isFavorite ? "Favorited" : "Favorite";
  els.dialogFavorite.classList.toggle("is-favorite", isFavorite);
  els.dialogFavorite.setAttribute("aria-pressed", String(isFavorite));
}

function toggleFavorite(plantId) {
  if (state.favorites.has(plantId)) {
    state.favorites.delete(plantId);
  } else {
    state.favorites.add(plantId);
  }
  localStorage.setItem(FAVORITES_KEY, JSON.stringify(Array.from(state.favorites)));
  render();
}

function orderedSections() {
  const actual = new Set(state.plants.map(plant => plant.section));
  const ordered = SECTION_ORDER.filter(section => actual.has(section));
  const remaining = Array.from(actual).filter(section => !SECTION_ORDER.includes(section)).sort(compareText);
  return [...ordered, ...remaining];
}

function uniqueValues(values) {
  return Array.from(new Set(values)).sort(compareText);
}

function compareText(a, b) {
  return a.localeCompare(b, undefined, { sensitivity: "base" });
}

function activeFilterCount() {
  return state.selectedSections.size + state.selectedDifficulties.size + state.selectedBloomTimes.size + state.selectedTraits.size;
}

function filterSetFor(group) {
  switch (group) {
    case "sections":
      return state.selectedSections;
    case "difficulties":
      return state.selectedDifficulties;
    case "bloom":
      return state.selectedBloomTimes;
    case "traits":
      return state.selectedTraits;
    default:
      return new Set();
  }
}

function bloomSeasonsFromNotes(notes) {
  const bloomSegments = folded(notes)
    .split(/[;.,\n]/)
    .map(segment => segment.trim())
    .filter(containsBloomCue);
  const seasons = new Set();

  bloomSegments.forEach(segment => {
    seasonsInBloomSegment(segment).forEach(season => seasons.add(season));
  });

  return BLOOM_SEASONS.filter(season => seasons.has(season));
}

function containsBloomCue(segment) {
  return [
    "flower",
    "flowers",
    "bloom",
    "blooms",
    "blossom",
    "blossoms",
    "catkin",
    "catkins",
    "spikelet",
    "spikelets"
  ].some(cue => segment.includes(cue));
}

function seasonsInBloomSegment(segment) {
  const seasons = new Set();

  if (segment.includes("spring to fall") || segment.includes("spring through fall")) {
    seasons.add("Spring");
    seasons.add("Summer");
    seasons.add("Fall");
  }

  if (
    segment.includes("spring to summer") ||
    segment.includes("spring through summer") ||
    segment.includes("spring and summer") ||
    segment.includes("spring/summer")
  ) {
    seasons.add("Spring");
    seasons.add("Summer");
  }

  if (
    segment.includes("summer to fall") ||
    segment.includes("summer through fall") ||
    segment.includes("summer and fall") ||
    segment.includes("summer/fall")
  ) {
    seasons.add("Summer");
    seasons.add("Fall");
  }

  if (
    segment.includes("winter to spring") ||
    segment.includes("winter through spring") ||
    segment.includes("winter and spring") ||
    segment.includes("december through spring")
  ) {
    seasons.add("Winter");
    seasons.add("Spring");
  }

  if (segment.includes("spring")) {
    seasons.add("Spring");
  }
  if (segment.includes("summer")) {
    seasons.add("Summer");
  }
  if (segment.includes("fall") || segment.includes("autumn")) {
    seasons.add("Fall");
  }
  if (segment.includes("winter") || segment.includes("december") || segment.includes("january") || segment.includes("february")) {
    seasons.add("Winter");
  }

  return seasons;
}

function isDisjoint(selected, values) {
  return values.every(value => !selected.has(value));
}

function folded(value) {
  return String(value)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase();
}

function escapeHTML(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function escapeAttr(value) {
  return escapeHTML(value);
}

function loadJSON(key, fallback) {
  try {
    return JSON.parse(localStorage.getItem(key)) || fallback;
  } catch {
    return fallback;
  }
}

function applyInitialTheme() {
  const theme = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  document.documentElement.setAttribute("data-theme", theme);
}
