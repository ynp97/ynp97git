const STORAGE_KEY = "ebay-record-lister-v1";
const DISCOGS_TOKEN_KEY = "ebay-record-lister-discogs-token";

const state = {
  items: [],
  selectedId: null,
  search: "",
  status: "all",
  photoFile: null,
  photoObjectUrl: "",
};

const fields = Array.from(document.querySelectorAll("[data-field]"));
const fieldMap = new Map(fields.map((field) => [field.dataset.field, field]));

const yen = new Intl.NumberFormat("ja-JP", {
  style: "currency",
  currency: "JPY",
  maximumFractionDigits: 0,
});

const usd = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
});

const numberFields = new Set([
  "weightGram",
  "purchasePriceJPY",
  "shippingJPY",
  "packingJPY",
  "targetProfitJPY",
  "feeRate",
  "exchangeRate",
  "priceJPY",
  "priceUSD",
]);

function makeId() {
  if (window.crypto?.randomUUID) return window.crypto.randomUUID();
  return `rec-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function defaultItem() {
  return {
    id: makeId(),
    sku: nextSku(),
    status: "未出品",
    artist: "",
    recordTitle: "",
    recordType: "EP",
    speed: "45 RPM",
    labelName: "",
    catalogNo: "",
    barcode: "",
    discogsReleaseId: "",
    country: "Japan",
    year: "",
    genre: "",
    weightGram: 120,
    mediaGrade: "VG+",
    sleeveGrade: "VG+",
    obi: "なし",
    insertSheet: "不明",
    conditionTags: [],
    purchasePriceJPY: 0,
    shippingJPY: 1800,
    shipMethod: "小形包装物(航空)",
    shipZone: "アメリカ",
    shipCostMode: "自動",
    shippingMode: "送料別",
    packingJPY: 120,
    targetProfitJPY: 1000,
    feeRate: 18,
    exchangeRate: 155,
    priceJPY: 0,
    priceUSD: 0,
    conditionMemo: "",
    photoFolder: "",
    sourceUrl: "",
    coverImageUrl: "",
    englishTitle: "",
    englishDescription: "",
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
}

function normalizeItem(item) {
  const normalized = {
    ...defaultItem(),
    ...item,
  };
  if (!Object.prototype.hasOwnProperty.call(item, "shippingMode")) {
    normalized.shippingMode = "送料無料";
  }
  // 既存データは従来挙動（入力済み送料）を守るため手動扱いにする
  if (!Object.prototype.hasOwnProperty.call(item, "shipCostMode")) {
    normalized.shipCostMode = "手動";
  }
  return normalized;
}

function nextSku() {
  const used = state.items
    .map((item) => item.sku)
    .filter(Boolean)
    .map((sku) => Number(String(sku).replace(/^REC-/, "")))
    .filter(Number.isFinite);
  const next = used.length ? Math.max(...used) + 1 : 1;
  return `REC-${String(next).padStart(4, "0")}`;
}

function load() {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return;
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed.items)) {
      state.items = parsed.items.map(normalizeItem);
      state.selectedId = parsed.selectedId ?? parsed.items[0]?.id ?? null;
    }
  } catch {
    localStorage.removeItem(STORAGE_KEY);
  }
}

function save() {
  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify({ items: state.items, selectedId: state.selectedId }),
  );
}

// ===== 送料表（発送方法 × 送り先 × 上限g → 円） =====
const SHIPPING_RATES_KEY = "ebay-record-lister-shipping-rates-v1";

// 初期値: 日本郵便 小形包装物(航空便) 公式料金（2026-07時点, post.japanpost.jp）
// アメリカ=第4地帯(100g 830円+100gごと210円), ヨーロッパ・カナダ・オセアニア=第3地帯(100g 510円+100gごと180円)
function defaultShippingRates() {
  const rows = [];
  const mk = (zone, base, step) => {
    for (let g = 100; g <= 2000; g += 100) {
      rows.push({ method: "小形包装物(航空)", zone, maxG: g, jpy: base + step * (g / 100 - 1) });
    }
  };
  mk("アメリカ", 830, 210);
  mk("ヨーロッパ・カナダ・オセアニア", 510, 180);
  return rows;
}

function loadShippingRates() {
  try {
    const parsed = JSON.parse(localStorage.getItem(SHIPPING_RATES_KEY) || "null");
    if (Array.isArray(parsed) && parsed.length) return parsed;
  } catch { /* 破損時は初期値 */ }
  return defaultShippingRates();
}

let shippingRates = loadShippingRates();

function saveShippingRates() {
  localStorage.setItem(SHIPPING_RATES_KEY, JSON.stringify(shippingRates));
}

function lookupShipping(method, zone, grams) {
  const rows = shippingRates
    .filter((r) => r.method === method && r.zone === zone && Number(r.maxG) > 0)
    .sort((a, b) => Number(a.maxG) - Number(b.maxG));
  if (!rows.length) return null;
  for (const r of rows) {
    if (grams <= Number(r.maxG)) return { jpy: Number(r.jpy) || 0, maxG: Number(r.maxG), over: false };
  }
  const last = rows[rows.length - 1];
  return { jpy: Number(last.jpy) || 0, maxG: Number(last.maxG), over: true };
}

// 自動モードなら送料表から送料コストを解決した item を返す
function resolveShipping(item) {
  if (!item || item.shipCostMode === "手動") return item;
  const hit = lookupShipping(item.shipMethod, item.shipZone, Number(item.weightGram || 0));
  return hit ? { ...item, shippingJPY: hit.jpy } : item;
}

// 貼り付け取り込み: 1行 = 発送方法 送り先 上限g 円（"500g" "1,450円" 表記可）
function parseRatePaste(text) {
  const rows = [];
  String(text || "").split(/\r?\n/).forEach((line) => {
    // 桁区切りカンマ(3,900)を先に除去してから区切る
    const t = line.replace(/(\d),(?=\d{3})/g, "$1").trim();
    if (!t) return;
    const parts = t.split(/[\t,、\s]+/).filter(Boolean);
    if (parts.length < 4) return;
    const nums = parts.slice(-2).map((x) => Number(String(x).replace(/[^\d.]/g, "")));
    if (!nums.every((n) => Number.isFinite(n) && n > 0)) return;
    const method = parts[0];
    const zone = parts.slice(1, -2).join("");
    if (!zone) return;
    rows.push({ method, zone, maxG: nums[0], jpy: nums[1] });
  });
  return rows;
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
}

function ensureShipOptions(item) {
  const mSel = document.querySelector("#shipMethodSelect");
  const zSel = document.querySelector("#shipZoneSelect");
  if (!mSel || !zSel) return;
  const methods = [...new Set(shippingRates.map((r) => r.method))];
  const zones = [...new Set(shippingRates.map((r) => r.zone))];
  if (item?.shipMethod && !methods.includes(item.shipMethod)) methods.push(item.shipMethod);
  if (item?.shipZone && !zones.includes(item.shipZone)) zones.push(item.shipZone);
  mSel.replaceChildren(...methods.map((m) => new Option(m, m)));
  zSel.replaceChildren(...zones.map((z) => new Option(z, z)));
}

function renderRateTable() {
  const tbody = document.querySelector("#rateTable tbody");
  if (!tbody) return;
  tbody.replaceChildren();
  shippingRates.forEach((r, i) => {
    const tr = document.createElement("tr");
    tr.innerHTML = `<td><input data-rate-i="${i}" data-rate-k="method" value="${escapeHtml(r.method)}"></td>
      <td><input data-rate-i="${i}" data-rate-k="zone" value="${escapeHtml(r.zone)}"></td>
      <td><input type="number" data-rate-i="${i}" data-rate-k="maxG" value="${Number(r.maxG) || 0}"></td>
      <td><input type="number" data-rate-i="${i}" data-rate-k="jpy" value="${Number(r.jpy) || 0}"></td>
      <td><button type="button" class="secondary" data-rate-del="${i}">削除</button></td>`;
    tbody.append(tr);
  });
  tbody.querySelectorAll("input").forEach((el) => {
    el.addEventListener("change", () => {
      const i = Number(el.dataset.rateI);
      const k = el.dataset.rateK;
      if (!shippingRates[i]) return;
      shippingRates[i][k] = (k === "maxG" || k === "jpy") ? Number(el.value || 0) : el.value.trim();
      saveShippingRates();
      ensureShipOptions(activeItem());
      updatePricePreview();
    });
  });
  tbody.querySelectorAll("[data-rate-del]").forEach((button) => {
    button.addEventListener("click", () => {
      shippingRates.splice(Number(button.dataset.rateDel), 1);
      saveShippingRates();
      renderRateTable();
      ensureShipOptions(activeItem());
      updatePricePreview();
    });
  });
}

// ===== コンディション定型文（eBayレコード出品でよく使う表記） =====
const CONDITION_PHRASES_KEY = "ebay-record-lister-condition-phrases-v1";

// 初期セット: Goldmine基準の出品で定番の状態表記（2026-07調査）
function defaultConditionPhrases() {
  return [
    { ja: "再生確認済み・飛びなし", en: "Play-tested, plays well with no skips" },
    { ja: "軽いスレ・音に影響なし", en: "Light surface scuffs that do not affect play" },
    { ja: "静かな部分で軽いノイズ", en: "Light surface noise in quiet passages" },
    { ja: "目視検品のみ・再生未確認", en: "Visually graded only, not play-tested" },
    { ja: "軽い反り・再生に影響なし", en: "Slight warp, does not affect play" },
    { ja: "ヘアライン傷あり", en: "Hairline scratches visible under light" },
    { ja: "レーベルにスピンドル跡", en: "Spindle marks on label" },
    { ja: "ジャケットにリングウェア", en: "Ring wear on cover" },
    { ja: "縁・角にスレあり", en: "Shelf wear on edges and corners" },
    { ja: "底辺に裂けあり", en: "Seam split on bottom edge" },
    { ja: "裏ジャケに書き込み", en: "Writing on back cover" },
    { ja: "ステッカー跡あり", en: "Sticker residue on cover" },
    { ja: "シミ・水濡れ跡あり", en: "Water stain on cover" },
    { ja: "帯付き・状態良好", en: "OBI strip included, in good condition" },
    { ja: "歌詞カード・インサート付き", en: "Original insert / lyric sheet included" },
  ];
}

function loadConditionPhrases() {
  try {
    const parsed = JSON.parse(localStorage.getItem(CONDITION_PHRASES_KEY) || "null");
    if (Array.isArray(parsed)) return parsed;
  } catch { /* 破損時は初期値 */ }
  return defaultConditionPhrases();
}

let conditionPhrases = loadConditionPhrases();

function saveConditionPhrases() {
  localStorage.setItem(CONDITION_PHRASES_KEY, JSON.stringify(conditionPhrases));
}

function itemTags(item) {
  return Array.isArray(item?.conditionTags) ? item.conditionTags : [];
}

function renderPhraseChips() {
  const wrap = document.querySelector("#phraseChips");
  if (!wrap) return;
  const item = activeItem();
  const selected = new Set(itemTags(item));
  wrap.replaceChildren();
  if (!conditionPhrases.length) {
    const empty = document.createElement("span");
    empty.className = "phrase-empty";
    empty.textContent = "定型文がありません。「定型文を編集」から追加してください。";
    wrap.append(empty);
  }
  conditionPhrases.forEach((phrase) => {
    const chip = document.createElement("button");
    chip.type = "button";
    chip.className = `phrase-chip${selected.has(phrase.en) ? " on" : ""}`;
    chip.textContent = phrase.ja;
    chip.title = phrase.en;
    chip.disabled = !item;
    chip.addEventListener("click", () => {
      const current = activeItem();
      if (!current) return;
      const tags = new Set(itemTags(current));
      if (tags.has(phrase.en)) tags.delete(phrase.en);
      else tags.add(phrase.en);
      current.conditionTags = [...tags];
      current.updatedAt = new Date().toISOString();
      save();
      renderPhraseChips();
      updateCopyPastePanel();
    });
    wrap.append(chip);
  });
}

function renderPhraseEditor() {
  const list = document.querySelector("#phraseEditorList");
  if (!list) return;
  list.replaceChildren();
  conditionPhrases.forEach((phrase, index) => {
    const row = document.createElement("div");
    row.className = "phrase-edit-row";
    const label = document.createElement("span");
    label.textContent = `${phrase.ja} — ${phrase.en}`;
    const removeButton = document.createElement("button");
    removeButton.type = "button";
    removeButton.className = "secondary";
    removeButton.textContent = "削除";
    removeButton.addEventListener("click", () => {
      conditionPhrases.splice(index, 1);
      saveConditionPhrases();
      renderPhraseEditor();
      renderPhraseChips();
    });
    row.append(label, removeButton);
    list.append(row);
  });
}

function addConditionPhrase() {
  const jaInput = document.querySelector("#newPhraseJa");
  const enInput = document.querySelector("#newPhraseEn");
  const ja = jaInput.value.trim();
  const en = enInput.value.trim();
  if (!en) {
    window.alert("英語表記は必須です（出品文に入る文字列です）。");
    return;
  }
  conditionPhrases.push({ ja: ja || en, en });
  saveConditionPhrases();
  jaInput.value = "";
  enInput.value = "";
  renderPhraseEditor();
  renderPhraseChips();
}

function importRates(replace) {
  const area = document.querySelector("#ratePasteArea");
  const rows = parseRatePaste(area.value);
  if (!rows.length) {
    window.alert("読み取れる行がありません。1行 =「発送方法 送り先 上限g 円」の形式で貼ってください。");
    return;
  }
  shippingRates = replace ? rows : shippingRates.concat(rows);
  saveShippingRates();
  renderRateTable();
  ensureShipOptions(activeItem());
  updatePricePreview();
  area.value = "";
  window.alert(`${rows.length}行を${replace ? "置き換えで" : "追加で"}取り込みました。`);
}

function activeItem() {
  return state.items.find((item) => item.id === state.selectedId) ?? null;
}

function readForm() {
  const item = activeItem();
  if (!item) return null;
  const next = { ...item };
  fields.forEach((field) => {
    const key = field.dataset.field;
    const value = field.value.trim();
    next[key] = numberFields.has(key) ? Number(value || 0) : value;
  });
  next.updatedAt = new Date().toISOString();
  return next;
}

function writeForm(item) {
  ensureShipOptions(item);
  fields.forEach((field) => {
    const key = field.dataset.field;
    field.value = item?.[key] ?? "";
    field.disabled = !item;
  });

  document.querySelector("#editorTitle").textContent = item
    ? displayName(item)
    : "レコードを登録";
  document.querySelector("#activeSku").textContent = item?.sku ?? "No record selected";

  const hasItem = Boolean(item);
  document.querySelector("#duplicateButton").disabled = !hasItem;
  document.querySelector("#deleteButton").disabled = !hasItem;
  document.querySelector("#calculateButton").disabled = !hasItem;
  document.querySelector("#generateTitleButton").disabled = !hasItem;
  document.querySelector("#generateDescriptionButton").disabled = !hasItem;
  document.querySelector("#fetchDiscogsButton").disabled = !hasItem;
  document.querySelector("#applyPhotoCluesButton").disabled = !hasItem;
  document.querySelector("#openDiscogsSearchButton").disabled = !hasItem;
  document.querySelector("#refreshCopyPackButton").disabled = !hasItem;
  document.querySelector("#copyAllButton").disabled = !hasItem;
  document.querySelectorAll("[data-copy-target]").forEach((button) => {
    button.disabled = !hasItem;
  });
  document.querySelector("#itemForm button[type='submit']").disabled = !hasItem;

  updatePricePreview(item);
  updateCopyPastePanel(item);
  renderPhraseChips();
}

function displayName(item) {
  const artist = item.artist || "Unknown Artist";
  const title = item.recordTitle || "Untitled";
  return `${artist} - ${title}`;
}

function filteredItems() {
  const query = state.search.toLowerCase();
  return state.items.filter((item) => {
    const statusMatch = state.status === "all" || item.status === state.status;
    const text = [
      item.sku,
      item.artist,
      item.recordTitle,
      item.labelName,
      item.catalogNo,
      item.barcode,
      item.discogsReleaseId,
      item.genre,
    ]
      .join(" ")
      .toLowerCase();
    return statusMatch && text.includes(query);
  });
}

function renderList() {
  const list = document.querySelector("#itemList");
  list.replaceChildren();

  const items = filteredItems();
  if (!items.length) {
    list.append(document.querySelector("#emptyStateTemplate").content.cloneNode(true));
    return;
  }

  items.forEach((item) => {
    const row = document.createElement("button");
    row.type = "button";
    row.className = `item-row${item.id === state.selectedId ? " active" : ""}`;
    row.setAttribute("role", "listitem");
    row.addEventListener("click", () => {
      state.selectedId = item.id;
      save();
      render();
    });

    const title = document.createElement("div");
    title.className = "item-title";
    title.textContent = displayName(item);

    const meta = document.createElement("div");
    meta.className = "item-meta";
    meta.textContent = [item.sku, item.recordType, item.catalogNo, item.mediaGrade]
      .filter(Boolean)
      .join(" / ");

    const foot = document.createElement("div");
    foot.className = "item-foot";

    const status = document.createElement("span");
    status.className = "status-pill";
    status.textContent = item.status;

    const price = document.createElement("span");
    price.textContent = item.priceUSD ? usd.format(item.priceUSD) : "$0.00";

    foot.append(status, price);
    row.append(title, meta, foot);
    list.append(row);
  });
}

function renderStats() {
  const total = state.items.length;
  const drafts = state.items.filter((item) => item.status === "未出品").length;
  const profits = state.items.reduce((sum, item) => sum + calculateProfit(item).profit, 0);
  const priced = state.items.filter((item) => item.priceUSD > 0);
  const average = priced.length
    ? priced.reduce((sum, item) => sum + item.priceUSD, 0) / priced.length
    : 0;

  document.querySelector("#totalCount").textContent = String(total);
  document.querySelector("#draftCount").textContent = String(drafts);
  document.querySelector("#profitTotal").textContent = yen.format(profits);
  document.querySelector("#averageUsd").textContent = usd.format(average);
}

function render() {
  renderStats();
  renderList();
  writeForm(activeItem());
}

function shippingIsSeparate(item) {
  return item.shippingMode !== "送料無料";
}

function calculateRecommendedPrice(item) {
  item = resolveShipping(item);
  const purchase = Number(item.purchasePriceJPY || 0);
  const shipping = Number(item.shippingJPY || 0);
  const packing = Number(item.packingJPY || 0);
  const targetProfit = Number(item.targetProfitJPY || 0);
  const feeRate = Math.min(Number(item.feeRate || 0), 80) / 100;
  const denominator = Math.max(1 - feeRate, 0.2);
  const priceBase = shippingIsSeparate(item)
    ? purchase + packing + targetProfit + (shipping * feeRate)
    : purchase + packing + shipping + targetProfit;
  const priceJPY = Math.ceil(priceBase / denominator);
  const exchangeRate = Number(item.exchangeRate || 1);
  const priceUSD = Math.ceil((priceJPY / exchangeRate) * 100) / 100;
  const buyerShippingJPY = shippingIsSeparate(item) ? shipping : 0;
  const buyerShippingUSD = Math.ceil((buyerShippingJPY / exchangeRate) * 100) / 100;
  const buyerTotalJPY = priceJPY + buyerShippingJPY;
  const buyerTotalUSD = Math.ceil((buyerTotalJPY / exchangeRate) * 100) / 100;
  return { priceJPY, priceUSD, buyerShippingJPY, buyerShippingUSD, buyerTotalJPY, buyerTotalUSD };
}

function calculateProfit(item) {
  item = resolveShipping(item);
  const purchase = Number(item.purchasePriceJPY || 0);
  const shipping = Number(item.shippingJPY || 0);
  const packing = Number(item.packingJPY || 0);
  const cost = purchase + shipping + packing;
  const shippingCharge = shippingIsSeparate(item) ? shipping : 0;
  const revenue = Number(item.priceJPY || 0) + shippingCharge;
  const fee = revenue * (Number(item.feeRate || 0) / 100);
  const profit = revenue - cost - fee;
  return { cost, fee, profit, buyerTotalJPY: revenue, shippingCharge };
}

function setReadout(id, text, negative) {
  const node = document.querySelector(`#${id}`);
  if (!node) return;
  node.textContent = text;
  node.classList.toggle("neg", Boolean(negative));
}

// 自動モード時は送料欄を送料表の値で同期し、編集不可にする
function syncShippingField(raw) {
  const el = fieldMap.get("shippingJPY");
  if (!el || !raw) return;
  const auto = raw.shipCostMode !== "手動";
  el.readOnly = auto;
  if (auto) {
    const hit = lookupShipping(raw.shipMethod, raw.shipZone, Number(raw.weightGram || 0));
    if (hit) el.value = hit.jpy;
  }
}

function updatePricePreview(item) {
  const raw = item ?? readForm();
  if (!raw) {
    ["shipAutoPreview", "breakEvenPreview", "breakEvenFreePreview", "recommendPreview", "profitPreview",
      "marginPreview", "buyerTotalPreview", "feePreview", "costPreview"]
      .forEach((id) => setReadout(id, "-"));
    return;
  }
  syncShippingField(raw);
  const { cost, fee, profit, buyerTotalJPY } = calculateProfit(raw);
  // 損益分岐は送料別/送料無料の両方を常時表示（切替不要で比較できる）
  const breakEvenSeparate = calculateRecommendedPrice({ ...raw, targetProfitJPY: 0, shippingMode: "送料別" });
  const breakEvenFree = calculateRecommendedPrice({ ...raw, targetProfitJPY: 0, shippingMode: "送料無料" });
  const separateNow = shippingIsSeparate(raw);
  const recommend = calculateRecommendedPrice(raw);
  const manual = raw.shipCostMode === "手動";
  const hit = manual ? null : lookupShipping(raw.shipMethod, raw.shipZone, Number(raw.weightGram || 0));
  let shipText;
  if (manual) shipText = `${yen.format(Number(raw.shippingJPY || 0))}（手動）`;
  else if (hit) shipText = `${yen.format(hit.jpy)}（〜${hit.maxG}g${hit.over ? "・重量超過!" : ""}）`;
  else shipText = "送料表に該当なし";
  setReadout("shipAutoPreview", shipText, hit ? hit.over : !manual);
  setReadout("breakEvenPreview", `$${Number(breakEvenSeparate.priceUSD || 0).toFixed(2)}${separateNow ? "（今の設定）" : ""}`);
  setReadout("breakEvenFreePreview", `$${Number(breakEvenFree.priceUSD || 0).toFixed(2)}${separateNow ? "" : "（今の設定）"}`);
  setReadout("recommendPreview", `$${Number(recommend.priceUSD || 0).toFixed(2)}（+${yen.format(Number(raw.targetProfitJPY || 0))}）`);
  setReadout("profitPreview", yen.format(profit), profit < 0);
  setReadout("marginPreview", buyerTotalJPY > 0 ? `${Math.round((profit / buyerTotalJPY) * 100)}%` : "-", profit < 0);
  setReadout("buyerTotalPreview", yen.format(buyerTotalJPY));
  setReadout("feePreview", yen.format(fee));
  setReadout("costPreview", yen.format(cost));
}

// 商品価格のUSD⇔円を為替で連動させる
function syncPricePair(changedKey) {
  const rate = Number(fieldMap.get("exchangeRate")?.value || 0) || 1;
  const usdField = fieldMap.get("priceUSD");
  const jpyField = fieldMap.get("priceJPY");
  if (!usdField || !jpyField) return;
  if (changedKey === "priceUSD") {
    jpyField.value = Math.round(Number(usdField.value || 0) * rate);
  } else if (changedKey === "priceJPY") {
    usdField.value = (Math.round((Number(jpyField.value || 0) / rate) * 100) / 100).toFixed(2);
  } else if (changedKey === "exchangeRate") {
    const usdValue = Number(usdField.value || 0);
    if (usdValue > 0) jpyField.value = Math.round(usdValue * rate);
  }
}

function commitForm() {
  const next = readForm();
  if (!next) return;
  const index = state.items.findIndex((item) => item.id === next.id);
  if (index >= 0) state.items[index] = next;
  save();
  render();
}

function createItem() {
  const item = defaultItem();
  const prices = calculateRecommendedPrice(item);
  item.priceJPY = prices.priceJPY;
  item.priceUSD = prices.priceUSD;
  state.items.unshift(item);
  state.selectedId = item.id;
  save();
  render();
}

function duplicateItem() {
  const item = activeItem();
  if (!item) return;
  const copy = {
    ...item,
    id: makeId(),
    sku: nextSku(),
    status: "未出品",
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  state.items.unshift(copy);
  state.selectedId = copy.id;
  save();
  render();
}

function deleteItem() {
  const item = activeItem();
  if (!item) return;
  const ok = window.confirm(`${displayName(item)} を削除しますか？`);
  if (!ok) return;
  state.items = state.items.filter((current) => current.id !== item.id);
  state.selectedId = state.items[0]?.id ?? null;
  save();
  render();
}

function generateEnglishTitle(item) {
  const parts = [
    item.artist,
    item.recordTitle,
    item.recordType,
    item.speed,
    item.catalogNo,
    item.country,
    item.year,
    item.obi === "あり" ? "OBI" : "",
    "Vinyl Record",
  ].filter(Boolean);

  return parts.join(" ").replace(/\s+/g, " ").slice(0, 80);
}

function generateEnglishDescription(item) {
  const detailLines = [
    ["Artist", item.artist],
    ["Title", item.recordTitle],
    ["Format", `${item.recordType} ${item.speed}`.trim()],
    ["Label", item.labelName],
    ["Catalog Number", item.catalogNo],
    ["Barcode", item.barcode],
    ["Country", item.country],
    ["Year", item.year],
    ["Genre", item.genre],
    ["OBI", item.obi],
    ["Insert", item.insertSheet],
  ]
    .filter(([, value]) => value)
    .map(([label, value]) => `- ${label}: ${value}`)
    .join("\n");

  const memo = item.conditionMemo
    ? `\nAdditional notes:\n${item.conditionMemo}`
    : "";

  return [
    "Used vinyl record from Japan.",
    "",
    "Item details:",
    detailLines || "- Please check the photos for details.",
    "",
    "Condition:",
    `- Media: ${item.mediaGrade}`,
    `- Sleeve: ${item.sleeveGrade}`,
    ...itemTags(item).map((tag) => `- ${tag}`),
    "- This is a used item. It may have light surface marks, spindle marks, noise, stains, ring wear, split seams, writing, or age-related wear.",
    "- Please check all photos carefully before purchasing.",
    memo,
    "",
    "Shipping:",
    "- Ships from Japan with careful packing.",
    "- Handling time may vary depending on holidays and carrier availability.",
    "",
    "Thank you for looking.",
  ]
    .filter(Boolean)
    .join("\n");
}

function valueOrDash(value) {
  const text = String(value ?? "").trim();
  return text || "-";
}

function compactLines(lines) {
  return lines
    .filter((line) => line !== null && line !== undefined)
    .map((line) => String(line))
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function listingTitle(item) {
  return (item.englishTitle || generateEnglishTitle(item)).trim();
}

function listingDescription(item) {
  return (item.englishDescription || generateEnglishDescription(item)).trim();
}

function listingPriceUsd(item) {
  const price = Number(item.priceUSD || 0);
  if (price > 0) return price.toFixed(2);
  const calculated = calculateRecommendedPrice(item);
  return Number(calculated.priceUSD || 0).toFixed(2);
}

function listingBuyerTotalUsd(item) {
  item = resolveShipping(item);
  const calculated = calculateRecommendedPrice(item);
  const priceJPY = Number(item.priceJPY || calculated.priceJPY || 0);
  const exchangeRate = Number(item.exchangeRate || 1);
  const buyerShippingJPY = shippingIsSeparate(item) ? Number(item.shippingJPY || 0) : 0;
  const buyerTotalJPY = priceJPY + buyerShippingJPY;
  return (Math.ceil((buyerTotalJPY / exchangeRate) * 100) / 100).toFixed(2);
}

function listingShippingUsd(item) {
  item = resolveShipping(item);
  const exchangeRate = Number(item.exchangeRate || 1);
  const shippingJPY = shippingIsSeparate(item) ? Number(item.shippingJPY || 0) : 0;
  return (Math.ceil((shippingJPY / exchangeRate) * 100) / 100).toFixed(2);
}

function generateSpecificsText(item) {
  const specifics = [
    ["Artist", item.artist],
    ["Release Title", item.recordTitle],
    ["Format", "Record"],
    ["Record Size", item.recordType],
    ["Speed", item.speed],
    ["Record Label", item.labelName],
    ["Catalog Number", item.catalogNo],
    ["Release Year", item.year],
    ["Country/Region of Manufacture", item.country],
    ["Genre", item.genre],
    ["Material", "Vinyl"],
    ["Record Grading", item.mediaGrade],
    ["Sleeve Grading", item.sleeveGrade],
    ["Inlay Condition", item.insertSheet === "あり" ? "Very Good Plus (VG+)" : ""],
    ["UPC", item.barcode],
  ];

  return specifics
    .filter(([, value]) => String(value || "").trim())
    .map(([label, value]) => `${label}: ${value}`)
    .join("\n");
}

function generateConditionText(item) {
  const accessoryLines = [
    `OBI: ${valueOrDash(item.obi)}`,
    `Insert: ${valueOrDash(item.insertSheet)}`,
  ];
  const memo = String(item.conditionMemo || "").trim();

  return compactLines([
    "Condition: Used",
    `Media grading: ${valueOrDash(item.mediaGrade)}`,
    `Sleeve grading: ${valueOrDash(item.sleeveGrade)}`,
    ...accessoryLines,
    ...itemTags(item).map((tag) => `- ${tag}`),
    "",
    "Please check all photos carefully.",
    "This is a used record. It may have light surface marks, spindle marks, noise, stains, ring wear, edge wear, writing, sticker residue, or age-related wear.",
    memo ? "" : "",
    memo ? "Seller notes:" : "",
    memo,
  ]);
}

function generatePriceText(item) {
  item = resolveShipping(item);
  const separate = shippingIsSeparate(item);
  return compactLines([
    `Listing format: Fixed price / Buy It Now`,
    `eBay Price field: USD $${listingPriceUsd(item)}`,
    separate
      ? `Shipping charged separately: about USD $${listingShippingUsd(item)} (${yen.format(Number(item.shippingJPY || 0))})`
      : "Shipping setting: Free shipping",
    `Buyer total target: USD $${listingBuyerTotalUsd(item)}`,
    `Quantity: 1`,
    `Custom label (SKU): ${valueOrDash(item.sku)}`,
    `Weight: ${Number(item.weightGram || 0)} g`,
  ]);
}

function generateShippingText(item) {
  item = resolveShipping(item);
  const separate = shippingIsSeparate(item);
  return compactLines([
    "Ships from Japan with careful packing.",
    "The record will be packed with cardboard protection.",
    separate
      ? `Shipping is charged separately. Set the shipping charge around USD $${listingShippingUsd(item)} if you are entering a flat shipping amount.`
      : "Free shipping is included in the item price.",
    "Handling time may vary depending on weekends, Japanese holidays, and carrier availability.",
    "International buyers are responsible for customs duties, import taxes, and local fees charged by their country.",
    "Return policy: Please follow the return setting shown on this eBay listing. If there is any problem, please contact me first.",
    "",
    `Packing memo: weight ${Number(item.weightGram || 0)} g / estimated international postage ${yen.format(Number(item.shippingJPY || 0))}`,
  ]);
}

function generatePhotoChecklistText(item) {
  return compactLines([
    "Photo checklist:",
    "- Front cover",
    "- Back cover",
    "- Disc label side A",
    "- Disc label side B",
    "- Vinyl surface close-up",
    "- Catalog number / matrix / barcode if visible",
    item.obi === "あり" ? "- OBI" : "",
    item.insertSheet === "あり" ? "- Insert / lyric sheet" : "",
  ]);
}

function buildCopyPack(item) {
  if (!item) {
    return {
      all: "",
      title: "",
      price: "",
      specifics: "",
      condition: "",
      description: "",
      shipping: "",
    };
  }

  const title = listingTitle(item);
  const price = generatePriceText(item);
  const specifics = generateSpecificsText(item);
  const condition = generateConditionText(item);
  const description = listingDescription(item);
  const shipping = generateShippingText(item);
  const photos = generatePhotoChecklistText(item);

  const all = compactLines([
    "=== EBAY COPY-PASTE LISTING PACK ===",
    "",
    "[TITLE]",
    title,
    "",
    "[CATEGORY]",
    "Music > Vinyl Records",
    "",
    "[PRICE / SKU]",
    price,
    "",
    "[CONDITION]",
    condition,
    "",
    "[ITEM SPECIFICS]",
    specifics || "-",
    "",
    "[DESCRIPTION]",
    description,
    "",
    "[SHIPPING / RETURNS]",
    shipping,
    "",
    "[PHOTOS]",
    photos,
    "",
    "[SOURCE / CHECK]",
    item.sourceUrl ? `Source: ${item.sourceUrl}` : "",
    item.discogsReleaseId ? `Discogs Release ID: ${item.discogsReleaseId}` : "",
  ]);

  return { all, title, price, specifics, condition, description, shipping };
}

function makeListingSearchQuery(item) {
  return [
    item.artist,
    item.recordTitle,
    item.catalogNo,
    item.labelName,
    item.year,
  ]
    .map((part) => String(part || "").trim())
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();
}

function listingSearchLinks(item) {
  if (!item) return [];
  const query = makeListingSearchQuery(item);
  if (!query && !item.sourceUrl) return [];
  const encoded = encodeURIComponent(query);
  const links = [];
  if (query) {
    links.push(["eBay sold", `https://www.ebay.com/sch/i.html?_nkw=${encoded}&LH_Sold=1&LH_Complete=1`]);
    links.push(["eBay active", `https://www.ebay.com/sch/i.html?_nkw=${encoded}`]);
    links.push(["Discogs", `https://www.discogs.com/search/?q=${encoded}&type=release`]);
    links.push(["Popsike", `https://www.popsike.com/php/quicksearch.php?searchtext=${encoded}`]);
    links.push(["Yahoo Auctions", `https://auctions.yahoo.co.jp/search/search?p=${encoded}`]);
  }
  if (item.sourceUrl) links.unshift(["Source", item.sourceUrl]);
  return links;
}

function renderVerificationLinks(item) {
  const container = document.querySelector("#verificationLinks");
  container.replaceChildren();
  listingSearchLinks(item).forEach(([label, href]) => {
    const anchor = document.createElement("a");
    anchor.href = href;
    anchor.target = "_blank";
    anchor.rel = "noopener";
    anchor.textContent = label;
    container.append(anchor);
  });
}

function updateCopyPastePanel(item = readForm() || activeItem()) {
  const pack = buildCopyPack(item);
  const targets = {
    copyAllText: pack.all,
    copyTitleText: pack.title,
    copyPriceText: pack.price,
    copySpecificsText: pack.specifics,
    copyConditionText: pack.condition,
    copyDescriptionText: pack.description,
    copyShippingText: pack.shipping,
  };

  Object.entries(targets).forEach(([id, value]) => {
    const node = document.querySelector(`#${id}`);
    if (node) node.value = value;
  });
  renderVerificationLinks(item);
}

function setCopyStatus(message, tone = "") {
  const node = document.querySelector("#copyStatus");
  node.textContent = message;
  node.className = `status-message${tone ? ` ${tone}` : ""}`;
}

async function copyTextFromNode(id) {
  const node = document.querySelector(`#${id}`);
  const text = node?.value || "";
  if (!text.trim()) {
    setCopyStatus("コピーする内容がありません", "warn");
    return;
  }

  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      setCopyStatus("コピーしました", "good");
      return;
    }
    throw new Error("Clipboard API unavailable");
  } catch {
    try {
      node.removeAttribute("readonly");
      node.focus();
      node.select();
      node.setSelectionRange(0, text.length);
      const copied = document.execCommand("copy");
      node.setAttribute("readonly", "");
      setCopyStatus(copied ? "コピーしました" : "テキストを選択しました。⌘Cでコピーしてください", copied ? "good" : "warn");
      return;
    } catch {
      node.setAttribute("readonly", "");
      node.focus();
      node.select();
    }
  }

  setCopyStatus("コピーに失敗しました。テキストを選択して⌘Cでコピーしてください", "error");
}

function updateCalculatedPrice() {
  const item = readForm();
  if (!item) return;
  const prices = calculateRecommendedPrice(item);
  fieldMap.get("priceJPY").value = prices.priceJPY;
  fieldMap.get("priceUSD").value = prices.priceUSD;
  updatePricePreview({ ...item, ...prices });
  updateCopyPastePanel({ ...item, ...prices });
}

function updateTitle() {
  const item = readForm();
  if (!item) return;
  fieldMap.get("englishTitle").value = generateEnglishTitle(item);
  updateCopyPastePanel({ ...item, englishTitle: fieldMap.get("englishTitle").value });
}

function updateDescription() {
  const item = readForm();
  if (!item) return;
  fieldMap.get("englishDescription").value = generateEnglishDescription(item);
  updateCopyPastePanel({ ...item, englishDescription: fieldMap.get("englishDescription").value });
}

function csvEscape(value) {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}

function toCsv(items) {
  const headers = [
    "SKU",
    "Status",
    "Title",
    "Description",
    "Quantity",
    "PriceUSD",
    "Artist",
    "RecordTitle",
    "Format",
    "Speed",
    "Label",
    "CatalogNumber",
    "Barcode",
    "DiscogsReleaseId",
    "Country",
    "Year",
    "Genre",
    "MediaGrade",
    "SleeveGrade",
    "OBI",
    "Insert",
    "WeightGram",
    "PhotoFolder",
    "SourceUrl",
    "CoverImageUrl",
  ];

  const rows = items.map((item) => [
    item.sku,
    item.status,
    item.englishTitle || generateEnglishTitle(item),
    item.englishDescription || generateEnglishDescription(item),
    1,
    item.priceUSD || "",
    item.artist,
    item.recordTitle,
    item.recordType,
    item.speed,
    item.labelName,
    item.catalogNo,
    item.barcode,
    item.discogsReleaseId,
    item.country,
    item.year,
    item.genre,
    item.mediaGrade,
    item.sleeveGrade,
    item.obi,
    item.insertSheet,
    item.weightGram,
    item.photoFolder,
    item.sourceUrl,
    item.coverImageUrl,
  ]);

  return [headers, ...rows].map((row) => row.map(csvEscape).join(",")).join("\n");
}

function download(filename, content, type) {
  const blob = new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

function exportCsv() {
  commitForm();
  const date = new Date().toISOString().slice(0, 10);
  download(`ebay-record-listings-${date}.csv`, toCsv(state.items), "text/csv;charset=utf-8");
}

function exportJson() {
  commitForm();
  const date = new Date().toISOString().slice(0, 10);
  download(
    `ebay-record-lister-backup-${date}.json`,
    JSON.stringify({ items: state.items, shippingRates, conditionPhrases }, null, 2),
    "application/json;charset=utf-8",
  );
}

function importJson(file) {
  if (!file) return;
  const reader = new FileReader();
  reader.addEventListener("load", () => {
    try {
      const parsed = JSON.parse(String(reader.result || "{}"));
      if (!Array.isArray(parsed.items)) throw new Error("Invalid JSON");
      state.items = parsed.items.map(normalizeItem);
      state.selectedId = state.items[0]?.id ?? null;
      if (Array.isArray(parsed.shippingRates) && parsed.shippingRates.length) {
        shippingRates = parsed.shippingRates;
        saveShippingRates();
        renderRateTable();
      }
      if (Array.isArray(parsed.conditionPhrases) && parsed.conditionPhrases.length) {
        conditionPhrases = parsed.conditionPhrases;
        saveConditionPhrases();
        renderPhraseChips();
      }
      save();
      render();
    } catch {
      window.alert("JSONを読み込めませんでした。");
    }
  });
  reader.readAsText(file);
}

function setAutomationStatus(message, tone = "") {
  const node = document.querySelector("#automationStatus");
  node.textContent = message;
  node.className = `status-message${tone ? ` ${tone}` : ""}`;
}

function getDiscogsToken() {
  return document.querySelector("#discogsTokenInput").value.trim();
}

function saveDiscogsToken() {
  const token = getDiscogsToken();
  if (token) {
    localStorage.setItem(DISCOGS_TOKEN_KEY, token);
    setAutomationStatus("Discogs Tokenを保存しました", "good");
  } else {
    localStorage.removeItem(DISCOGS_TOKEN_KEY);
    setAutomationStatus("Discogs Tokenを削除しました", "warn");
  }
}

function loadDiscogsToken() {
  document.querySelector("#discogsTokenInput").value =
    localStorage.getItem(DISCOGS_TOKEN_KEY) || "";
}

function extractDiscogsReleaseId(input) {
  const text = String(input || "").trim();
  if (/^\d+$/.test(text)) return text;
  const match = text.match(/(?:release|releases)\/(\d+)/i);
  return match?.[1] || "";
}

function discogsHeaders() {
  const headers = {
    Accept: "application/vnd.discogs.v2.discogs+json",
  };
  const token = getDiscogsToken();
  if (token) headers.Authorization = `Discogs token=${token}`;
  return headers;
}

async function fetchJson(url) {
  const response = await fetch(url, { headers: discogsHeaders() });
  if (!response.ok) {
    const message = response.status === 401
      ? "Discogsの認証に失敗しました"
      : `Discogsから取得できませんでした (${response.status})`;
    throw new Error(message);
  }
  return response.json();
}

function firstUseful(values) {
  return values.find((value) => String(value || "").trim()) || "";
}

function cleanDiscogsName(value) {
  return String(value || "")
    .replace(/\s+\(\d+\)$/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function detectSpeed(text) {
  const source = String(text || "").toLowerCase();
  if (source.includes("78 rpm")) return "78 RPM";
  if (source.includes("45 rpm")) return "45 RPM";
  if (source.includes("33") || source.includes("lp")) return "33 RPM";
  return "";
}

function detectRecordType(text) {
  const source = String(text || "").toLowerCase();
  if (/\bep\b/.test(source)) return "EP";
  if (/\blp\b/.test(source)) return "LP";
  if (source.includes('7"') || source.includes("7 inch") || source.includes("7-inch")) {
    return "7 inch";
  }
  if (source.includes('10"') || source.includes("10 inch") || source.includes("10-inch")) {
    return "10 inch";
  }
  if (source.includes('12"') || source.includes("12 inch") || source.includes("12-inch")) {
    return "12 inch";
  }
  if (source.includes("single")) return "Single";
  if (source.includes("album")) return "Album";
  return "";
}

function identifierValue(release, typeName) {
  const target = String(typeName || "").toLowerCase();
  const identifier = release.identifiers?.find((entry) =>
    String(entry.type || "").toLowerCase().includes(target),
  );
  return identifier?.value || "";
}

function mapDiscogsRelease(release) {
  const format = release.formats?.[0] || {};
  const formatText = [
    format.name,
    ...(format.descriptions || []),
    release.title,
  ].join(" ");
  const labels = release.labels || [];
  const catno = firstUseful(labels.map((label) => label.catno).filter((value) => value !== "none"));
  const images = release.images || [];
  const barcode = identifierValue(release, "barcode");

  return {
    artist: cleanDiscogsName(
      release.artists_sort ||
      release.artists?.map((artist) => artist.name).join(", "),
    ),
    recordTitle: cleanDiscogsName(release.title),
    recordType: detectRecordType(formatText),
    speed: detectSpeed(formatText),
    labelName: labels.map((label) => cleanDiscogsName(label.name)).filter(Boolean).join(" / "),
    catalogNo: catno,
    barcode,
    discogsReleaseId: release.id ? String(release.id) : "",
    country: release.country || "",
    year: release.year ? String(release.year) : "",
    genre: [...(release.genres || []), ...(release.styles || [])].join(", "),
    sourceUrl: release.uri || (release.id ? `https://www.discogs.com/release/${release.id}` : ""),
    coverImageUrl: images[0]?.resource_url || release.thumb || "",
  };
}

function setFieldIfPresent(key, value, { overwrite = true } = {}) {
  const field = fieldMap.get(key);
  if (!field) return false;
  const text = String(value ?? "").trim();
  if (!text) return false;
  if (!overwrite && field.value.trim()) return false;
  field.value = text;
  field.dispatchEvent(new Event("input", { bubbles: true }));
  return true;
}

function appendConditionMemo(text) {
  const field = fieldMap.get("conditionMemo");
  const addition = String(text || "").trim();
  if (!field || !addition || field.value.includes(addition)) return;
  field.value = [field.value.trim(), addition].filter(Boolean).join("\n\n");
  field.dispatchEvent(new Event("input", { bubbles: true }));
}

function applyMappedData(data, { overwrite = true, sourceNote = "" } = {}) {
  const applied = Object.entries(data).filter(([key, value]) =>
    setFieldIfPresent(key, value, { overwrite }),
  );
  if (sourceNote) appendConditionMemo(sourceNote);
  updateTitle();
  updateDescription();
  commitForm();
  return applied.length;
}

async function importDiscogsRelease(releaseId) {
  if (!releaseId) {
    setAutomationStatus("Release IDが見つかりません", "error");
    return;
  }
  setAutomationStatus("Discogsから取得中");
  try {
    const release = await fetchJson(`https://api.discogs.com/releases/${releaseId}`);
    const mapped = mapDiscogsRelease(release);
    const count = applyMappedData(mapped, { overwrite: true });
    setAutomationStatus(`${count}項目を取り込みました`, "good");
  } catch (error) {
    setAutomationStatus(error.message || "Discogs取込に失敗しました", "error");
  }
}

function importDiscogsFromInput() {
  const releaseId = extractDiscogsReleaseId(document.querySelector("#discogsInput").value);
  importDiscogsRelease(releaseId);
}

function clearDiscogsResults() {
  document.querySelector("#discogsResults").replaceChildren();
}

function renderDiscogsResults(results) {
  const container = document.querySelector("#discogsResults");
  container.replaceChildren();
  results.slice(0, 6).forEach((result) => {
    const row = document.createElement("div");
    row.className = "discogs-result";

    const image = document.createElement("img");
    image.className = "result-thumb";
    image.alt = "";
    image.src = result.thumb || "";

    const body = document.createElement("div");
    const title = document.createElement("div");
    title.className = "result-title";
    title.textContent = result.title || "Untitled";
    const meta = document.createElement("div");
    meta.className = "result-meta";
    meta.textContent = [
      result.year,
      result.country,
      result.catno,
      Array.isArray(result.label) ? result.label.join(" / ") : result.label,
    ].filter(Boolean).join(" / ");
    body.append(title, meta);

    const button = document.createElement("button");
    button.className = "secondary";
    button.type = "button";
    button.textContent = "取込";
    button.addEventListener("click", () => importDiscogsRelease(result.id));

    row.append(image, body, button);
    container.append(row);
  });
}

function textWithoutExtension(filename) {
  return String(filename || "").replace(/\.[a-z0-9]+$/i, "");
}

function escapeRegExp(text) {
  return String(text).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function extractCluesFromText(text) {
  const normalized = String(text || "")
    .replace(/[＿−―–—]/g, "-")
    .replace(/\s+/g, " ")
    .trim();
  const upper = normalized.toUpperCase();
  const barcode = normalized.match(/\b\d{8,14}\b/)?.[0] || "";
  const catalogNo = upper.match(/\b[A-Z]{1,6}[-\s]?\d{2,6}[A-Z]?\b/)?.[0]?.replace(/\s+/g, "-") || "";
  const year = normalized.match(/\b(19[4-9]\d|20[0-3]\d)\b/)?.[0] || "";
  const recordType = detectRecordType(normalized);
  const speed = detectSpeed(normalized);
  const country = /japan|日本/i.test(normalized) ? "Japan" : "";
  const titleParts = textWithoutExtension(normalized).split(/\s+-\s+/);
  const rawTitle = titleParts.length >= 2 ? titleParts.slice(1).join(" - ") : "";
  const noiseTokens = [
    catalogNo,
    barcode,
    year,
    recordType,
    speed,
    country,
    "Japan",
    "日本",
  ].filter(Boolean);
  const recordTitle = noiseTokens
    .reduce((title, token) => title.replace(new RegExp(escapeRegExp(token), "ig"), " "), rawTitle)
    .replace(/\b(rpm|vinyl|record)\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();

  return {
    artist: titleParts.length >= 2 ? titleParts[0] : "",
    recordTitle,
    catalogNo,
    barcode,
    year,
    recordType,
    speed,
    country,
  };
}

function applyPhotoClues({ overwrite = false } = {}) {
  const text = [
    state.photoFile?.name || "",
    document.querySelector("#ocrText").value,
  ].filter(Boolean).join("\n");
  const clues = extractCluesFromText(text);
  const count = applyMappedData(clues, { overwrite });
  setAutomationStatus(count ? `${count}項目を反映しました` : "反映できる候補がありません", count ? "good" : "warn");
  return clues;
}

function makeDiscogsSearchQuery() {
  const item = readForm() || activeItem() || {};
  const ocrText = document.querySelector("#ocrText").value;
  const clues = extractCluesFromText([state.photoFile?.name || "", ocrText].join(" "));
  const parts = [
    item.artist,
    item.recordTitle,
    item.catalogNo,
    item.barcode,
    clues.artist,
    clues.recordTitle,
    clues.catalogNo,
    clues.barcode,
  ];
  return [...new Set(parts.map((part) => String(part || "").trim()).filter(Boolean))]
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();
}

async function searchDiscogs() {
  const item = readForm() || {};
  const clues = extractCluesFromText([
    state.photoFile?.name || "",
    document.querySelector("#ocrText").value,
  ].join(" "));
  const barcode = item.barcode || clues.barcode;
  const query = makeDiscogsSearchQuery();
  if (!query && !barcode) {
    setAutomationStatus("検索語がありません", "warn");
    return;
  }

  const token = getDiscogsToken();
  if (!token) {
    const webQuery = encodeURIComponent(barcode || query);
    window.open(`https://www.discogs.com/search/?q=${webQuery}&type=release`, "_blank", "noopener");
    setAutomationStatus("Discogs検索を開きました", "good");
    return;
  }

  const params = new URLSearchParams({
    type: "release",
    per_page: "6",
  });
  if (barcode) params.set("barcode", barcode);
  if (query) params.set("q", query);

  setAutomationStatus("Discogs候補を検索中");
  try {
    const data = await fetchJson(`https://api.discogs.com/database/search?${params}`);
    const results = Array.isArray(data.results) ? data.results : [];
    renderDiscogsResults(results);
    setAutomationStatus(results.length ? `${results.length}件の候補` : "候補なし", results.length ? "good" : "warn");
  } catch (error) {
    clearDiscogsResults();
    const webQuery = encodeURIComponent(barcode || query);
    window.open(`https://www.discogs.com/search/?q=${webQuery}&type=release`, "_blank", "noopener");
    setAutomationStatus(error.message || "検索ページを開きました", "warn");
  }
}

async function detectBarcodeFromPhoto(file) {
  if (!("BarcodeDetector" in window)) return "";
  const supported = await BarcodeDetector.getSupportedFormats();
  const formats = [
    "ean_13",
    "ean_8",
    "upc_a",
    "upc_e",
    "code_39",
    "code_128",
  ].filter((format) => supported.includes(format));
  if (!formats.length) return "";
  const detector = new BarcodeDetector({ formats });
  const bitmap = await createImageBitmap(file);
  const detected = await detector.detect(bitmap);
  bitmap.close?.();
  return detected[0]?.rawValue || "";
}

async function detectTextFromPhoto(file) {
  if (!("TextDetector" in window)) return "";
  const detector = new TextDetector();
  const bitmap = await createImageBitmap(file);
  const detected = await detector.detect(bitmap);
  bitmap.close?.();
  return detected.map((entry) => entry.rawValue).filter(Boolean).join("\n");
}

function renderPhotoPreview(file) {
  const node = document.querySelector("#photoPreview");
  node.replaceChildren();
  if (state.photoObjectUrl) URL.revokeObjectURL(state.photoObjectUrl);
  state.photoObjectUrl = URL.createObjectURL(file);

  const image = document.createElement("img");
  image.src = state.photoObjectUrl;
  image.alt = "";
  const label = document.createElement("span");
  label.textContent = file.name;
  node.append(image, label);
  node.classList.add("has-image");
}

async function handlePhotoFile(file) {
  if (!file) return;
  state.photoFile = file;
  renderPhotoPreview(file);
  setFieldIfPresent("photoFolder", file.name, { overwrite: false });
  applyPhotoClues({ overwrite: false });

  try {
    const [barcode, detectedText] = await Promise.all([
      detectBarcodeFromPhoto(file),
      detectTextFromPhoto(file),
    ]);
    if (barcode) setFieldIfPresent("barcode", barcode, { overwrite: true });
    if (detectedText) {
      const ocr = document.querySelector("#ocrText");
      ocr.value = [ocr.value.trim(), detectedText].filter(Boolean).join("\n");
      applyPhotoClues({ overwrite: false });
    }
    if (barcode) {
      setAutomationStatus(`バーコード ${barcode} を検出しました`, "good");
      searchDiscogs();
    } else {
      setAutomationStatus("写真候補を反映しました", "good");
    }
  } catch {
    setAutomationStatus("写真候補を反映しました", "warn");
  }
}

function bindEvents() {
  document.querySelector("#newItemButton").addEventListener("click", createItem);
  document.querySelector("#duplicateButton").addEventListener("click", duplicateItem);
  document.querySelector("#deleteButton").addEventListener("click", deleteItem);
  document.querySelector("#calculateButton").addEventListener("click", updateCalculatedPrice);
  document.querySelector("#generateTitleButton").addEventListener("click", updateTitle);
  document.querySelector("#generateDescriptionButton").addEventListener("click", updateDescription);
  document.querySelector("#refreshCopyPackButton").addEventListener("click", () => {
    updateCopyPastePanel();
    setCopyStatus("再生成しました", "good");
  });
  document.querySelector("#copyAllButton").addEventListener("click", () => copyTextFromNode("copyAllText"));
  document.querySelectorAll("[data-copy-target]").forEach((button) => {
    button.addEventListener("click", () => copyTextFromNode(button.dataset.copyTarget));
  });
  document.querySelector("#fetchDiscogsButton").addEventListener("click", importDiscogsFromInput);
  document.querySelector("#saveDiscogsTokenButton").addEventListener("click", saveDiscogsToken);
  document.querySelector("#applyPhotoCluesButton").addEventListener("click", () => {
    applyPhotoClues({ overwrite: true });
  });
  document.querySelector("#openDiscogsSearchButton").addEventListener("click", searchDiscogs);
  document.querySelector("#photoInput").addEventListener("change", (event) => {
    handlePhotoFile(event.target.files?.[0]);
    event.target.value = "";
  });
  document.querySelector("#exportCsvButton").addEventListener("click", exportCsv);
  document.querySelector("#exportJsonButton").addEventListener("click", exportJson);
  document.querySelector("#importJsonButton").addEventListener("click", () => {
    document.querySelector("#importJsonInput").click();
  });
  document.querySelector("#importJsonInput").addEventListener("change", (event) => {
    importJson(event.target.files?.[0]);
    event.target.value = "";
  });

  document.querySelector("#searchInput").addEventListener("input", (event) => {
    state.search = event.target.value;
    renderList();
  });

  document.querySelector("#statusFilter").addEventListener("change", (event) => {
    state.status = event.target.value;
    renderList();
  });

  document.querySelector("#itemForm").addEventListener("submit", (event) => {
    event.preventDefault();
    commitForm();
  });

  fields.forEach((field) => {
    field.addEventListener("input", () => {
      syncPricePair(field.dataset.field);
      updatePricePreview();
      updateCopyPastePanel();
    });
  });

  document.querySelector("#addRateRowButton").addEventListener("click", () => {
    shippingRates.push({ method: "小形包装物(航空)", zone: "", maxG: 0, jpy: 0 });
    saveShippingRates();
    renderRateTable();
  });
  document.querySelector("#importRatesButton").addEventListener("click", () => importRates(false));
  document.querySelector("#replaceRatesButton").addEventListener("click", () => importRates(true));

  document.querySelector("#editPhrasesButton").addEventListener("click", () => {
    const editor = document.querySelector("#phraseEditor");
    editor.hidden = !editor.hidden;
    if (!editor.hidden) renderPhraseEditor();
  });
  document.querySelector("#addPhraseButton").addEventListener("click", addConditionPhrase);
}

// ===== 多重起動ガード =====
// 別ウインドウが既に開いていたら、後から開いた方に警告を出して閉じるよう促す。
// （両方で編集すると保存が上書きされ、どちらかの入力が消えるため）
const INSTANCE_ID = Math.random().toString(36).slice(2);
const HEARTBEAT_KEY = `${STORAGE_KEY}-hb`;

function heartbeatMap() {
  try { return JSON.parse(localStorage.getItem(HEARTBEAT_KEY)) || {}; } catch { return {}; }
}

function otherInstancesActive() {
  const now = Date.now();
  const hb = heartbeatMap();
  return Object.keys(hb).filter((k) => k !== INSTANCE_ID && now - hb[k] < 12000).length;
}

function writeHeartbeat() {
  try {
    const now = Date.now();
    const hb = heartbeatMap();
    hb[INSTANCE_ID] = now;
    Object.keys(hb).forEach((k) => { if (now - hb[k] > 12000) delete hb[k]; });
    localStorage.setItem(HEARTBEAT_KEY, JSON.stringify(hb));
  } catch { /* localStorage不可でも本体は動かす */ }
}

function showInstanceBlocker() {
  if (document.querySelector("#instanceBlocker")) return;
  const overlay = document.createElement("div");
  overlay.id = "instanceBlocker";
  overlay.style.cssText = "position:fixed;inset:0;z-index:9999;background:rgba(24,25,31,.72);display:flex;align-items:center;justify-content:center;";
  const card = document.createElement("div");
  card.style.cssText = "background:#fff;border-radius:14px;padding:28px 30px;max-width:460px;text-align:center;font-size:14px;line-height:1.7;box-shadow:0 20px 50px rgba(0,0,0,.3);";
  card.innerHTML = `<div style="font-size:17px;font-weight:800;margin-bottom:8px;color:#005f59">eBay Record Lister は既に開いています</div>
    <div style="color:#626976">2つの画面で同時に編集すると、保存が上書きされて入力が消えることがあります。<b>このウインドウは閉じて、先に開いている方を使ってください。</b></div>`;
  const buttonRow = document.createElement("div");
  buttonRow.style.cssText = "margin-top:18px;display:flex;gap:10px;justify-content:center;";
  const closeButton = document.createElement("button");
  closeButton.textContent = "このウインドウを閉じる";
  closeButton.style.cssText = "padding:10px 18px;border-radius:10px;border:none;background:#007c74;color:#fff;font-weight:700;cursor:pointer;";
  closeButton.addEventListener("click", () => {
    window.close();
    // window.close()が効かない環境向けの案内
    card.innerHTML = "<div style='font-size:15px'>閉じられない場合は、このウインドウを手動で閉じてください（⌘W）。</div>";
  });
  const forceButton = document.createElement("button");
  forceButton.textContent = "それでもこちらを使う";
  forceButton.style.cssText = "padding:10px 18px;border-radius:10px;border:1px solid #d7dce3;background:#fff;color:#626976;cursor:pointer;";
  forceButton.addEventListener("click", () => overlay.remove());
  buttonRow.append(closeButton, forceButton);
  card.append(buttonRow);
  overlay.append(card);
  document.body.append(overlay);
}

load();
loadDiscogsToken();
bindEvents();
renderRateTable();
if (!state.items.length) createItem();
render();

if (otherInstancesActive()) showInstanceBlocker();
writeHeartbeat();
setInterval(writeHeartbeat, 4000);
