/**
 * Shared Three.js stage helpers for the dark "layer" pages (/topo, /network).
 *
 * Extracted from topo.js so new pages can reuse the same scene setup,
 * canvas-text sprites, deterministic hashing, and panel styling without
 * copying them. Defaults match topo.js exactly, so /topo renders unchanged.
 */

import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";

export const STAGE_BG = 0x0b1020;

export const PANEL_CSS =
  "position:absolute;top:12px;left:12px;z-index:10;background:rgba(15,23,42,0.92);" +
  "border:1px solid #334155;border-radius:8px;padding:10px 12px;color:#94a3b8;" +
  "font:12px system-ui,sans-serif;display:flex;flex-direction:column;gap:8px;min-width:230px;";
export const SIDEBAR_CSS =
  "position:absolute;top:12px;right:12px;z-index:10;background:rgba(15,23,42,0.92);" +
  "border:1px solid #334155;border-radius:8px;padding:10px 12px;color:#94a3b8;" +
  "font:12px system-ui,sans-serif;display:flex;flex-direction:column;gap:4px;min-width:190px;" +
  "max-height:calc(100% - 24px);overflow-y:auto;";
export const SELECT_CSS =
  "flex:1;background:#1e293b;color:#f1f5f9;border:1px solid #334155;border-radius:4px;" +
  "padding:2px 4px;font-size:11px;cursor:pointer;min-width:0;";
export const TOOLTIP_CSS =
  "position:absolute;z-index:20;pointer-events:none;display:none;background:rgba(15,23,42,0.95);" +
  "border:1px solid #38bdf8;border-radius:6px;padding:6px 9px;color:#e2e8f0;" +
  "font:11px system-ui,sans-serif;max-width:280px;";

/** Canvas-text sprite; width follows the text, height is fixed. */
export function makeSprite(text, cssColor, scale = 1) {
  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d");
  const font = "600 30px system-ui, sans-serif";
  ctx.font = font;
  canvas.width = Math.ceil(ctx.measureText(text).width) + 16;
  canvas.height = 40;
  ctx.font = font;
  ctx.fillStyle = cssColor;
  ctx.textBaseline = "middle";
  ctx.fillText(text, 8, 20);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  const sprite = new THREE.Sprite(
    new THREE.SpriteMaterial({ map: texture, transparent: true, depthTest: false })
  );
  sprite.scale.set((canvas.width / 40) * 0.55 * scale, 0.55 * scale, 1);
  return sprite;
}

/** Deterministic 0..1 hash — layouts must be stable across reloads (no RNG). */
export function hashString(text) {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0) / 4294967296;
}

export function hexColor(color) {
  return "#" + color.toString(16).padStart(6, "0");
}

/** Seeded PRNG for procedural-but-stable datasets. */
export function mulberry32(seed) {
  return function () {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Scene + camera + renderer + OrbitControls + tooltip element, sized to the
 * container and kept in sync on resize.
 */
export function createStage(container, options = {}) {
  const {
    background = STAGE_BG,
    fog = [26, 60],
    fov = 55,
    near = 0.1,
    far = 120,
    cameraPosition = [11, 8, 13],
  } = options;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(background);
  if (fog) scene.fog = new THREE.Fog(background, fog[0], fog[1]);

  const camera = new THREE.PerspectiveCamera(fov, 1, near, far);
  camera.position.set(...cameraPosition);

  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(window.devicePixelRatio);
  container.appendChild(renderer.domElement);

  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;

  scene.add(new THREE.AmbientLight(0xffffff, 0.7));
  const keyLight = new THREE.DirectionalLight(0xffffff, 1.1);
  keyLight.position.set(6, 10, 8);
  scene.add(keyLight);

  function resize() {
    const width = container.clientWidth;
    const height = container.clientHeight;
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height);
  }
  window.addEventListener("resize", resize);
  resize();

  const tooltip = document.createElement("div");
  tooltip.style.cssText = TOOLTIP_CSS;
  container.appendChild(tooltip);

  // For stages that come and go (a LiveView hook); a full-page stage never calls it.
  function dispose() {
    window.removeEventListener("resize", resize);
    controls.dispose();
    renderer.dispose();
    renderer.domElement.remove();
    tooltip.remove();
  }

  return { scene, camera, renderer, controls, tooltip, resize, dispose };
}
