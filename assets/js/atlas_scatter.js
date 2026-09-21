// /atlas — the 3D scatter: one point per event, in a volume spanned by three
// opposing-pole axes. The server decides where points go and what the axes are
// (Indivisual.Atlas.Scatter); this file only draws what it is handed, so making
// the positions meaningful later changes nothing here.
//
// Data contract, as parsed from the hook element's data attributes:
//   axes:   [{ id, negative, positive }]            — x, y, z in that order
//   points: [{ id, title, date, truth, color, x, y, z, selected, future }]
//           x/y/z in -1..1; `future` = after the scrubber's position.

import * as THREE from "three";
import { createStage, makeSprite } from "./three_stage";

const EXTENT = 4; // world units from the origin to the end of an axis
const POINT_RADIUS = 0.11;
const AXIS_COLOR = 0x64748b;
const POLE_COLOR = "#cbd5e1";
const CLICK_SLOP = 4; // px the pointer may travel and still count as a click

const geometry = new THREE.SphereGeometry(POINT_RADIUS, 20, 14);

export function createScatter(container, { onSelect } = {}) {
  const stage = createStage(container, {
    cameraPosition: [9.5, 6.5, 12],
    fog: [18, 48],
  });
  const { scene, camera, renderer, controls, tooltip } = stage;
  controls.enablePan = false;
  controls.minDistance = 5;
  controls.maxDistance = 26;

  const axesGroup = new THREE.Group();
  const pointsGroup = new THREE.Group();
  scene.add(axesGroup, pointsGroup);

  // A faint cube around the volume: without it a cloud of dots has no depth.
  const cube = new THREE.LineSegments(
    new THREE.EdgesGeometry(new THREE.BoxGeometry(EXTENT * 2, EXTENT * 2, EXTENT * 2)),
    new THREE.LineBasicMaterial({ color: 0x334155 })
  );
  scene.add(cube);

  const halo = new THREE.Mesh(
    new THREE.SphereGeometry(POINT_RADIUS * 3, 12, 8),
    new THREE.MeshBasicMaterial({ color: 0xffffff, wireframe: true, transparent: true, opacity: 0.3 })
  );
  halo.visible = false;
  scene.add(halo);

  const meshes = new Map(); // event id -> mesh

  let drawnAxes = null;

  function drawAxes(axes) {
    // Axes rarely change; rebuilding their label textures on every append would leak.
    const key = JSON.stringify(axes);
    if (key === drawnAxes) return;
    drawnAxes = key;

    axesGroup.children.forEach((child) => {
      child.geometry?.dispose();
      child.material?.map?.dispose();
      child.material?.dispose();
    });
    axesGroup.clear();
    const directions = [
      new THREE.Vector3(1, 0, 0),
      new THREE.Vector3(0, 1, 0),
      new THREE.Vector3(0, 0, 1),
    ];

    axes.slice(0, 3).forEach((axis, i) => {
      const end = directions[i].clone().multiplyScalar(EXTENT * 1.12);
      const line = new THREE.Line(
        new THREE.BufferGeometry().setFromPoints([end.clone().negate(), end]),
        new THREE.LineBasicMaterial({ color: AXIS_COLOR })
      );
      axesGroup.add(line);

      [[axis.negative, -1], [axis.positive, 1]].forEach(([label, sign]) => {
        const sprite = makeSprite(label, POLE_COLOR, 0.9);
        sprite.position.copy(directions[i]).multiplyScalar(sign * EXTENT * 1.3);
        axesGroup.add(sprite);
      });
    });
  }

  function drawPoints(points) {
    const seen = new Set();
    halo.visible = false;

    points.forEach((p) => {
      seen.add(p.id);
      let mesh = meshes.get(p.id);

      if (!mesh) {
        mesh = new THREE.Mesh(
          geometry,
          new THREE.MeshStandardMaterial({ roughness: 0.45, transparent: true })
        );
        meshes.set(p.id, mesh);
        pointsGroup.add(mesh);
      }

      mesh.userData = p;
      mesh.position.set(p.x * EXTENT, p.y * EXTENT, p.z * EXTENT);
      // The truth-state palette was chosen for ink on paper; against near-black
      // the indigo and blue all but vanish, so lift them and let them glow a little.
      mesh.material.color.set(p.color).offsetHSL(0, 0.05, 0.2);
      mesh.material.emissive.copy(mesh.material.color).multiplyScalar(0.35);
      mesh.material.opacity = p.future ? 0.3 : 1;
      mesh.scale.setScalar(p.selected ? 1.7 : 1);

      if (p.selected) {
        halo.position.copy(mesh.position);
        halo.visible = true;
      }
    });

    // Events that left the lens leave the volume.
    for (const [id, mesh] of meshes) {
      if (!seen.has(id)) {
        pointsGroup.remove(mesh);
        mesh.material.dispose();
        meshes.delete(id);
      }
    }
  }

  // ── pointer: hover names a point, a click (not a drag) selects it ────────
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();
  let downAt = null;

  function pick(event) {
    const rect = renderer.domElement.getBoundingClientRect();
    pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);
    const hit = raycaster.intersectObjects(pointsGroup.children, false)[0];
    return hit ? { point: hit.object.userData, rect } : { point: null, rect };
  }

  function onMove(event) {
    const { point, rect } = pick(event);
    renderer.domElement.style.cursor = point ? "pointer" : "grab";

    if (!point) {
      tooltip.style.display = "none";
      return;
    }

    tooltip.replaceChildren();
    const title = document.createElement("strong");
    title.textContent = point.title;
    const meta = document.createElement("div");
    meta.textContent = `${point.date} · ${point.truth}`;
    tooltip.append(title, meta);
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
    if (moved > CLICK_SLOP) return; // that was an orbit, not a click

    const { point } = pick(event);
    if (point && onSelect) onSelect(point.id);
  }

  function onLeave() {
    tooltip.style.display = "none";
  }

  const canvas = renderer.domElement;
  canvas.addEventListener("pointermove", onMove);
  canvas.addEventListener("pointerdown", onDown);
  canvas.addEventListener("pointerup", onUp);
  canvas.addEventListener("pointerleave", onLeave);

  // ── loop: only while on screen — this component is always mounted ────────
  let frame = null;
  let visible = true;

  function tick() {
    frame = null;
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

  // The stage listens for window resizes; a column changing width is not one.
  const onResize = new ResizeObserver(() => stage.resize());
  onResize.observe(container);

  frame = requestAnimationFrame(tick);

  return {
    update({ axes, points }) {
      drawAxes(axes);
      drawPoints(points);
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
      for (const mesh of meshes.values()) mesh.material.dispose();
      meshes.clear();
      stage.dispose();
    },
  };
}
