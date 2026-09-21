// /atlas — "Spacetime": every activity and every entity as a point in ONE scene,
// with the timeline, the map and the graph as LAYOUTS of those points rather
// than separate pictures. Switching layout tweens each point to its new place,
// so a 2D view is visibly a slice of the volume and not a different drawing.
//
// The server decides every position (Indivisual.Atlas.Scene); this file only
// draws and moves what it is handed.
//
// Data contract, parsed from the hook element's data attributes:
//   layout:  "timeline" | "moment" | "map" | "graph" | "space"
//   kinds:   which node kinds to draw (all, when empty)
//
// The sticky timeline is the same COMPONENT in its flat variant, drawn by
// atlas_timeline_strip.js: a band has different needs (pixel layout, zoom along
// time, year and month markers) from a volume you orbit.
//   span:    { from: ms, to: ms } | null — the moments z = -1 and z = 1 stand for
//   nodes:   [{ id, kind: "event" | "entity", label, pos: { layout: [x,y,z] },
//               placed: { layout: bool }, color?, date?, truth?, selected?, focused?,
//               read? — false when the filters exclude it: drawn quiet, never dropped }]
//   links:   [{ from: "kind:id", to: "kind:id", kind: "relationship" | "touches", color? }]
//   ground:  bool — x is longitude and y is latitude, so there is a map to stand
//            on (the Map preset, or any custom mode with those two axes)
//   map:     { cx, cy, half } | null — the square of ground under the `map`
//            layout, in Web Mercator world units (0..1); x,y = -1..1 span it
//   frames:  { layout: { center: [x,y,z], size: [x,y,z] } } — the box each layout
//            draws its 2D space in, flat along the axis it does not use
//
// Axes: in every data layout x and y are the layout's 2D space and Z IS TIME
// (-1 earliest … 1 latest). `timeline` is that seen from the side; `moment` is a
// plane cutting z at one instant.

import * as THREE from "three";
import { createStage, makeSprite } from "./three_stage";

const SCALE = 4; // scene units → world units
const TWEEN_MS = 900;
const CLICK_SLOP = 4;
const DAY = 86_400_000;
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// Where the camera stands for each layout. Time is z, so the timeline is seen
// from the SIDE (from -x, which puts later on the right), and the layouts that
// arrange x and y are seen from the front, a little off-axis so the depth of
// time behind and ahead of the plane still reads.
const CAMERAS = {
  space: { position: [9.5, 6.5, 12], target: [0, 0, 0] },
  // Square-on, like the map from above: the timeline is one flat picture.
  timeline: { position: [-12, 1.2, 0], target: [0, 1.2, 0] },
  moment: { position: [5, 2.4, 12.5], target: [0, -0.4, 0] },
  graph: { position: [5.5, 2.5, 11], target: [0, 0, -1.5] },
  // Bird's-eye: straight down at the ground, as a map is read. The Map has no
  // time axis, so everything lies in the plane z = 0.
  map: { position: [0, 0, 12], target: [0, 0, 0] },
};

// `moment`'s plane moves along z with the selection, and its camera goes with it.
// A reader's own choice of axes has no preset to stand at, so it is read off the
// frame: face whichever axis was folded flat, or stand three-quarter if none was.
function standFor(frame) {
  const [sx, sy, sz] = frame?.size || [2, 2, 2];
  if (sx === 0) return CAMERAS.timeline; // flat in x: from the side
  if (sz === 0) return { position: [0, 0.6, 13], target: [0, 0, 0] }; // flat in z: from the front
  if (sy === 0) return { position: [0, 13, 0.01], target: [0, 0, 0] }; // flat in y: from above
  return CAMERAS.space;
}

function cameraFor(layout, frame, strip) {
  // The timeline stands where its whole height just fits (see `fitStrip`).
  const preset =
    layout === "timeline" && strip
      ? { position: [-strip.distance, strip.centerY, 0], target: [0, strip.centerY, 0] }
      : CAMERAS[layout] || standFor(frame);
  if (!preset) return null;
  const dz = layout === "moment" && frame ? frame.center[2] * SCALE : 0;

  return {
    position: new THREE.Vector3(preset.position[0], preset.position[1], preset.position[2] + dz),
    target: new THREE.Vector3(preset.target[0], preset.target[1], preset.target[2] + dz),
  };
}

const eventGeometry = new THREE.SphereGeometry(0.1, 18, 12);
const entityGeometry = new THREE.OctahedronGeometry(0.17);

// An entity whose kind has an icon (a person, a map pin) is drawn AS that icon: a
// sprite, so it always faces the reader. The glyph is white on the texture and
// takes its colour from the material, so state is a tint like any other node's.
// The path data comes from the server (one icon set for the page), is a 20×20
// heroicon, and is drawn with a dark keyline so it holds against map tiles.
const ICON_PX = 96;
const ICON_SIZE = 0.46; // scene units, a little over the octahedron it replaces
const iconTextures = new Map();

function iconTexture(kind, icon) {
  if (iconTextures.has(kind)) return iconTextures.get(kind);

  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = ICON_PX;
  const ctx = canvas.getContext("2d");
  const path = new Path2D(icon.d);
  const k = (ICON_PX - 12) / 20;

  ctx.translate(6, 6);
  ctx.scale(k, k);
  ctx.lineJoin = "round";
  ctx.lineWidth = 2.2;
  ctx.strokeStyle = "rgba(2, 6, 23, 0.9)";
  ctx.stroke(path);
  ctx.fillStyle = "#ffffff";
  ctx.fill(path, icon.rule === "evenodd" ? "evenodd" : "nonzero");

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  iconTextures.set(kind, texture);
  return texture;
}

const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const keyOf = (node) => `${node.kind}:${node.id}`;

export function createScene(container, { onSelectEvent, onFocusEntity, kinds = null } = {}) {
  // The scene is drawn on the page's own paper, in its inks — the same ground as
  // the sticky timeline and everything else on the page — rather than as a dark
  // stage of its own. The truth palette was chosen for ink on paper, so it is
  // used as it comes.
  const css = getComputedStyle(container);
  const token = (name, fallback) => css.getPropertyValue(name).trim() || fallback;
  const theme = {
    paper: token("--paper", "#ffffff"),
    ink: token("--ink", "#111111"),
    soft: token("--ink-soft", "#555555"),
    faint: token("--ink-faint", "#888888"),
    rule: token("--rule", "#dddddd"),
    link: token("--link", "#0000cc"),
  };

  const stage = createStage(container, {
    cameraPosition: CAMERAS.moment.position,
    fog: [22, 60],
    background: new THREE.Color(theme.paper).getHex(),
  });
  const { scene, camera, renderer, controls, tooltip } = stage;
  controls.enablePan = false;
  controls.minDistance = 4;
  controls.maxDistance = 30;
  controls.target.set(...CAMERAS.moment.target);

  const nodesGroup = new THREE.Group();
  const labelsGroup = new THREE.Group();
  const guideGroup = new THREE.Group();
  scene.add(guideGroup, nodesGroup, labelsGroup);

  // Two line sets, redrawn from the points every frame so they follow a tween.
  const lineSet = (color, opacity) => {
    const lines = new THREE.LineSegments(
      new THREE.BufferGeometry(),
      new THREE.LineBasicMaterial({ color, transparent: true, opacity })
    );
    lines.frustumCulled = false;
    scene.add(lines);
    return lines;
  };
  const relationshipLines = lineSet(theme.ink, 0.7);
  const touchLines = lineSet(theme.faint, 0.35);

  const halo = new THREE.Mesh(
    new THREE.SphereGeometry(0.3, 12, 8),
    new THREE.MeshBasicMaterial({ color: theme.link, wireframe: true, transparent: true, opacity: 0.45 })
  );
  halo.visible = false;
  scene.add(halo);

  const items = new Map(); // "kind:id" -> { mesh, label?, from, to, node }
  let links = [];
  let layout = null;
  let tweenStart = null;
  let cameraTween = null;
  let reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ── guides: ONE frame that morphs, and axes that travel with it ─────────
  // Every layout's 2D space is the same box at different proportions: a cube for
  // the volume, flat in z for a slice you face, flat in x for the timeline you
  // see side-on. So the frame is one unit cube, scaled and moved by the same
  // tween as the points — cube to square to timeline to map to graph — and the
  // axes are its children, so they collapse and extend with it.
  function disposeGroup(group) {
    group.traverse((child) => {
      child.geometry?.dispose();
      child.material?.map?.dispose();
      child.material?.dispose();
    });
    group.clear();
  }

  const FLAT = 0.0001; // a scale of exactly 0 makes a singular matrix

  // The whole span of x, y and time, always there and faint: the volume every
  // frame is a cut through.
  const volume = new THREE.LineSegments(
    new THREE.EdgesGeometry(new THREE.BoxGeometry(SCALE * 2, SCALE * 2, SCALE * 2)),
    new THREE.LineBasicMaterial({ color: theme.rule, transparent: true })
  );

  const frameBox = new THREE.Group();
  frameBox.add(
    new THREE.LineSegments(
      new THREE.EdgesGeometry(new THREE.BoxGeometry(1, 1, 1)),
      new THREE.LineBasicMaterial({ color: theme.soft })
    )
  );
  [
    [1, 0, 0],
    [0, 1, 0],
    [0, 0, 1],
  ].forEach(([x, y, z]) => {
    const half = new THREE.Vector3(x, y, z).multiplyScalar(0.5);
    frameBox.add(
      new THREE.Line(
        new THREE.BufferGeometry().setFromPoints([half.clone().negate(), half]),
        new THREE.LineBasicMaterial({ color: theme.faint })
      )
    );
  });

  scene.add(volume, frameBox);

  // ── the timeline is a STRIP ──────────────────────────────────────────────
  // Time runs -1..1 like every other axis, which makes the Timeline layout about
  // as tall as it is wide: events stack up and entities hang down from one axis.
  // In a wide window that leaves the axis crossing under half of it. So in this
  // layout time is STRETCHED until the picture has the window's own proportions,
  // and the camera stands where the whole height just fits: the first and last
  // moments then sit at the window's left and right edges. Everything drawn
  // along time in this layout — points, the ruled axis, the frame, the pan limit
  // — goes through `timeZ`, so they cannot disagree.
  const strip = { stretch: 1, centerY: 1.2, distance: 12 };
  let lastNodes = [];
  let lastSpan = null;
  let lastFrames = {};

  function fitStrip(nodes) {
    const ys = (nodes || []).map((n) => n.pos?.timeline?.[1]).filter((y) => typeof y === "number");
    const top = ys.length ? Math.max(...ys) : 1;
    const bottom = ys.length ? Math.min(...ys) : -1;
    // Room for labels under the lowest entity and above the tallest stack.
    // Entity labels hang a line BELOW their point, so the bottom needs more than the top.
    const height = Math.max((top - bottom) * SCALE, SCALE) * 1.32;
    const aspect = Math.max(container.clientWidth / Math.max(container.clientHeight, 1), 0.5);

    strip.centerY = ((top + bottom) / 2) * SCALE - 0.35;
    strip.distance = height / 2 / Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    // The axis ends reach toward the window's edges, short of them by the half-width
    // of a label: entities at the first and last moment are named there, centred on
    // their point, and a name cut in half is worse than a margin.
    strip.stretch = THREE.MathUtils.clamp((height * aspect * 0.8) / (SCALE * 2), 1, 6);
  }

  const timeZ = (z) => (layout === "timeline" ? z * strip.stretch : z);

  const box = (f, forLayout = layout) => {
    const size = new THREE.Vector3(...(f?.size || [2, 2, 2])).multiplyScalar(SCALE);
    if (forLayout === "timeline") size.z *= strip.stretch;

    return {
      center: new THREE.Vector3(...(f?.center || [0, 0, 0])).multiplyScalar(SCALE),
      size,
    };
  };

  let frameFrom = box(null);
  let frameTo = box(null);
  const frameNow = box(null);
  let axisLabels = []; // [{ sprite, axis }]

  // What each axis MEANS is said in the axes bar under the stage, in the DOM,
  // where it can be read and changed. In the scene an axis carries only its
  // letter, at its positive end, so the bar's x, y and z can be found in it.
  function labelAxes() {
    if (axisLabels.length) return;

    ["x", "y", "z"].forEach((axis) => {
      const sprite = makeSprite(axis, theme.soft, 0.7);
      guideGroup.add(sprite);
      axisLabels.push({ sprite, axis });
    });
  }

  function placeFrame(k) {
    frameNow.center.lerpVectors(frameFrom.center, frameTo.center, k);
    frameNow.size.lerpVectors(frameFrom.size, frameTo.size, k);

    frameBox.position.copy(frameNow.center);
    frameBox.scale.set(
      Math.max(frameNow.size.x, FLAT),
      Math.max(frameNow.size.y, FLAT),
      Math.max(frameNow.size.z, FLAT)
    );

    // A label sits past the positive end of its axis, low and to the near side
    // so it clears the points. Where the frame is flat along a labelled axis
    // (time, in a slice), the label goes to the end of the whole volume instead.
    const reach = (size) => (size > 0.01 ? size / 2 : SCALE) * 1.18;

    axisLabels.forEach(({ sprite, axis }) => {
      const p = frameNow.center.clone();
      if (axis === "x") p.add(new THREE.Vector3(reach(frameNow.size.x), -frameNow.size.y / 2 - 0.4, 0));
      if (axis === "y") p.add(new THREE.Vector3(-frameNow.size.x / 2 - 0.4, reach(frameNow.size.y), 0));
      if (axis === "z") {
        p.z = reach(frameNow.size.z) + (frameNow.size.z > 0.01 ? frameNow.center.z : 0);
        p.y = frameNow.center.y - frameNow.size.y / 2 - 0.4;
      }
      sprite.position.copy(p);
    });
  }

  // ── the timeline's rule: years, months and "now", IN the scene ───────────
  // The Timeline layout is this same scene seen from the side, so it keeps the
  // journey from the other layouts — and it is ruled like the sticky strip: an
  // axis along time, a tall tick and a label at each year, short ticks at the
  // months (named when there is room), and a red tick at the present. It lies in
  // the plane the layout folds onto (x = 0), just under the events, and fades
  // in and out with the layout.
  const rule = new THREE.Group();
  scene.add(rule);
  let ruleKey = null;
  let ruleOpacity = 0;

  function clearRule() {
    rule.traverse((child) => {
      child.geometry?.dispose();
      child.material?.map?.dispose();
      child.material?.dispose();
    });
    rule.clear();
  }

  function ruleLine(from, to, color) {
    const line = new THREE.Line(
      new THREE.BufferGeometry().setFromPoints([from, to]),
      new THREE.LineBasicMaterial({ color, transparent: true, opacity: 0 })
    );
    line.userData.opacity = 1;
    rule.add(line);
    return line;
  }

  function ruleLabel(text, color, scale, z, y) {
    const sprite = makeSprite(text, color, scale);
    sprite.material.opacity = 0;
    sprite.userData.opacity = 1;
    sprite.position.set(0, y, z);
    rule.add(sprite);
  }

  function drawRule(span) {
    const key = span ? `${span.from}-${span.to}-${layout === "timeline" ? strip.stretch.toFixed(3) : 1}` : null;
    if (key === ruleKey) return;
    ruleKey = key;
    clearRule();
    if (!span) return;

    // z = -1 is the first moment in view, z = 1 the last.
    const extent = Math.max(span.to - span.from, 1);
    const zOf = (ms) => timeZ((((ms - span.from) / extent) * 2 - 1) * SCALE);
    const pad = timeZ(SCALE) + SCALE * 0.12;

    ruleLine(new THREE.Vector3(0, 0, -pad), new THREE.Vector3(0, 0, pad), theme.ink);

    const months = extent / (DAY * 30.44);
    const start = new Date(span.from);
    const cursor = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), 1));

    for (let i = 0; i < 600 && cursor.getTime() <= span.to + DAY * 31; i++) {
      const ms = cursor.getTime();
      const month = cursor.getUTCMonth();
      const z = zOf(ms);

      if (Math.abs(z) <= pad) {
        if (month === 0) {
          ruleLine(new THREE.Vector3(0, -0.42, z), new THREE.Vector3(0, SCALE * 1.05, z), theme.faint);
          ruleLabel(`${cursor.getUTCFullYear()}`, theme.ink, 0.62, z + 0.32, -0.3);
        } else if (months <= 72) {
          // Every month while there are few enough to tell apart; quarters named
          // first, every month once a month is wide enough for its name.
          ruleLine(new THREE.Vector3(0, month % 3 === 0 ? -0.24 : -0.14, z), new THREE.Vector3(0, 0, z), theme.faint);
          if (months <= 14 || (months <= 40 && month % 3 === 0)) {
            ruleLabel(MONTHS[month], theme.soft, 0.46, z + 0.26, -0.3);
          }
        }
      }

      cursor.setUTCMonth(month + 1);
    }

    const now = zOf(Date.now());
    if (Math.abs(now) <= pad) {
      ruleLine(new THREE.Vector3(0, -0.42, now), new THREE.Vector3(0, SCALE * 1.05, now), "#cc0000");
      ruleLabel("now", "#cc0000", 0.5, now - 0.3, SCALE * 1.0);
    }
  }

  function fadeRule() {
    const want = layout === "timeline" ? 1 : 0;
    ruleOpacity += (want - ruleOpacity) * 0.1;
    rule.visible = ruleOpacity > 0.01;
    rule.children.forEach((child) => {
      child.material.opacity = ruleOpacity * (child.userData.opacity ?? 1);
    });
  }

  // ── the ground: a slippy map on the `map` layout's plane ────────────────
  // The server lays the map out in Web Mercator and says which square of the
  // world the frame covers, so ordinary map tiles fit the plane and a pin lands
  // on its street. It behaves as a web map does: seen from directly above, drag
  // to pan, scroll to zoom, and tiles are chosen from WHAT IS ON SCREEN — the
  // zoom level from how big a tile would be drawn, the tiles from the rectangle
  // in view — loaded as the view moves and dropped once they are out of it.
  const TILE_URL = (z, x, y) => `https://tile.openstreetmap.org/${z}/${x}/${y}.png`;
  const TILE_PX = 256; // draw a tile at about its native size
  const MAX_TILES = 80;
  const PAN_LIMIT = SCALE * 4; // how far the view may wander from the data

  const ground = new THREE.Group();
  scene.add(ground);
  const tileLoader = new THREE.TextureLoader();
  tileLoader.setCrossOrigin("anonymous");
  const tiles = new Map(); // "z/x/y" -> mesh
  let mapView = null; // { cx, cy, half }: the world square the frame covers
  let groundOn = false; // x is longitude and y is latitude: there is a map to lay
  let groundOpacity = 0;
  let tilesDue = null;

  function dropTile(key) {
    const tile = tiles.get(key);
    if (!tile) return;
    ground.remove(tile);
    tile.geometry.dispose();
    tile.material.map?.dispose();
    tile.material.dispose();
    tiles.delete(key);
  }

  function clearGround() {
    [...tiles.keys()].forEach(dropTile);
  }

  function setGround(view, z) {
    ground.position.z = z * SCALE - 0.02; // a hair behind the pins standing on it
    const changed = JSON.stringify(view) !== JSON.stringify(mapView);
    mapView = view;
    if (changed) clearGround();
  }

  // The rectangle of the WORLD on screen, from a camera looking straight down
  // the time axis at the ground.
  function worldInView() {
    const distance = camera.position.z - ground.position.z;
    const halfH = distance * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    const halfW = halfH * camera.aspect;
    const toWorld = mapView.half / SCALE;

    return {
      x0: mapView.cx + (controls.target.x - halfW) * toWorld,
      x1: mapView.cx + (controls.target.x + halfW) * toWorld,
      // World y runs south; scene y runs north.
      y0: mapView.cy - (controls.target.y + halfH) * toWorld,
      y1: mapView.cy - (controls.target.y - halfH) * toWorld,
      height: halfH * 2 * toWorld,
    };
  }

  // Under an orbiting camera (a custom mode on a map) there is no tidy rectangle
  // "in view", so the ground is simply the frame and a margin round it.
  function worldRoundFrame() {
    const reach = mapView.half * 1.6;
    return {
      x0: mapView.cx - reach,
      x1: mapView.cx + reach,
      y0: mapView.cy - reach,
      y1: mapView.cy + reach,
      height: mapView.half * 2,
    };
  }

  function refreshTiles() {
    tilesDue = null;
    if (!groundOn || !mapView) return;

    // Bird's-eye (the Map preset) loads what is on screen, as a web map does.
    const view = layout === "map" ? worldInView() : worldRoundFrame();
    const px = renderer.domElement.clientHeight || 1;
    // The zoom at which a tile is drawn at about TILE_PX on screen.
    let zoom = Math.round(Math.log2(px / TILE_PX / view.height));
    zoom = Math.max(0, Math.min(19, zoom));

    let n, x0, x1, y0, y1;
    // Too many to fetch politely: step out a level until it is not.
    for (; zoom >= 0; zoom--) {
      n = 2 ** zoom;
      x0 = Math.floor(view.x0 * n);
      x1 = Math.floor(view.x1 * n);
      y0 = Math.max(0, Math.floor(view.y0 * n));
      y1 = Math.min(n - 1, Math.floor(view.y1 * n));
      if ((x1 - x0 + 1) * (y1 - y0 + 1) <= MAX_TILES) break;
    }
    if (zoom < 0) return;

    const wanted = new Set();
    const side = (1 / n / mapView.half) * SCALE;

    for (let tx = x0; tx <= x1; tx++) {
      for (let ty = y0; ty <= y1; ty++) {
        const key = `${zoom}/${tx}/${ty}`;
        wanted.add(key);
        if (tiles.has(key)) continue;

        const material = new THREE.MeshBasicMaterial({
          transparent: true,
          opacity: 0,
          // Drawn for white paper, which this is — only eased back a little so
          // the points and their colours stay in front of the streets.
          color: 0xd9dde3,
          depthWrite: false,
        });
        const tile = new THREE.Mesh(new THREE.PlaneGeometry(side, side), material);
        tile.position.set(
          (((tx + 0.5) / n - mapView.cx) / mapView.half) * SCALE,
          -(((ty + 0.5) / n - mapView.cy) / mapView.half) * SCALE,
          0
        );
        // Finer tiles draw over coarser ones still waiting to be replaced.
        tile.renderOrder = zoom;
        tile.userData = { loaded: false, zoom };
        tiles.set(key, tile);
        ground.add(tile);

        // Longitude wraps; latitude does not.
        tileLoader.load(TILE_URL(zoom, ((tx % n) + n) % n, ty), (texture) => {
          if (!tiles.has(key)) return texture.dispose(); // dropped while loading
          texture.colorSpace = THREE.SRGBColorSpace;
          material.map = texture;
          material.needsUpdate = true;
          tile.userData.loaded = true;
        });
      }
    }

    // Tiles no longer wanted stay until what replaces them has arrived, so a
    // zoom does not flash to black; then they go.
    const arrived = [...wanted].every((key) => tiles.get(key)?.userData.loaded);
    for (const key of [...tiles.keys()]) {
      if (!wanted.has(key) && (arrived || tiles.size > MAX_TILES * 2)) dropTile(key);
    }
    if (!arrived) tilesDue = setTimeout(refreshTiles, 250);
  }

  // Debounced: a drag or a scroll fires many changes; fetch for where it settles.
  function tilesSoon() {
    if (layout !== "map") return; // only the bird's-eye view changes what is wanted
    clearTimeout(tilesDue);
    tilesDue = setTimeout(refreshTiles, 120);
  }
  controls.addEventListener("change", tilesSoon);

  // The layouts that are one flat picture — the map from directly above, the
  // timeline square-on — are read as a page is: no turning, drag pans, scroll
  // zooms. Turning either would only show it edge-on.
  const FLAT_LAYOUTS = { map: ["x", "y"], timeline: ["z", "y"] }; // the axes a drag moves along

  function mapControls(on) {
    controls.enableRotate = !on;
    controls.enablePan = on;
    controls.screenSpacePanning = true;
    controls.mouseButtons.LEFT = on ? THREE.MOUSE.PAN : THREE.MOUSE.ROTATE;
    controls.touches.ONE = on ? THREE.TOUCH.PAN : THREE.TOUCH.ROTATE;
    controls.minDistance = on ? 1.2 : 4;
  }

  function fadeGround() {
    // Present only in the Map layout, arriving and leaving with the morph.
    const want = groundOn ? 0.9 : 0;
    groundOpacity += (want - groundOpacity) * 0.12;
    ground.visible = groundOpacity > 0.01;
    for (const tile of tiles.values()) {
      const target = tile.userData.loaded ? groundOpacity : 0;
      tile.material.opacity += (target - tile.material.opacity) * 0.2;
    }

    // Wandering is fine; getting lost is not.
    if (FLAT_LAYOUTS[layout] && tweenStart === null) {
      const limit = layout === "map" ? PAN_LIMIT : SCALE * 1.6;
      const along = (axis) => (layout === "timeline" && axis === "z" ? timeZ(limit) : limit);

      FLAT_LAYOUTS[layout].forEach((axis) => {
        const held = THREE.MathUtils.clamp(controls.target[axis], -along(axis), along(axis));
        camera.position[axis] += held - controls.target[axis];
        controls.target[axis] = held;
      });
    }
  }

  // The links and the faint cube belong to the volume. In the timeline they are
  // clutter — a band of dated events has nothing to be joined to and no box
  // round it — so they fade out there and back in elsewhere.
  let linkOpacity = 1;

  function fadeLinks() {
    const want = layout === "timeline" ? 0 : 1;
    linkOpacity += (want - linkOpacity) * 0.12;
    relationshipLines.material.opacity = 0.7 * linkOpacity;
    touchLines.material.opacity = 0.35 * linkOpacity;
    relationshipLines.visible = touchLines.visible = linkOpacity > 0.01;
    volume.material.opacity = linkOpacity;
    volume.visible = linkOpacity > 0.01;
  }

  // ── nodes ────────────────────────────────────────────────────────────────
  let icons = {}; // entity kind -> { d, rule }, from the server

  function target(node) {
    const [x, y, z] = node.pos[layout] || [0, 0, 0];

    return new THREE.Vector3(x * SCALE, y * SCALE, timeZ(z * SCALE));
  }

  function style(item) {
    const { node, mesh, label } = item;
    const placed = node.placed?.[layout] !== false;

    if (node.kind === "event") {
      // The truth palette was chosen for ink on paper; lift it against near-black.
      mesh.material.color.set(node.color || theme.soft);
      mesh.material.emissive.copy(mesh.material.color).multiplyScalar(0.5);
      mesh.scale.setScalar(node.selected ? 1.7 : 1);
      if (node.read === false) mesh.material.emissive.multiplyScalar(0.3);
    } else {
      // The same two state colours as everywhere else an entity is drawn:
      // FOCUSED (open in the reader) is amber, AFFECTED by the selected event is
      // blue. Focus wins when both hold. Blue is lifted for the dark stage.
      const tint = node.focused ? 0xd97706 : node.affected ? 0x60a5fa : theme.ink;
      mesh.material.color.set(tint);
      mesh.material.emissive?.set(tint); // sprites have no emissive
      mesh.scale.setScalar((item.base || 1) * (node.focused ? 1.4 : node.affected ? 1.2 : 1));
    }

    // Three ways a point can be present without being part of the picture, in
    // order of how far back it stands:
    //   filtered  the filters exclude it — it keeps its place and loses its ink
    //   shelved   the layout cannot place it (no location, no score)
    //   off-slice in `moment`, it happened at another time: context
    // Drawing a filtered point rather than removing it is what keeps the scene
    // the same picture as the reader narrows it.
    const filtered = node.read === false;
    const offSlice = layout === "moment" && node.kind === "event" && node.in_slice === false;

    mesh.material.opacity = !placed ? 0.22 : filtered ? 0.18 : offSlice ? 0.45 : 1;
    if (label) label.material.opacity = !placed ? 0.3 : filtered ? 0.25 : 0.95;
  }

  function sync(nodes) {
    const seen = new Set();

    nodes.forEach((node) => {
      if (kinds && !kinds.includes(node.kind)) return;
      const key = keyOf(node);
      seen.add(key);
      let item = items.get(key);

      if (!item) {
        const icon = node.kind === "entity" && icons[node.entity_kind];
        let mesh;
        let base = 1;

        if (icon) {
          mesh = new THREE.Sprite(
            new THREE.SpriteMaterial({
              map: iconTexture(node.entity_kind, icon),
              transparent: true,
              depthTest: false,
            })
          );
          base = ICON_SIZE;
          // A pin stands ON its place: its tip, not its middle, is the position.
          if (node.entity_kind === "place") mesh.center.set(0.5, 0.05);
          // Above the ground: tiles take `renderOrder = zoom` (up to ~19), and a
          // sprite that does not depth-test would otherwise be painted over by them.
          mesh.renderOrder = 100;
        } else {
          mesh = new THREE.Mesh(
            node.kind === "event" ? eventGeometry : entityGeometry,
            new THREE.MeshStandardMaterial({ roughness: 0.45, transparent: true })
          );
        }

        let label = null;

        if (node.kind === "entity") {
          label = makeSprite(node.label, theme.soft, 0.62);
          label.material.transparent = true;
          labelsGroup.add(label);
        }

        item = { mesh, label, node, base, from: target(node), to: target(node) };
        mesh.position.copy(item.to);
        items.set(key, item);
        nodesGroup.add(mesh);
      }

      item.node = node;
      item.mesh.userData = node;
      item.from = item.mesh.position.clone();
      item.to = target(node);
      style(item);
    });

    // What left the lens leaves the scene.
    for (const [key, item] of items) {
      if (seen.has(key)) continue;
      nodesGroup.remove(item.mesh);
      item.mesh.material.dispose();
      if (item.label) {
        labelsGroup.remove(item.label);
        item.label.material.map?.dispose();
        item.label.material.dispose();
      }
      items.delete(key);
    }
  }

  function writeLines(lines, kind) {
    const points = [];

    links.forEach((link) => {
      if (link.kind !== kind) return;
      const a = items.get(link.from);
      const b = items.get(link.to);
      if (!a || !b) return;
      points.push(a.mesh.position, b.mesh.position);
    });

    // NOT `geometry.setFromPoints`: once a geometry has a position buffer,
    // three.js writes into it at its ORIGINAL size — extra lines are silently
    // dropped and removed ones stay on screen as stale segments. So the buffer
    // is ours: grown when it must be, and only the live part is drawn.
    const needed = points.length * 3;
    let position = lines.geometry.getAttribute("position");

    if (!position || position.array.length < needed) {
      lines.geometry.dispose();
      lines.geometry = new THREE.BufferGeometry();
      position = new THREE.BufferAttribute(new Float32Array(Math.max(needed * 2, 96)), 3);
      position.setUsage(THREE.DynamicDrawUsage);
      lines.geometry.setAttribute("position", position);
    }

    points.forEach((point, i) => position.setXYZ(i, point.x, point.y, point.z));
    position.needsUpdate = true;
    lines.geometry.setDrawRange(0, points.length);
  }

  function place(progress) {
    const k = ease(progress);
    placeFrame(k);

    for (const item of items.values()) {
      item.mesh.position.lerpVectors(item.from, item.to, k);

      if (item.label) {
        item.label.position.copy(item.mesh.position);
        item.label.position.y -= 0.34;
      }

      if (item.node.kind === "event" && item.node.selected) {
        halo.position.copy(item.mesh.position);
      }
    }

    writeLines(relationshipLines, "relationship");
    writeLines(touchLines, "touches");
  }

  // ── pointer: hover names a point; a click (not a drag) opens it ──────────
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();
  let downAt = null;

  function pick(event) {
    const rect = renderer.domElement.getBoundingClientRect();
    pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);
    const hit = raycaster.intersectObjects(nodesGroup.children, false)[0];
    return { node: hit ? hit.object.userData : null, rect };
  }

  function onMove(event) {
    const { node, rect } = pick(event);
    renderer.domElement.style.cursor = node ? "pointer" : "grab";

    if (!node) {
      tooltip.style.display = "none";
      return;
    }

    tooltip.replaceChildren();
    const title = document.createElement("strong");
    title.textContent = node.label;
    const meta = document.createElement("div");
    meta.textContent =
      node.kind === "event" ? `${node.date} · ${node.truth}` : `entity · ${node.entity_kind}`;
    tooltip.append(title, meta);

    if (node.placed?.[layout] === false) {
      const note = document.createElement("div");
      note.textContent = "not placeable in this layout";
      tooltip.append(note);
    }

    tooltip.style.display = "block";
    tooltip.style.left = `${event.clientX - rect.left + 12}px`;
    tooltip.style.top = `${event.clientY - rect.top + 12}px`;
  }

  function onDown(event) {
    downAt = [event.clientX, event.clientY];
  }

  function onUp(event) {
    if (!downAt) return;
    const moved = Math.hypot(event.clientX - downAt[0], event.clientY - downAt[1]);
    downAt = null;
    if (moved > CLICK_SLOP) return; // that was an orbit

    const { node } = pick(event);
    if (!node) return;
    if (node.kind === "event") onSelectEvent?.(node.id);
    else onFocusEntity?.(node.id);
  }

  const onLeave = () => (tooltip.style.display = "none");

  const canvas = renderer.domElement;
  canvas.addEventListener("pointermove", onMove);
  canvas.addEventListener("pointerdown", onDown);
  canvas.addEventListener("pointerup", onUp);
  canvas.addEventListener("pointerleave", onLeave);

  // ── loop: only while on screen ───────────────────────────────────────────
  let frame = null;
  let visible = true;

  function tick(now) {
    frame = null;

    if (tweenStart !== null) {
      const progress = Math.min((now - tweenStart) / TWEEN_MS, 1);
      place(progress);

      if (cameraTween) {
        const k = ease(progress);
        camera.position.lerpVectors(cameraTween.fromPosition, cameraTween.toPosition, k);
        controls.target.lerpVectors(cameraTween.fromTarget, cameraTween.toTarget, k);
      }

      if (progress === 1) {
        tweenStart = null;
        cameraTween = null;
      }
    }

    fadeGround();
    fadeRule();
    fadeLinks();
    controls.update();
    halo.rotation.y += 0.01;
    renderer.render(scene, camera);
    if (visible) frame = requestAnimationFrame(tick);
  }

  const onScreen = new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    if (visible && frame === null) frame = requestAnimationFrame(tick);
  });
  onScreen.observe(container);

  const onResize = new ResizeObserver(() => {
    stage.resize();
    if (layout !== "timeline") return;

    // The strip is shaped to the window, so a new window is a new strip: refit,
    // put everything where it now belongs, and stand where it all fits again.
    fitStrip(lastNodes);
    drawRule(lastSpan);
    frameTo = box(lastFrames.timeline);
    frameFrom = { center: frameTo.center.clone(), size: frameTo.size.clone() };

    for (const item of items.values()) {
      item.to = target(item.node);
      item.from = item.to.clone();
    }

    place(1);
    const stand = cameraFor("timeline", lastFrames.timeline, strip);
    camera.position.copy(stand.position);
    controls.target.copy(stand.target);
  });
  onResize.observe(container);

  frame = requestAnimationFrame(tick);

  return {
    update({ layout: next, nodes, links: nextLinks, frames, map, span, ground, icons: nextIcons }) {
      icons = nextIcons || icons;
      const changedLayout = next !== layout;
      const first = layout === null;
      layout = next;
      links = nextLinks || [];
      lastNodes = nodes || [];
      lastSpan = span;
      fitStrip(lastNodes);

      drawRule(span);

      // In the Map layout the view is bird's-eye and behaves as a web map does:
      // no turning, drag to pan, scroll to zoom. Every other layout still orbits.
      mapControls(next === "map" || next === "timeline");

      // No request leaves the page for tiles until the map is actually asked for.
      groundOn = !!ground && !!map;

      if (groundOn) {
        // Behind everything: entities rest at z = -1.15 in the Map preset, and a
        // custom mode's z can run the whole -1..1.
        setGround(map, next === "map" ? ((frames || {}).map?.center || [0, 0, 0])[2] : -1.2);
        clearTimeout(tilesDue);
        // After the camera has arrived: tiles are chosen from what it sees.
        tilesDue = setTimeout(refreshTiles, first || reduceMotion ? 0 : TWEEN_MS + 60);
      }

      labelAxes();
      sync(nodes || []);

      // The frame starts from wherever it is now, mid-morph included.
      lastFrames = frames || {};
      const nextFrame = (frames || {})[next];
      const movedBy = box(nextFrame).center.z - frameTo.center.z;
      frameFrom = { center: frameNow.center.clone(), size: frameNow.size.clone() };
      frameTo = box(nextFrame);

      halo.visible = (nodes || []).some((n) => n.kind === "event" && n.selected);

      const stand = cameraFor(next, nextFrame, strip);

      if (first || reduceMotion) {
        // No journey to show: arrive.
        frameFrom = { center: frameTo.center.clone(), size: frameTo.size.clone() };
        place(1);
        if (changedLayout && stand) {
          camera.position.copy(stand.position);
          controls.target.copy(stand.target);
        }
        return;
      }

      tweenStart = performance.now();

      if (changedLayout && stand) {
        // A new layout: travel to where it is best seen from.
        cameraTween = {
          fromPosition: camera.position.clone(),
          toPosition: stand.position,
          fromTarget: controls.target.clone(),
          toTarget: stand.target,
        };
      } else if (next === "moment" && Math.abs(movedBy) > 1e-6) {
        // Same layout, but the moment moved: follow the plane along time, keeping
        // whatever angle the reader has orbited to. Nothing else moves the camera
        // — a filter narrowing the points must not yank the view away.
        const shift = new THREE.Vector3(0, 0, movedBy);
        cameraTween = {
          fromPosition: camera.position.clone(),
          toPosition: camera.position.clone().add(shift),
          fromTarget: controls.target.clone(),
          toTarget: controls.target.clone().add(shift),
        };
      }
    },

    destroy() {
      visible = false;
      if (frame !== null) cancelAnimationFrame(frame);
      onScreen.disconnect();
      onResize.disconnect();
      canvas.removeEventListener("pointermove", onMove);
      canvas.removeEventListener("pointerdown", onDown);
      canvas.removeEventListener("pointerup", onUp);
      canvas.removeEventListener("pointerleave", onLeave);
      disposeGroup(guideGroup);
      disposeGroup(frameBox);
      clearRule();
      clearTimeout(tilesDue);
      controls.removeEventListener("change", tilesSoon);
      clearGround();
      volume.geometry.dispose();
      volume.material.dispose();
      for (const item of items.values()) {
        item.mesh.material.dispose();
        item.label?.material.map?.dispose();
        item.label?.material.dispose();
      }
      items.clear();
      relationshipLines.geometry.dispose();
      relationshipLines.material.dispose();
      touchLines.geometry.dispose();
      touchLines.material.dispose();
      stage.dispose();
    },
  };
}
