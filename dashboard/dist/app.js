"use strict";

/* ============================================================
   VSGAME 開発記録庫 — 画面構築
   ============================================================ */

const DATA_FILES = ["project", "roadmap", "maps", "enemies", "bosses", "classes", "systems", "bugs", "decisions", "relations", "gallery"];

const NAV = [
  { id: "overview",  label: "ホーム",       icon: "⌂", eyebrow: "ARCHIVE HOME",          group: "" },
  { id: "classes",   label: "職業",         icon: "♞", eyebrow: "PLAYER / BOSS ROSTER",  group: "図鑑" },
  { id: "enemies",   label: "敵図鑑",       icon: "♟", eyebrow: "ENEMY ARCHIVE",         group: "図鑑" },
  { id: "bosses",    label: "ボス図鑑",     icon: "♜", eyebrow: "BOSS ARCHIVE",          group: "図鑑" },
  { id: "maps",      label: "マップ",       icon: "▦", eyebrow: "WORLD MAPS",            group: "図鑑" },
  { id: "combat",    label: "戦闘システム", icon: "⚔", eyebrow: "COMBAT SYSTEM",         group: "システム" },
  { id: "talents",   label: "天賦・成長",   icon: "✦", eyebrow: "TALENT & GROWTH",       group: "システム" },
  { id: "items",     label: "アイテム・報酬", icon: "⛃", eyebrow: "ITEMS & REWARDS",     group: "システム" },
  { id: "relations", label: "相関図",       icon: "⟡", eyebrow: "RELATION MAP",          group: "開発" },
  { id: "roadmap",   label: "開発フェーズ", icon: "◆", eyebrow: "PHASES & TASKS",        group: "開発" },
  { id: "decisions", label: "検討事項",     icon: "◈", eyebrow: "DECISIONS & OPEN ITEMS",group: "開発" },
  { id: "bugs",      label: "品質・性能",   icon: "⚠", eyebrow: "QUALITY WATCH",         group: "開発" }
];

const ROUTE_ALIAS = { systems: "combat", equipment: "items", talent: "talents" };
const BOTTOM = ["overview", "enemies", "bosses", "relations", "roadmap"];

const RANK_ORDER = ["mob", "standard", "strong", "elite", "midboss", "boss"];
const RANK_NUMERAL = { mob: "Ⅰ", standard: "Ⅱ", strong: "Ⅲ", elite: "Ⅳ", midboss: "Ⅴ", boss: "Ⅵ" };
const RANK_CARD_SIZE = { mob: "size-s", standard: "size-m", strong: "size-l", elite: "size-l", midboss: "size-xl", boss: "size-xl" };

const HOME_ENTRIES = [
  { route: "classes",   title: "職業",         kicker: "PLAYER / BOSS",  accent: "seal",  image: "assets/portraits/classes/knight.png",      kind: "portrait", desc: "正式Player6職と、ボスへ転用した4職の役割。" },
  { route: "enemies",   title: "敵図鑑",       kicker: "ENEMY",          accent: "seal",  image: "assets/portraits/enemies/armored_orc.png", kind: "portrait", desc: "6段階の階級で並べた通常敵のRoster。" },
  { route: "bosses",    title: "ボス図鑑",     kicker: "BOSS",           accent: "blood", image: "assets/portraits/bosses/minotaur.png",     kind: "portrait", desc: "現行ボスと職業転用ボス。ペア戦を含む決戦の一覧。" },
  { route: "maps",      title: "マップ",       kicker: "WORLD",          accent: "gold",  image: "assets/images/map-exploration.png",        kind: "scene",    desc: "3MAPの進行条件、敵系統、ボス、宝箱。" },
  { route: "talents",   title: "天賦・成長",   kicker: "TALENT",         accent: "seal",  image: "assets/images/talent-top.png",             kind: "scene",    desc: "Tで開く魔導書、剣士2流派、レベルアップ三択。" },
  { route: "items",     title: "アイテム・報酬", kicker: "ITEM",         accent: "gold",  image: "assets/images/equipment-catalog.png",      kind: "scene",    desc: "装備、希少度、合成、ドロップと宝箱。" },
  { route: "combat",    title: "戦闘システム", kicker: "COMBAT",         accent: "blood", image: "assets/images/boss-minotaur-cleave.png",   kind: "scene",    desc: "状態異常、Fusion、UI・VFX・音の現行仕様。" },
  { route: "roadmap",   title: "開発フェーズ", kicker: "PHASE",          accent: "gold",  sigil: "◆", desc: "現在・次・将来の3レーンで追う実装タスク。" },
  { route: "relations", title: "相関図",       kicker: "RELATION",       accent: "seal",  sigil: "⟡", desc: "職業、マップ、敵、ボス、開発項目のつながり。" },
  { route: "decisions", title: "検討事項",     kicker: "OPEN ITEMS",     accent: "blood", sigil: "◈", desc: "保留中の判断と、確定済みの決定記録。" }
];

const state = { data: {}, route: "overview", filters: {}, graphZoom: 1, focusNode: null, diagram: null };

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const esc = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" }[char]));
const jpStatus = value => state.data.project?.statusLabels?.[value] ?? value;
const jpPriority = value => state.data.project?.priorityLabels?.[value] ?? value;
const pct = value => Math.max(0, Math.min(100, Math.round(Number(value) || 0)));
const array = value => Array.isArray(value) ? value : [];

document.addEventListener("DOMContentLoaded", init);

async function init() {
  buildNavigation();
  bindShell();
  try {
    const loaded = await Promise.all(DATA_FILES.map(async name => {
      const response = await fetch(`data/${name}.json`, { cache: "no-store" });
      if (!response.ok) throw new Error(`${name}.json: ${response.status}`);
      return [name, await response.json()];
    }));
    state.data = Object.fromEntries(loaded);
    $("#updatedAt").textContent = state.data.project.updatedAt;
    $("#dashVersion").textContent = state.data.project.version ?? "";
    routeFromHash();
  } catch (error) {
    $("#updatedAt").textContent = "—";
    $("#mainContent").innerHTML = `<section class="error-state"><strong>記録を読み込めませんでした</strong><p>${esc(error.message)}<br>ローカルではHTTPサーバー経由で開いてください。</p></section>`;
  }
}

/* ---------------- シェル ---------------- */

function buildNavigation() {
  let markup = "";
  let currentGroup = null;
  NAV.forEach(item => {
    if (item.group !== currentGroup) {
      currentGroup = item.group;
      if (currentGroup) markup += `<span class="nav-group-label">${esc(currentGroup)}</span>`;
    }
    markup += navLink(item);
  });
  $("#sideNav").innerHTML = markup;
  $("#drawerNav").innerHTML = markup;
  $("#bottomNav").innerHTML = BOTTOM.map(id => {
    const item = NAV.find(entry => entry.id === id);
    return `<a class="bottom-link" href="#${id}" data-route="${id}"><span aria-hidden="true">${item.icon}</span><span>${esc(item.label.replace("開発", ""))}</span></a>`;
  }).join("");
}

function navLink(item) {
  return `<a class="nav-link" href="#${item.id}" data-route="${item.id}"><span class="nav-icon" aria-hidden="true">${item.icon}</span><span class="nav-label">${esc(item.label)}</span><span class="nav-count" data-count="${item.id}"></span></a>`;
}

function bindShell() {
  window.addEventListener("hashchange", routeFromHash);
  $("#menuButton").addEventListener("click", openDrawer);
  $("#drawerClose").addEventListener("click", closeDrawer);
  $("#drawerBackdrop").addEventListener("click", closeDrawer);
  document.addEventListener("keydown", event => {
    if (event.key === "Escape") closeDrawer();
    if (event.key === "/" && !["INPUT", "SELECT", "TEXTAREA"].includes(document.activeElement.tagName)) {
      event.preventDefault();
      $("#globalSearch").focus();
    }
  });
  $("#globalSearch").addEventListener("keydown", event => {
    if (event.key === "Enter" && event.currentTarget.value.trim()) {
      state.filters.global = event.currentTarget.value.trim();
      if (location.hash === "#search") render(); else location.hash = "search";
    }
  });
  $("#imageDialogClose").addEventListener("click", () => $("#imageDialog").close());
  $("#imageDialog").addEventListener("click", event => {
    if (event.target === event.currentTarget) event.currentTarget.close();
  });
  window.addEventListener("resize", refreshGraph);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) refreshGraph(); });
}

function openDrawer() {
  $("#mobileDrawer").classList.add("open");
  $("#mobileDrawer").setAttribute("aria-hidden", "false");
  $("#menuButton").setAttribute("aria-expanded", "true");
  $("#drawerBackdrop").hidden = false;
  requestAnimationFrame(() => $("#drawerBackdrop").classList.add("open"));
}

function closeDrawer() {
  $("#mobileDrawer").classList.remove("open");
  $("#mobileDrawer").setAttribute("aria-hidden", "true");
  $("#menuButton").setAttribute("aria-expanded", "false");
  $("#drawerBackdrop").classList.remove("open");
  setTimeout(() => { $("#drawerBackdrop").hidden = true; }, 200);
}

function routeFromHash() {
  if (!state.data.project) return;
  const raw = location.hash.slice(1) || "overview";
  const id = ROUTE_ALIAS[raw] ?? raw;
  const next = NAV.some(item => item.id === id) || id === "search" ? id : "overview";
  if (next !== state.route) { state.focusNode = null; state.graphZoom = 1; }
  state.route = next;
  closeDrawer();
  render();
  window.scrollTo(0, 0);
}

function render() {
  const navItem = NAV.find(item => item.id === state.route);
  $("#pageTitle").textContent = navItem?.label ?? "検索結果";
  $("#pageEyebrow").textContent = navItem?.eyebrow ?? "ARCHIVE SEARCH";
  $$("[data-route]").forEach(link => link.classList.toggle("active", link.dataset.route === state.route));
  updateCounts();
  const renderers = {
    overview: renderOverview, classes: renderClasses, enemies: renderEnemies, bosses: renderBosses,
    maps: renderMaps, combat: renderCombat, talents: renderTalents, items: renderItems,
    relations: renderRelations, roadmap: renderRoadmap, decisions: renderDecisions, bugs: renderBugs,
    search: renderSearch
  };
  $("#mainContent").innerHTML = renderers[state.route]();
  document.body.dataset.page = state.route;
  bindPageControls();
  refreshGraph();
  requestAnimationFrame(refreshGraph);
  $("#mainContent").focus({ preventScroll: true });
}

function updateCounts() {
  const classes = array(state.data.classes.classes);
  const counts = {
    classes: `${classes.filter(item => item.disposition === "player").length}+${classes.filter(item => item.disposition === "boss").length}`,
    enemies: array(state.data.enemies.enemies).length,
    bosses: array(state.data.bosses.bosses).length,
    maps: array(state.data.maps.maps).length,
    combat: array(state.data.systems.attributes).length,
    talents: array(state.data.systems.survival?.upgrades).length,
    items: state.data.systems.equipment?.catalogCount ?? "",
    relations: array(state.data.relations.diagrams).length,
    roadmap: allTasks().filter(task => task.status !== "completed").length,
    decisions: array(state.data.relations.board).filter(item => item.decision === "hold" || item.decision === "redesign").length,
    bugs: array(state.data.bugs.bugs).filter(bug => !["fixed", "closed"].includes(bug.status)).length
  };
  $$("[data-count]").forEach(el => { el.textContent = counts[el.dataset.count] ?? ""; });
}

/* ---------------- 共通パーツ ---------------- */

function allTasks() {
  return array(state.data.roadmap.categories).flatMap(category =>
    array(category.tasks).map(task => ({ ...task, categoryId: category.id, categoryName: category.name, categoryWeight: category.weight })));
}

function tasksOfCategories(ids) {
  return allTasks().filter(task => ids.includes(task.categoryId));
}

function categoryProgress(category) {
  const tasks = array(category.tasks);
  if (!tasks.length) return 0;
  return tasks.reduce((sum, task) => sum + pct(task.progress), 0) / tasks.length;
}

function overallProgress() {
  const categories = array(state.data.roadmap.categories);
  const totalWeight = categories.reduce((sum, category) => sum + Number(category.weight || 1), 0);
  return totalWeight ? categories.reduce((sum, category) => sum + categoryProgress(category) * Number(category.weight || 1), 0) / totalWeight : 0;
}

function progressBar(value, label = "進捗", tone = "") {
  const n = pct(value);
  return `<div class="progress-track ${tone}" role="progressbar" aria-label="${esc(label)} ${n}%" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${n}" style="--value:${n}%"><span></span></div>`;
}

function progressRow(name, progress, detail = "") {
  const n = pct(progress);
  return `<div class="progress-row"><div class="progress-label"><strong>${esc(name)}</strong><small>${esc(detail)}</small></div>${progressBar(n, name)}<div class="progress-value">${n}%</div></div>`;
}

function badge(kind, value, label) {
  return `<span class="badge ${kind}-${esc(value)}">${esc(label ?? value)}</span>`;
}

function crest(rank, large = false) {
  return `<span class="crest ${large ? "crest-lg" : ""} rank-${esc(rank)}" aria-hidden="true"><i>${RANK_NUMERAL[rank] ?? "◆"}</i></span>`;
}

function intro(title, description, aside = "") {
  return `<header class="section-intro"><div class="intro-copy"><h2>${esc(title)}</h2><p>${esc(description)}</p></div>${aside}</header>`;
}

function blockTitle(title, description, count = "") {
  return `<div class="block-title"><div><h3>${esc(title)}</h3>${description ? `<small>${esc(description)}</small>` : ""}</div>${count ? `<span class="block-count">${esc(count)}</span>` : ""}</div>`;
}

function empty(message = "該当する記録はありません") {
  return `<div class="empty-state"><strong>${esc(message)}</strong><span>検索条件を変えてください。</span></div>`;
}

function mapLabel(id) { return String(id).replace("map", "MAP "); }
function rankName(id) { return state.data.enemies.hierarchy.find(item => item.id === id)?.name ?? id; }
function classById(id) { return array(state.data.classes.classes).find(item => item.id === id); }
function bossById(id) { return array(state.data.bosses.bosses).find(item => item.id === id); }
function bossByName(name) { return array(state.data.bosses.bosses).find(item => item.name === name); }
function enemiesOfMap(mapId) { return array(state.data.enemies.enemies).filter(item => array(item.maps).includes(mapId)); }
function bossRank(boss) { return boss.sourceClass ? "boss" : "midboss"; }

function tagList(values, tone = "") {
  if (!values.length) return "";
  return `<div class="tag-list">${values.map(value => `<span class="tag ${tone}">${esc(value)}</span>`).join("")}</div>`;
}

function moreBlock(label, pairs, note = "") {
  const rows = pairs.filter(([, value]) => value !== undefined && value !== null && value !== "")
    .map(([key, value]) => `<div><dt>${esc(key)}</dt><dd>${esc(value)}</dd></div>`).join("");
  if (!rows && !note) return "";
  return `<details class="more"><summary>${esc(label)}</summary><div class="more-body">${rows ? `<dl>${rows}</dl>` : ""}${note ? `<p>${esc(note)}</p>` : ""}</div></details>`;
}

/* ---------------- ギャラリー ---------------- */

function galleryByIds(ids) {
  const source = array(state.data.gallery?.items);
  return ids.map(id => source.find(item => item.id === id)).filter(Boolean);
}

function galleryByCategory(...categories) {
  return array(state.data.gallery?.items).filter(item => categories.includes(item.category));
}

function visualSection(title, description, items, id) {
  if (!items.length) return "";
  return `<section class="panel slab ornate">${blockTitle(title, description, `${items.length}枚`)}${visualGallery(items, id)}</section>`;
}

function visualGallery(items, id = "gallery") {
  if (!items.length) return `<div class="empty-state" style="min-height:180px">該当する実画面はありません</div>`;
  return `<div class="visual-grid" id="${esc(id)}">${items.map(visualCard).join("")}</div>`;
}

function visualCard(item) {
  const category = state.data.gallery.categoryLabels[item.category] ?? item.category;
  return `<button class="visual-card decision-${esc(item.decision)}" type="button" data-image-id="${esc(item.id)}" aria-label="${esc(item.title)}を拡大">
    <span class="visual-image"><img src="${esc(item.image)}" alt="${esc(item.alt ?? `${item.title}の実ゲーム画面`)}" loading="lazy" decoding="async"></span>
    <span class="visual-copy"><span class="visual-kicker"><span>${esc(category)}</span>${decisionBadge(item.decision)}</span><strong>${esc(item.title)}</strong><small>${esc(item.caption)}</small><span class="tag-list">${array(item.related).map(value => `<span class="tag">${esc(value)}</span>`).join("")}</span></span>
  </button>`;
}

function decisionBadge(decision) {
  const label = state.data.relations?.decisionLabels?.[decision] ?? decision;
  return `<span class="decision-badge decision-${esc(decision)}"><i aria-hidden="true"></i>${esc(label)}</span>`;
}

/* ============================================================
   ホーム
   ============================================================ */

function renderOverview() {
  const tasks = allTasks();
  const overall = pct(overallProgress());
  const active = tasks.filter(task => ["implementing", "testing"].includes(task.status)).sort(prioritySort).slice(0, 5);
  const next = tasks.filter(task => ["not_started", "design"].includes(task.status)).sort(prioritySort).slice(0, 5);
  const openBugs = array(state.data.bugs.bugs).filter(bug => !["fixed", "closed"].includes(bug.status));
  const critical = openBugs.filter(bug => bug.severity === "critical");
  const categories = array(state.data.roadmap.categories);
  const completed = tasks.filter(task => task.status === "completed").length;
  const project = state.data.project;

  return `
    ${intro("VSGAMEの現在地", "職業、敵、ボス、マップ、成長、開発計画。記録庫の全体をここから開きます。")}
    ${dailySummary()}
    ${critical.length ? `<div class="alert-slab"><span class="alert-mark" aria-hidden="true">⚠</span><div><strong>重大バグ ${critical.length}件</strong><p>${esc(critical.map(bug => bug.name).join(" / "))}</p></div></div>` : ""}
    <section class="home-hero slab ornate">
      <div class="progress-orb" style="--progress:${overall * 3.6}deg"><span class="orb-value"><strong>${overall}%</strong><small>TOTAL</small></span></div>
      <div class="hero-copy">
        <span class="eyebrow">TOTAL DEVELOPMENT</span>
        <h2>ゲーム全体進捗</h2>
        <p>${esc(project.summary)}</p>
        <hr class="rule hero-rule">
        <p class="hero-note">${esc(project.progressRule)}</p>
      </div>
      <div class="hero-stats">
        <div class="hero-stat"><small>完了タスク</small><strong>${completed}</strong></div>
        <div class="hero-stat"><small>総タスク</small><strong>${tasks.length}</strong></div>
        <div class="hero-stat"><small>現行MAP</small><strong>${array(state.data.maps.maps).length}</strong></div>
        <div class="hero-stat"><small>未解決バグ</small><strong>${openBugs.length}</strong></div>
      </div>
    </section>

    <section class="panel slab ornate" style="margin-bottom:18px">
      ${blockTitle("記録庫の入口", "掲載している内容の全体です。見たい章を選んでください。", `${HOME_ENTRIES.length}章`)}
      <div class="entry-grid">${HOME_ENTRIES.map(entryCard).join("")}</div>
    </section>

    <section class="metrics-grid" style="margin-bottom:18px">
      <article class="metric-card slab"><div class="metric-label">登録敵</div><div class="metric-value">${array(state.data.enemies.enemies).length}体</div><div class="metric-detail">6階級の通常Roster</div></article>
      <article class="metric-card slab"><div class="metric-label">ボス戦</div><div class="metric-value">${array(state.data.bosses.bosses).length}戦</div><div class="metric-detail">終盤6種＋旧Boss・設計履歴</div></article>
      <article class="metric-card slab"><div class="metric-label">正式Player職</div><div class="metric-value">${array(state.data.classes.classes).filter(item => item.disposition === "player").length}職</div><div class="metric-detail">6職の選択画面へ反映済み</div></article>
      <article class="metric-card slab ${critical.length ? "danger" : ""}"><div class="metric-label">Critical Bug</div><div class="metric-value">${critical.length}件</div><div class="metric-detail">${critical.length ? "即時対応が必要" : "現在なし"}</div></article>
    </section>

    ${visualSection("実画面で見る現在地", "入口、探索、決戦、成長の現状です。画像を押すと拡大できます。", galleryByIds(["open-field", "open-field-boss", "open-field-recovery", "survival-growth-choices"]), "overview-visuals")}

    <div class="panel-grid" style="margin-top:18px">
      <section class="panel slab ornate span-7">${blockTitle("カテゴリ進捗", "", `${categories.length}カテゴリ`)}<div class="progress-list">${categories.map(category => progressRow(category.name, categoryProgress(category), `重要度 ${category.weight}`)).join("")}</div></section>
      <section class="panel slab ornate span-5">${blockTitle("現在実装中", "", `${active.length}件`)}${taskList(active, false)}</section>
      <section class="panel slab ornate span-6">${blockTitle("次に実装", "優先度順", "")}${taskList(next, true)}</section>
      <section class="panel slab ornate span-6">${blockTitle("品質監視", "", `${openBugs.length}件`)}${bugList(openBugs.slice(0, 5))}</section>
      <section class="panel slab ornate span-12">${blockTitle("最近の決定", "仕様変更の理由と影響", "")}${decisionTimeline(array(state.data.decisions.decisions).slice(0, 3))}</section>
    </div>`;
}

function entryCard(entry) {
  const counts = {
    classes: `${array(state.data.classes.classes).filter(item => item.disposition === "player").length}職 + 転用${array(state.data.classes.classes).filter(item => item.disposition === "boss").length}職`,
    enemies: `${array(state.data.enemies.enemies).length}体`,
    bosses: `${array(state.data.bosses.bosses).length}戦`,
    maps: `${array(state.data.maps.maps).length}MAP`,
    talents: `剣士2流派`,
    items: `装備${state.data.systems.equipment?.catalogCount ?? 0}`,
    combat: `状態${array(state.data.systems.attributes).length}`,
    roadmap: `${allTasks().length}タスク`,
    relations: `${array(state.data.relations.diagrams).length}図`,
    decisions: `${array(state.data.decisions.decisions).length}件`
  };
  const visual = entry.sigil
    ? `<span class="entry-visual is-sigil" aria-hidden="true"><span><i>${entry.sigil}</i></span></span>`
    : `<span class="entry-visual ${entry.kind === "portrait" ? "is-portrait" : ""}"><img src="${esc(entry.image)}" alt="${esc(entry.title)}の代表画像" loading="lazy" decoding="async"></span>`;
  return `<a class="entry-card accent-${esc(entry.accent)}" href="#${esc(entry.route)}">
    ${visual}
    <span class="entry-copy">
      <span class="entry-kicker"><span>${esc(entry.kicker)}</span><b>${esc(counts[entry.route] ?? "")}</b></span>
      <strong class="entry-name">${esc(entry.title)}</strong>
      <small>${esc(entry.desc)}</small>
    </span>
  </a>`;
}

function taskList(tasks, numbered) {
  if (!tasks.length) return `<div class="empty-state" style="min-height:150px">該当するタスクはありません</div>`;
  return `<ol class="task-list">${tasks.map((task, index) => `<li class="task-item">${numbered ? `<span class="task-rank"><span>${index + 1}</span></span>` : `<span>${badge("status", task.status, jpStatus(task.status))}</span>`}<span class="task-copy"><strong>${esc(task.name)}</strong><small>${esc(task.categoryName)} · ${pct(task.progress)}%</small></span>${badge("priority", task.priority, jpPriority(task.priority))}</li>`).join("")}</ol>`;
}

function prioritySort(a, b) {
  const rank = { high: 0, medium: 1, low: 2 };
  return (rank[a.priority] ?? 9) - (rank[b.priority] ?? 9) || b.progress - a.progress;
}

/* ============================================================
   職業
   ============================================================ */

function renderClasses() {
  const classes = array(state.data.classes.classes);
  const players = classes.filter(item => item.disposition === "player");
  const converted = classes.filter(item => item.disposition === "boss");
  return `${intro("職業図鑑", "10職を正式Player6職とボス転用4職へ分けます。残す職業は役割を尖らせ、転用職はボス固有の読み合いへ作り替えます。")}
    <section class="metrics-grid" style="margin-bottom:18px">
      <article class="metric-card slab"><div class="metric-label">再編前</div><div class="metric-value">${classes.length}職</div><div class="metric-detail">戦闘接続済み</div></article>
      <article class="metric-card slab"><div class="metric-label">正式Player</div><div class="metric-value">${players.length}職</div><div class="metric-detail">個性を強化する対象</div></article>
      <article class="metric-card slab"><div class="metric-label">ボス転用</div><div class="metric-value">${converted.length}職</div><div class="metric-detail">3つのボス戦へ再構成</div></article>
      <article class="metric-card slab"><div class="metric-label">ペアボス</div><div class="metric-value">1戦</div><div class="metric-detail">聖堂騎士＋司祭</div></article>
    </section>

    <section class="codex-section">
      <div class="codex-band rank-standard"><span class="crest rank-standard" aria-hidden="true"><i>◆</i></span><div class="band-copy"><h3>正式Player 6職</h3><p>操作の役割を分離し、各職の個性を強める対象です。</p></div><span class="block-count">${players.length}職</span></div>
      <div class="codex-grid size-l">${players.map(playerClassCard).join("")}</div>
    </section>

    <section class="codex-section">
      <div class="codex-band rank-boss"><span class="crest rank-boss" aria-hidden="true"><i>◆</i></span><div class="band-copy"><h3>ボス転用 4職</h3><p>槍兵と死霊術師は単独戦、聖堂騎士と司祭は同時に出現するペア戦です。</p></div><span class="block-count">${converted.length}職 / 3戦</span></div>
      <div class="codex-grid size-l">${converted.map(convertedClassCard).join("")}</div>
    </section>

    ${visualSection("職業選択から天賦分岐へ", "正式Player6職の選択画面は実装済み。天賦図は剣士の2流派に対応しています。ボス転用4職へPlayer用天賦は追加しません。", galleryByIds(["characters-six", "talent-top"]), "class-visuals")}`;
}

function playerClassCard(item) {
  return `<article class="codex-card rank-standard">
    <div class="codex-portrait">
      ${crest("standard")}
      <span class="portrait-rank">Player</span>
      <img src="${esc(item.image)}" alt="${esc(item.name)}のSprite" width="256" height="256" loading="lazy" decoding="async">
    </div>
    <div class="codex-body">
      <div class="codex-head"><div><span class="codex-id">${esc(item.id)}</span><h3 class="codex-name">${esc(item.name)}</h3></div>${badge("status", "player", "Player継続")}</div>
      <p class="codex-role"><b>通常攻撃</b><span>${esc(item.attack)}</span></p>
      <p class="codex-role"><b>能動Skill</b><span>${esc(item.activeSkill)}</span></p>
      <dl class="codex-stats"><div><dt>HP</dt><dd>${esc(item.hp)}</dd></div><div><dt>移動速度</dt><dd>${esc(item.speed)}</dd></div><div><dt>区分</dt><dd>正式</dd></div></dl>
      <p class="codex-desc">${esc(item.notes)}</p>
      ${moreBlock("詳細を見る", [["通常攻撃", item.attack], ["能動Skill", item.activeSkill], ["HP", item.hp], ["移動速度", item.speed]], item.notes)}
    </div>
  </article>`;
}

function convertedClassCard(item) {
  const boss = bossById(item.bossEncounter);
  const beforeImage = `assets/portraits/classes/${item.id}.png`;
  return `<article class="codex-card rank-boss">
    <div class="codex-portrait">
      ${crest("boss")}
      <span class="portrait-rank">BOSS転用</span>
      <img src="${esc(item.image)}" alt="${esc(item.name)}のSprite" width="256" height="256" loading="lazy" decoding="async">
    </div>
    <div class="codex-body">
      <div class="codex-head"><div><span class="codex-id">${esc(item.id)}</span><h3 class="codex-name">${esc(item.name)}</h3></div>${badge("status", "boss", "ボス転用")}</div>
      <div class="transform-row">
        <div class="transform-side"><figure><img src="${esc(beforeImage)}" alt="${esc(item.name)}の再編前Sprite" loading="lazy" decoding="async"></figure><small>再編前 / Player</small></div>
        <div class="transform-arrow" aria-hidden="true"><span>➜</span><small>転用</small></div>
        <div class="transform-side after"><figure><img src="${esc(item.image)}" alt="${esc(item.name)}の再編後Sprite" loading="lazy" decoding="async"></figure><small>再編後 / ボス</small></div>
      </div>
      <p class="codex-role"><b>戦闘</b><span>${esc(boss?.role ?? "ボス戦へ転用")}</span></p>
      <dl class="codex-stats"><div><dt>HP</dt><dd>${esc(item.hp)}</dd></div><div><dt>移動速度</dt><dd>${esc(item.speed)}</dd></div><div><dt>通常攻撃</dt><dd>${esc(item.attack)}</dd></div></dl>
      <p class="codex-desc">${esc(item.notes)}</p>
      ${boss ? `<div class="tag-list"><a class="tag tag-blood" href="#bosses">ボス図鑑で見る: ${esc(boss.name)}</a></div>` : ""}
    </div>
  </article>`;
}

/* ============================================================
   敵図鑑
   ============================================================ */

function renderEnemies() {
  const enemies = filterEnemies();
  const hierarchy = array(state.data.enemies.hierarchy);
  const groups = RANK_ORDER.map(rank => [rank, enemies.filter(enemy => enemy.rank === rank)]).filter(([, list]) => list.length);

  return `<p class="slab" style="padding:18px;margin-bottom:20px"><a href="strong-enemies.html">▶ 強敵6体の動き見本を見る（スマホ対応MP4）</a><br><a href="elite-affixes.html">◆ 精鋭6能力の新エフェクトを見る（スマホ対応MP4）</a></p>${intro("敵図鑑", "実ゲームの姿と階級、登場MAP、攻撃、実装状況を並べます。階級が上がるほど枠と紋章が強くなります。")}
    <section class="panel slab ornate" style="margin-bottom:18px">
      ${blockTitle("正式な敵階級", "雑魚から順に、数で圧をかける敵から専用Patternを持つボスまで6段階で管理します。", "6段階")}
      <div class="hierarchy">${hierarchy.map(hierarchyStep).join("")}</div>
    </section>
    <div class="filter-bar slab" style="margin-bottom:18px">
      ${filterInput("enemyQuery", "敵を検索", "名称・ID・メモ")}
      ${filterSelect("enemyRank", "階級", Object.fromEntries(hierarchy.map(item => [item.id, item.name])))}
      ${filterSelect("enemyMap", "登場MAP", { map1: "MAP 1", map2: "MAP 2", map3: "MAP 3" })}
      ${filterSelect("enemyStatus", "実装状況", state.data.project.statusLabels)}
    </div>
    ${groups.length ? groups.map(([rank, list]) => `
      <section class="codex-section">
        <div class="codex-band rank-${rank}">${crest(rank, true)}<div class="band-copy"><h3>${esc(rankName(rank))}</h3><p>${esc(hierarchy.find(item => item.id === rank)?.notes ?? "")}</p></div><span class="block-count">${list.length}体</span></div>
        <div class="codex-grid ${RANK_CARD_SIZE[rank]}">${list.map(enemyCard).join("")}</div>
      </section>`).join("") : empty("該当する敵はいません")}`;
}

function hierarchyStep(item) {
  const count = array(state.data.enemies.enemies).filter(enemy => enemy.rank === item.id).length
    || array(state.data.bosses.bosses).filter(boss => bossRank(boss) === item.id).length;
  return `<article class="hierarchy-step rank-${esc(item.id)}">
    <div class="hierarchy-head">${crest(item.id)}<h4>${esc(item.name)}</h4></div>
    <dl><div><dt>HP</dt><dd>${esc(item.hp)}</dd></div><div><dt>攻撃</dt><dd>${esc(item.attack)}</dd></div></dl>
    <p>${esc(item.notes)}</p>
    ${count ? `<span class="step-count">登録 ${count}</span>` : ""}
  </article>`;
}

function enemyCard(enemy) {
  const maps = array(enemy.maps).map(mapLabel);
  return `<article class="codex-card rank-${esc(enemy.rank)}">
    <div class="codex-portrait">
      ${crest(enemy.rank)}
      <span class="portrait-rank">${esc(rankName(enemy.rank))}</span>
      <img src="${esc(enemy.image)}" alt="${esc(enemy.name)}のSprite" width="256" height="256" loading="lazy" decoding="async">
      <span class="portrait-maps">${maps.map(label => `<span class="tag">${esc(label)}</span>`).join("")}</span>
    </div>
    <div class="codex-body">
      <div class="codex-head"><div><span class="codex-id">${esc(enemy.id)}</span><h3 class="codex-name">${esc(enemy.name)}</h3></div>${badge("status", enemy.status, jpStatus(enemy.status))}</div>
      <div class="tag-list mobile-maps">${maps.map(label => `<span class="tag">${esc(label)}</span>`).join("")}<span class="tag tag-muted">${esc(rankName(enemy.rank))}</span></div>
      <p class="codex-role"><b>役割</b><span>${esc(enemy.attack)}${enemy.skill && enemy.skill !== "なし" ? ` / ${esc(enemy.skill)}` : ""}</span></p>
      <dl class="codex-stats"><div><dt>HP</dt><dd>${esc(enemy.hp)}</dd></div><div><dt>攻撃力</dt><dd>${esc(enemy.damage)}</dd></div><div><dt>進捗</dt><dd>${pct(enemy.progress)}%</dd></div></dl>
      <p class="codex-desc">${esc(enemy.notes)}</p>
      ${moreBlock("詳細を見る", [["階級", rankName(enemy.rank)], ["登場MAP", maps.join(" / ") || "未配置"], ["攻撃", enemy.attack], ["技", enemy.skill], ["属性", enemy.attribute], ["Drop", enemy.drop], ["状況", jpStatus(enemy.status)]], enemy.notes)}
    </div>
  </article>`;
}

function filterEnemies() {
  const query = (state.filters.enemyQuery || "").toLowerCase();
  return array(state.data.enemies.enemies).filter(enemy =>
    (!query || `${enemy.name} ${enemy.id} ${enemy.notes} ${enemy.attack}`.toLowerCase().includes(query)) &&
    (!state.filters.enemyRank || enemy.rank === state.filters.enemyRank) &&
    (!state.filters.enemyMap || array(enemy.maps).includes(state.filters.enemyMap)) &&
    (!state.filters.enemyStatus || enemy.status === state.filters.enemyStatus));
}

/* ============================================================
   ボス図鑑
   ============================================================ */

function renderBosses() {
  const bosses = array(state.data.bosses.bosses);
  const converted = bosses.filter(boss => boss.sourceClass);
  const current = bosses.filter(boss => boss.stageUse === "final");
  const historical = bosses.filter(boss => !boss.sourceClass && boss.stageUse !== "final");
  const mapGroups = [["map1", "MAP 1"], ["map2", "MAP 2"], ["map3", "MAP 3"]]
    .map(([id, label]) => [label, current.filter(boss => array(boss.maps).includes(id))]);

  return `${intro("ボス図鑑", "現行ステージの終盤ボスは従来の強敵から6種類。旧ボスと職業転用の設計も履歴として保持しています。")}
    <section class="metrics-grid" style="margin-bottom:18px">
      <article class="metric-card slab"><div class="metric-label">現行の終盤ボス</div><div class="metric-value">${current.length}種</div><div class="metric-detail">各ステージ2候補から1体</div></article>
      <article class="metric-card slab"><div class="metric-label">旧ボス</div><div class="metric-value">${historical.length}種</div><div class="metric-detail">現在のステージには出現しない</div></article>
      <article class="metric-card slab"><div class="metric-label">職業転用の設計</div><div class="metric-value">${converted.length}戦</div><div class="metric-detail">未実装・ペア戦を含む</div></article>
      <article class="metric-card slab"><div class="metric-label">登録ボス</div><div class="metric-value">${bosses.length}件</div><div class="metric-detail">記録庫の総数</div></article>
    </section>
    <section class="codex-section">
      <div class="codex-band rank-boss">${crest("boss", true)}<div class="band-copy"><h3>現行ステージの終盤ボス</h3><p>約4分後に1体出現。5分を過ぎても戦闘は続き、撃破してクリアします。</p></div><span class="block-count">${current.length}種</span></div>
      ${mapGroups.map(([label, list]) => list.length ? `
        <div class="block-title" style="margin-top:18px"><div><h3>${esc(label)}</h3></div><span class="block-count">${list.length}候補から1体</span></div>
        <div class="codex-grid size-xl">${list.map(bossCard).join("")}</div>` : "").join("")}
    </section>
    ${visualSection("終盤ボスと討伐報酬", "元の強敵の技を保持。討伐後は装備と宝箱を回収し、自分で帰還できます。", galleryByIds(["open-field-boss", "open-field-recovery"]), "boss-visuals")}
    <section class="codex-section">
      <div class="codex-band rank-midboss">${crest("midboss", true)}<div class="band-copy"><h3>旧ボスの記録</h3><p>以前の戦闘・Test Labの記録。現在のステージには出現しません。</p></div><span class="block-count">${historical.length}種</span></div>
      <div class="codex-grid size-xl">${historical.map(bossCard).join("")}</div>
    </section>
    <section class="codex-section">
      <div class="codex-band rank-boss">${crest("boss", true)}<div class="band-copy"><h3>職業転用ボスの設計</h3><p>Player職から外した4職の転用案。現行ステージへの導入は未決定です。</p></div><span class="block-count">${converted.length}戦</span></div>
      <div class="boss-feature-grid">${converted.map(boss => boss.members ? duoBossCard(boss) : featureBossCard(boss)).join("")}</div>
    </section>`;
}

function featureBossCard(boss) {
  const source = array(boss.sourceClass).map(id => classById(id)?.name).filter(Boolean);
  return `<article class="boss-feature">
    <div class="boss-portrait">${crest("boss", true)}<img src="${esc(boss.image)}" alt="${esc(boss.name)}のSprite" width="256" height="256" loading="lazy" decoding="async"></div>
    <div class="boss-body">
      <div class="boss-head">
        <div><span class="codex-id">${esc(boss.id)}</span><h3>${esc(boss.name)}</h3></div>
        <div class="tag-list" style="margin:0"><span class="boss-kind">${esc(boss.role)}</span>${badge("status", boss.status, jpStatus(boss.status))}</div>
      </div>
      <p class="boss-pattern"><b>攻撃PATTERN</b><span>${esc(boss.attackPattern)}</span></p>
      <dl class="codex-stats"><div><dt>HP</dt><dd>${esc(boss.hp)}</dd></div><div><dt>攻撃力</dt><dd>${esc(boss.damage)}</dd></div><div><dt>表示倍率</dt><dd>${esc(boss.visualScale)}</dd></div></dl>
      <div class="boss-flags">${bossFlags(boss)}</div>
      <p class="codex-desc">${esc(boss.notes)}</p>
      ${source.length ? `<div class="tag-list"><span class="tag tag-gold">転用元: ${esc(source.join(" / "))}</span><a class="tag" href="#classes">職業図鑑で見る</a></div>` : ""}
      ${moreBlock("詳細を見る", [["登場MAP", array(boss.maps).map(mapLabel).join(" / ") || "未配置"], ["Drop", boss.drop], ["進捗", `${pct(boss.progress)}%`]], boss.notes)}
    </div>
  </article>`;
}

function duoBossCard(boss) {
  const members = array(boss.members);
  const portraitOf = memberName => {
    const cls = array(state.data.classes.classes).find(item => item.bossEncounter === boss.id && item.name === memberName);
    return cls?.image ?? boss.image;
  };
  const front = members[0];
  const support = members[1];
  return `<article class="boss-feature duo-boss">
    <div class="duo-banner">
      <div class="boss-portrait">${crest("boss", true)}<img src="${esc(boss.image)}" alt="${esc(boss.name)}の対戦Sprite" width="256" height="256" loading="lazy" decoding="async"></div>
      <div class="boss-body">
        <div class="boss-head">
          <div><span class="codex-id">${esc(boss.id)}</span><h3>${esc(boss.name)}</h3></div>
          <div class="tag-list" style="margin:0"><span class="boss-kind">${esc(boss.role)}</span>${badge("status", boss.status, jpStatus(boss.status))}</div>
        </div>
        <p class="boss-pattern"><b>ペア戦の構図</b><span>${esc(boss.attackPattern)}</span></p>
        <dl class="codex-stats"><div><dt>HP</dt><dd>${esc(boss.hp)}</dd></div><div><dt>攻撃力</dt><dd>${esc(boss.damage)}</dd></div><div><dt>表示倍率</dt><dd>${esc(boss.visualScale)}</dd></div></dl>
        <div class="boss-flags">${bossFlags(boss)}</div>
      </div>
    </div>
    <div class="duo-pair">
      ${front ? duoMember(front, portraitOf(front.name), false) : ""}
      <div class="duo-link" aria-hidden="true"><span class="duo-arrow"><i>◀</i></span><small>強化・回復・聖域</small></div>
      ${support ? duoMember(support, portraitOf(support.name), true) : ""}
    </div>
    <div class="duo-verdict"><b>プレイヤーの判断</b><p>${esc(boss.notes)}</p></div>
  </article>`;
}

function duoMember(member, image, isSupport) {
  return `<div class="duo-member ${isSupport ? "support" : ""}">
    <figure><img src="${esc(image)}" alt="${esc(member.name)}のSprite" width="256" height="256" loading="lazy" decoding="async"></figure>
    <div class="duo-copy">
      <h4>${esc(member.name)}</h4>
      <span class="duo-role">${esc(member.role)}</span>
      <p>${esc(member.behavior)}</p>
    </div>
  </div>`;
}

function bossFlags(boss) {
  return [["登場演出", boss.intro], ["専用HP Bar", boss.hpBar], ["Treasure", boss.treasure]]
    .map(([label, on]) => `<span class="flag ${on ? "on" : "off"}">${on ? "✔" : "—"} ${esc(label)}</span>`).join("");
}

function bossCard(boss) {
  const maps = array(boss.maps).map(mapLabel);
  return `<article class="codex-card rank-${boss.stageUse === "final" ? "boss" : "midboss"}">
    <div class="codex-portrait">
      ${crest(boss.stageUse === "final" ? "boss" : "midboss")}
      <span class="portrait-rank">${esc(boss.role.split("/")[0].trim())}</span>
      <img src="${esc(boss.image)}" alt="${esc(boss.name)}のSprite" width="256" height="256" loading="lazy" decoding="async">
      <span class="portrait-maps">${maps.map(label => `<span class="tag">${esc(label)}</span>`).join("")}</span>
    </div>
    <div class="codex-body">
      <div class="codex-head"><div><span class="codex-id">${esc(boss.id)}</span><h3 class="codex-name">${esc(boss.name)}</h3></div>${badge("status", boss.status, jpStatus(boss.status))}</div>
      <div class="tag-list mobile-maps">${(maps.length ? maps : ["未配置"]).map(label => `<span class="tag">${esc(label)}</span>`).join("")}</div>
      <p class="codex-role"><b>役割</b><span>${esc(boss.role)}</span></p>
      <p class="boss-pattern"><b>固有攻撃</b><span>${esc(boss.attackPattern)}</span></p>
      <dl class="codex-stats"><div><dt>HP</dt><dd>${esc(boss.hp)}</dd></div><div><dt>攻撃力</dt><dd>${esc(boss.damage)}</dd></div><div><dt>表示倍率</dt><dd>${esc(boss.visualScale)}</dd></div></dl>
      <div class="boss-flags">${bossFlags(boss)}</div>
      <p class="codex-desc">${esc(boss.notes)}</p>
      ${moreBlock("詳細を見る", [["出典", boss.appearance], ["Drop", boss.drop], ["進捗", `${pct(boss.progress)}%`]], boss.notes)}
    </div>
  </article>`;
}

/* ============================================================
   マップ
   ============================================================ */

function renderMaps() {
  const maps = array(state.data.maps.maps);
  return `${intro("マップ", "3テーマの床だけが続く広い戦場。壁・柱・地形小物なし。約4分の大群戦の後に強敵由来のBossを倒し、約5分のステージを目指します。")}
    ${maps.map(mapSlab).join("")}
    <div style="margin-top:18px">${visualSection("現行の戦場と地形の履歴", "現在の床だけの戦場を先頭に表示。以前の部屋・壁・ランドマークは比較用の履歴です。", galleryByCategory("exploration"), "map-visuals")}</div>`;
}

function mapSlab(map) {
  const enemies = map.encounterEnemyIds ? array(state.data.enemies.enemies).filter(enemy => map.encounterEnemyIds.includes(enemy.id)) : enemiesOfMap(map.id);
  const bossUnits = array(map.boss).map(name => ({ name, boss: bossByName(name) }));
  return `<section class="map-slab slab ornate">
    <header class="map-head">
      <span class="map-numeral" aria-hidden="true"><i>${map.index}</i></span>
      <div><h3>${esc(map.name)}</h3><small>${esc(map.theme)}</small></div>
      <div class="map-progress">${badge("status", map.status, jpStatus(map.status))}${progressBar(map.progress, map.name)}<b>${pct(map.progress)}%</b></div>
    </header>
    ${map.image ? `<button class="map-preview" type="button" data-image-id="${esc(map.imageId || (map.id === "map2" ? "map2-amethyst-depths" : map.id === "map3" ? "map3-ruin-forge" : "map-exploration"))}" aria-label="${esc(map.name)}の実ゲーム画面を拡大"><img src="${esc(map.image)}" alt="${esc(map.name)}の実ゲーム画面" loading="lazy" decoding="async"><span>実ゲーム画面を拡大</span></button>` : ""}
    <div class="map-body">
      <dl class="map-facts">
        <div><dt>規模</dt><dd>${map.openField ? "壁なし・床が連続" : `${map.width}×${map.height}`}</dd></div>
        <div><dt>ボス解放</dt><dd>${esc(map.bossUnlock || `${map.bossKillRequirement}体`)}</dd></div>
        <div><dt>同時出現上限</dt><dd>PC ${map.enemyCap}体・スマホ ${map.mobileEnemyCap}体（時間による連続増援）</dd></div>
        <div><dt>${map.openField ? "終盤ボス候補" : "強敵"}</dt><dd>${esc(map.strongEnemy)}</dd></div>
        <div><dt>精鋭</dt><dd>${esc(map.elite)}</dd></div>
        <div><dt>中ボス</dt><dd>${esc(map.midBoss)}</dd></div>
        <div><dt>宝箱</dt><dd>${esc(map.treasure)}</dd></div>
        <div><dt>背景</dt><dd>${esc(map.background)}</dd></div>
        <div><dt>BGM</dt><dd>${esc(map.bgm)}</dd></div>
      </dl>
      <div class="map-roster">
        <div class="roster-block">
          <h4>${map.openField ? "終盤ボス候補" : "登場ボス"} <em>${bossUnits.length}${map.openField ? "体から1体" : "戦"}</em></h4>
          <div class="mini-roster">${bossUnits.map(unit => unit.boss
            ? `<span class="mini-unit is-boss"><figure><img src="${esc(unit.boss.image)}" alt="${esc(unit.name)}のSprite" loading="lazy" decoding="async"></figure><span class="mini-copy"><strong>${esc(unit.name)}</strong><small>${esc(unit.boss.role)}</small></span></span>`
            : `<span class="tag tag-blood">${esc(unit.name)}</span>`).join("")}</div>
        </div>
        <div class="roster-block">
          <h4>登場敵 <em>${enemies.length}体</em></h4>
          <div class="mini-roster">${enemies.map(enemy => `<span class="mini-unit rank-${esc(enemy.rank)}"><figure><img src="${esc(enemy.image)}" alt="${esc(enemy.name)}のSprite" loading="lazy" decoding="async"></figure><span class="mini-copy"><strong>${esc(enemy.name)}</strong><small>${esc(rankName(enemy.rank))}</small></span></span>`).join("")}</div>
        </div>
        <div class="roster-block">
          <h4>敵系統</h4>
          ${tagList(array(map.enemyFamily), "tag-gold")}
        </div>
        <p class="record-note">${esc(map.notes)}</p>
      </div>
    </div>
  </section>`;
}

/* ============================================================
   戦闘システム
   ============================================================ */

function renderCombat() {
  const systems = state.data.systems;
  const tasks = tasksOfCategories(["combat", "attribute", "fusion"]);
  return `${intro("戦闘システム", "状態異常、Fusionの再定義、UI・VFX・音の表現品質を、現行仕様と廃止履歴ごとに管理します。")}
    <section class="panel slab ornate" style="margin-bottom:18px">
      ${blockTitle("約5分のステージ", "壁のない大群戦から、強敵を使う最後のBoss戦へ。撃破して初めてステージをクリアします。", "05:00")}
      <p>${esc(systems.survival.finish)}</p><p>${esc(systems.survival.spawn)}</p><p>${esc(systems.survival.rewards)}</p>
    </section>
    ${visualSection("戦闘の実画面", "予兆から判定までを同期した現行の戦闘基準と、探索中のHUDです。", galleryByIds(["survival-growth-effects", "open-field-boss", "open-field-recovery"]), "combat-visuals")}
    ${visualSection("飛行する装備武器", "52武器に自動攻撃を接続。浮遊する武器は絵の長辺48px、5色の輪郭と揺らぐオーラでレア度を示します。薄い円が索敵範囲です。斬撃は剣本体の接触と同期し、弓・魔法は武器から発射します。", galleryByIds(["floating-weapon-aura", "equipment-attack-wanderer_iron_sword", "equipment-attack-rune_greatsword", "equipment-attack-star_sorcerer_staff"]), "auto-weapon-visuals")}
    <div class="panel-grid" style="margin-top:18px">
      <section class="panel slab ornate span-6">
        ${blockTitle("状態異常 / 旧属性", "旧属性レベルとElement Fusionは廃止済み。名称は状態異常・完成大技・演出テーマの文脈に限定します。", `${systems.attributes.length}項目`)}
        <div class="progress-list">${systems.attributes.map(item => progressRow(item.name, item.progress, item.lifecycle)).join("")}</div>
      </section>
      <section class="panel slab ornate span-6">
        ${blockTitle("Fusion関係", "旧レシピをどこへ再定義したかの対応表です。", `${systems.fusions.length}件`)}
        <div class="relation-grid">${systems.fusions.map(item => `<div class="relation"><span>${esc(item.sources.join(" ＋ "))}</span><span aria-hidden="true">→</span><span>${esc(item.result)}<small>${esc(item.state)}</small></span></div>`).join("")}</div>
      </section>
      <section class="panel slab ornate span-6">
        ${blockTitle("UI / VFX", "表現品質の到達度です。", "")}
        <div class="progress-list">${[...systems.ui, ...systems.vfx].map(item => progressRow(item.name, item.progress, item.group)).join("")}</div>
      </section>
      <section class="panel slab ornate span-6">
        ${blockTitle("Audio", "SEとBGM遷移の到達度です。", "")}
        <div class="progress-list">${systems.audio.map(item => progressRow(item.name, item.progress, item.group)).join("")}</div>
      </section>
      <section class="panel slab ornate span-12">
        ${blockTitle("戦闘まわりのタスク", "Combat・状態異常・Fusionのカテゴリから抽出しています。", `${tasks.length}件`)}
        <div class="cards-grid">${tasks.map(taskCard).join("")}</div>
      </section>
    </div>`;
}

/* ============================================================
   天賦・成長
   ============================================================ */

function renderTalents() {
  const skills = array(state.data.systems.skills);
  const byState = {};
  skills.forEach(skill => { (byState[skill.state] = byState[skill.state] || []).push(skill); });
  const tasks = tasksOfCategories(["skill", "attribute"]);
  const holds = array(state.data.relations.board).filter(item => item.decision === "hold");

  return `${intro("天賦・レベルアップ", "大きな本を開き、左ページで天賦を選び、右ページで職業・流派・熟練段階と効果・習得条件を確認します。取得はレベルアップ三択で行います。")}
    ${visualSection("見た目で選ぶレベルアップ", state.data.systems.survival.upgradeSelection, galleryByIds(["survival-growth-choices", "survival-growth-effects", "survival-growth-shots"]), "growth-visuals")}
    <section class="panel slab ornate" style="margin-top:18px">${blockTitle("5分の成長", state.data.systems.survival.growth, "8系統")}
      <div class="panel-grid">${array(state.data.systems.survival.upgrades).map(item => `<article class="panel slab span-4"><img src="${esc(item.image)}" alt="${esc(item.name)}のアイコン" width="64" height="64" style="image-rendering:pixelated"><h3>${esc(item.name)}</h3><p>${esc(item.description)}</p><small>${item.maxRank ? `最大Lv.${item.maxRank}` : "繰り返し取得可能"}</small></article>`).join("")}</div>
    </section>
    ${visualSection("天賦図とレベルアップ", "背表紙を固定して表紙が右から左へ開き、3枚の紙がめくれます。最後の紙には天賦図が描かれ、その下から刻印の記録が現れます。文字の後出しフェードはなく、開いた2ページをそのまま操作できます。他職の分岐は準備中です。", galleryByIds(["ember-book-opening", "talent-top"]), "talent-visuals")}
    <section class="panel slab ornate" style="margin-top:18px">
      ${blockTitle("完成大技", "通常MAPの宝箱からは取得しません。旧23種はデータ保存のみで、再導入は未決定です。", `${skills.length}件`)}
      <div class="table-wrap">
        <table class="data-table">
          <thead><tr><th>Skill</th><th>状態</th><th>発動条件</th><th>Cooldown</th><th>Synergy</th><th>VFX</th><th>進捗</th></tr></thead>
          <tbody>${skills.map(skill => `<tr>
            <td><strong>${esc(skill.name)}</strong><small>${esc(skill.id)}</small></td>
            <td><span class="state-pip pip-${esc(skill.state)}">${esc(skill.state)}</span></td>
            <td>${esc(skill.trigger)}</td><td>${esc(skill.cooldown)}</td><td>${esc(skill.synergy)}</td><td>${esc(skill.vfx)}</td>
            <td style="min-width:110px">${progressBar(skill.progress, skill.name)}<small>${pct(skill.progress)}%</small></td>
          </tr>`).join("")}</tbody>
        </table>
      </div>
    </section>
    <div class="panel-grid" style="margin-top:18px">
      <section class="panel slab ornate span-6">
        ${blockTitle("状態別の内訳", "どの状態にどれだけ大技が寄っているかを見ます。", "")}
        <div class="progress-list">${Object.entries(byState).map(([stateId, list]) => `<div class="progress-row"><div class="progress-label"><strong><span class="state-pip pip-${esc(stateId)}">${esc(stateId)}</span></strong><small>${list.length}件</small></div>${progressBar(list.reduce((sum, item) => sum + pct(item.progress), 0) / list.length, stateId, "gold")}<div class="progress-value">${list.length}</div></div>`).join("")}</div>
      </section>
      <section class="panel slab ornate span-6">
        ${blockTitle("確定前の検討事項", "天賦図の全職展開はこれらの判断待ちです。", `${holds.length}件`)}
        <div class="sort-column decision-hold"><div>${holds.map(item => `<article class="sort-card"><h4>${esc(item.name)}</h4><p>${esc(item.reason)}</p>${tagList(array(item.affects))}</article>`).join("") || `<p class="sort-empty">保留中の項目はありません</p>`}</div></div>
      </section>
      <section class="panel slab ornate span-12">
        ${blockTitle("天賦・大技まわりのタスク", "Skill・状態異常カテゴリから抽出しています。", `${tasks.length}件`)}
        <div class="cards-grid">${tasks.map(taskCard).join("")}</div>
      </section>
    </div>`;
}

/* ============================================================
   アイテム・報酬
   ============================================================ */

function renderItems() {
  const equipment = state.data.systems.equipment;
  const tasks = tasksOfCategories(["equipment"]);
  const bosses = array(state.data.bosses.bosses).filter(boss => boss.drop && boss.drop !== "設計中");
  const dropGroups = {};
  array(state.data.enemies.enemies).forEach(enemy => {
    (dropGroups[enemy.drop] = dropGroups[enemy.drop] || []).push(enemy);
  });

  return `${intro("アイテム・報酬", "装備、希少度、合成、そしてドロップと宝箱。Run中の成長軸として扱う取得物を一か所にまとめます。")}
    ${visualSection("ビジュアル刷新：200装備と細いUI", "64pxの透過アイコン、1pxのレア度輪郭、半透明の比較カード。実ゲームで装着と連続鍛造を確認しました。", galleryByIds(["floating-weapon-aura", "equipment-readable", "ember-v5-hover", "forge-readable"]), "ember-items-visuals")}
    ${visualSection("武器ごとの攻撃比較", "大剣・細剣・弓・斧で、動きも待ち時間も変わります。実ゲームの比較と、特色を表示する装備詳細です。ここに載せた攻撃比較動画のUIは刷新前です。", galleryByIds(["weapon-traits-comparison", "weapon-traits-inventory"]), "weapon-traits-visuals")}
    <section class="panel slab ornate" style="margin-top:18px">
      ${blockTitle("武器の特色", "同じ攻撃力でも一撃と間隔が異なります。基準間隔は攻撃速度の強化で短縮。レア度は色・残光・火花へ反映します。", "9系統 / 52武器")}
      <div class="table-wrap"><table class="data-table"><thead><tr><th>武器</th><th>特色</th><th>基準間隔</th><th>一撃倍率</th></tr></thead>
      <tbody>${array(equipment.weaponProfiles).map(profile => `<tr><td><strong>${esc(profile.name)}</strong></td><td>${esc(profile.trait)}</td><td>${profile.interval.toFixed(2)}秒</td><td>×${profile.power.toFixed(2)}</td></tr>`).join("")}</tbody></table></div>
    </section>
    ${visualSection("ComfyUIで生成した新武器24種", "色違いだけでなく、刃・穂先・武器全体の形を変えた素材です。画像を押すと拡大できます。レア度は候補で、ゲームへの追加は次の実装段階です。", galleryByIds(["weapon-variety-12a", "weapon-variety-12b"]), "weapon-variety-visuals")}
    ${visualSection("浮遊武器の自動攻撃", "剣本体が範囲内の敵へ飛んで斬り、戻ります。ComfyUI生成の斬撃と、種類・レア度別の動きを実ゲームの動画で確認できます。", galleryByIds(["equipment-attack-moonblue_dagger", "equipment-attack-wanderer_iron_sword", "equipment-attack-rune_greatsword", "equipment-attack-fallen_dynasty_02", "equipment-attack-sunfire_battle_axe", "equipment-attack-royal_guard_04", "equipment-attack-abyss_watch_03", "equipment-attack-traveler_shortbow", "equipment-attack-star_sorcerer_staff"]), "equipment-attack-visuals")}
    ${visualSection("装備とショップの実画面", "6部位、50枠、比較、保護、お気に入り、鍛造まで。色の意味を全報酬画面で統一する基準です。", galleryByIds(["equipment-readable", "forge-readable", "shop", "shop-purchased", "result"]), "item-visuals")}
    <section class="panel slab ornate equipment-catalog">
      ${blockTitle("装備図鑑 · 200種類", "8系統の出自で分類。能力は候補であり、入手時にレア度に応じた数と値が抽選されます。セット効果はありません。", "200種を64pxへ刷新")}
      ${[...new Set(array(equipment.catalog).map(item => item.collection))].map((collection, index) => `<details class="equipment-collection" ${index === 0 ? "open" : ""}><summary>${esc(collection)} <span>25種</span></summary><div class="equipment-catalog-grid">${array(equipment.catalog).filter(item => item.collection === collection).map(item => `<article class="equipment-catalog-card" style="--item-color:${({uncommon:'#6bb88c',rare:'#67a1d3',epic:'#ac82ca',legendary:'#d5a35f',mythic:'#d16c70'})[item.rarity]}"><img loading="lazy" src="${esc(item.image)}" alt="${esc(item.display_name)}" width="64" height="64"><h4>${esc(item.display_name)}</h4><p>${({weapon:'武器',head:'頭',body:'胴',arms:'腕',legs:'脚',accessory:'アクセサリー'})[item.slot]} · ${({uncommon:'アンコモン',rare:'レア',epic:'エピック',legendary:'レジェンダリー',mythic:'ミシック'})[item.rarity]}</p><small>能力候補：${item.stats.map(stat => ({attack_power:'攻撃力',defense:'防御力',max_hp:'最大HP',move_speed:'移動速度',attack_speed:'攻撃速度',crit_rate:'会心率',crit_damage:'会心ダメージ'})[stat] || stat).join('・')}</small></article>`).join('')}</div></details>`).join('')}
    </section>
    <div class="panel-grid" style="margin-top:18px">
      <section class="panel slab ornate span-6">
        ${blockTitle("Equipment", "地面Dropから合成までの実装到達度です。", `${equipment.catalogCount} templates`)}
        <div class="progress-list">${equipment.features.map(feature => progressRow(feature.name, feature.progress, feature.notes)).join("")}</div>
        <hr class="rule">
        <div class="block-title" style="border:0;padding:0;margin:0 0 8px"><div><h3>希少度</h3></div></div>
        ${tagList(equipment.rarities, "tag-gold")}
      </section>
      <section class="panel slab ornate span-6">
        ${blockTitle("MAPごとの宝箱", "各MAPで取得できる宝箱構成です。", `${array(state.data.maps.maps).length}MAP`)}
        <ul class="link-list">${array(state.data.maps.maps).map(map => `<li class="link-row"><b>${esc(map.name)}</b><span class="link-arrow" aria-hidden="true">→</span><div class="tag-list">${String(map.treasure).split("・").filter(Boolean).map(part => `<span class="tag">${esc(part)}</span>`).join("")}</div></li>`).join("")}</ul>
      </section>
      <section class="panel slab ornate span-6">
        ${blockTitle("通常敵のDrop", "同じDrop内容ごとにまとめています。", `${Object.keys(dropGroups).length}種`)}
        <ul class="link-list">${Object.entries(dropGroups).map(([drop, list]) => `<li class="link-row"><b>${esc(drop)}</b><span class="link-arrow" aria-hidden="true">←</span><div class="tag-list">${list.slice(0, 8).map(enemy => `<span class="tag">${esc(enemy.name)}</span>`).join("")}${list.length > 8 ? `<span class="tag tag-muted">ほか${list.length - 8}体</span>` : ""}</div></li>`).join("")}</ul>
      </section>
      <section class="panel slab ornate span-6">
        ${blockTitle("ボスのDrop", "決戦の報酬です。設計中のボスは除いています。", `${bosses.length}戦`)}
        <ul class="link-list">${bosses.map(boss => `<li class="link-row" style="--accent:var(--rank-midboss)"><b>${esc(boss.name)}</b><span class="link-arrow" aria-hidden="true">→</span><div class="tag-list"><span class="tag tag-gold">${esc(boss.drop)}</span>${boss.treasure ? `<span class="tag">Treasure有</span>` : ""}</div></li>`).join("")}</ul>
      </section>
      <section class="panel slab ornate span-12">
        ${blockTitle("装備・報酬まわりのタスク", "Equipmentカテゴリから抽出しています。", `${tasks.length}件`)}
        <div class="cards-grid">${tasks.map(taskCard).join("")}</div>
      </section>
    </div>`;
}

/* ============================================================
   相関図
   ============================================================ */

function renderRelations() {
  const relations = state.data.relations;
  const diagrams = array(relations.diagrams);
  const current = diagrams.find(item => item.id === state.diagram) ?? diagrams[0];
  return `${intro("相関図", "職業、マップ、敵、ボス、開発項目のつながりを追います。節を押すと、つながっている要素だけが強調されます。")}
    <section class="panel slab ornate" style="margin-bottom:18px">
      ${blockTitle("判断区分", "図の色は、その項目を残すか作り直すかの判断を示します。", "4区分")}
      <div class="decision-legend">${Object.entries(relations.decisionLabels).map(([key]) => `<article class="legend-card decision-${key}">${decisionBadge(key)}<p>${esc(relations.decisionDescriptions[key])}</p></article>`).join("")}</div>
    </section>

    <div class="diagram-tabs" role="tablist">${diagrams.map((diagram, index) => `<button class="diagram-tab ${diagram === current ? "active" : ""}" type="button" data-diagram="${esc(diagram.id)}" role="tab" aria-selected="${diagram === current}"><span class="tab-index">${String(index + 1).padStart(2, "0")}</span>${esc(diagram.title)}</button>`).join("")}</div>

    ${current ? relationDiagram(current) : ""}

    <section class="panel slab ornate" style="margin-top:18px">
      ${blockTitle("データから見る相関", "記録庫のデータから自動で組み立てた対応です。図では追いにくい量の関係をここで確認します。", "4系統")}
      <div class="matrix-grid">
        <div>
          <div class="block-title" style="border:0;padding:0"><div><h3>職業 × 武器・能動Skill</h3></div></div>
          <ul class="link-list">${array(state.data.classes.classes).map(item => `<li class="link-row" style="--accent:${item.disposition === "boss" ? "var(--blood)" : "var(--seal-dim)"}"><b>${esc(item.name)}</b><span class="link-arrow" aria-hidden="true">→</span><div class="tag-list"><span class="tag">${esc(item.attack)}</span><span class="tag tag-gold">${esc(item.activeSkill)}</span>${item.disposition === "boss" ? `<span class="tag tag-blood">ボス転用</span>` : ""}</div></li>`).join("")}</ul>
        </div>
        <div>
          <div class="block-title" style="border:0;padding:0"><div><h3>マップ × 登場敵</h3></div></div>
          <ul class="link-list">${array(state.data.maps.maps).map(map => `<li class="link-row"><b>${esc(map.name)}</b><span class="link-arrow" aria-hidden="true">→</span><div class="tag-list">${enemiesOfMap(map.id).map(enemy => `<span class="tag">${esc(enemy.name)}</span>`).join("")}</div></li>`).join("")}</ul>
        </div>
        <div>
          <div class="block-title" style="border:0;padding:0"><div><h3>敵階級 × 能力・報酬</h3></div></div>
          <ul class="link-list">${array(state.data.enemies.hierarchy).map(item => {
            const list = array(state.data.enemies.enemies).filter(enemy => enemy.rank === item.id);
            const drops = [...new Set(list.map(enemy => enemy.drop))];
            return `<li class="link-row rank-${esc(item.id)}" style="--accent:var(--rank-${esc(item.id)})"><b>${esc(item.name)}</b><span class="link-arrow" aria-hidden="true">→</span><div class="tag-list"><span class="tag">HP ${esc(item.hp)}</span><span class="tag">${esc(item.attack)}</span>${drops.map(drop => `<span class="tag tag-gold">${esc(drop)}</span>`).join("")}</div></li>`;
          }).join("")}</ul>
        </div>
        <div>
          <div class="block-title" style="border:0;padding:0"><div><h3>ボス × マップ・報酬</h3></div></div>
          <ul class="link-list">${array(state.data.bosses.bosses).map(boss => `<li class="link-row" style="--accent:${boss.sourceClass ? "var(--blood)" : "var(--rank-midboss)"}"><b>${esc(boss.name)}</b><span class="link-arrow" aria-hidden="true">→</span><div class="tag-list">${(array(boss.maps).map(mapLabel).length ? array(boss.maps).map(mapLabel) : ["未配置"]).map(label => `<span class="tag">${esc(label)}</span>`).join("")}<span class="tag tag-gold">${esc(boss.drop)}</span></div></li>`).join("")}</ul>
        </div>
      </div>
    </section>`;
}

function relationDiagram(diagram) {
  const edgeLedger = diagram.edges.map(edge => {
    const from = diagram.nodes.find(node => node.id === edge.from)?.title ?? edge.from;
    const to = diagram.nodes.find(node => node.id === edge.to)?.title ?? edge.to;
    return `<li><span>${esc(from)}</span><b aria-hidden="true">→</b><span>${esc(to)}</span><small>${esc(edge.label)}</small></li>`;
  }).join("");
  return `<section class="panel slab ornate relation-panel">
    ${blockTitle(diagram.title, diagram.description, `${diagram.nodes.length}項目 / ${diagram.edges.length}関係`)}
    <div class="graph-toolbar">
      <span class="hint">節を押すと関係する要素だけが強調されます。もう一度押すと解除します。</span>
      <button class="zoom-button" type="button" data-zoom="out" aria-label="相関図を縮小">−</button>
      <button class="zoom-button text" type="button" data-zoom="reset">等倍</button>
      <button class="zoom-button" type="button" data-zoom="in" aria-label="相関図を拡大">＋</button>
      ${state.focusNode ? `<button class="zoom-button text" type="button" data-zoom="clear">強調を解除</button>` : ""}
    </div>
    <div class="graph-viewport" id="graphViewport">
      <div class="graph-sizer">
      <div class="graph-stage" data-graph="${esc(diagram.id)}" style="--zoom:${state.graphZoom}">
        <svg class="graph-lines" aria-hidden="true"><defs><marker id="arrow-${esc(diagram.id)}" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 Z"></path></marker></defs><g></g></svg>
        <div class="graph-grid" style="--graph-columns:${diagram.columns}">${diagram.nodes.map(node => `<button class="relation-node decision-${esc(node.decision)}" type="button" data-node="${esc(node.id)}" style="--node-col:${node.col};--node-row:${node.row}">${decisionBadge(node.decision)}<h4>${esc(node.title)}</h4><p>${esc(node.detail)}</p></button>`).join("")}</div>
      </div>
      </div>
    </div>
    <details class="edge-details"><summary>矢印の意味を一覧で確認</summary><ul class="edge-ledger">${edgeLedger}</ul></details>
  </section>`;
}

let graphObserver = null;

/* 相関図はrAFに依存せず、レイアウト確定のたびに引き直す */
function refreshGraph() {
  drawGraphEdges();
  highlightGraph();
}

function observeGraph() {
  if (graphObserver) { graphObserver.disconnect(); graphObserver = null; }
  const viewport = $(".graph-viewport");
  if (!viewport || typeof ResizeObserver !== "function") return;
  let lastWidth = viewport.clientWidth;
  graphObserver = new ResizeObserver(() => {
    if (viewport.clientWidth === lastWidth) return;
    lastWidth = viewport.clientWidth;
    refreshGraph();
  });
  graphObserver.observe(viewport);
  refreshGraph();
}

function currentDiagram() {
  const diagrams = array(state.data.relations?.diagrams);
  return diagrams.find(item => item.id === state.diagram) ?? diagrams[0];
}

/* 拡大率に合わせて舞台の実寸とスクロール範囲を合わせる */
function layoutGraphStage(stage) {
  const viewport = stage.closest(".graph-viewport");
  const sizer = stage.parentElement;
  if (!viewport || !sizer || !sizer.classList.contains("graph-sizer")) return;
  const zoom = state.graphZoom || 1;
  const available = viewport.clientWidth;
  if (!available) return;
  const minWidth = window.innerWidth < 768 ? 700 : 0;
  const layoutWidth = Math.max(minWidth, zoom >= 1 ? available : available / zoom);
  stage.style.setProperty("--zoom", zoom);
  stage.style.width = `${layoutWidth}px`;
  sizer.style.width = `${layoutWidth * zoom}px`;
  sizer.style.height = `${stage.offsetHeight * zoom}px`;
}

function drawGraphEdges() {
  $$("[data-graph]").forEach(stage => {
    const diagram = array(state.data.relations?.diagrams).find(item => item.id === stage.dataset.graph);
    layoutGraphStage(stage);
    const grid = $(".graph-grid", stage);
    const svg = $(".graph-lines", stage);
    const group = $("g", svg);
    if (!diagram || !grid || !svg || !group) return;
    const zoom = state.graphZoom || 1;
    const gridRect = grid.getBoundingClientRect();
    if (!gridRect.width || !gridRect.height) return;
    const width = gridRect.width / zoom;
    const height = gridRect.height / zoom;
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
    svg.setAttribute("width", width);
    svg.setAttribute("height", height);
    group.innerHTML = diagram.edges.map(edge => {
      const from = $(`[data-node="${edge.from}"]`, grid);
      const to = $(`[data-node="${edge.to}"]`, grid);
      if (!from || !to) return "";
      const a = from.getBoundingClientRect();
      const b = to.getBoundingClientRect();
      const aw = a.width / zoom, ah = a.height / zoom, bw = b.width / zoom, bh = b.height / zoom;
      const ax = (a.left - gridRect.left) / zoom + aw / 2;
      const ay = (a.top - gridRect.top) / zoom + ah / 2;
      const bx = (b.left - gridRect.left) / zoom + bw / 2;
      const by = (b.top - gridRect.top) / zoom + bh / 2;
      const horizontal = Math.abs(bx - ax) >= Math.abs(by - ay);
      let sx, sy, tx, ty, d;
      if (horizontal) {
        const direction = bx >= ax ? 1 : -1;
        sx = ax + direction * aw / 2; sy = ay;
        tx = bx - direction * (bw / 2 + 8); ty = by;
        const bend = Math.max(28, Math.abs(tx - sx) * .38);
        d = `M ${sx} ${sy} C ${sx + direction * bend} ${sy}, ${tx - direction * bend} ${ty}, ${tx} ${ty}`;
      } else {
        const direction = by >= ay ? 1 : -1;
        sx = ax; sy = ay + direction * ah / 2;
        tx = bx; ty = by - direction * (bh / 2 + 8);
        const bend = Math.max(28, Math.abs(ty - sy) * .38);
        d = `M ${sx} ${sy} C ${sx} ${sy + direction * bend}, ${tx} ${ty - direction * bend}, ${tx} ${ty}`;
      }
      return `<path d="${d}" data-from="${esc(edge.from)}" data-to="${esc(edge.to)}" marker-end="url(#arrow-${esc(diagram.id)})"><title>${esc(edge.label)}</title></path>`;
    }).join("");

    const sizer = stage.parentElement;
    if (sizer && sizer.classList.contains("graph-sizer")) sizer.style.height = `${stage.offsetHeight * zoom}px`;
  });
}

function highlightGraph() {
  const nodes = $$(".relation-node");
  const paths = $$(".graph-lines path[data-from]");
  nodes.forEach(node => node.classList.remove("lit", "dim", "focus"));
  paths.forEach(path => path.classList.remove("lit", "dim"));
  const focus = state.focusNode;
  if (!focus) return;
  const diagram = currentDiagram();
  if (!diagram) return;
  const related = new Set([focus]);
  diagram.edges.forEach(edge => {
    if (edge.from === focus) related.add(edge.to);
    if (edge.to === focus) related.add(edge.from);
  });
  nodes.forEach(node => {
    const id = node.dataset.node;
    if (id === focus) node.classList.add("focus");
    else if (related.has(id)) node.classList.add("lit");
    else node.classList.add("dim");
  });
  paths.forEach(path => {
    if (path.dataset.from === focus || path.dataset.to === focus) path.classList.add("lit");
    else path.classList.add("dim");
  });
}

/* ============================================================
   開発フェーズ
   ============================================================ */

function renderRoadmap() {
  const tasks = filterTasks();
  const lanes = ["now", "next", "future"];
  const categories = array(state.data.roadmap.categories);
  return `${intro("開発フェーズ", "現在・次・将来の3レーンで実装順を管理します。進捗率はデータから計算され、完了はテスト済みだけに限定します。")}
    <section class="panel slab ornate" style="margin-bottom:18px">
      ${blockTitle("カテゴリ進捗", "重要度で重み付けした全体進捗の内訳です。", `${categories.length}カテゴリ`)}
      <div class="progress-list">${categories.map(category => progressRow(category.name, categoryProgress(category), `重要度 ${category.weight} · ${array(category.tasks).length}タスク`)).join("")}</div>
    </section>
    <div class="filter-bar slab" style="margin-bottom:18px">
      ${filterInput("taskQuery", "タスクを検索", "名称・メモ")}
      ${filterSelect("taskStatus", "状態", state.data.project.statusLabels)}
      ${filterSelect("taskPriority", "優先度", state.data.project.priorityLabels)}
      ${filterSelect("taskCategory", "カテゴリ", Object.fromEntries(categories.map(category => [category.id, category.name])))}
    </div>
    <section class="roadmap-lanes">${lanes.map(lane => {
      const list = tasks.filter(task => task.lane === lane).sort((a, b) => (a.impactOrder ?? 99) - (b.impactOrder ?? 99));
      return `<div class="slab lane ${lane}">
        <header><h3>${esc(state.data.roadmap.laneLabels[lane])}</h3><span class="block-count">${list.length}件</span></header>
        <div class="lane-body">${list.map(taskCard).join("") || `<p class="empty-state" style="min-height:120px">該当なし</p>`}</div>
      </div>`;
    }).join("")}</section>`;
}

function filterTasks() {
  const query = (state.filters.taskQuery || "").toLowerCase();
  return allTasks().filter(task =>
    (!query || `${task.name} ${task.notes} ${task.categoryName}`.toLowerCase().includes(query)) &&
    (!state.filters.taskStatus || task.status === state.filters.taskStatus) &&
    (!state.filters.taskPriority || task.priority === state.filters.taskPriority) &&
    (!state.filters.taskCategory || task.categoryId === state.filters.taskCategory));
}

function taskCard(task) {
  return `<article class="record-card slab">
    <div class="record-head"><div><small>${esc(task.categoryName)}</small><h3>${esc(task.name)}</h3></div>${badge("priority", task.priority, jpPriority(task.priority))}</div>
    <div class="tag-list" style="margin-top:0">${badge("status", task.status, jpStatus(task.status))}</div>
    ${progressRow("進捗", task.progress)}
    ${task.notes ? `<p class="record-note">${esc(task.notes)}</p>` : ""}
  </article>`;
}

/* ============================================================
   検討事項
   ============================================================ */

function renderDecisions() {
  const relations = state.data.relations;
  const decision = state.filters.relationDecision || "";
  const category = state.filters.galleryCategory || "";
  const board = array(relations.board).filter(item => !decision || item.decision === decision);
  const open = array(relations.board).filter(item => ["hold", "redesign"].includes(item.decision));
  const galleryItems = array(state.data.gallery.items).filter(item => (!decision || item.decision === decision) && (!category || item.category === category));
  return `${intro("検討事項と決定記録", "先に判断しないと手戻りが大きい項目と、すでに確定した決定の理由・影響をまとめます。")}
    <section class="metrics-grid" style="margin-bottom:18px">
      <article class="metric-card slab"><div class="metric-label">要検討</div><div class="metric-value">${open.length}件</div><div class="metric-detail">保留・再設計</div></article>
      <article class="metric-card slab"><div class="metric-label">保留</div><div class="metric-value">${array(relations.board).filter(item => item.decision === "hold").length}件</div><div class="metric-detail">別判断の待ち</div></article>
      <article class="metric-card slab"><div class="metric-label">維持</div><div class="metric-value">${array(relations.board).filter(item => item.decision === "keep").length}件</div><div class="metric-detail">現行の強み</div></article>
      <article class="metric-card slab"><div class="metric-label">決定記録</div><div class="metric-value">${array(state.data.decisions.decisions).length}件</div><div class="metric-detail">理由と影響つき</div></article>
    </section>

    <section class="panel slab ornate" style="margin-bottom:18px">
      ${blockTitle("判断区分", "この4区分で、残すもの・作り直すもの・やめるものを仕分けます。", "4区分")}
      <div class="decision-legend">${Object.entries(relations.decisionLabels).map(([key]) => `<article class="legend-card decision-${key}">${decisionBadge(key)}<p>${esc(relations.decisionDescriptions[key])}</p></article>`).join("")}</div>
    </section>

    <section class="panel slab ornate" style="margin-bottom:18px">
      ${blockTitle("要不要の仕分けボード", "判断区分で絞り込み、影響範囲まで確認します。", `${board.length} / ${relations.board.length}`)}
      <div class="filter-bar slab" style="margin-bottom:14px;max-width:360px">${filterSelect("relationDecision", "判断", relations.decisionLabels)}</div>
      <div class="sort-board">${Object.keys(relations.decisionLabels).map(key => sortColumn(key, board.filter(item => item.decision === key))).join("")}</div>
    </section>

    <section class="panel slab ornate" style="margin-bottom:18px">
      ${blockTitle("実画面ライブラリ", "画面分類と判断で絞り込み、実画面から判断します。画像を押すと拡大できます。", `${galleryItems.length} / ${array(state.data.gallery.items).length}枚`)}
      <div class="filter-bar slab" style="margin-bottom:14px">${filterSelect("galleryCategory", "画面分類", state.data.gallery.categoryLabels)}${filterSelect("relationDecision", "判断", relations.decisionLabels)}</div>
      ${visualGallery(galleryItems, "decision-gallery")}
    </section>

    <section class="panel slab ornate">
      ${blockTitle("決定記録", "何を決めたかだけでなく、理由と影響を残します。", `${array(state.data.decisions.decisions).length}件`)}
      ${decisionTimeline(state.data.decisions.decisions)}
    </section>`;
}

function sortColumn(decision, items) {
  return `<section class="sort-column decision-${esc(decision)}">
    <header>${decisionBadge(decision)}<strong>${items.length}</strong></header>
    <div>${items.map(item => `<article class="sort-card"><h4>${esc(item.name)}</h4><p>${esc(item.reason)}</p>${tagList(array(item.affects))}</article>`).join("") || `<p class="sort-empty">該当なし</p>`}</div>
  </section>`;
}

function decisionTimeline(decisions) {
  return `<div>${array(decisions).map(item => `<article class="decision-line">
    <time class="decision-date">${esc(item.date)}</time>
    <h3>${esc(item.title)}</h3>
    <div class="decision-body">
      <div><b>決定</b><p>${esc(item.decision)}</p></div>
      <div><b>理由</b><p>${esc(item.reason)}</p></div>
      <div><b>影響</b><p>${esc(item.impact)}</p></div>
    </div>
  </article>`).join("")}</div>`;
}

/* ============================================================
   品質・性能
   ============================================================ */

function renderBugs() {
  const bugs = filterBugs();
  const performance = array(state.data.systems.performance);
  return `${intro("品質・性能", "重大度、発生条件、原因、修正・検証状況と、計測済みの性能課題を追跡します。")}
    <div class="filter-bar slab" style="margin-bottom:18px">
      ${filterInput("bugQuery", "バグを検索", "名称・原因・関連System")}
      ${filterSelect("bugSeverity", "重大度", { critical: "Critical", high: "High", medium: "Medium", low: "Low" })}
      ${filterSelect("bugStatus", "状態", state.data.bugs.statusLabels)}
    </div>
    <div class="cards-grid">${bugs.map(bug => `<article class="record-card slab">
      <div class="record-head"><div><small>${esc(bug.id)}</small><h3>${esc(bug.name)}</h3></div>${badge("severity", bug.severity, bug.severity.toUpperCase())}</div>
      <div class="tag-list" style="margin-top:0">${badge("status", bug.status, state.data.bugs.statusLabels[bug.status])}<span class="tag">${esc(bug.relatedSystem)}</span></div>
      <dl class="record-meta"><div><dt>発生条件</dt><dd>${esc(bug.trigger)}</dd></div><div><dt>原因</dt><dd>${esc(bug.cause)}</dd></div></dl>
      <p class="record-note"><strong>対応:</strong> ${esc(bug.fix)}<br><strong>次の確認:</strong> ${esc(bug.nextCheck)}</p>
    </article>`).join("")}</div>
    ${!bugs.length ? empty("該当するバグはありません") : ""}
    <section class="panel slab ornate" style="margin-top:18px">
      ${blockTitle("Performance", "計測値と残課題です。", `${performance.length}項目`)}
      <div class="cards-grid">${performance.map(item => `<article class="record-card slab">
        <div class="record-head"><div><small>${esc(item.metric)}</small><h3>${esc(item.name)}</h3></div>${badge("status", item.status, jpStatus(item.status))}</div>
        <dl class="record-meta"><div><dt>現在値</dt><dd>${esc(item.current)}</dd></div><div><dt>目標</dt><dd>${esc(item.target)}</dd></div><div><dt>関連</dt><dd>${esc(item.related)}</dd></div><div><dt>進捗</dt><dd>${pct(item.progress)}%</dd></div></dl>
        <p class="record-note">${esc(item.notes)}</p>
      </article>`).join("")}</div>
    </section>`;
}

function filterBugs() {
  const query = (state.filters.bugQuery || "").toLowerCase();
  return array(state.data.bugs.bugs).filter(bug =>
    (!query || Object.values(bug).join(" ").toLowerCase().includes(query)) &&
    (!state.filters.bugSeverity || bug.severity === state.filters.bugSeverity) &&
    (!state.filters.bugStatus || bug.status === state.filters.bugStatus));
}

function bugList(bugs) {
  if (!bugs.length) return `<p class="empty-state" style="min-height:150px">未解決バグはありません</p>`;
  return `<ul class="compact-list">${bugs.map(bug => `<li class="task-item"><span>${badge("severity", bug.severity, bug.severity.toUpperCase())}</span><span class="task-copy"><strong>${esc(bug.name)}</strong><small>${esc(bug.relatedSystem)}</small></span>${badge("status", bug.status, state.data.bugs.statusLabels[bug.status])}</li>`).join("")}</ul>`;
}

/* ============================================================
   検索
   ============================================================ */

function renderSearch() {
  const query = (state.filters.global || "").toLowerCase();
  const results = [];
  allTasks().forEach(item => pushSearch(results, query, "タスク", item.name, `${item.categoryName} / ${jpStatus(item.status)}`, "roadmap"));
  array(state.data.classes.classes).forEach(item => pushSearch(results, query, "職業", item.name, `${item.disposition === "player" ? "正式Player" : "ボス転用"} / ${item.attack}`, "classes", item.notes));
  array(state.data.enemies.enemies).forEach(item => pushSearch(results, query, "敵", item.name, `${rankName(item.rank)} / ${array(item.maps).map(mapLabel).join("・")}`, "enemies", item.notes));
  array(state.data.bosses.bosses).forEach(item => pushSearch(results, query, "ボス", item.name, `${item.role} / ${item.attackPattern}`, "bosses", item.notes));
  array(state.data.maps.maps).forEach(item => pushSearch(results, query, "MAP", item.name, `${item.theme} / ${item.strongEnemy}`, "maps", item.notes));
  array(state.data.bugs.bugs).forEach(item => pushSearch(results, query, "バグ", item.name, `${item.severity} / ${state.data.bugs.statusLabels[item.status]}`, "bugs", Object.values(item).join(" ")));
  array(state.data.systems.survival?.upgrades).forEach(item => pushSearch(results, query, "レベルアップ強化", item.name, item.description, "talents", Object.values(item).join(" ")));
  array(state.data.systems.skills).forEach(item => pushSearch(results, query, "完成大技", item.name, `${item.state} / ${item.trigger}`, "talents", Object.values(item).join(" ")));
  array(state.data.systems.attributes).forEach(item => pushSearch(results, query, "状態異常", item.name, item.lifecycle, "combat"));
  array(state.data.decisions.decisions).forEach(item => pushSearch(results, query, "決定", item.title, item.decision, "decisions", Object.values(item).join(" ")));
  array(state.data.relations.board).forEach(item => pushSearch(results, query, "仕分け", item.name, `${state.data.relations.decisionLabels[item.decision]} / ${item.reason}`, "decisions", array(item.affects).join(" ")));
  array(state.data.gallery.items).forEach(item => pushSearch(results, query, "実画面", item.title, item.caption, "relations", array(item.related).join(" ")));
  return `${intro(`「${state.filters.global}」の検索結果`, `${results.length}件見つかりました。`)}
    <div class="cards-grid">${results.map(item => `<a class="record-card slab" href="#${item.route}"><div class="record-head"><div><small>${esc(item.type)}</small><h3>${esc(item.title)}</h3></div><span class="tag">開く</span></div><p class="record-note">${esc(item.detail)}</p></a>`).join("")}</div>
    ${!results.length ? empty() : ""}`;
}

function pushSearch(results, query, type, title, detail, route, haystack = "") {
  if (`${title} ${detail} ${haystack}`.toLowerCase().includes(query)) results.push({ type, title, detail, route });
}

/* ============================================================
   フィルタ・操作
   ============================================================ */

function filterInput(key, label, placeholder) {
  return `<label class="filter-field search-wide"><span>${esc(label)}</span><input data-filter="${key}" type="search" value="${esc(state.filters[key] || "")}" placeholder="${esc(placeholder)}"></label>`;
}

function filterSelect(key, label, options) {
  return `<label class="filter-field"><span>${esc(label)}</span><select data-filter="${key}"><option value="">すべて</option>${Object.entries(options).map(([value, text]) => `<option value="${esc(value)}" ${state.filters[key] === value ? "selected" : ""}>${esc(text)}</option>`).join("")}</select></label>`;
}

function bindPageControls() {
  $$("[data-filter]").forEach(control => control.addEventListener(control.tagName === "SELECT" ? "change" : "input", event => {
    state.filters[event.currentTarget.dataset.filter] = event.currentTarget.value;
    const position = window.scrollY;
    render();
    window.scrollTo(0, position);
    const replacement = $(`[data-filter="${event.currentTarget.dataset.filter}"]`);
    if (replacement && event.currentTarget.tagName !== "SELECT") {
      replacement.focus();
      replacement.setSelectionRange(replacement.value.length, replacement.value.length);
    }
  }));

  $$("[data-image-id]").forEach(button => button.addEventListener("click", () => openImageDialog(button.dataset.imageId)));

  $$("[data-diagram]").forEach(tab => tab.addEventListener("click", () => {
    state.diagram = tab.dataset.diagram;
    state.focusNode = null;
    state.graphZoom = 1;
    render();
  }));

  $$(".relation-node").forEach(node => node.addEventListener("click", () => {
    state.focusNode = state.focusNode === node.dataset.node ? null : node.dataset.node;
    const toolbar = $(".graph-toolbar");
    if (toolbar) {
      const clear = $('[data-zoom="clear"]', toolbar);
      if (state.focusNode && !clear) {
        toolbar.insertAdjacentHTML("beforeend", `<button class="zoom-button text" type="button" data-zoom="clear">強調を解除</button>`);
        bindZoomButtons();
      } else if (!state.focusNode && clear) {
        clear.remove();
      }
    }
    highlightGraph();
  }));

  bindZoomButtons();
  observeGraph();
}

function bindZoomButtons() {
  $$("[data-zoom]").forEach(button => {
    if (button.dataset.bound) return;
    button.dataset.bound = "1";
    button.addEventListener("click", () => {
      const action = button.dataset.zoom;
      if (action === "clear") { state.focusNode = null; button.remove(); highlightGraph(); return; }
      if (action === "in") state.graphZoom = Math.min(1.6, Math.round((state.graphZoom + .15) * 100) / 100);
      if (action === "out") state.graphZoom = Math.max(.6, Math.round((state.graphZoom - .15) * 100) / 100);
      if (action === "reset") state.graphZoom = 1;
      const stage = $("[data-graph]");
      if (stage) stage.style.setProperty("--zoom", state.graphZoom);
      refreshGraph();
      requestAnimationFrame(refreshGraph);
    });
  });
}

function openImageDialog(id) {
  const item = array(state.data.gallery.items).find(entry => entry.id === id);
  if (!item) return;
  $("#imageDialogImage").src = item.image;
  $("#imageDialogImage").alt = `${item.title}の実ゲーム画面`;
  $("#imageDialogTitle").textContent = item.title;
  $("#imageDialogCaption").textContent = item.caption;
  $("#imageDialogMeta").innerHTML = `${decisionBadge(item.decision)}${array(item.related).map(value => `<span class="tag">${esc(value)}</span>`).join("")}`;
  $("#imageDialog").showModal();
}

function dailySummary() {
  const day=state.data.project.dailyUpdate;
  if(!day) return "";
  return `<section class="daily-section"><div class="daily-keyart" role="img" aria-label="封印門と剣士の新タイトル背景"></div><div class="daily-heading"><span>${esc(day.date)} · 開発日誌</span><h2>${esc(day.title)}</h2><p>今日つくった世界を、そのまま記録へ。</p></div><div class="daily-grid">${day.items.map((item,i)=>`<a class="daily-card" href="#${esc(item.route)}"><span class="daily-number">0${i+1}</span><h3>${esc(item.title)}</h3><p>${esc(item.body)}</p><small>記録を開く →</small></a>`).join("")}</div><p class="daily-note">${esc(day.note)}</p></section>`;
}
