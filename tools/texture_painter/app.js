// Pintor de texturas de Rumbang: pinta sobre el modelo 3D desde el celular y guarda la textura en el proyecto.
// Servidor: tools/texture_painter/server.py. Cada textura = base (sin pintar) + capa de pintura transparente.
import * as THREE from 'three';
import { GLTFLoader } from './vendor/GLTFLoader.js';
import { OrbitControls } from './vendor/OrbitControls.js';
import { computeBoundsTree, acceleratedRaycast } from './vendor/three-mesh-bvh.module.js';

THREE.BufferGeometry.prototype.computeBoundsTree = computeBoundsTree;
THREE.Mesh.prototype.raycast = acceleratedRaycast;

const KEY = new URLSearchParams(location.search).get('k') || '';
const api = (path, params = {}) => path + '?' + new URLSearchParams({ k: KEY, ...params });
const $ = (id) => document.getElementById(id);

const INK = '#0f0d14';  // el mismo negro de la tinta horneada (tools/toonify_weapon_textures.py)
const SWATCHES = [INK, '#3a2f3f', '#ffffff', '#f2e6c9', '#b0182a', '#e07a1f', '#e8c547', '#4fb06a',
  '#2f7fc1', '#7a4fb0', '#8a8a96', '#5a3a22'];
const MAX_UNDO = 15;

// ---------- estado ----------
const S = {
  tool: 'brush',      // brush | erase | pick
  paintMode: true,    // true: un dedo pinta; false: un dedo gira
  color: INK,
  size: 6,            // diámetro en px de pantalla
  opacity: 1,
  stab: 0.4,
  light: true,
  pressure: true,
  weapons: [],
  weapon: null,
  textures: new Map(),  // nombre -> PaintTex
  meshes: [],
  undo: [],
  redo: [],
};

// ---------- three ----------
const canvas = $('view');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
const scene = new THREE.Scene();
scene.background = new THREE.Color('#2e2d38');
const camera = new THREE.PerspectiveCamera(40, 1, 0.01, 200);
camera.position.set(0, 0.5, 2);
scene.add(camera);
scene.add(new THREE.AmbientLight(0xffffff, 1.1));
const sun = new THREE.DirectionalLight(0xffffff, 1.6);
sun.position.set(0.6, 1, 0.8);
camera.add(sun);  // la luz sigue a la cámara: siempre se ve la cara que se pinta
const root = new THREE.Group();
scene.add(root);

const controls = new OrbitControls(camera, canvas);
controls.enableDamping = true;
controls.dampingFactor = 0.15;
controls.zoomSpeed = 1.2;

function applyMode() {
  if (S.paintMode) {
    controls.touches = { ONE: null, TWO: THREE.TOUCH.DOLLY_ROTATE };
    controls.mouseButtons = { LEFT: null, MIDDLE: THREE.MOUSE.PAN, RIGHT: THREE.MOUSE.ROTATE };
  } else {
    controls.touches = { ONE: THREE.TOUCH.ROTATE, TWO: THREE.TOUCH.DOLLY_PAN };
    controls.mouseButtons = { LEFT: THREE.MOUSE.ROTATE, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.PAN };
  }
  $('mode').textContent = S.paintMode ? 'Pintar' : 'Mover';
  $('mode').classList.toggle('on', S.paintMode);
}

function resize() {
  const w = window.innerWidth, h = window.innerHeight;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}
window.addEventListener('resize', resize);
resize();

// ---------- texturas pintables ----------
class PaintTex {
  constructor(name, img, layerImg) {
    this.name = name;
    // texturas chicas (paletas, 256 px) se agrandan sin suavizar para que la tinta no salga en bloques
    let w = img.width, h = img.height;
    const up = Math.max(1, Math.floor(1024 / Math.max(w, h)));
    w = Math.min(w * up, 2048); h = Math.min(h * up, 2048);
    this.w = w; this.h = h;
    this.base = mkCanvas(w, h);
    const bctx = this.base.getContext('2d');
    bctx.imageSmoothingEnabled = up === 1;
    bctx.drawImage(img, 0, 0, w, h);
    this.layer = mkCanvas(w, h);
    this.lctx = this.layer.getContext('2d', { willReadFrequently: true });
    if (layerImg) this.lctx.drawImage(layerImg, 0, 0, w, h);
    this.stroke = null;  // capa del trazo en curso (se crea al pintar)
    this.sctx = null;
    this.sdata = null;   // ImageData del trazo: cobertura en alfa, se sube por rectángulo sucio
    this.sdirty = null;  // [x0, y0, x1, y1] pendiente de subir al canvas del trazo
    this.tmp = null;     // para previsualizar el borrador
    this.ids = null;     // Int32Array w*h: isla de UV de cada texel (-1 = hueco del atlas, -2 = UV compartida)
    this.comp = mkCanvas(w, h);
    this.cctx = this.comp.getContext('2d', { willReadFrequently: true });
    this.tex = new THREE.CanvasTexture(this.comp);
    this.tex.flipY = false;  // UV de glTF
    this.tex.colorSpace = THREE.SRGBColorSpace;
    this.tex.wrapS = this.tex.wrapT = THREE.RepeatWrapping;
    this.tex.anisotropy = Math.min(4, renderer.capabilities.getMaxAnisotropy());
    this.changed = false;
    this.dirty = true;
    this.strokeAlpha = 1;
  }
  ensureStroke() {
    if (!this.stroke) {
      this.stroke = mkCanvas(this.w, this.h);
      this.sctx = this.stroke.getContext('2d');
      this.sdata = this.sctx.createImageData(this.w, this.h);
    }
  }
  clearStroke() {
    if (!this.stroke) return;
    this.sdata.data.fill(0);
    this.sctx.clearRect(0, 0, this.w, this.h);
    this.sdirty = null;
  }
  // círculo con borde suave, solo dentro de la isla tocada: así no se mancha la isla vecina del atlas
  stamp(px, py, rad, island, rgb) {
    const w = this.w, h = this.h, d = this.sdata.data, ids = this.ids;
    const x0 = Math.max(0, Math.floor(px - rad - 1)), x1 = Math.min(w - 1, Math.ceil(px + rad + 1));
    const y0 = Math.max(0, Math.floor(py - rad - 1)), y1 = Math.min(h - 1, Math.ceil(py + rad + 1));
    if (x0 > x1 || y0 > y1) return;
    for (let y = y0; y <= y1; y++) {
      const dy = y + 0.5 - py;
      for (let x = x0; x <= x1; x++) {
        const i = y * w + x;
        if (ids && island >= 0 && ids[i] !== island && ids[i] !== -2) continue;
        const cov = rad + 0.5 - Math.hypot(x + 0.5 - px, dy);
        if (cov <= 0) continue;
        const a = cov >= 1 ? 255 : (cov * 255) | 0;
        const o = i * 4;
        if (a > d[o + 3]) { d[o] = rgb[0]; d[o + 1] = rgb[1]; d[o + 2] = rgb[2]; d[o + 3] = a; }
      }
    }
    const r = this.sdirty;
    this.sdirty = r ? [Math.min(r[0], x0), Math.min(r[1], y0), Math.max(r[2], x1), Math.max(r[3], y1)] : [x0, y0, x1, y1];
    this.dirty = true;
  }
  flushStroke() {
    const r = this.sdirty;
    if (!r) return;
    this.sctx.putImageData(this.sdata, 0, 0, r[0], r[1], r[2] - r[0] + 1, r[3] - r[1] + 1);
    this.sdirty = null;
  }
  redraw() {
    const c = this.cctx;
    if (this.strokeActive) this.flushStroke();
    c.globalCompositeOperation = 'copy';
    c.globalAlpha = 1;
    c.drawImage(this.base, 0, 0);
    c.globalCompositeOperation = 'source-over';
    if (this.strokeActive && this.strokeErase) {
      if (!this.tmp) this.tmp = mkCanvas(this.w, this.h);
      const t = this.tmp.getContext('2d');
      t.globalCompositeOperation = 'copy';
      t.drawImage(this.layer, 0, 0);
      t.globalCompositeOperation = 'destination-out';
      t.globalAlpha = this.strokeAlpha;
      t.drawImage(this.stroke, 0, 0);
      t.globalAlpha = 1;
      c.drawImage(this.tmp, 0, 0);
    } else {
      c.drawImage(this.layer, 0, 0);
      if (this.strokeActive) {
        c.globalAlpha = this.strokeAlpha;
        c.drawImage(this.stroke, 0, 0);
        c.globalAlpha = 1;
      }
    }
    this.tex.needsUpdate = true;
    this.dirty = false;
  }
}

// ---------- islas de UV ----------
// Vértices unidos por triángulos (o con la misma UV) = una isla. glTF parte los vértices en las costuras de UV.
function vertexIslands(geo, uvName, firstId) {
  const n = geo.attributes.position.count;
  const uv = geo.attributes[uvName];
  const parent = new Int32Array(n);
  for (let i = 0; i < n; i++) parent[i] = i;
  const find = (x) => { while (parent[x] !== x) { parent[x] = parent[parent[x]]; x = parent[x]; } return x; };
  const unite = (a, b) => { a = find(a); b = find(b); if (a !== b) parent[a] = b; };
  const idx = geo.index ? geo.index.array : null;
  const tris = idx ? idx.length / 3 : n / 3;
  for (let t = 0; t < tris; t++) {
    const a = idx ? idx[t * 3] : t * 3, b = idx ? idx[t * 3 + 1] : t * 3 + 1, c = idx ? idx[t * 3 + 2] : t * 3 + 2;
    unite(a, b); unite(a, c);
  }
  if (uv) {
    const seen = new Map();
    for (let i = 0; i < n; i++) {
      const k = Math.round(uv.getX(i) * 8192) * 65536 + Math.round(uv.getY(i) * 8192);
      const j = seen.get(k);
      if (j === undefined) seen.set(k, i); else unite(i, j);
    }
  }
  const label = new Map();
  const out = new Int32Array(n);
  for (let i = 0; i < n; i++) {
    const r = find(i);
    let id = label.get(r);
    if (id === undefined) { id = firstId + label.size; label.set(r, id); }
    out[i] = id;
  }
  return { vert: out, count: label.size };
}

// pinta en ids la isla de cada triángulo; grow = margen en texels (2.º pase rellena el hueco de alrededor)
function rasterIslands(pt, geo, uvName, vert, grow, onlyEmpty) {
  const uv = geo.attributes[uvName];
  if (!uv) return;
  const ids = pt.ids, w = pt.w, h = pt.h;
  const idx = geo.index ? geo.index.array : null;
  const tris = idx ? idx.length / 3 : geo.attributes.position.count / 3;
  for (let t = 0; t < tris; t++) {
    const a = idx ? idx[t * 3] : t * 3, b = idx ? idx[t * 3 + 1] : t * 3 + 1, c = idx ? idx[t * 3 + 2] : t * 3 + 2;
    const ax = uv.getX(a) * w, ay = uv.getY(a) * h, bx = uv.getX(b) * w, by = uv.getY(b) * h;
    const cx = uv.getX(c) * w, cy = uv.getY(c) * h;
    const area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay);
    if (Math.abs(area) < 1e-6) continue;
    const s = area > 0 ? 1 : -1;
    const lab = Math.hypot(bx - ax, by - ay), lbc = Math.hypot(cx - bx, cy - by), lca = Math.hypot(ax - cx, ay - cy);
    const x0 = Math.max(0, Math.floor(Math.min(ax, bx, cx) - grow)), x1 = Math.min(w - 1, Math.ceil(Math.max(ax, bx, cx) + grow));
    const y0 = Math.max(0, Math.floor(Math.min(ay, by, cy) - grow)), y1 = Math.min(h - 1, Math.ceil(Math.max(ay, by, cy) + grow));
    const id = vert[a];
    for (let y = y0; y <= y1; y++) {
      const py = y + 0.5;
      for (let x = x0; x <= x1; x++) {
        const px = x + 0.5;
        const e0 = s * ((bx - ax) * (py - ay) - (by - ay) * (px - ax)) / lab;
        if (e0 < -grow) continue;
        const e1 = s * ((cx - bx) * (py - by) - (cy - by) * (px - bx)) / lbc;
        if (e1 < -grow) continue;
        const e2 = s * ((ax - cx) * (py - cy) - (ay - cy) * (px - cx)) / lca;
        if (e2 < -grow) continue;
        const i = y * w + x;
        const cur = ids[i];
        if (onlyEmpty) { if (cur === -1) ids[i] = id; }
        else ids[i] = cur >= 0 && cur !== id ? -2 : (cur === -2 ? -2 : id);  // -2: UV superpuesta, de varias islas
      }
    }
  }
}

function buildIslandMaps() {
  const users = new Map();  // PaintTex -> [{mesh, uvName}]
  for (const m of S.meshes) {
    for (const s of m.userData.slots || []) {
      if (!s) continue;
      if (!users.has(s.pt)) users.set(s.pt, []);
      users.get(s.pt).push({ mesh: m, uvName: s.uv === 1 ? 'uv1' : 'uv' });
    }
  }
  for (const [pt, list] of users) {
    pt.ids = new Int32Array(pt.w * pt.h).fill(-1);
    let next = 0;
    for (const u of list) {
      const r = vertexIslands(u.mesh.geometry, u.uvName, next);
      u.mesh.userData.vertIsland = r.vert;
      next += r.count;
    }
    for (const u of list) rasterIslands(pt, u.mesh.geometry, u.uvName, u.mesh.userData.vertIsland, 0.75, false);
    for (const u of list) rasterIslands(pt, u.mesh.geometry, u.uvName, u.mesh.userData.vertIsland, 3, true);
  }
}

function hexRgb(c) {
  const n = parseInt(c.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function mkCanvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return c;
}

async function fetchImage(url) {
  const r = await fetch(url);
  if (!r.ok) return null;
  return createImageBitmap(await r.blob(), { premultiplyAlpha: 'none', colorSpaceConversion: 'none' });
}

// ---------- carga de armas ----------
const loader = new GLTFLoader();

async function loadWeapon(w) {
  if (anyChanged() && !confirm('Hay pintura sin guardar. ¿Cambiar de arma y perderla?')) {
    $('weapon').value = S.weapon?.glb || '';
    return;
  }
  showLoading(true);
  try {
    disposeWeapon();
    S.weapon = w;
    localStorage.setItem('rumbang_painter_weapon', w.glb);
    const buf = await (await fetch(api('/api/glb', { p: w.glb }))).arrayBuffer();
    const gltf = await loader.parseAsync(buf, '');
    const byIndex = new Map(w.materials.map((m) => [m.index, m]));
    const pending = [];
    gltf.scene.traverse((o) => {
      if (!o.isMesh) return;
      o.geometry.computeBoundsTree();
      const mats = Array.isArray(o.material) ? o.material : [o.material];
      o.userData.slots = mats.map(() => null);
      mats.forEach((m, slot) => {
        const assoc = gltf.parser.associations.get(m);
        const info = assoc && byIndex.get(assoc.materials);
        if (info) pending.push({ mesh: o, slot, info, orig: m });
      });
      S.meshes.push(o);
    });
    for (const p of pending) {
      let pt = S.textures.get(p.info.tex);
      if (!pt) {
        const [img, layer] = await Promise.all([
          fetchImage(api('/api/base', { t: p.info.tex })),
          p.info.painted ? fetchImage(api('/api/layer', { t: p.info.tex })) : null,
        ]);
        if (!img) continue;
        pt = new PaintTex(p.info.tex, img, layer);
        S.textures.set(p.info.tex, pt);
      }
      const common = {
        map: pt.tex,
        side: p.orig.side,
        transparent: p.orig.transparent,
        alphaTest: p.info.alpha === 'MASK' ? (p.orig.alphaTest || 0.5) : 0,
      };
      const lit = new THREE.MeshLambertMaterial(common);
      const flat = new THREE.MeshBasicMaterial(common);
      p.mesh.userData.slots[p.slot] = { pt, uv: p.info.uv, lit, flat };
      setSlotMaterial(p.mesh, p.slot, S.light ? lit : flat);
      p.orig.dispose();
    }
    buildIslandMaps();
    root.add(gltf.scene);
    applyWire();
    frame();
    updateInfo();
  } catch (e) {
    console.error(e);
    toast('No se pudo cargar: ' + e.message);
  } finally {
    showLoading(false);
  }
}

function setSlotMaterial(mesh, slot, mat) {
  if (Array.isArray(mesh.material)) mesh.material[slot] = mat;
  else mesh.material = mat;
}

function disposeWeapon() {
  root.clear();
  for (const m of S.meshes) {
    m.geometry.disposeBoundsTree?.();
    m.geometry.dispose();
  }
  for (const pt of S.textures.values()) pt.tex.dispose();
  S.meshes = [];
  S.textures.clear();
  S.undo = [];
  S.redo = [];
  updateSaveButton();
}

function frame() {
  const box = new THREE.Box3().setFromObject(root);
  if (box.isEmpty()) return;
  const c = box.getCenter(new THREE.Vector3());
  const r = box.getSize(new THREE.Vector3()).length() * 0.5;
  const vHalf = THREE.MathUtils.degToRad(camera.fov * 0.5);
  const hHalf = Math.atan(Math.tan(vHalf) * camera.aspect);  // en vertical (celular) manda el ancho
  const d = r / Math.sin(Math.min(vHalf, hHalf)) * 1.05;
  const dir = camera.position.clone().sub(controls.target).normalize();
  if (dir.lengthSq() < 0.5) dir.set(0, 0.3, 1).normalize();
  controls.target.copy(c);
  camera.position.copy(c).addScaledVector(dir, d);
  camera.near = Math.max(r / 500, 0.001);
  camera.far = d + r * 10;
  camera.updateProjectionMatrix();
  controls.update();
}

function applyWire() {
  const on = $('wire').checked;
  for (const m of S.meshes) {
    for (const s of m.userData.slots || []) if (s) { s.lit.wireframe = on; s.flat.wireframe = on; }
  }
}

function applyLight() {
  for (const m of S.meshes) {
    (m.userData.slots || []).forEach((s, i) => { if (s) setSlotMaterial(m, i, S.light ? s.lit : s.flat); });
  }
}

// ---------- pintura ----------
const ray = new THREE.Raycaster();
ray.firstHitOnly = true;
const ndc = new THREE.Vector2();
const _a = new THREE.Vector3(), _b = new THREE.Vector3(), _c = new THREE.Vector3();
const _ua = new THREE.Vector2(), _ub = new THREE.Vector2(), _uc = new THREE.Vector2();

function hitAt(x, y) {
  const r = canvas.getBoundingClientRect();
  ndc.set(((x - r.left) / r.width) * 2 - 1, -((y - r.top) / r.height) * 2 + 1);
  ray.setFromCamera(ndc, camera);
  const hits = ray.intersectObjects(S.meshes, false);
  for (const h of hits) {
    const slot = h.face?.materialIndex ?? 0;
    const s = h.object.userData.slots?.[Array.isArray(h.object.material) ? slot : 0];
    const uv = s && (s.uv === 1 && h.uv1 ? h.uv1 : h.uv);
    if (s && uv) return { h, s, uv };
    return null;  // lo primero que se toca no es pintable: no se pinta a través
  }
  return null;
}

// texels por unidad de mundo en el triángulo tocado: el pincel mide lo mismo en pantalla en todo el modelo
function texelsPerWorld(hit, pt, uvAttrName) {
  const g = hit.h.object.geometry;
  const pos = g.attributes.position, uvA = g.attributes[uvAttrName];
  const f = hit.h.face;
  if (!uvA) return 0;
  const mw = hit.h.object.matrixWorld;
  _a.fromBufferAttribute(pos, f.a).applyMatrix4(mw);
  _b.fromBufferAttribute(pos, f.b).applyMatrix4(mw);
  _c.fromBufferAttribute(pos, f.c).applyMatrix4(mw);
  const areaW = _b.sub(_a).cross(_c.sub(_a)).length() * 0.5;
  _ua.fromBufferAttribute(uvA, f.a); _ub.fromBufferAttribute(uvA, f.b); _uc.fromBufferAttribute(uvA, f.c);
  const areaT = Math.abs((_ub.x - _ua.x) * (_uc.y - _ua.y) - (_uc.x - _ua.x) * (_ub.y - _ua.y)) * 0.5 * pt.w * pt.h;
  if (areaW < 1e-12 || areaT < 1e-6) return 0;
  return Math.sqrt(areaT / areaW);
}

function worldPerScreenPx(dist) {
  return (2 * dist * Math.tan(THREE.MathUtils.degToRad(camera.fov * 0.5))) / canvas.clientHeight;
}

let stroke = null;  // { touched:Set<PaintTex>, snaps:[], last:{x,y}, smooth:{x,y}, pointerId, lastUV:Map }

function beginStroke(e) {
  stroke = { touched: new Set(), snaps: [], smooth: { x: e.clientX, y: e.clientY }, last: null,
    pointerId: e.pointerId, pen: e.pointerType === 'pen', lastStamp: new Map() };
  stroke.rgb = S.tool === 'erase' ? [0, 0, 0] : hexRgb(S.color);
  for (const pt of S.textures.values()) { pt.strokeAlpha = S.opacity; pt.strokeErase = S.tool === 'erase'; }
  strokeTo(e.clientX, e.clientY, e.pressure, true);
}

function touchTex(pt) {
  if (stroke.touched.has(pt)) return;
  stroke.touched.add(pt);
  stroke.snaps.push({ pt, img: pt.lctx.getImageData(0, 0, pt.w, pt.h), changed: pt.changed });
  pt.ensureStroke();
  pt.clearStroke();
  pt.strokeActive = true;
}

function stampAt(x, y, pressure) {
  const hit = hitAt(x, y);
  if (!hit) { stroke.lastStamp.clear(); return; }
  const pt = hit.s.pt;
  touchTex(pt);
  const tpw = texelsPerWorld(hit, pt, hit.s.uv === 1 ? 'uv1' : 'uv');
  let rad = S.size * 0.5 * worldPerScreenPx(hit.h.distance) * (tpw || 0);
  if (stroke.pen && S.pressure && pressure > 0) rad *= 0.25 + 0.75 * pressure;
  rad = Math.max(rad, 0.6);
  const u = hit.uv.x - Math.floor(hit.uv.x), v = hit.uv.y - Math.floor(hit.uv.y);
  const island = hit.h.object.userData.vertIsland?.[hit.h.face.a] ?? -1;
  const px = u * pt.w, py = v * pt.h;
  // unir con el sello anterior si sigue en la misma isla y cerca: línea sin huecos aunque el dedo vaya rápido
  const prev = stroke.lastStamp.get(pt);
  if (prev && prev.island === island) {
    const dist = Math.hypot(px - prev.x, py - prev.y);
    if (dist < Math.max(prev.r, rad) * 6) {
      const n = Math.ceil(dist / Math.max(0.5, rad * 0.35));
      for (let i = 1; i < n; i++) {
        const t = i / n;
        pt.stamp(prev.x + (px - prev.x) * t, prev.y + (py - prev.y) * t, prev.r + (rad - prev.r) * t, island, stroke.rgb);
      }
    }
  }
  pt.stamp(px, py, rad, island, stroke.rgb);
  stroke.lastStamp.clear();
  stroke.lastStamp.set(pt, { x: px, y: py, r: rad, island });
}

function strokeTo(x, y, pressure, first = false) {
  const k = first ? 1 : 1 - S.stab;
  const sx = stroke.smooth.x + (x - stroke.smooth.x) * k;
  const sy = stroke.smooth.y + (y - stroke.smooth.y) * k;
  stroke.smooth = { x: sx, y: sy };
  if (!stroke.last) { stampAt(sx, sy, pressure); stroke.last = { x: sx, y: sy }; return; }
  const dx = sx - stroke.last.x, dy = sy - stroke.last.y;
  const dist = Math.hypot(dx, dy);
  const step = Math.max(1, S.size * 0.3);
  const n = Math.min(64, Math.floor(dist / step));
  for (let i = 1; i <= n; i++) stampAt(stroke.last.x + (dx * i) / n, stroke.last.y + (dy * i) / n, pressure);
  if (n > 0) stroke.last = { x: sx, y: sy };
}

function endStroke(commit) {
  if (!stroke) return;
  for (const pt of stroke.touched) {
    if (commit) {
      pt.flushStroke();
      pt.lctx.globalCompositeOperation = pt.strokeErase ? 'destination-out' : 'source-over';
      pt.lctx.globalAlpha = pt.strokeAlpha;
      pt.lctx.drawImage(pt.stroke, 0, 0);
      pt.lctx.globalAlpha = 1;
      pt.lctx.globalCompositeOperation = 'source-over';
    }
    pt.clearStroke();
    pt.strokeActive = false;
    pt.dirty = true;
  }
  if (commit) {
    if (stroke.snaps.length) {
      for (const s of stroke.snaps) s.pt.changed = true;
      S.undo.push(stroke.snaps);
      if (S.undo.length > MAX_UNDO) S.undo.shift();
      S.redo = [];
    }
  } else {
    for (const s of stroke.snaps) { s.pt.lctx.putImageData(s.img, 0, 0); s.pt.changed = s.changed; }
  }
  stroke = null;
  updateSaveButton();
}

function swapHistory(from, to) {
  const entry = from.pop();
  if (!entry) return;
  const back = entry.map((s) => ({ pt: s.pt, img: s.pt.lctx.getImageData(0, 0, s.pt.w, s.pt.h), changed: s.pt.changed }));
  for (const s of entry) { s.pt.lctx.putImageData(s.img, 0, 0); s.pt.changed = true; s.pt.dirty = true; }
  to.push(back);
  updateSaveButton();
}

function pickAt(x, y) {
  const hit = hitAt(x, y);
  if (!hit) return;
  const pt = hit.s.pt;
  const u = hit.uv.x - Math.floor(hit.uv.x), v = hit.uv.y - Math.floor(hit.uv.y);
  const d = pt.cctx.getImageData(Math.min(pt.w - 1, Math.floor(u * pt.w)), Math.min(pt.h - 1, Math.floor(v * pt.h)), 1, 1).data;
  setColor('#' + [d[0], d[1], d[2]].map((c) => c.toString(16).padStart(2, '0')).join(''));
  setTool('brush');
}

// ---------- entrada ----------
const pointers = new Map();
canvas.addEventListener('pointerdown', (e) => {
  pointers.set(e.pointerId, e.pointerType);
  if (stroke) {  // segundo dedo: era un gesto de cámara, se anula el trazo
    if (e.pointerType === 'touch') endStroke(false);
    return;
  }
  const wantsPaint = e.pointerType === 'pen' || (S.paintMode && (e.pointerType !== 'mouse' || e.button === 0));
  const fingersDown = [...pointers.values()].filter((t) => t === 'touch').length;
  if (!wantsPaint || fingersDown > 1 || S.weapon == null) return;
  if (S.tool === 'pick') { pickAt(e.clientX, e.clientY); return; }
  try { canvas.setPointerCapture(e.pointerId); } catch { /* puntero sintético o ya soltado */ }
  beginStroke(e);
});
canvas.addEventListener('pointermove', (e) => {
  moveCursor(e);
  if (!stroke || e.pointerId !== stroke.pointerId) return;
  const evs = e.getCoalescedEvents ? e.getCoalescedEvents() : [e];
  for (const ce of (evs.length ? evs : [e])) strokeTo(ce.clientX, ce.clientY, ce.pressure);
});
const up = (e) => {
  pointers.delete(e.pointerId);
  if (stroke && e.pointerId === stroke.pointerId) endStroke(e.type !== 'pointercancel');
  if (e.pointerType !== 'mouse') $('cursor').style.display = 'none';
};
canvas.addEventListener('pointerup', up);
canvas.addEventListener('pointercancel', up);
canvas.addEventListener('pointerleave', () => { if (!stroke) $('cursor').style.display = 'none'; });
canvas.addEventListener('contextmenu', (e) => e.preventDefault());

function moveCursor(e) {
  const c = $('cursor');
  if (S.tool === 'pick' || (!S.paintMode && e.pointerType !== 'pen')) { c.style.display = 'none'; return; }
  c.style.display = 'block';
  c.style.left = e.clientX + 'px';
  c.style.top = e.clientY + 'px';
  c.style.width = c.style.height = Math.max(4, S.size) + 'px';
}

window.addEventListener('keydown', (e) => {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return;
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') { e.preventDefault(); swapHistory(e.shiftKey ? S.redo : S.undo, e.shiftKey ? S.undo : S.redo); }
  else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'y') { e.preventDefault(); swapHistory(S.redo, S.undo); }
  else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') { e.preventDefault(); save(); }
  else if (e.key === 'b') setTool('brush');
  else if (e.key === 'e') setTool('erase');
  else if (e.key === 'i') setTool('pick');
  else if (e.key === '[') setSize(S.size - 1);
  else if (e.key === ']') setSize(S.size + 1);
});

// ---------- guardar ----------
const toBlob = (c) => new Promise((res) => c.toBlob(res, 'image/png'));

async function save() {
  const list = [...S.textures.values()].filter((pt) => pt.changed);
  if (!list.length) { toast('Nada nuevo que guardar'); return; }
  $('save').disabled = true;
  const done = [];
  try {
    for (const pt of list) {
      pt.redraw();
      const [fin, lay] = await Promise.all([toBlob(pt.comp), toBlob(pt.layer)]);
      const body = new Blob([fin, lay]);
      const r = await fetch(api('/api/save', { t: pt.name, nf: fin.size }), { method: 'POST', body });
      const j = await r.json();
      if (!r.ok) throw new Error(j.error || r.status);
      pt.changed = false;
      done.push(j.path.split('/').pop());
      const info = S.weapon.materials.find((m) => m.tex === pt.name);
      if (info) info.painted = true;
    }
    toast('Guardado: ' + done.join(', ') + ' — enfoca el editor de Godot para reimportar');
  } catch (e) {
    toast('Error al guardar: ' + e.message);
  } finally {
    $('save').disabled = false;
    updateSaveButton();
  }
}

function anyChanged() { return [...S.textures.values()].some((pt) => pt.changed); }
function updateSaveButton() { $('save').classList.toggle('dirty', anyChanged()); }
window.addEventListener('beforeunload', (e) => { if (anyChanged()) { e.preventDefault(); e.returnValue = ''; } });

// ---------- UI ----------
function toast(msg) {
  const t = $('toast');
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => t.classList.remove('show'), 3500);
}
function showLoading(on) { $('loading').classList.toggle('show', on); }

function setTool(t) {
  S.tool = t;
  document.querySelectorAll('.tool').forEach((b) => b.classList.toggle('on', b.dataset.tool === t));
}
function setColor(c) {
  S.color = c;
  $('picker').value = c;
  document.querySelectorAll('.swatch').forEach((b) => b.classList.toggle('on', b.dataset.c === c));
  $('sizeDot').style.background = c;
}
function setSize(v) {
  S.size = Math.max(1, Math.min(60, v));
  $('size').value = S.size;
  $('sizeVal').textContent = S.size;
  const d = $('sizeDot');
  d.style.width = d.style.height = Math.max(3, S.size) + 'px';
}

function updateInfo() {
  const w = S.weapon;
  if (!w) return;
  const names = w.materials.map((m) => m.tex + (m.has_toon ? '' : ' (sin toon)') + (m.painted ? ' ✎' : ''));
  $('info').textContent = names.length
    ? `${w.name}: ${names.join(' · ')}`
    : `${w.name}: no tiene texturas (colores planos), no se puede pintar`;
}

function buildUI() {
  const sw = $('swatches');
  for (const c of SWATCHES) {
    const b = document.createElement('button');
    b.className = 'swatch';
    b.dataset.c = c;
    b.style.background = c;
    b.addEventListener('click', () => { setColor(c); if (S.tool === 'pick') setTool('brush'); });
    sw.appendChild(b);
  }
  const pick = document.createElement('input');
  pick.type = 'color';
  pick.id = 'picker';
  pick.addEventListener('input', () => setColor(pick.value));
  sw.appendChild(pick);

  document.querySelectorAll('.tool').forEach((b) => b.addEventListener('click', () => setTool(b.dataset.tool)));
  $('mode').addEventListener('click', () => { S.paintMode = !S.paintMode; applyMode(); });
  $('undo').addEventListener('click', () => swapHistory(S.undo, S.redo));
  $('redo').addEventListener('click', () => swapHistory(S.redo, S.undo));
  $('frame').addEventListener('click', frame);
  $('more').addEventListener('click', () => $('panel').classList.toggle('open'));
  $('save').addEventListener('click', save);
  $('size').addEventListener('input', (e) => setSize(+e.target.value));
  $('opacity').addEventListener('input', (e) => { S.opacity = e.target.value / 100; $('opacityVal').textContent = e.target.value; });
  $('stab').addEventListener('input', (e) => { S.stab = e.target.value / 100; $('stabVal').textContent = e.target.value; });
  $('light').addEventListener('change', (e) => { S.light = e.target.checked; applyLight(); });
  $('pressure').addEventListener('change', (e) => { S.pressure = e.target.checked; });
  $('wire').addEventListener('change', applyWire);
  $('clearLayer').addEventListener('click', () => {
    const list = [...S.textures.values()];
    if (!list.length || !confirm('¿Borrar toda la pintura de esta arma? (se puede deshacer)')) return;
    const snaps = list.map((pt) => ({ pt, img: pt.lctx.getImageData(0, 0, pt.w, pt.h), changed: pt.changed }));
    for (const pt of list) { pt.lctx.clearRect(0, 0, pt.w, pt.h); pt.changed = true; pt.dirty = true; }
    S.undo.push(snaps);
    S.redo = [];
    updateSaveButton();
  });
  $('weapon').addEventListener('change', (e) => {
    const w = S.weapons.find((x) => x.glb === e.target.value);
    if (w) loadWeapon(w);
  });
  setColor(INK);
  setSize(S.size);
  applyMode();
}

async function init() {
  buildUI();
  if (!KEY) { toast('Falta la clave: abre la URL completa que imprime server.py'); return; }
  const r = await fetch(api('/api/weapons'));
  if (!r.ok) { toast('Clave incorrecta: abre la URL que imprime server.py'); return; }
  S.weapons = await r.json();
  const sel = $('weapon');
  for (const w of S.weapons) {
    const o = document.createElement('option');
    o.value = w.glb;
    o.textContent = w.name + (w.materials.length ? '' : ' — sin textura');
    o.disabled = !w.materials.length;
    sel.appendChild(o);
  }
  const last = localStorage.getItem('rumbang_painter_weapon');
  const first = S.weapons.find((w) => w.glb === last && w.materials.length) || S.weapons.find((w) => w.materials.length);
  if (first) { sel.value = first.glb; loadWeapon(first); }
}

renderer.setAnimationLoop(() => {
  for (const pt of S.textures.values()) if (pt.dirty) pt.redraw();
  controls.update();
  renderer.render(scene, camera);
});

init();

window.__painter = { S, hitAt, camera };  // depuración desde la consola del navegador
