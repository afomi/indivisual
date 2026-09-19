// /topo — stacked 3D layer spaces (FC2.18/FC2.19, cocktail layers spike).
//
// Two views share one layer-stack engine (createLayerStack): a layer is an
// object that owns its entity set and coordinate space, and typed edges
// connect ADJACENT visible layers, so the stack order determines which
// correspondences you see.
//
//  /topo            — municipal-code records ("muni" view):
//     "3D axes"     — one volume, records positioned by scores on three
//                     selectable semantic axes; radar-style spokes.
//     "Layers"      — a geographic layer (cities as lat/lng hubs) plus
//                     semantic slices (two axes each); identity edges connect
//                     each record (or its city hub) across layers.
//  /topo/cocktails  — cocktail layers ("cocktails" view): spirits, drinks,
//                     and supporting ingredients as three layers; edges are
//                     drink→spirit and drink→ingredient relations. Hovering
//                     a spirit (dot or sidebar row) isolates its drinks and
//                     their ingredients.
//
// Layer contract (view-supplied; engine owns group/mesh/targetY/dims):
//   { id, title, visible, entities: [{key, label, color, size?, meta}],
//     localPosition(entity) -> Vector3|null, entityVisible?(entity),
//     decorate?(group), tooltipHtml?(entity), countShown? }

import * as THREE from "three";
import {
  createStage,
  makeSprite,
  hashString,
  hexColor,
  PANEL_CSS,
  SIDEBAR_CSS,
  SELECT_CSS,
} from "./three_stage.js";

const RADIUS = 5;
const LAYER_SPACING = 4.4;
const CITY_COLORS = {
  vacaville: 0x38bdf8,
  fairfield: 0xf59e0b,
};
const FALLBACK_COLORS = [0x4ade80, 0xa78bfa, 0xf472b6];
const AXIS_DIRECTIONS = [
  new THREE.Vector3(1, 0, 0),
  new THREE.Vector3(0, 1, 0),
  new THREE.Vector3(0, 0, 1),
];
const PREFERRED_AXES = ["Permissiveness", "Substance", "Verbosity", "Explicitness"];

// Topic tether/label palette (Topics mode) — points stay city-colored;
// topics get their own hue for centroids, labels, and tethers.
const TOPIC_COLORS = [
  0x4ade80, 0xa78bfa, 0xf472b6, 0x22d3ee, 0xfacc15, 0xfb7185, 0x818cf8, 0x34d399,
  0xf9a8d4, 0xc084fc, 0xf87171, 0x2dd4bf, 0xfbbf24, 0x93c5fd, 0xbef264, 0xe879f9,
];

const SPIRIT_COLORS = {
  whiskey: 0xf59e0b,
  gin: 0x4ade80,
  vodka: 0x38bdf8,
  rum: 0xfb7185,
  tequila: 0xa78bfa,
  brandy: 0xf87171,
  unclassified: 0x64748b,
};
const CATEGORY_COLORS = {
  liqueur: 0xc084fc,
  juice: 0xfacc15,
  syrup_sweetener: 0xf9a8d4,
  bitters: 0xef4444,
  wine_vermouth: 0x818cf8,
  mixer: 0x22d3ee,
  dairy_egg: 0xe2e8f0,
  other: 0x94a3b8,
};
const CATEGORY_LABELS = {
  liqueur: "Liqueurs",
  juice: "Juices",
  syrup_sweetener: "Syrups & sweeteners",
  bitters: "Bitters",
  wine_vermouth: "Wine & vermouth",
  mixer: "Mixers",
  dairy_egg: "Dairy & egg",
  other: "Other",
};

const DIM_COLOR = new THREE.Color(0x1e293b);
const LINK_OPACITIES = { normal: 0.16, hi: 0.85, lo: 0.04 };

// Shared helpers (createStage, makeSprite, hashString, hexColor, panel CSS)
// live in three_stage.js so other pages can reuse them.

// ── Layer-stack engine ───────────────────────────────────────────────────

const sphereGeometry = new THREE.SphereGeometry(0.09, 16, 12);
const dummy = new THREE.Object3D();
const scratchColor = new THREE.Color();

function createLayerStack(scene) {
  const root = new THREE.Group();
  scene.add(root);
  const linkGroup = new THREE.Group();
  root.add(linkGroup);

  let layers = [];
  let edgesBetween = null; // (upper, lower) => [{a, b, color, emphasis?}]

  function disposeDecorations(layer) {
    for (const child of [...layer.decorations.children]) {
      child.material?.map?.dispose?.();
      child.material?.dispose?.();
      child.geometry?.dispose?.();
    }
    layer.decorations.clear();
  }

  function clearLinks() {
    for (const child of [...linkGroup.children]) {
      child.geometry.dispose();
      child.material.dispose();
    }
    linkGroup.clear();
  }

  function setLayers(next) {
    clearLinks();
    for (const layer of layers) {
      disposeDecorations(layer);
      layer.mesh.material.dispose();
      root.remove(layer.group);
    }
    layers = next;
    for (const layer of layers) {
      if (layer.visible === undefined) layer.visible = true;
      const group = new THREE.Group();
      layer.group = group;
      layer.targetY = 0;
      root.add(group);

      const grid = new THREE.GridHelper(RADIUS * 2, 8, 0x334155, 0x1e293b);
      grid.material.transparent = true;
      grid.material.opacity = 0.6;
      group.add(grid);

      layer.decorations = new THREE.Group();
      group.add(layer.decorations);

      const material = new THREE.MeshStandardMaterial({ roughness: 0.5, metalness: 0.1 });
      layer.mesh = new THREE.InstancedMesh(sphereGeometry, material, layer.entities.length);
      layer.mesh.userData.layer = layer;
      group.add(layer.mesh);

      // Per-entity highlight state, eased in tick(): dim 0→1 fades toward the
      // background, boost 0→1 enlarges the highlighted entity.
      layer.dims = new Float32Array(layer.entities.length);
      layer.dimTargets = new Float32Array(layer.entities.length);
      layer.boosts = new Float32Array(layer.entities.length);
      layer.boostTargets = new Float32Array(layer.entities.length);
      applyInstances(layer);
    }
  }

  function applyInstances(layer) {
    let shown = 0;
    layer.entities.forEach((entity, i) => {
      const visible = !!entity._position;
      dummy.position.copy(entity._position || dummy.position.set(0, 0, 0));
      const scale = visible
        ? (entity.size || 1) * (1 + 0.3 * layer.boosts[i] - 0.45 * layer.dims[i])
        : 0.0001;
      dummy.scale.set(scale, scale, scale);
      dummy.updateMatrix();
      layer.mesh.setMatrixAt(i, dummy.matrix);
      scratchColor.set(entity.color).lerp(DIM_COLOR, layer.dims[i] * 0.85);
      layer.mesh.setColorAt(i, scratchColor);
      if (visible) shown += 1;
    });
    layer.mesh.instanceMatrix.needsUpdate = true;
    layer.mesh.instanceColor.needsUpdate = true;
    return shown;
  }

  // Recompute stack positions, entity positions, and decorations.
  // Returns the max shown-entity count over layers with countShown set.
  function refresh() {
    const offset = ((layers.length - 1) * LAYER_SPACING) / 2;
    layers.forEach((layer, index) => {
      layer.targetY = offset - index * LAYER_SPACING;
      layer.group.visible = layer.visible;
    });

    let shown = 0;
    for (const layer of layers) {
      if (layer.decorate) {
        disposeDecorations(layer);
        layer.decorate(layer.decorations);
      }
      layer.entities.forEach((entity) => {
        const position = layer.localPosition(entity);
        const visible = !!position && (!layer.entityVisible || layer.entityVisible(entity));
        entity._position = visible ? position : null;
      });
      const count = applyInstances(layer);
      if (layer.visible && layer.countShown) shown = Math.max(shown, count);
    }
    rebuildLinks();
    return shown;
  }

  // Typed edges between ADJACENT visible layers in stack order, bucketed by
  // emphasis so highlighted relations pop while the rest recede.
  function rebuildLinks() {
    clearLinks();
    if (!edgesBetween) return;
    const visible = layers.filter((l) => l.visible);

    for (let i = 0; i + 1 < visible.length; i++) {
      const upper = visible[i];
      const lower = visible[i + 1];
      const buckets = { normal: [], hi: [], lo: [] };

      for (const edge of edgesBetween(upper, lower) || []) {
        buckets[edge.emphasis || "normal"].push(edge);
      }

      for (const [emphasis, edges] of Object.entries(buckets)) {
        if (edges.length === 0) continue;
        const positions = [];
        const colors = [];
        for (const edge of edges) {
          positions.push(
            edge.a.x, edge.a.y + upper.group.position.y, edge.a.z,
            edge.b.x, edge.b.y + lower.group.position.y, edge.b.z
          );
          scratchColor.set(edge.color);
          colors.push(
            scratchColor.r, scratchColor.g, scratchColor.b,
            scratchColor.r, scratchColor.g, scratchColor.b
          );
        }
        const geometry = new THREE.BufferGeometry();
        geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
        geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
        const material = new THREE.LineBasicMaterial({
          vertexColors: true,
          transparent: true,
          opacity: LINK_OPACITIES[emphasis],
        });
        linkGroup.add(new THREE.LineSegments(geometry, material));
      }
    }
  }

  // highlightSets: {layerId: Set(entityKey)} | null.
  function setHighlight(highlightSets) {
    for (const layer of layers) {
      const keys = highlightSets ? highlightSets[layer.id] : null;
      layer.entities.forEach((entity, i) => {
        const lit = !highlightSets || (keys && keys.has(entity.key));
        layer.dimTargets[i] = lit ? 0 : 1;
        layer.boostTargets[i] = highlightSets && lit ? 1 : 0;
      });
    }
    rebuildLinks();
  }

  function pick(raycaster) {
    const targets = layers.filter((l) => l.visible).map((l) => l.mesh);
    const hit = raycaster.intersectObjects(targets, false)[0];
    if (!hit || hit.instanceId === undefined) return null;
    const layer = hit.object.userData.layer;
    const entity = layer.entities[hit.instanceId];
    if (!entity || !entity._position) return null;
    return { layer, entity };
  }

  // Per-frame: settle stack Y positions and ease highlight dims/boosts.
  function tick() {
    let settled = true;
    for (const layer of layers) {
      const y = layer.group.position.y;
      if (Math.abs(y - layer.targetY) > 0.002) {
        layer.group.position.y = y + (layer.targetY - y) * 0.15;
        settled = false;
      } else {
        layer.group.position.y = layer.targetY;
      }

      let easing = false;
      for (let i = 0; i < layer.dims.length; i++) {
        for (const [values, targets] of [
          [layer.dims, layer.dimTargets],
          [layer.boosts, layer.boostTargets],
        ]) {
          const delta = targets[i] - values[i];
          if (Math.abs(delta) > 0.005) {
            values[i] += delta * 0.18;
            easing = true;
          } else {
            values[i] = targets[i];
          }
        }
      }
      if (easing) applyInstances(layer);
    }
    if (!settled) rebuildLinks();
  }

  return { root, setLayers, setEdges: (fn) => (edgesBetween = fn), refresh, rebuildLinks, setHighlight, pick, tick, layers: () => layers };
}

// ── Entry ────────────────────────────────────────────────────────────────

export function renderTopo(selector) {
  const container = document.querySelector(selector);
  if (container.dataset.view === "cocktails") renderCocktails(container);
  else renderMuni(container);
}

// ── Muni view (records × semantic axes) ──────────────────────────────────

function renderMuni(container) {
  const records = JSON.parse(container.dataset.records || "[]");
  const axes = JSON.parse(container.dataset.axes || "[]");
  const cityInfo = JSON.parse(container.dataset.cities || "[]");
  const topicData = JSON.parse(container.dataset.topics || "null") || {};
  let models = JSON.parse(container.dataset.models || "[]");
  if (models.length === 0) {
    models = [...new Set(records.flatMap((r) => Object.keys(r.scores || {})))].sort();
  }
  const shortModel = (m) => (m || "").split(":")[0];
  const scoreOf = (record, model, axisId) => (record.scores[model] || {})[axisId];

  if (records.length === 0 || axes.length < 3) {
    container.innerHTML =
      '<p style="color:#94a3b8;font-family:system-ui;padding:2rem;">' +
      "Nothing to plot yet — needs records with scores on at least 3 computed semantic axes. " +
      "Run mix indivisual.import_muni_codes, then compute + score axes at /axes.</p>";
    return;
  }

  const cities = [...new Set(records.map((r) => r.city))].filter(Boolean).sort();
  const cityColor = (city) =>
    CITY_COLORS[city] !== undefined
      ? CITY_COLORS[city]
      : FALLBACK_COLORS[cities.indexOf(city) % FALLBACK_COLORS.length];
  const cityHex = (city) => hexColor(cityColor(city));

  // ── State ──────────────────────────────────────────────────────────────
  const byName = Object.fromEntries(axes.map((a) => [a.name, a]));
  const preferred = PREFERRED_AXES.filter((n) => byName[n]).map((n) => byName[n]);
  const pick = (i) => (preferred[i] || axes[i % axes.length]).id;

  let mode = "axes"; // "axes" | "layers" | "topics"
  const visibleCities = new Set(cities.slice(0, 1)); // one city at a time by default
  const axisState = [pick(0), pick(1), pick(2)]; // 3D-axes mode mapping
  let axesModel = models[0]; // 3D-axes mode embedding model

  // Topics mode: unsupervised atlas — PCA positions + k-means clusters,
  // fitted per embedding model (mix indivisual.topics).
  const topicModels = Object.keys(topicData).sort();
  let topicsModel = topicModels[0] || null;
  const soloTopics = new Set(); // empty = show all topics

  const axisById = (id) => axes.find((a) => a.id === id);

  function scaleFor(axisId, model) {
    const values = records.map((r) => scoreOf(r, model, axisId)).filter((v) => v !== undefined);
    let min = Math.min(...values);
    let max = Math.max(...values);
    if (min === max || values.length === 0) {
      min = (min || 0) - 0.01;
      max = (max || 0) + 0.01;
    }
    return (v) => ((v - min) / (max - min)) * 2 * RADIUS - RADIUS;
  }

  // Geographic projection: fit the city coordinates into the layer plane.
  // x = east, z = south (so north reads as "up" from above).
  function geoPositions() {
    const located = cityInfo.filter((c) => c.lat != null);
    const lats = located.map((c) => c.lat);
    const lngs = located.map((c) => c.lng);
    const midLat = (Math.min(...lats) + Math.max(...lats)) / 2;
    const midLng = (Math.min(...lngs) + Math.max(...lngs)) / 2;
    const span = Math.max(
      Math.max(...lats) - Math.min(...lats),
      (Math.max(...lngs) - Math.min(...lngs)) * Math.cos((midLat * Math.PI) / 180),
      0.0001
    );
    const k = (RADIUS * 1.2) / span;
    const positions = {};
    for (const c of located) {
      positions[c.city] = new THREE.Vector3(
        (c.lng - midLng) * Math.cos((midLat * Math.PI) / 180) * k,
        0,
        -(c.lat - midLat) * k
      );
    }
    return positions;
  }
  const cityPositions = geoPositions();

  const { scene, camera, renderer, controls, tooltip } = createStage(container, {
    cameraPosition: [RADIUS * 2.2, RADIUS * 1.6, RADIUS * 2.6],
  });

  function recordTooltip(record, axisIds, model) {
    const scoreLines = axisIds
      .map((id) => `${axisById(id).name}: ${scoreOf(record, model, id)?.toFixed(3)}`)
      .join("<br>");
    const years =
      record.earliest_year != null ? ` · ${record.earliest_year}–${record.latest_year}` : "";
    return (
      `<strong>${record.name}</strong><br>` +
      `<span style="color:#94a3b8">${record.city} · ${record.section_count} sections${years} · ${shortModel(model)}</span><br>` +
      scoreLines
    );
  }

  // ── Mode: 3D axes (its own volume, not part of the layer stack) ────────
  const axesGroup = new THREE.Group();
  scene.add(axesGroup);

  const axesWeb = new THREE.Group();
  const ringMaterial = new THREE.LineBasicMaterial({ color: 0x334155, transparent: true, opacity: 0.5 });
  for (const radius of [RADIUS / 2, RADIUS]) {
    const points = new THREE.EllipseCurve(0, 0, radius, radius).getPoints(96);
    const geometry = new THREE.BufferGeometry().setFromPoints(points);
    for (const rotate of [null, "x", "y"]) {
      const line = new THREE.LineLoop(geometry, ringMaterial);
      if (rotate === "x") line.rotation.x = Math.PI / 2;
      if (rotate === "y") line.rotation.y = Math.PI / 2;
      axesWeb.add(line);
    }
  }
  const spokeMaterial = new THREE.LineBasicMaterial({ color: 0x64748b });
  for (const direction of AXIS_DIRECTIONS) {
    const geometry = new THREE.BufferGeometry().setFromPoints([
      direction.clone().multiplyScalar(-RADIUS),
      direction.clone().multiplyScalar(RADIUS),
    ]);
    axesWeb.add(new THREE.Line(geometry, spokeMaterial));
  }
  axesGroup.add(axesWeb);

  const axesLabels = new THREE.Group();
  axesGroup.add(axesLabels);
  const axesMesh = new THREE.InstancedMesh(
    sphereGeometry,
    new THREE.MeshStandardMaterial({ roughness: 0.5, metalness: 0.1 }),
    records.length
  );
  records.forEach((record, i) => axesMesh.setColorAt(i, new THREE.Color(cityColor(record.city))));
  axesMesh.instanceColor.needsUpdate = true;
  axesGroup.add(axesMesh);

  function updateAxesMode() {
    axesLabels.clear();
    axisState.forEach((axisId, i) => {
      const axis = axisById(axisId);
      const direction = AXIS_DIRECTIONS[i];
      const negative = makeSprite("− " + axis.negative_pole, "#f87171");
      negative.position.copy(direction.clone().multiplyScalar(-(RADIUS + 0.8)));
      axesLabels.add(negative);
      const positive = makeSprite("+ " + axis.positive_pole, "#4ade80");
      positive.position.copy(direction.clone().multiplyScalar(RADIUS + 0.8));
      axesLabels.add(positive);
      const name = makeSprite(axis.name, "#94a3b8", 0.9);
      name.position.copy(direction.clone().multiplyScalar(RADIUS + 1.7));
      axesLabels.add(name);
    });

    const scales = axisState.map((id) => scaleFor(id, axesModel));
    let shown = 0;
    records.forEach((record, i) => {
      const values = axisState.map((id) => scoreOf(record, axesModel, id));
      const position =
        values.some((v) => v === undefined)
          ? null
          : new THREE.Vector3(scales[0](values[0]), scales[1](values[1]), scales[2](values[2]));
      const visible = position && visibleCities.has(record.city);
      dummy.position.copy(position || dummy.position.set(0, 0, 0));
      const s = visible ? 1 : 0.0001;
      dummy.scale.set(s, s, s);
      dummy.updateMatrix();
      axesMesh.setMatrixAt(i, dummy.matrix);
      if (visible) shown += 1;
    });
    axesMesh.instanceMatrix.needsUpdate = true;
    shownCount.textContent = `${shown} of ${records.length} records · ${shortModel(axesModel)}`;
  }

  // ── Mode: topics (unsupervised atlas — its own volume) ─────────────────
  const topicsGroup = new THREE.Group();
  scene.add(topicsGroup);

  const topicsBox = new THREE.LineSegments(
    new THREE.EdgesGeometry(new THREE.BoxGeometry(RADIUS * 2, RADIUS * 2, RADIUS * 2)),
    new THREE.LineBasicMaterial({ color: 0x334155, transparent: true, opacity: 0.5 })
  );
  topicsGroup.add(topicsBox);

  const topicsMesh = new THREE.InstancedMesh(
    sphereGeometry,
    new THREE.MeshStandardMaterial({ roughness: 0.5, metalness: 0.1 }),
    records.length
  );
  records.forEach((record, i) => topicsMesh.setColorAt(i, new THREE.Color(cityColor(record.city))));
  topicsMesh.instanceColor.needsUpdate = true;
  topicsGroup.add(topicsMesh);

  const topicDecorations = new THREE.Group();
  topicsGroup.add(topicDecorations);

  const topicColor = (cluster) => TOPIC_COLORS[Number(cluster) % TOPIC_COLORS.length];
  const topicShown = (cluster) => soloTopics.size === 0 || soloTopics.has(String(cluster));

  function clearTopicDecorations() {
    for (const child of [...topicDecorations.children]) {
      child.material?.map?.dispose?.();
      child.material?.dispose?.();
      child.geometry?.dispose?.();
    }
    topicDecorations.clear();
  }

  function updateTopicsMode() {
    clearTopicDecorations();
    const data = topicData[topicsModel];

    if (!data) {
      shownCount.textContent = "no topic model stored — run: mix indivisual.topics";
      records.forEach((_r, i) => {
        dummy.position.set(0, 0, 0);
        dummy.scale.set(0.0001, 0.0001, 0.0001);
        dummy.updateMatrix();
        topicsMesh.setMatrixAt(i, dummy.matrix);
      });
      topicsMesh.instanceMatrix.needsUpdate = true;
      return;
    }

    let shown = 0;
    const memberPositions = {}; // cluster -> [{position, record, visible}]
    const tetherPositions = [];
    const tetherColors = [];

    records.forEach((record, i) => {
      const placement = data.placements[String(record.id)];
      const cluster = placement && placement.topic;
      const visible =
        placement && visibleCities.has(record.city) && topicShown(cluster);
      const position = placement
        ? new THREE.Vector3(
            placement.pos[0] * RADIUS,
            placement.pos[1] * RADIUS,
            placement.pos[2] * RADIUS
          )
        : new THREE.Vector3();

      dummy.position.copy(position);
      const s = visible ? 1 : 0.0001;
      dummy.scale.set(s, s, s);
      dummy.updateMatrix();
      topicsMesh.setMatrixAt(i, dummy.matrix);

      if (placement) {
        (memberPositions[cluster] = memberPositions[cluster] || []).push({ position, visible });
      }
      if (visible) shown += 1;
    });
    topicsMesh.instanceMatrix.needsUpdate = true;

    // Topic centroids: label sprite + tethers from visible members.
    for (const [cluster, members] of Object.entries(memberPositions)) {
      const visibleMembers = members.filter((m) => m.visible);
      if (visibleMembers.length === 0) continue;

      const centroid = new THREE.Vector3();
      for (const m of visibleMembers) centroid.add(m.position);
      centroid.divideScalar(visibleMembers.length);

      const topic = data.topics[String(cluster)];
      const color = topicColor(cluster);
      const label = makeSprite(topic ? topic.label : `topic ${cluster}`, hexColor(color), 0.75);
      label.position.copy(centroid.clone().add(new THREE.Vector3(0, 0.45, 0)));
      topicDecorations.add(label);

      const c = new THREE.Color(color);
      for (const m of visibleMembers) {
        tetherPositions.push(
          m.position.x, m.position.y, m.position.z,
          centroid.x, centroid.y, centroid.z
        );
        tetherColors.push(c.r, c.g, c.b, c.r, c.g, c.b);
      }
    }

    if (tetherPositions.length > 0) {
      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute("position", new THREE.Float32BufferAttribute(tetherPositions, 3));
      geometry.setAttribute("color", new THREE.Float32BufferAttribute(tetherColors, 3));
      const material = new THREE.LineBasicMaterial({
        vertexColors: true,
        transparent: true,
        opacity: 0.14,
      });
      topicDecorations.add(new THREE.LineSegments(geometry, material));
    }

    shownCount.textContent =
      `${shown} of ${records.length} records · ${shortModel(topicsModel)} · k=${data.k}`;
  }

  // ── Mode: layers (engine-backed) ───────────────────────────────────────
  const stack = createLayerStack(scene);

  // Fresh entity objects per layer — the engine caches _position on each
  // entity, so layers must not share them.
  const recordEntities = () =>
    records.map((record) => ({
      key: record.id,
      label: record.name,
      color: cityColor(record.city),
      meta: { record },
    }));

  function makeGeoLayer() {
    const layer = {
      id: "geo",
      type: "geo",
      title: "Geography (lat/lng)",
      visible: true,
      entities: cities.map((city) => ({
        key: city,
        label: city,
        color: cityColor(city),
        size: 0.28 / 0.09,
        meta: { city },
      })),
      localPosition: (entity) => cityPositions[entity.meta.city] || null,
      entityVisible: (entity) => visibleCities.has(entity.meta.city),
      decorate: (group) => {
        const title = makeSprite(layer.title, "#94a3b8", 0.9);
        title.position.set(-RADIUS, 0.4, -RADIUS - 0.8);
        group.add(title);
        for (const city of cities) {
          const position = cityPositions[city];
          if (!position) continue;
          const label = makeSprite(city, cityHex(city), 0.9);
          label.position.copy(position.clone().add(new THREE.Vector3(0, 0.7, 0)));
          group.add(label);
        }
      },
      tooltipHtml: (entity) => {
        const city = entity.meta.city;
        const count = records.filter((r) => r.city === city).length;
        return `<strong>${city}</strong><br><span style="color:#94a3b8">${count} chapters</span>`;
      },
    };
    return layer;
  }

  function makeSliceLayer(config) {
    const layer = {
      id: `slice-${config.xAxis}-${config.zAxis}-${config.model}`,
      type: "slice",
      visible: config.visible,
      xAxis: config.xAxis,
      zAxis: config.zAxis,
      model: config.model,
      countShown: true,
      entities: recordEntities(),
      localPosition: (entity) => {
        const record = entity.meta.record;
        const xv = scoreOf(record, layer.model, layer.xAxis);
        const zv = scoreOf(record, layer.model, layer.zAxis);
        if (xv === undefined || zv === undefined) return null;
        return new THREE.Vector3(layer.scaleX(xv), 0.05, layer.scaleZ(zv));
      },
      entityVisible: (entity) => visibleCities.has(entity.meta.record.city),
      decorate: (group) => {
        const xAxis = axisById(layer.xAxis);
        const zAxis = axisById(layer.zAxis);
        const title = makeSprite(
          `${xAxis.name} × ${zAxis.name} · ${shortModel(layer.model)}`,
          "#94a3b8",
          0.9
        );
        title.position.set(-RADIUS, 0.4, -RADIUS - 0.8);
        group.add(title);
        const edges = [
          ["− " + xAxis.negative_pole, "#f87171", -RADIUS - 0.8, 0],
          ["+ " + xAxis.positive_pole, "#4ade80", RADIUS + 0.8, 0],
          ["− " + zAxis.negative_pole, "#f87171", 0, -RADIUS - 0.8],
          ["+ " + zAxis.positive_pole, "#4ade80", 0, RADIUS + 0.8],
        ];
        for (const [text, color, x, z] of edges) {
          const sprite = makeSprite(text, color, 0.8);
          sprite.position.set(x, 0.15, z);
          group.add(sprite);
        }
      },
      tooltipHtml: (entity) =>
        recordTooltip(entity.meta.record, [layer.xAxis, layer.zAxis], layer.model),
    };
    return layer;
  }

  // Default stack: with two or more embedding models available this is the
  // TRIANGULATION view — the same two axes surveyed by two models, where
  // displacement between the layers is model disagreement.
  const sliceConfigs =
    models.length >= 2
      ? [
          { visible: true, xAxis: pick(0), zAxis: pick(1), model: models[0] },
          { visible: true, xAxis: pick(0), zAxis: pick(1), model: models[1] },
        ]
      : [
          { visible: true, xAxis: pick(0), zAxis: pick(1), model: models[0] },
          { visible: true, xAxis: pick(2), zAxis: pick(3), model: models[0] },
        ];
  stack.setLayers([makeGeoLayer(), ...sliceConfigs.map(makeSliceLayer)]);

  // Where a record sits in a layer's space — geo layers place it at its city
  // hub. Identity edges pair each record with itself across adjacent layers.
  function positionInLayer(layer, record) {
    if (layer.type === "geo") return cityPositions[record.city] || null;
    const xv = scoreOf(record, layer.model, layer.xAxis);
    const zv = scoreOf(record, layer.model, layer.zAxis);
    if (xv === undefined || zv === undefined) return null;
    return new THREE.Vector3(layer.scaleX(xv), 0.05, layer.scaleZ(zv));
  }

  stack.setEdges((upper, lower) => {
    const edges = [];
    for (const record of records) {
      if (!visibleCities.has(record.city)) continue;
      const a = positionInLayer(upper, record);
      const b = positionInLayer(lower, record);
      if (!a || !b) continue;
      edges.push({ a, b, color: cityColor(record.city) });
    }
    return edges;
  });

  function updateLayersMode() {
    for (const layer of stack.layers()) {
      if (layer.type === "slice") {
        layer.scaleX = scaleFor(layer.xAxis, layer.model);
        layer.scaleZ = scaleFor(layer.zAxis, layer.model);
      }
    }
    const shown = stack.refresh();
    shownCount.textContent = `${shown} of ${records.length} records`;
  }

  // ── Overlay UI ─────────────────────────────────────────────────────────
  const panel = document.createElement("div");
  panel.style.cssText = PANEL_CSS;
  container.appendChild(panel);

  const title = document.createElement("div");
  title.style.cssText = "color:#38bdf8;font-weight:600;letter-spacing:0.05em;font-size:11px;";
  title.textContent = "SEMANTIC SPACE";
  panel.appendChild(title);

  // Mode toggle
  const modeRow = document.createElement("div");
  modeRow.style.cssText = "display:flex;gap:4px;";
  const modeButtons = {};
  for (const [value, label] of [["axes", "3D axes"], ["layers", "Layers"], ["topics", "Topics"]]) {
    const button = document.createElement("button");
    button.textContent = label;
    button.addEventListener("click", () => setMode(value));
    modeButtons[value] = button;
    modeRow.appendChild(button);
  }
  panel.appendChild(modeRow);

  function styleModeButtons() {
    for (const [value, button] of Object.entries(modeButtons)) {
      button.style.cssText =
        "flex:1;border-radius:4px;padding:3px 0;font-size:11px;cursor:pointer;" +
        (mode === value
          ? "background:#1e3a5f;color:#38bdf8;border:1px solid #38bdf8;"
          : "background:#1e293b;color:#94a3b8;border:1px solid #334155;");
    }
  }

  // City toggles
  const cityRow = document.createElement("div");
  cityRow.style.cssText = "display:flex;flex-direction:column;gap:4px;";
  for (const city of cities) {
    const label = document.createElement("label");
    label.style.cssText = "display:flex;align-items:center;gap:6px;cursor:pointer;";
    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.checked = visibleCities.has(city);
    checkbox.addEventListener("change", () => {
      if (checkbox.checked) visibleCities.add(city);
      else visibleCities.delete(city);
      refresh();
    });
    const swatch = document.createElement("span");
    swatch.style.cssText =
      `width:10px;height:10px;border-radius:50%;display:inline-block;background:${cityHex(city)};`;
    const count = records.filter((r) => r.city === city).length;
    label.append(checkbox, swatch, `${city} (${count})`);
    cityRow.appendChild(label);
  }
  panel.appendChild(cityRow);

  function axisSelect(currentId, onChange) {
    const select = document.createElement("select");
    select.style.cssText = SELECT_CSS;
    for (const axis of axes) {
      const option = document.createElement("option");
      option.value = axis.id;
      option.textContent = `${axis.name} (${axis.negative_pole} ↔ ${axis.positive_pole})`;
      if (axis.id === currentId) option.selected = true;
      select.appendChild(option);
    }
    select.addEventListener("change", () => onChange(parseInt(select.value, 10)));
    return select;
  }

  function modelSelect(current, onChange) {
    const select = document.createElement("select");
    select.style.cssText = SELECT_CSS + "color:#a78bfa;";
    for (const model of models) {
      const option = document.createElement("option");
      option.value = model;
      option.textContent = model;
      if (model === current) option.selected = true;
      select.appendChild(option);
    }
    select.addEventListener("change", () => onChange(select.value));
    return select;
  }

  // 3D-axes mode controls
  const axesControls = document.createElement("div");
  axesControls.style.cssText = "display:flex;flex-direction:column;gap:5px;";
  ["X", "Y", "Z"].forEach((dimension, i) => {
    const row = document.createElement("div");
    row.style.cssText = "display:flex;align-items:center;gap:6px;";
    const tag = document.createElement("span");
    tag.style.cssText = "width:12px;color:#38bdf8;";
    tag.textContent = dimension;
    row.append(tag, axisSelect(axisState[i], (id) => {
      axisState[i] = id;
      refresh();
    }));
    axesControls.appendChild(row);
  });
  if (models.length > 1) {
    const row = document.createElement("div");
    row.style.cssText = "display:flex;align-items:center;gap:6px;";
    const tag = document.createElement("span");
    tag.style.cssText = "width:12px;color:#a78bfa;font-size:10px;";
    tag.textContent = "M";
    row.append(tag, modelSelect(axesModel, (model) => {
      axesModel = model;
      refresh();
    }));
    axesControls.appendChild(row);
  }
  panel.appendChild(axesControls);

  // Topics mode controls: model select + clickable topic legend (solo/dim)
  const topicsControls = document.createElement("div");
  topicsControls.style.cssText = "display:flex;flex-direction:column;gap:5px;";
  panel.appendChild(topicsControls);

  function rebuildTopicsControls() {
    topicsControls.innerHTML = "";
    if (!topicsModel) {
      const hint = document.createElement("div");
      hint.style.cssText = "color:#64748b;font-size:11px;";
      hint.textContent = "No topic model stored — run: mix indivisual.topics";
      topicsControls.appendChild(hint);
      return;
    }

    if (topicModels.length > 1) {
      const row = document.createElement("div");
      row.style.cssText = "display:flex;align-items:center;gap:6px;";
      const tag = document.createElement("span");
      tag.style.cssText = "width:12px;color:#a78bfa;font-size:10px;";
      tag.textContent = "M";
      const select = document.createElement("select");
      select.style.cssText = SELECT_CSS + "color:#a78bfa;";
      for (const model of topicModels) {
        const option = document.createElement("option");
        option.value = model;
        option.textContent = model;
        if (model === topicsModel) option.selected = true;
        select.appendChild(option);
      }
      select.addEventListener("change", () => {
        topicsModel = select.value;
        soloTopics.clear();
        rebuildTopicsControls();
        refresh();
      });
      row.append(tag, select);
      topicsControls.appendChild(row);
    }

    const data = topicData[topicsModel];
    const legend = document.createElement("div");
    legend.style.cssText =
      "display:flex;flex-direction:column;gap:2px;max-height:220px;overflow-y:auto;";

    Object.entries(data.topics)
      .sort(([, a], [, b]) => b.size - a.size)
      .forEach(([cluster, topic]) => {
        const row = document.createElement("div");
        const active = topicShown(cluster);
        row.style.cssText =
          "display:flex;align-items:center;gap:5px;cursor:pointer;font-size:10px;" +
          `padding:1px 3px;border-radius:3px;opacity:${active ? 1 : 0.4};`;
        const swatch = document.createElement("span");
        swatch.style.cssText =
          "width:8px;height:8px;border-radius:50%;flex-shrink:0;display:inline-block;" +
          `background:${hexColor(topicColor(cluster))};`;
        const text = document.createElement("span");
        text.style.cssText = "flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;";
        text.textContent = `${topic.label} (${topic.size})`;
        text.title = topic.terms.join(", ");
        row.append(swatch, text);
        row.addEventListener("click", () => {
          // Click to solo a topic; click again to release.
          if (soloTopics.has(cluster)) soloTopics.delete(cluster);
          else soloTopics.add(cluster);
          rebuildTopicsControls();
          refresh();
        });
        legend.appendChild(row);
      });

    topicsControls.appendChild(legend);
  }
  rebuildTopicsControls();

  // Layers mode controls: visibility, reorder, per-slice axis mapping
  const layerControls = document.createElement("div");
  layerControls.style.cssText = "display:flex;flex-direction:column;gap:6px;";
  panel.appendChild(layerControls);

  function rebuildLayerControls() {
    layerControls.innerHTML = "";
    const layers = stack.layers();
    layers.forEach((layer, index) => {
      const box = document.createElement("div");
      box.style.cssText =
        "display:flex;flex-direction:column;gap:4px;border-top:1px solid #1e293b;padding-top:5px;";

      const row = document.createElement("div");
      row.style.cssText = "display:flex;align-items:center;gap:5px;";

      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.checked = layer.visible;
      checkbox.addEventListener("change", () => {
        layer.visible = checkbox.checked;
        refresh();
      });

      const name = document.createElement("span");
      name.style.cssText = "flex:1;color:#e2e8f0;font-size:11px;";
      name.textContent =
        layer.type === "geo"
          ? layer.title
          : `${axisById(layer.xAxis).name} × ${axisById(layer.zAxis).name} · ${shortModel(layer.model)}`;

      row.append(checkbox, name);

      for (const [arrow, delta] of [["↑", -1], ["↓", 1]]) {
        const button = document.createElement("button");
        button.textContent = arrow;
        button.style.cssText =
          "background:#1e293b;color:#94a3b8;border:1px solid #334155;border-radius:3px;" +
          "font-size:10px;cursor:pointer;padding:0 5px;";
        const target = index + delta;
        button.disabled = target < 0 || target >= layers.length;
        if (button.disabled) button.style.opacity = "0.3";
        button.addEventListener("click", () => {
          [layers[index], layers[target]] = [layers[target], layers[index]];
          rebuildLayerControls();
          refresh();
        });
        row.appendChild(button);
      }
      box.appendChild(row);

      if (layer.type === "slice") {
        for (const key of ["xAxis", "zAxis"]) {
          const selectRow = document.createElement("div");
          selectRow.style.cssText = "display:flex;align-items:center;gap:5px;padding-left:18px;";
          const tag = document.createElement("span");
          tag.style.cssText = "width:12px;color:#38bdf8;font-size:10px;";
          tag.textContent = key === "xAxis" ? "X" : "Z";
          selectRow.append(tag, axisSelect(layer[key], (id) => {
            layer[key] = id;
            rebuildLayerControls();
            refresh();
          }));
          box.appendChild(selectRow);
        }
        if (models.length > 1) {
          const selectRow = document.createElement("div");
          selectRow.style.cssText = "display:flex;align-items:center;gap:5px;padding-left:18px;";
          const tag = document.createElement("span");
          tag.style.cssText = "width:12px;color:#a78bfa;font-size:10px;";
          tag.textContent = "M";
          selectRow.append(tag, modelSelect(layer.model, (model) => {
            layer.model = model;
            rebuildLayerControls();
            refresh();
          }));
          box.appendChild(selectRow);
        }
      }

      layerControls.appendChild(box);
    });
  }
  rebuildLayerControls();

  const shownCount = document.createElement("div");
  shownCount.style.cssText = "color:#64748b;font-size:11px;";
  panel.appendChild(shownCount);

  function setMode(next) {
    mode = next;
    axesGroup.visible = mode === "axes";
    stack.root.visible = mode === "layers";
    topicsGroup.visible = mode === "topics";
    axesControls.style.display = mode === "axes" ? "flex" : "none";
    layerControls.style.display = mode === "layers" ? "flex" : "none";
    topicsControls.style.display = mode === "topics" ? "flex" : "none";
    styleModeButtons();
    refresh();
  }

  function refresh() {
    if (mode === "axes") updateAxesMode();
    else if (mode === "topics") updateTopicsMode();
    else updateLayersMode();
  }

  // ── Hover tooltip ──────────────────────────────────────────────────────
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();

  renderer.domElement.addEventListener("mousemove", (event) => {
    const rect = renderer.domElement.getBoundingClientRect();
    pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);

    let html = null;
    if (mode === "axes") {
      const hit = raycaster.intersectObject(axesMesh, false)[0];
      if (hit && hit.instanceId !== undefined) {
        const record = records[hit.instanceId];
        if (visibleCities.has(record.city)) html = recordTooltip(record, axisState, axesModel);
      }
    } else if (mode === "topics") {
      const hit = raycaster.intersectObject(topicsMesh, false)[0];
      const data = topicData[topicsModel];
      if (hit && hit.instanceId !== undefined && data) {
        const record = records[hit.instanceId];
        const placement = data.placements[String(record.id)];
        if (placement && visibleCities.has(record.city) && topicShown(placement.topic)) {
          const topic = data.topics[String(placement.topic)];
          html =
            `<strong>${record.name}</strong><br>` +
            `<span style="color:#94a3b8">${record.city} · ${record.section_count} sections</span><br>` +
            `<span style="color:${hexColor(topicColor(placement.topic))}">${topic.label}</span>`;
        }
      }
    } else {
      const picked = stack.pick(raycaster);
      if (picked && picked.layer.tooltipHtml) html = picked.layer.tooltipHtml(picked.entity);
    }

    if (html) {
      tooltip.innerHTML = html;
      tooltip.style.display = "block";
      tooltip.style.left = event.clientX - rect.left + 14 + "px";
      tooltip.style.top = event.clientY - rect.top + 10 + "px";
    } else {
      tooltip.style.display = "none";
    }
  });

  setMode("axes");

  renderer.setAnimationLoop(() => {
    controls.update();
    stack.tick();
    renderer.render(scene, camera);
  });
}

// ── Cocktails view (spirits / drinks / supporting ingredients) ───────────

function renderCocktails(container) {
  const payload = JSON.parse(container.dataset.cocktails || "null");
  const datasets = payload?.datasets?.filter((d) => d.count > 0) || [];

  if (datasets.length === 0) {
    container.innerHTML =
      '<p style="color:#94a3b8;font-family:system-ui;padding:2rem;">' +
      "No cocktail data vendored yet — run mix run scripts/fetch_opendrinks.exs and " +
      "mix run scripts/fetch_boston_cocktails.exs, then reload.</p>";
    return;
  }

  const { scene, camera, renderer, controls, tooltip } = createStage(container, {
    cameraPosition: [RADIUS * 2.2, RADIUS * 1.6, RADIUS * 2.6],
  });
  const stack = createLayerStack(scene);

  let dataset = datasets[0];
  // Per-dataset lookups, rebuilt by buildDataset().
  let drinkById = {};
  let drinksBySpirit = {};
  let drinksByIngredient = {};
  let spiritPositions = {};
  let drinkPositions = {};
  let ingredientPositions = {};

  // Highlight = the connected sets to keep lit; hover wins over a pinned
  // sidebar selection. null = nothing highlighted, everything full.
  let hoverHighlight = null;
  let pinnedSpirit = null;

  function highlightForSpirit(spiritId) {
    const drinks = drinksBySpirit[spiritId] || new Set();
    const ingredients = new Set();
    for (const drinkId of drinks) {
      for (const ing of drinkById[drinkId].ingredients) ingredients.add(ing);
    }
    return { spirits: new Set([spiritId]), drinks, ingredients };
  }

  function highlightForDrink(drinkId) {
    const drink = drinkById[drinkId];
    return {
      spirits: new Set(drink.spirits),
      drinks: new Set([drinkId]),
      ingredients: new Set(drink.ingredients),
    };
  }

  function highlightForIngredient(ingredientId) {
    const drinks = drinksByIngredient[ingredientId] || new Set();
    const spirits = new Set();
    for (const drinkId of drinks) {
      for (const spirit of drinkById[drinkId].spirits) spirits.add(spirit);
    }
    return { spirits, drinks, ingredients: new Set([ingredientId]) };
  }

  function activeHighlight() {
    if (hoverHighlight) return hoverHighlight;
    if (pinnedSpirit) return highlightForSpirit(pinnedSpirit);
    return null;
  }

  function applyHighlight() {
    const h = activeHighlight();
    stack.setHighlight(
      h ? { spirits: h.spirits, drinks: h.drinks, ingredients: h.ingredients } : null
    );
  }

  // ── Layouts (deterministic — stable across reloads) ────────────────────

  function buildPositions() {
    spiritPositions = {};
    drinkPositions = {};
    ingredientPositions = {};

    // Spirits: ring ordered by drink count (payload order), unclassified at
    // the center so unmatched drinks read as an honest residual cluster.
    const ringSpirits = dataset.spirits.filter((s) => s.id !== "unclassified");
    ringSpirits.forEach((spirit, i) => {
      const angle = (i / ringSpirits.length) * Math.PI * 2;
      spiritPositions[spirit.id] = new THREE.Vector3(
        Math.cos(angle) * RADIUS * 0.7,
        0.05,
        Math.sin(angle) * RADIUS * 0.7
      );
    });
    spiritPositions["unclassified"] = new THREE.Vector3(0, 0.05, 0);

    // Drinks: clustered around their primary spirit's ring angle, jittered by
    // a hash of the drink id. Multi-spirit drinks sit under spirits[0] but
    // link to all of their spirits.
    for (const drink of dataset.drinks) {
      const anchor = spiritPositions[drink.spirits[0]];
      const radius = 0.25 + 1.35 * hashString(drink.id);
      const angle = Math.PI * 2 * hashString(drink.id + "θ");
      drinkPositions[drink.id] = new THREE.Vector3(
        anchor.x + Math.cos(angle) * radius,
        0.05,
        anchor.z + Math.sin(angle) * radius
      );
    }

    // Ingredients: one wedge per category, filled outward golden-ratio style
    // in usage order (payload order is count-desc, so heavy hitters sit near
    // the center of the wedge).
    const categories = Object.keys(CATEGORY_LABELS);
    const wedge = (Math.PI * 2) / categories.length;
    const rankInCategory = {};
    for (const ingredient of dataset.ingredients) {
      const rank = rankInCategory[ingredient.category] || 0;
      rankInCategory[ingredient.category] = rank + 1;
      const sector = categories.indexOf(ingredient.category);
      const start = sector * wedge + wedge * 0.08;
      const angle = start + wedge * 0.84 * ((rank * 0.618034) % 1);
      const radius = Math.min(RADIUS * 1.05, 0.7 + 0.16 * Math.sqrt(rank));
      ingredientPositions[ingredient.id] = new THREE.Vector3(
        Math.cos(angle) * radius,
        0.05,
        Math.sin(angle) * radius
      );
    }
  }

  // ── Layers ─────────────────────────────────────────────────────────────

  function makeSpiritsLayer() {
    const maxCount = Math.max(...dataset.spirits.map((s) => s.count), 1);
    const layer = {
      id: "spirits",
      title: "Spirits",
      visible: true,
      countShown: true,
      entities: dataset.spirits.map((spirit) => ({
        key: spirit.id,
        label: spirit.name,
        color: SPIRIT_COLORS[spirit.id] ?? 0x64748b,
        size: 1.6 + 2.6 * Math.sqrt(spirit.count / maxCount),
        meta: spirit,
      })),
      localPosition: (entity) => spiritPositions[entity.key] || null,
      decorate: (group) => {
        const title = makeSprite("Spirits", "#94a3b8", 0.9);
        title.position.set(-RADIUS, 0.4, -RADIUS - 0.8);
        group.add(title);
        for (const entity of layer.entities) {
          const position = spiritPositions[entity.key];
          if (!position) continue;
          const label = makeSprite(entity.label, hexColor(entity.color), 0.9);
          label.position.copy(position.clone().add(new THREE.Vector3(0, 0.75, 0)));
          group.add(label);
        }
      },
      tooltipHtml: (entity) =>
        `<strong>${entity.label}</strong><br>` +
        `<span style="color:#94a3b8">${entity.meta.count} drinks</span>`,
    };
    return layer;
  }

  function makeDrinksLayer() {
    return {
      id: "drinks",
      title: "Drinks",
      visible: true,
      countShown: true,
      entities: dataset.drinks.map((drink) => ({
        key: drink.id,
        label: drink.name,
        color: SPIRIT_COLORS[drink.spirits[0]] ?? 0x64748b,
        size: 0.8,
        meta: drink,
      })),
      localPosition: (entity) => drinkPositions[entity.key] || null,
      decorate: (group) => {
        const title = makeSprite("Drinks", "#94a3b8", 0.9);
        title.position.set(-RADIUS, 0.4, -RADIUS - 0.8);
        group.add(title);
      },
      tooltipHtml: (entity) => {
        const drink = entity.meta;
        const spirits = drink.spirits
          .map((s) => dataset.spirits.find((x) => x.id === s)?.name || s)
          .join(", ");
        const ingredients = drink.ingredients
          .map((i) => dataset.ingredients.find((x) => x.id === i)?.name || i)
          .join(", ");
        return (
          `<strong>${drink.name}</strong><br>` +
          `<span style="color:#94a3b8">${spirits}</span>` +
          (ingredients ? `<br>${ingredients}` : "")
        );
      },
    };
  }

  function makeIngredientsLayer() {
    const maxCount = Math.max(...dataset.ingredients.map((i) => i.count), 1);
    const byCategory = {};
    for (const ingredient of dataset.ingredients) {
      (byCategory[ingredient.category] ||= []).push(ingredient);
    }
    const layer = {
      id: "ingredients",
      title: "Supporting ingredients",
      visible: true,
      countShown: true,
      entities: dataset.ingredients.map((ingredient) => ({
        key: ingredient.id,
        label: ingredient.name,
        color: CATEGORY_COLORS[ingredient.category] ?? 0x94a3b8,
        size: 0.55 + 1.4 * Math.sqrt(ingredient.count / maxCount),
        meta: ingredient,
      })),
      localPosition: (entity) => ingredientPositions[entity.key] || null,
      decorate: (group) => {
        const title = makeSprite("Supporting ingredients", "#94a3b8", 0.9);
        title.position.set(-RADIUS, 0.4, -RADIUS - 0.8);
        group.add(title);
        const categories = Object.keys(CATEGORY_LABELS);
        const wedge = (Math.PI * 2) / categories.length;
        categories.forEach((category, i) => {
          if (!byCategory[category]) return;
          const angle = i * wedge + wedge / 2;
          const label = makeSprite(
            CATEGORY_LABELS[category],
            hexColor(CATEGORY_COLORS[category]),
            0.75
          );
          label.position.set(
            Math.cos(angle) * (RADIUS + 0.9),
            0.3,
            Math.sin(angle) * (RADIUS + 0.9)
          );
          group.add(label);
          // Only the heaviest ingredients get labels — instances are cheap,
          // sprites are clutter.
          for (const ingredient of byCategory[category].slice(0, 6)) {
            if (ingredient.count < 3) continue;
            const position = ingredientPositions[ingredient.id];
            const sprite = makeSprite(ingredient.name, "#cbd5e1", 0.55);
            sprite.position.copy(position.clone().add(new THREE.Vector3(0, 0.45, 0)));
            group.add(sprite);
          }
        });
      },
      tooltipHtml: (entity) =>
        `<strong>${entity.label}</strong><br>` +
        `<span style="color:#94a3b8">${CATEGORY_LABELS[entity.meta.category] || entity.meta.category}` +
        ` · in ${entity.meta.count} drinks</span>`,
    };
    return layer;
  }

  // Typed edges: drink→spirit and drink→ingredient relations. Other layer
  // adjacencies (e.g. spirits next to ingredients with drinks hidden) have no
  // direct relation and draw nothing.
  stack.setEdges((upper, lower) => {
    const pair = [upper.id, lower.id].sort().join(":");
    const h = activeHighlight();
    const edges = [];

    const emphasis = (drinkId, otherLit) => {
      if (!h) return undefined;
      return h.drinks.has(drinkId) && otherLit ? "hi" : "lo";
    };

    if (pair === "drinks:spirits") {
      for (const drink of dataset.drinks) {
        const drinkPos = drinkPositions[drink.id];
        for (const spirit of drink.spirits) {
          const spiritPos = spiritPositions[spirit];
          if (!drinkPos || !spiritPos) continue;
          const [a, b] = upper.id === "spirits" ? [spiritPos, drinkPos] : [drinkPos, spiritPos];
          edges.push({
            a,
            b,
            color: SPIRIT_COLORS[spirit] ?? 0x64748b,
            emphasis: emphasis(drink.id, h?.spirits.has(spirit)),
          });
        }
      }
    } else if (pair === "drinks:ingredients") {
      for (const drink of dataset.drinks) {
        const drinkPos = drinkPositions[drink.id];
        for (const ingredient of drink.ingredients) {
          const ingredientPos = ingredientPositions[ingredient];
          if (!drinkPos || !ingredientPos) continue;
          const [a, b] =
            upper.id === "ingredients" ? [ingredientPos, drinkPos] : [drinkPos, ingredientPos];
          edges.push({
            a,
            b,
            color: SPIRIT_COLORS[drink.spirits[0]] ?? 0x64748b,
            emphasis: emphasis(drink.id, h?.ingredients.has(ingredient)),
          });
        }
      }
    }
    return edges;
  });

  function buildDataset(id) {
    dataset = datasets.find((d) => d.id === id) || datasets[0];
    drinkById = Object.fromEntries(dataset.drinks.map((d) => [d.id, d]));
    drinksBySpirit = {};
    drinksByIngredient = {};
    for (const drink of dataset.drinks) {
      for (const spirit of drink.spirits) {
        (drinksBySpirit[spirit] ||= new Set()).add(drink.id);
      }
      for (const ingredient of drink.ingredients) {
        (drinksByIngredient[ingredient] ||= new Set()).add(drink.id);
      }
    }
    hoverHighlight = null;
    pinnedSpirit = null;
    buildPositions();
    stack.setLayers([makeSpiritsLayer(), makeDrinksLayer(), makeIngredientsLayer()]);
    stack.refresh();
    rebuildLayerControls();
    rebuildSidebar();
    shownCount.textContent =
      `${dataset.count} drinks · ${dataset.spirits.length} spirits · ` +
      `${dataset.ingredients.length} ingredients`;
  }

  // ── Camera presets ─────────────────────────────────────────────────────
  let cameraTween = null; // {position, target}

  function flyTo(position, target) {
    cameraTween = { position, target };
  }
  renderer.domElement.addEventListener("pointerdown", () => (cameraTween = null));

  const PRESET_DISTANCE = RADIUS * 3.4;
  const presets = [
    // Near-vertical (exact vertical fights OrbitControls' polar clamp).
    ["Birds-eye", () => flyTo(new THREE.Vector3(0, PRESET_DISTANCE, 0.02), new THREE.Vector3(0, 0, 0))],
    ["Side", () => flyTo(new THREE.Vector3(PRESET_DISTANCE * 1.15, 0.5, 0), new THREE.Vector3(0, 0, 0))],
    ["3/4", () => flyTo(new THREE.Vector3(RADIUS * 2.2, RADIUS * 1.6, RADIUS * 2.6), new THREE.Vector3(0, 0, 0))],
  ];

  // ── Overlay UI: left panel ─────────────────────────────────────────────
  const panel = document.createElement("div");
  panel.style.cssText = PANEL_CSS;
  container.appendChild(panel);

  const title = document.createElement("div");
  title.style.cssText = "color:#38bdf8;font-weight:600;letter-spacing:0.05em;font-size:11px;";
  title.textContent = "COCKTAIL SPACE";
  panel.appendChild(title);

  // Dataset toggle
  if (datasets.length > 1) {
    const datasetRow = document.createElement("div");
    datasetRow.style.cssText = "display:flex;flex-direction:column;gap:4px;";
    for (const d of datasets) {
      const label = document.createElement("label");
      label.style.cssText = "display:flex;align-items:center;gap:6px;cursor:pointer;";
      const radio = document.createElement("input");
      radio.type = "radio";
      radio.name = "cocktail-dataset";
      radio.checked = d.id === dataset.id;
      radio.addEventListener("change", () => {
        if (radio.checked) buildDataset(d.id);
      });
      label.append(radio, `${d.label} (${d.count})`);
      datasetRow.appendChild(label);
    }
    panel.appendChild(datasetRow);
  }

  // Camera preset buttons
  const presetRow = document.createElement("div");
  presetRow.style.cssText = "display:flex;gap:4px;";
  for (const [label, action] of presets) {
    const button = document.createElement("button");
    button.textContent = label;
    button.style.cssText =
      "flex:1;border-radius:4px;padding:3px 0;font-size:11px;cursor:pointer;" +
      "background:#1e293b;color:#94a3b8;border:1px solid #334155;";
    button.addEventListener("click", action);
    presetRow.appendChild(button);
  }
  panel.appendChild(presetRow);

  // Layer visibility + reorder
  const layerControls = document.createElement("div");
  layerControls.style.cssText = "display:flex;flex-direction:column;gap:6px;";
  panel.appendChild(layerControls);

  function rebuildLayerControls() {
    layerControls.innerHTML = "";
    const layers = stack.layers();
    layers.forEach((layer, index) => {
      const row = document.createElement("div");
      row.style.cssText =
        "display:flex;align-items:center;gap:5px;border-top:1px solid #1e293b;padding-top:5px;";

      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.checked = layer.visible;
      checkbox.addEventListener("change", () => {
        layer.visible = checkbox.checked;
        stack.refresh();
      });

      const name = document.createElement("span");
      name.style.cssText = "flex:1;color:#e2e8f0;font-size:11px;";
      name.textContent = layer.title;
      row.append(checkbox, name);

      for (const [arrow, delta] of [["↑", -1], ["↓", 1]]) {
        const button = document.createElement("button");
        button.textContent = arrow;
        button.style.cssText =
          "background:#1e293b;color:#94a3b8;border:1px solid #334155;border-radius:3px;" +
          "font-size:10px;cursor:pointer;padding:0 5px;";
        const target = index + delta;
        button.disabled = target < 0 || target >= layers.length;
        if (button.disabled) button.style.opacity = "0.3";
        button.addEventListener("click", () => {
          [layers[index], layers[target]] = [layers[target], layers[index]];
          rebuildLayerControls();
          stack.refresh();
        });
        row.appendChild(button);
      }
      layerControls.appendChild(row);
    });
  }

  const shownCount = document.createElement("div");
  shownCount.style.cssText = "color:#64748b;font-size:11px;";
  panel.appendChild(shownCount);

  // ── Overlay UI: right sidebar (browsable spirit list) ──────────────────
  const sidebar = document.createElement("div");
  sidebar.style.cssText = SIDEBAR_CSS;
  container.appendChild(sidebar);

  function rebuildSidebar() {
    sidebar.innerHTML = "";
    const heading = document.createElement("div");
    heading.style.cssText = "color:#38bdf8;font-weight:600;letter-spacing:0.05em;font-size:11px;";
    heading.textContent = "SPIRITS";
    sidebar.appendChild(heading);

    for (const spirit of dataset.spirits) {
      const row = document.createElement("div");
      const pinned = pinnedSpirit === spirit.id;
      row.style.cssText =
        "display:flex;align-items:center;gap:6px;cursor:pointer;padding:3px 4px;border-radius:4px;" +
        (pinned ? "background:#1e3a5f;color:#e2e8f0;" : "color:#94a3b8;");
      const swatch = document.createElement("span");
      swatch.style.cssText =
        "width:10px;height:10px;border-radius:50%;display:inline-block;" +
        `background:${hexColor(SPIRIT_COLORS[spirit.id] ?? 0x64748b)};`;
      const name = document.createElement("span");
      name.style.cssText = "flex:1;";
      name.textContent = spirit.name;
      const count = document.createElement("span");
      count.style.cssText = "color:#64748b;font-size:10px;";
      count.textContent = spirit.count;
      row.append(swatch, name, count);

      row.addEventListener("mouseenter", () => {
        hoverHighlight = highlightForSpirit(spirit.id);
        applyHighlight();
      });
      row.addEventListener("mouseleave", () => {
        hoverHighlight = null;
        applyHighlight();
      });
      row.addEventListener("click", () => {
        pinnedSpirit = pinnedSpirit === spirit.id ? null : spirit.id;
        rebuildSidebar();
        applyHighlight();
      });
      sidebar.appendChild(row);

      // Pinned spirit expands into its browsable drink list.
      if (pinned) {
        const list = document.createElement("div");
        list.style.cssText =
          "display:flex;flex-direction:column;gap:1px;max-height:38vh;overflow-y:auto;" +
          "margin:2px 0 4px 12px;padding-right:4px;";
        const drinkIds = [...(drinksBySpirit[spirit.id] || [])].sort((a, b) =>
          drinkById[a].name.localeCompare(drinkById[b].name)
        );
        for (const drinkId of drinkIds) {
          const drinkRow = document.createElement("div");
          drinkRow.style.cssText =
            "color:#94a3b8;font-size:11px;cursor:pointer;padding:1px 4px;border-radius:3px;";
          drinkRow.textContent = drinkById[drinkId].name;
          drinkRow.addEventListener("mouseenter", () => {
            drinkRow.style.background = "#1e293b";
            drinkRow.style.color = "#e2e8f0";
            hoverHighlight = highlightForDrink(drinkId);
            applyHighlight();
          });
          drinkRow.addEventListener("mouseleave", () => {
            drinkRow.style.background = "transparent";
            drinkRow.style.color = "#94a3b8";
            hoverHighlight = null;
            applyHighlight();
          });
          list.appendChild(drinkRow);
        }
        sidebar.appendChild(list);
      }
    }
  }

  window.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && pinnedSpirit) {
      pinnedSpirit = null;
      rebuildSidebar();
      applyHighlight();
    }
  });

  // ── Canvas hover: tooltip + highlight ──────────────────────────────────
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();

  renderer.domElement.addEventListener("mousemove", (event) => {
    const rect = renderer.domElement.getBoundingClientRect();
    pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);

    const picked = stack.pick(raycaster);
    let html = null;
    let nextHighlight = null;

    if (picked) {
      html = picked.layer.tooltipHtml?.(picked.entity);
      if (picked.layer.id === "spirits") nextHighlight = highlightForSpirit(picked.entity.key);
      else if (picked.layer.id === "drinks") nextHighlight = highlightForDrink(picked.entity.key);
      else if (picked.layer.id === "ingredients")
        nextHighlight = highlightForIngredient(picked.entity.key);
    }

    const changed =
      JSON.stringify(nextHighlight && [...nextHighlight.drinks].sort()) !==
      JSON.stringify(hoverHighlight && [...hoverHighlight.drinks].sort());
    hoverHighlight = nextHighlight;
    if (changed) applyHighlight();

    if (html) {
      tooltip.innerHTML = html;
      tooltip.style.display = "block";
      tooltip.style.left = event.clientX - rect.left + 14 + "px";
      tooltip.style.top = event.clientY - rect.top + 10 + "px";
    } else {
      tooltip.style.display = "none";
    }
  });

  renderer.domElement.addEventListener("mouseleave", () => {
    if (hoverHighlight) {
      hoverHighlight = null;
      applyHighlight();
    }
    tooltip.style.display = "none";
  });

  buildDataset(dataset.id);

  renderer.setAnimationLoop(() => {
    controls.update();
    if (cameraTween) {
      camera.position.lerp(cameraTween.position, 0.08);
      controls.target.lerp(cameraTween.target, 0.08);
      if (camera.position.distanceTo(cameraTween.position) < 0.05) cameraTween = null;
    }
    stack.tick();
    renderer.render(scene, camera);
  });
}
