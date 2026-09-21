// /atlas — the sticky timeline, as the flat ("strip") variant of Spacetime.
//
// The rectangle's extents are the first and last activity of the WHOLE record.
// Every activity is on it, always. Filters do not remove anything from it: what
// they leave is inked, the rest goes hollow, and the view FOCUSES — it zooms
// along time to the span the filtered activities cover, and back out to the
// whole record on request. Year and month markers are drawn in the same space,
// so they zoom with the activities and gain detail as there is room for it.
//
// The band is a SLICE, and is drawn to say so. The axis is an arc of a circle so
// large it is all but flat — a few pixels of sag across the whole width — which
// is enough to read as a piece of something that carries on round. It is inked
// only across the record's own span; beyond the first and last activity it
// continues faint and fades out at both edges rather than stopping, because the
// record stops there and time does not. A "now" tick marks the present, so
// anything to its right is about the future rather than from it.
//
// Motion is after Yugo Nakamura's Flash work (yugop.com): nothing snaps. The
// view window is on a spring, so a zoom arrives with a little overshoot and
// settles; stacks of simultaneous activities re-sort as the zoom pulls them
// apart; marker detail fades in with the space for it rather than popping.
//
// Everything is laid out in PIXELS under an orthographic camera, so a dot stays
// round however wide the band is and type stays the size it was set at.
//
// Data contract (from the hook element's data-scene):
//   extent: { from: ms, to: ms }            — first and last activity of the record
//   focus:  { from: ms, to: ms } | null     — span of what the filters leave
//   fit:    "focus" | "all"                 — which of those the view shows
//   nodes:  [{ id, label, at: ms, date, truth, color, read, selected }]

import * as THREE from "three";
import { createStage } from "./three_stage";

const INSET = 14; // px kept clear at each end, so an end dot is never clipped
const AXIS_Y = 22; // px from the bottom: the line the dots stand on, type beneath
const DOT = 4.5; // px radius
const STEP = 12; // px between stacked dots
const CLICK_SLOP = 4;
const DAY = 86_400_000;
const SAG = 5; // px the arc drops at the edges: a very large circle
const FADE = 0.09; // fraction of the width, at each end, over which the axis fades out
const ARC_SEGMENTS = 64;

// Spring for the view window: a touch underdamped, so it overshoots and settles.
const STIFFNESS = 170;
const DAMPING = 21;

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const smoothstep = (a, b, x) => {
  const t = Math.min(Math.max((x - a) / (b - a), 0), 1);
  return t * t * (3 - 2 * t);
};

export function createTimelineStrip(container, { onSelectEvent } = {}) {
  const css = getComputedStyle(container);
  const token = (name, fallback) => css.getPropertyValue(name).trim() || fallback;
  const paper = token("--paper", "#ffffff");
  const ink = token("--ink", "#111111");
  const inkSoft = token("--ink-soft", "#555555");
  const inkFaint = token("--ink-faint", "#888888");
  const rule = token("--rule", "#dddddd");

  const stage = createStage(container, { fog: null, background: new THREE.Color(paper).getHex() });
  const { scene, renderer, controls, tooltip } = stage;
  controls.enabled = false; // flat and fixed: there is nothing to orbit

  const camera = new THREE.OrthographicCamera(0, 1, 1, 0, -100, 100);
  camera.position.z = 10;

  let width = 1;
  let height = 1;

  function fit() {
    width = Math.max(container.clientWidth, 1);
    height = Math.max(container.clientHeight, 1);
    camera.right = width;
    camera.top = height;
    camera.updateProjectionMatrix();
  }
  fit();

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ── the view window, on a spring ─────────────────────────────────────────
  const view = { from: 0, to: 1, vFrom: 0, vTo: 0, targetFrom: 0, targetTo: 1, ready: false };
  let extent = { from: 0, to: 1 };

  const x = (ms) => INSET + ((ms - view.from) / Math.max(view.to - view.from, 1)) * (width - INSET * 2);

  // How far the arc has dropped at a given x: nothing at the centre, SAG at the edges.
  const sag = (px) => {
    const u = (px - width / 2) / (width / 2);
    return -SAG * u * u;
  };

  function aim(from, to) {
    // Never a zero-width window: one instant still gets a day either side.
    // Room at both ends, so there is always some "beyond" in view.
    const pad = Math.max((to - from) * 0.1, to - from < DAY ? DAY : 0);
    view.targetFrom = from - pad;
    view.targetTo = to + pad;

    if (!view.ready || reduceMotion) {
      Object.assign(view, { from: view.targetFrom, to: view.targetTo, vFrom: 0, vTo: 0, ready: true });
    }
  }

  function spring(dt) {
    const span = Math.max(view.targetTo - view.targetFrom, 1);

    for (const [p, v, t] of [["from", "vFrom", "targetFrom"], ["to", "vTo", "targetTo"]]) {
      const force = (view[t] - view[p]) * STIFFNESS - view[v] * DAMPING;
      view[v] += force * dt;
      view[p] += view[v] * dt;

      // Close enough, and slow enough: rest exactly on target.
      if (Math.abs(view[t] - view[p]) < span * 1e-5 && Math.abs(view[v]) < span * 1e-4) {
        view[p] = view[t];
        view[v] = 0;
      }
    }
  }

  // ── type: crisp canvas sprites, sized in pixels ──────────────────────────
  function makeLabel(text, color, px, weight = 400) {
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d");
    const font = `${weight} ${px * ratio}px Helvetica, "Helvetica Neue", Inter, system-ui, sans-serif`;
    ctx.font = font;
    const w = Math.ceil(ctx.measureText(text).width) + 4 * ratio;
    const h = Math.ceil(px * ratio * 1.4);
    canvas.width = w;
    canvas.height = h;
    ctx.font = font;
    ctx.fillStyle = color;
    ctx.textBaseline = "middle";
    ctx.fillText(text, 2 * ratio, h / 2);

    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    const sprite = new THREE.Sprite(
      new THREE.SpriteMaterial({ map: texture, transparent: true, depthTest: false })
    );
    sprite.scale.set(w / ratio, h / ratio, 1);
    sprite.center.set(0, 0.5); // anchored at its left edge, so it reads from its tick
    return sprite;
  }

  const line = (color) =>
    new THREE.Line(
      new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(0, 0, 0), new THREE.Vector3(0, 1, 0)]),
      new THREE.LineBasicMaterial({ color, transparent: true })
    );

  // ── furniture: the axis, the focus band, the markers ─────────────────────
  // The axis is a polyline with a colour per vertex: ink across the record,
  // faint beyond it, and paper at the edges of the band.
  const axis = new THREE.Line(new THREE.BufferGeometry(), new THREE.LineBasicMaterial({ vertexColors: true }));
  axis.frustumCulled = false;
  axis.geometry.setAttribute("position", new THREE.BufferAttribute(new Float32Array((ARC_SEGMENTS + 1) * 3), 3));
  axis.geometry.setAttribute("color", new THREE.BufferAttribute(new Float32Array((ARC_SEGMENTS + 1) * 3), 3));
  scene.add(axis);

  const cInk = new THREE.Color(ink);
  const cFaint = new THREE.Color(rule);
  const cPaper = new THREE.Color(paper);
  const cMix = new THREE.Color();

  // The present. Left of it happened; right of it has not.
  const now = { tick: null, label: null };

  // Where the filtered activities sit within the whole record: visible as a
  // band when zoomed out, and the whole width once focused.
  const band = new THREE.Mesh(
    new THREE.PlaneGeometry(1, 1),
    new THREE.MeshBasicMaterial({ color: ink, transparent: true, opacity: 0.05 })
  );
  band.visible = false;
  scene.add(band);

  const markers = new Map(); // "YYYY" | "YYYY-MM" -> { tick, label, kind }
  const markerGroup = new THREE.Group();
  scene.add(markerGroup);

  function marker(key, kind, text) {
    let m = markers.get(key);
    if (m) return m;

    const year = kind === "year";
    m = {
      kind,
      tick: line(year ? ink : inkFaint),
      label: makeLabel(text, year ? ink : inkSoft, year ? 11 : 9, year ? 700 : 400),
    };
    markerGroup.add(m.tick, m.label);
    markers.set(key, m);
    return m;
  }

  function drawNow() {
    if (!now.tick) {
      now.tick = line("#cc0000");
      now.label = makeLabel("now", "#cc0000", 9, 700);
      markerGroup.add(now.tick, now.label);
    }

    const px = x(Date.now());
    const shown = px >= 0 && px <= width;
    now.tick.visible = now.label.visible = shown;
    if (!shown) return;

    now.tick.position.set(px, AXIS_Y + sag(px) - 9, 1);
    now.tick.scale.y = height - AXIS_Y - sag(px) + 9 - 4;
    now.tick.material.opacity = 0.8;
    // Reads leftward from its tick when there is no room to its right.
    const flip = px > width - 34;
    now.label.center.set(flip ? 1 : 0, 0.5);
    now.label.position.set(px + (flip ? -3 : 3), height - 8, 2);
  }

  function drawMarkers() {
    const pxPerMonth = ((width - INSET * 2) / Math.max(view.to - view.from, 1)) * DAY * 30.44;

    // Detail arrives with the room for it: month ticks first, then their names.
    const monthTicks = smoothstep(5, 14, pxPerMonth);
    const monthNames = smoothstep(26, 40, pxPerMonth);
    // Quarters carry the month names until every month has room for its own.
    const quarterNames = smoothstep(9, 16, pxPerMonth);

    const seen = new Set();
    const start = new Date(view.from);
    const cursor = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), 1));

    // Bounded: a very long record zoomed right out draws years only.
    for (let i = 0; i < 1200 && cursor.getTime() <= view.to; i++) {
      const ms = cursor.getTime();
      const month = cursor.getUTCMonth();
      const year = cursor.getUTCFullYear();
      const px = x(ms);

      if (px >= -40 && px <= width + 40) {
        if (month === 0) {
          const key = `${year}`;
          const m = marker(key, "year", key);
          seen.add(key);
          m.tick.visible = m.label.visible = true;
          m.tick.position.set(px, AXIS_Y + sag(px) - 9, 0);
          m.tick.scale.y = height - AXIS_Y - sag(px) + 9 - 4;
          m.tick.material.opacity = 0.55;
          m.label.position.set(px + 3, 8 + sag(px), 1);
        } else if (monthTicks > 0.01) {
          const key = `${year}-${month}`;
          const m = marker(key, "month", MONTHS[month]);
          seen.add(key);
          const named = Math.max(monthNames, month % 3 === 0 ? quarterNames : 0);

          m.tick.visible = true;
          m.tick.position.set(px, AXIS_Y + sag(px) - 5, 0);
          // The tick grows out of the axis as the zoom makes room for it.
          m.tick.scale.y = 5 + (month % 3 === 0 ? 5 : 2) * monthTicks;
          m.tick.material.opacity = 0.7 * monthTicks;
          m.label.visible = named > 0.01;
          m.label.material.opacity = named;
          m.label.position.set(px + 3, 8 + sag(px), 1);
        }
      }

      cursor.setUTCMonth(month + 1);
    }

    for (const [key, m] of markers) {
      if (!seen.has(key)) m.tick.visible = m.label.visible = false;
    }
  }

  // ── the activities ───────────────────────────────────────────────────────
  const dotGeometry = new THREE.CircleGeometry(DOT, 24);
  const ringGeometry = new THREE.RingGeometry(DOT - 1.25, DOT, 24);
  const dotsGroup = new THREE.Group();
  scene.add(dotsGroup);

  const halo = new THREE.Mesh(
    new THREE.RingGeometry(DOT + 3, DOT + 4.25, 32),
    new THREE.MeshBasicMaterial({ color: token("--link", "#0000cc"), transparent: true })
  );
  halo.visible = false;
  scene.add(halo);

  const items = new Map(); // id -> { mesh, node, y }
  let focus = null;

  function sync(nodes) {
    const seen = new Set();

    nodes.forEach((node) => {
      seen.add(node.id);
      let item = items.get(node.id);

      if (!item) {
        const mesh = new THREE.Mesh(dotGeometry, new THREE.MeshBasicMaterial({ transparent: true }));
        item = { mesh, node, y: AXIS_Y + DOT + 2, solid: true };
        items.set(node.id, item);
        dotsGroup.add(mesh);
      }

      item.node = node;
      item.mesh.userData = node;
      item.mesh.material.color.set(node.color || ink);

      // Filtered out is drawn as filtered out — hollow and quiet — never removed.
      const solid = node.read !== false;
      if (solid !== item.solid) {
        item.mesh.geometry = solid ? dotGeometry : ringGeometry;
        item.solid = solid;
      }
      item.mesh.material.opacity = solid ? 1 : 0.3;
    });

    for (const [id, item] of items) {
      if (seen.has(id)) continue;
      dotsGroup.remove(item.mesh);
      item.mesh.material.dispose();
      items.delete(id);
    }
  }

  function placeDots() {
    // Stack by what actually collides at THIS zoom, so a pile pulls apart into
    // a row as the view closes in on it. Read dots take the low slots.
    const order = [...items.values()].sort(
      (a, b) => a.node.at - b.node.at || Number(b.solid) - Number(a.solid)
    );
    const columns = []; // [{ px, count }]
    halo.visible = false;

    order.forEach((item) => {
      const px = x(item.node.at);
      let column = columns.length ? columns[columns.length - 1] : null;
      if (!column || px - column.px > DOT * 2 + 1) {
        column = { px, count: 0 };
        columns.push(column);
      }

      const room = Math.max(Math.floor((height - AXIS_Y - DOT * 2 - 4) / STEP), 1);
      const slot = Math.min(column.count++, room);
      // Standing on the arc, not on a straight line through it.
      const targetY = AXIS_Y + sag(px) + DOT + 3 + slot * STEP;

      // Ease toward the slot rather than jumping to it.
      item.y += (targetY - item.y) * (reduceMotion ? 1 : 0.22);
      item.mesh.position.set(px, item.y, 2);
      // Filtered out stays, smaller: so a narrowed view reads at a glance.
      item.mesh.scale.setScalar(item.node.selected ? 1.5 : item.solid ? 1 : 0.7);

      if (item.node.selected) {
        halo.visible = true;
        halo.position.set(px, item.y, 3);
      }
    });
  }

  function placeFurniture() {
    const positions = axis.geometry.attributes.position;
    const colors = axis.geometry.attributes.color;
    const recordFrom = x(extent.from);
    const recordTo = x(extent.to);

    for (let i = 0; i <= ARC_SEGMENTS; i++) {
      const px = (i / ARC_SEGMENTS) * width;
      positions.setXYZ(i, px, AXIS_Y + sag(px), 0);

      // Ink where the record is; faint where it is not; gone at the edges.
      const inRecord = px >= recordFrom - DOT && px <= recordTo + DOT;
      const edge = Math.min(px, width - px) / (width * FADE);
      cMix.copy(inRecord ? cInk : cFaint).lerp(cPaper, 1 - smoothstep(0, 1, edge));
      colors.setXYZ(i, cMix.r, cMix.g, cMix.b);
    }

    positions.needsUpdate = true;
    colors.needsUpdate = true;

    if (focus) {
      const a = x(focus.from);
      const b = x(focus.to);
      band.visible = true;
      band.position.set((a + b) / 2, (AXIS_Y + height) / 2, -1);
      band.scale.set(Math.max(b - a, 2) + DOT * 4, height - AXIS_Y, 1);
    } else {
      band.visible = false;
    }
  }

  // ── pointer ──────────────────────────────────────────────────────────────
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();
  let downAt = null;

  function pick(event) {
    const rect = renderer.domElement.getBoundingClientRect();
    pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);
    const hit = raycaster.intersectObjects(dotsGroup.children, false)[0];
    return { node: hit ? hit.object.userData : null, rect };
  }

  function onMove(event) {
    const { node, rect } = pick(event);
    renderer.domElement.style.cursor = node ? "pointer" : "default";

    if (!node) {
      tooltip.style.display = "none";
      return;
    }

    tooltip.replaceChildren();
    const title = document.createElement("strong");
    title.textContent = node.label;
    const meta = document.createElement("div");
    meta.textContent = `${node.date} · ${node.truth}${node.read === false ? " · filtered out" : ""}`;
    tooltip.append(title, meta);
    tooltip.style.display = "block";
    // Keep it inside the band: flip to the left of the pointer near the right edge.
    const left = event.clientX - rect.left;
    tooltip.style.left = left > rect.width - 300 ? `${Math.max(left - 292, 0)}px` : `${left + 12}px`;
    tooltip.style.top = `${event.clientY - rect.top + 12}px`;
  }

  const onDown = (event) => (downAt = [event.clientX, event.clientY]);

  function onUp(event) {
    if (!downAt) return;
    const moved = Math.hypot(event.clientX - downAt[0], event.clientY - downAt[1]);
    downAt = null;
    if (moved > CLICK_SLOP) return;
    const { node } = pick(event);
    if (node) onSelectEvent?.(node.id);
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
  let last = null;

  function tick(now) {
    frame = null;
    // Clamped: a tab coming back from the background must not fling the spring.
    const dt = last === null ? 1 / 60 : Math.min((now - last) / 1000, 1 / 30);
    last = now;

    spring(dt);
    placeFurniture();
    drawMarkers();
    drawNow();
    placeDots();
    halo.rotation.z += 0.01;

    renderer.render(scene, camera);
    if (visible) frame = requestAnimationFrame(tick);
  }

  const onScreen = new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    last = null;
    if (visible && frame === null) frame = requestAnimationFrame(tick);
  });
  onScreen.observe(container);

  const onResize = new ResizeObserver(() => {
    stage.resize();
    fit();
  });
  onResize.observe(container);

  frame = requestAnimationFrame(tick);

  return {
    update({ extent: nextExtent, focus: nextFocus, fit: mode, nodes }) {
      extent = nextExtent || extent;
      focus = nextFocus || null;
      sync(nodes || []);

      const to = mode !== "all" && focus ? focus : extent;
      aim(to.from, to.to);
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

      for (const item of items.values()) item.mesh.material.dispose();
      items.clear();
      if (now.tick) markers.set("now", now);
      for (const m of markers.values()) {
        m.tick.geometry.dispose();
        m.tick.material.dispose();
        m.label.material.map?.dispose();
        m.label.material.dispose();
      }
      markers.clear();
      [axis, band, halo].forEach((o) => {
        o.geometry.dispose();
        o.material.dispose();
      });
      dotGeometry.dispose();
      ringGeometry.dispose();
      stage.dispose();
    },
  };
}
