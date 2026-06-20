const DB_NAME = "black-nebula-archive";
const DB_VERSION = 1;
const STORE_NAME = "tracks";

const state = {
  tracks: [],
  pendingArt: null,
  artistFilter: "all",
  query: "",
  displayFilter: "all",
};

const els = {
  dropzone: document.querySelector("#dropzone"),
  fileInput: document.querySelector("#fileInput"),
  folderInput: document.querySelector("#folderInput"),
  filePickButton: document.querySelector("#filePickButton"),
  folderPickButton: document.querySelector("#folderPickButton"),
  dropStatus: document.querySelector("#dropStatus"),
  importSummaryText: document.querySelector("#importSummaryText"),
  trackList: document.querySelector("#trackList"),
  emptyState: document.querySelector("#emptyState"),
  template: document.querySelector("#trackTemplate"),
  searchInput: document.querySelector("#searchInput"),
  filterSelect: document.querySelector("#filterSelect"),
  artistTabs: document.querySelector("#artistTabs"),
  pendingArt: document.querySelector("#pendingArt"),
  pendingArtName: document.querySelector("#pendingArtName"),
  clearPendingArt: document.querySelector("#clearPendingArt"),
  exportButton: document.querySelector("#exportButton"),
  importInput: document.querySelector("#importInput"),
};

const objectUrls = new Set();

init();

async function init() {
  state.tracks = await restore();
  bindDropzone();
  bindControls();
  render();
}

function bindDropzone() {
  els.filePickButton.addEventListener("click", (event) => {
    event.stopPropagation();
    els.fileInput.click();
  });

  els.folderPickButton.addEventListener("click", (event) => {
    event.stopPropagation();
    pickFolder();
  });

  els.dropzone.addEventListener("click", (event) => {
    if (event.target.closest("button")) return;
    els.fileInput.click();
  });

  els.fileInput.addEventListener("change", (event) => {
    setDropStatus("ファイルを確認中...", "busy");
    handleFiles(normalizeFiles([...event.target.files]), "ファイル");
    event.target.value = "";
  });

  els.folderInput.addEventListener("change", (event) => {
    setDropStatus("フォルダーを読み取り中...", "busy");
    handleFiles(normalizeFiles([...event.target.files]), "フォルダー");
    event.target.value = "";
  });

  ["dragenter", "dragover"].forEach((type) => {
    els.dropzone.addEventListener(type, (event) => {
      event.preventDefault();
      els.dropzone.classList.add("is-dragging");
    });
  });

  ["dragleave", "drop"].forEach((type) => {
    els.dropzone.addEventListener(type, () => els.dropzone.classList.remove("is-dragging"));
  });

  els.dropzone.addEventListener("drop", async (event) => {
    event.preventDefault();
    setDropStatus("フォルダーを探索中...", "busy");
    const files = await getDroppedFiles(event.dataTransfer);
    handleFiles(files, "ドロップ");
  });
}

function bindControls() {
  els.searchInput.addEventListener("input", (event) => {
    state.query = event.target.value.trim().toLowerCase();
    render();
  });

  els.filterSelect.addEventListener("change", (event) => {
    state.displayFilter = event.target.value;
    render();
  });

  els.clearPendingArt.addEventListener("click", () => {
    state.pendingArt = null;
    renderPendingArt();
  });

  els.exportButton.addEventListener("click", exportList);

  els.importInput.addEventListener("change", async (event) => {
    const file = event.target.files[0];
    if (!file) return;
    await importList(await file.text());
    event.target.value = "";
  });
}

async function handleFiles(files, sourceLabel = "取り込み") {
  if (!files.length) {
    setDropStatus(`${sourceLabel}: 読み込めるファイルが見つかりませんでした`, "error");
    setImportSummary(sourceLabel, 0, 0, 0);
    return;
  }

  const imageFiles = files.filter(({ file }) => isImageFile(file));
  const audioFiles = files.filter(({ file }) => isAudioFile(file));

  setDropStatus(`${sourceLabel}: 音源 ${audioFiles.length}件 / 画像 ${imageFiles.length}件を検出`, "busy");
  setImportSummary(sourceLabel, files.length, audioFiles.length, imageFiles.length);

  if (!audioFiles.length && !imageFiles.length) {
    setDropStatus(`${sourceLabel}: 対応している音源・画像が見つかりませんでした`, "error");
    return;
  }

  if (imageFiles.length) {
    state.pendingArt = fileToMedia(imageFiles[imageFiles.length - 1].file);
  }

  for (const { file: audioFile, path } of audioFiles) {
    const art = state.pendingArt ? { ...state.pendingArt } : null;
    state.tracks.unshift({
      id: crypto.randomUUID(),
      title: stripExtension(audioFile.name),
      artist: getArtistFromPath(path),
      note: "",
      size: audioFile.size,
      isPublic: false,
      audio: fileToMedia(audioFile),
      art,
      createdAt: Date.now(),
    });
  }

  setDropStatus(`${sourceLabel}: 保存中...`, "busy");
  await persist();
  render();
  setDropStatus(
    audioFiles.length ? `${sourceLabel}: ${audioFiles.length}件の音源を取り込みました` : `${sourceLabel}: 画像をジャケット候補にしました`,
    "done",
  );
}

function normalizeFiles(files) {
  return files.map((file) => ({ file, path: file.webkitRelativePath || file.name }));
}

async function getDroppedFiles(dataTransfer) {
  const entries = [...dataTransfer.items].map((item) => item.webkitGetAsEntry?.()).filter(Boolean);
  if (!entries.length) return normalizeFiles([...dataTransfer.files]);
  const nested = await Promise.all(entries.map((entry) => readEntry(entry)));
  return nested.flat().filter(({ file }) => isAudioFile(file) || isImageFile(file));
}

async function pickFolder() {
  if (!window.showDirectoryPicker) {
    setDropStatus("このブラウザではフォルダー選択入力を使います", "busy");
    els.folderInput.click();
    return;
  }

  try {
    setDropStatus("フォルダーを選択中...", "busy");
    const directoryHandle = await window.showDirectoryPicker();
    setDropStatus(`${directoryHandle.name} を探索中...`, "busy");
    const files = await readDirectoryHandle(directoryHandle, `${directoryHandle.name}/`);
    handleFiles(files, directoryHandle.name);
  } catch (error) {
    if (error.name !== "AbortError") {
      console.warn(error);
      setDropStatus("フォルダーを開けませんでした。ドラッグ&ドロップも試せます", "error");
    }
  }
}

function readEntry(entry, parentPath = "") {
  if (entry.isFile) {
    return new Promise((resolve, reject) => {
      entry.file((file) => resolve([{ file, path: `${parentPath}${file.name}` }]), reject);
    });
  }

  if (entry.isDirectory) {
    const directoryPath = `${parentPath}${entry.name}/`;
    const reader = entry.createReader();
    return readAllDirectoryEntries(reader).then(async (entries) => {
      const nested = await Promise.all(entries.map((child) => readEntry(child, directoryPath)));
      return nested.flat();
    });
  }

  return Promise.resolve([]);
}

function readAllDirectoryEntries(reader) {
  const entries = [];
  return new Promise((resolve, reject) => {
    function readBatch() {
      reader.readEntries((batch) => {
        if (!batch.length) {
          resolve(entries);
          return;
        }
        entries.push(...batch);
        readBatch();
      }, reject);
    }
    readBatch();
  });
}

async function readDirectoryHandle(directoryHandle, parentPath = "") {
  const found = [];
  for await (const [name, handle] of directoryHandle.entries()) {
    const path = `${parentPath}${name}`;
    if (handle.kind === "file") found.push({ file: await handle.getFile(), path });
    if (handle.kind === "directory") found.push(...(await readDirectoryHandle(handle, `${path}/`)));
  }
  return found.filter(({ file }) => isAudioFile(file) || isImageFile(file));
}

function render() {
  renderArtistTabs();
  renderPendingArt();
  renderTracks();
}

function renderArtistTabs() {
  const artists = [...new Set(state.tracks.map((track) => cleanArtist(track.artist)))].sort((a, b) => {
    if (a === "未分類") return -1;
    if (b === "未分類") return 1;
    return a.localeCompare(b, "ja");
  });

  els.artistTabs.replaceChildren(
    makeArtistButton("all", `全部 ${state.tracks.length}`),
    ...artists.map((artist) => {
      const count = state.tracks.filter((track) => cleanArtist(track.artist) === artist).length;
      return makeArtistButton(artist, `${artist} ${count}`);
    }),
  );
}

function makeArtistButton(value, label) {
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = label;
  button.classList.toggle("is-active", state.artistFilter === value);
  button.addEventListener("click", () => {
    state.artistFilter = value;
    render();
  });
  return button;
}

function renderPendingArt() {
  els.pendingArt.hidden = !state.pendingArt;
  if (state.pendingArt) els.pendingArtName.textContent = state.pendingArt.name;
}

function renderTracks() {
  revokeObjectUrls();
  const visibleTracks = state.tracks.filter(matchesFilters);
  els.trackList.replaceChildren(...visibleTracks.map(renderTrack));
  els.emptyState.hidden = state.tracks.length > 0;
}

function renderTrack(track) {
  const node = els.template.content.firstElementChild.cloneNode(true);
  const cover = node.querySelector(".cover-slot");
  const title = node.querySelector(".track-title");
  const artist = node.querySelector(".track-artist");
  const note = node.querySelector(".track-note");
  const size = node.querySelector(".track-size");
  const isPublic = node.querySelector(".track-public");
  const audio = node.querySelector(".track-audio");
  const remove = node.querySelector(".remove-button");
  const artInput = node.querySelector(".art-input");
  const artButton = node.querySelector(".art-button");
  const artClearButton = node.querySelector(".art-clear-button");

  title.value = track.title;
  artist.value = track.artist;
  note.value = track.note;
  size.textContent = formatBytes(track.size);
  isPublic.checked = Boolean(track.isPublic);
  audio.src = makeObjectUrl(track.audio);

  if (track.art) {
    const img = document.createElement("img");
    img.alt = `${track.title} artwork`;
    img.src = makeObjectUrl(track.art);
    cover.append(img);
  }

  title.addEventListener("input", () => updateTrack(track.id, { title: title.value }));
  artist.addEventListener("input", () => updateTrack(track.id, { artist: artist.value }, true));
  note.addEventListener("input", () => updateTrack(track.id, { note: note.value }));
  isPublic.addEventListener("change", () => updateTrack(track.id, { isPublic: isPublic.checked }));
  artButton.addEventListener("click", () => artInput.click());
  artClearButton.addEventListener("click", async () => {
    await updateTrack(track.id, { art: null });
    setDropStatus(`${track.title}: ジャケットを外しました`, "done");
    render();
  });
  artInput.addEventListener("change", async (event) => {
    const image = [...event.target.files].find((file) => isImageFile(file));
    if (!image) return;
    await setTrackArt(track.id, image, `${track.title}: ジャケットを挿入しました`);
    event.target.value = "";
  });
  remove.addEventListener("click", async () => {
    state.tracks = state.tracks.filter((item) => item.id !== track.id);
    await deleteTrack(track.id);
    render();
  });
  cover.addEventListener("dragover", (event) => event.preventDefault());
  cover.addEventListener("drop", async (event) => {
    event.preventDefault();
    const image = [...event.dataTransfer.files].find((file) => isImageFile(file));
    if (image) await setTrackArt(track.id, image, `${track.title}: ジャケットを差し替えました`);
  });

  return node;
}

async function setTrackArt(id, image, message) {
  await updateTrack(id, { art: fileToMedia(image) });
  setDropStatus(message, "done");
  render();
}

async function updateTrack(id, patch, shouldRefreshArtists = false) {
  const track = state.tracks.find((item) => item.id === id);
  if (!track) return;
  Object.assign(track, patch);
  await persistTrack(track);
  if (shouldRefreshArtists) renderArtistTabs();
}

function matchesFilters(track) {
  const artist = cleanArtist(track.artist);
  const haystack = `${track.title} ${artist} ${track.note}`.toLowerCase();
  const matchesQuery = !state.query || haystack.includes(state.query);
  const matchesArtist = state.artistFilter === "all" || artist === state.artistFilter;
  const matchesDisplay =
    state.displayFilter === "all" ||
    (state.displayFilter === "with-art" && track.art) ||
    (state.displayFilter === "no-art" && !track.art) ||
    (state.displayFilter === "public" && track.isPublic);
  return matchesQuery && matchesArtist && matchesDisplay;
}

function cleanArtist(value) {
  return value.trim() || "未分類";
}

function getArtistFromPath(path) {
  const parts = path.split("/").filter(Boolean);
  return parts.length > 1 ? parts[0] : "";
}

function stripExtension(name) {
  return name.replace(/\.[^/.]+$/, "");
}

function isAudioFile(file) {
  return file.type.startsWith("audio/") || /\.(mp3|wav|m4a|aac|ogg|flac|aif|aiff)$/i.test(file.name);
}

function isImageFile(file) {
  return file.type.startsWith("image/") || /\.(png|jpe?g|webp|gif)$/i.test(file.name);
}

function formatBytes(bytes) {
  const units = ["B", "KB", "MB", "GB"];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
}

function fileToMedia(file) {
  return { name: file.name, type: file.type, blob: file };
}

function makeObjectUrl(media) {
  const url = URL.createObjectURL(media.blob);
  objectUrls.add(url);
  return url;
}

function revokeObjectUrls() {
  for (const url of objectUrls) URL.revokeObjectURL(url);
  objectUrls.clear();
}

function setDropStatus(message, tone = "") {
  els.dropStatus.textContent = message;
  els.dropStatus.classList.toggle("is-busy", tone === "busy");
  els.dropStatus.classList.toggle("is-done", tone === "done");
  els.dropStatus.classList.toggle("is-error", tone === "error");
}

function setImportSummary(label, total, audio, images) {
  els.importSummaryText.textContent = `${label}: 候補 ${total} / 音源 ${audio} / 画像 ${images}`;
}

async function persist() {
  await Promise.all(state.tracks.map(persistTrack));
}

async function persistTrack(track) {
  const db = await openDb();
  return requestToPromise(db.transaction(STORE_NAME, "readwrite").objectStore(STORE_NAME).put(track));
}

async function deleteTrack(id) {
  const db = await openDb();
  return requestToPromise(db.transaction(STORE_NAME, "readwrite").objectStore(STORE_NAME).delete(id));
}

async function replaceAllTracks(tracks) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, "readwrite");
    const store = transaction.objectStore(STORE_NAME);
    store.clear().addEventListener("success", () => tracks.forEach((track) => store.put(track)));
    transaction.addEventListener("complete", resolve);
    transaction.addEventListener("error", () => reject(transaction.error));
  });
}

async function restore() {
  const db = await openDb();
  const tracks = await requestToPromise(db.transaction(STORE_NAME, "readonly").objectStore(STORE_NAME).getAll());
  return tracks.sort((a, b) => b.createdAt - a.createdAt);
}

function openDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.addEventListener("upgradeneeded", () => request.result.createObjectStore(STORE_NAME, { keyPath: "id" }));
    request.addEventListener("success", () => resolve(request.result));
    request.addEventListener("error", () => reject(request.error));
  });
}

function requestToPromise(request) {
  return new Promise((resolve, reject) => {
    request.addEventListener("success", () => resolve(request.result));
    request.addEventListener("error", () => reject(request.error));
  });
}

function exportList() {
  const payload = {
    title: "Graveyard of the Black Nebula",
    exportedAt: new Date().toISOString(),
    tracks: state.tracks.map(({ audio, art, ...track }) => ({
      ...track,
      audioName: audio?.name || "",
      artName: art?.name || "",
    })),
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = "black-nebula-track-list.json";
  link.click();
  URL.revokeObjectURL(link.href);
}

async function importList(text) {
  try {
    const parsed = JSON.parse(text);
    const imported = Array.isArray(parsed) ? parsed : parsed.tracks || [];
    state.tracks = imported.map((track) => ({
      ...track,
      audio: track.audio || { name: track.audioName || "missing audio", type: "", blob: new Blob([]) },
      art: track.art || null,
    }));
    await replaceAllTracks(state.tracks);
    render();
  } catch {
    alert("読み込めないJSONです。");
  }
}
