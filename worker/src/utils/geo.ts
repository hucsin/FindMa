import type { GeofenceRow } from '../types';

const EARTH_R = 6371008.8; // 平均地球半径（米）
const DEG = Math.PI / 180;

/** Haversine 球面距离（米） */
export function haversineMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const dLat = (lat2 - lat1) * DEG;
  const dLng = (lng2 - lng1) * DEG;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * DEG) * Math.cos(lat2 * DEG) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_R * Math.asin(Math.min(1, Math.sqrt(a)));
}

/**
 * 射线法（Ray Casting）判断点是否在多边形内。
 * polygon 为 [[lat,lng], ...]，与 DESIGN 6.3 polygon_json 格式一致。
 */
export function pointInPolygon(lat: number, lng: number, polygon: number[][]): boolean {
  if (!Array.isArray(polygon) || polygon.length < 3) return false;
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const yi = polygon[i][0];
    const xi = polygon[i][1];
    const yj = polygon[j][0];
    const xj = polygon[j][1];
    // 注意：这里把 lng 当 x、lat 当 y，与 polygon 的 [lat,lng] 对应
    const intersect = yi > lat !== yj > lat && lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

/** 点到线段的最近距离（米）：局部等距圆柱投影近似，几十公里内误差 < 0.1% */
function distPointToSegmentMeters(
  lat: number,
  lng: number,
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const k = Math.cos(lat * DEG);
  const ax = (lng1 - lng) * 111320 * k;
  const ay = (lat1 - lat) * 110540;
  const bx = (lng2 - lng) * 111320 * k;
  const by = (lat2 - lat) * 110540;
  const dx = bx - ax;
  const dy = by - ay;
  const len2 = dx * dx + dy * dy;
  let t = len2 === 0 ? 0 : (-ax * dx - ay * dy) / len2;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(ax + t * dx, ay + t * dy);
}

/** 点到多边形边界的最短距离（米）；点在内部时返回 0 */
export function distanceToPolygonMeters(
  lat: number,
  lng: number,
  polygon: number[][],
): number {
  if (pointInPolygon(lat, lng, polygon)) return 0;
  let min = Number.POSITIVE_INFINITY;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const d = distPointToSegmentMeters(lat, lng, polygon[i][0], polygon[i][1], polygon[j][0], polygon[j][1]);
    if (d < min) min = d;
  }
  return min;
}

export interface FenceEvalInput {
  fence: Pick<GeofenceRow, 'type' | 'center_lat' | 'center_lng' | 'radius_m' | 'polygon_json'> | null;
  lat: number;
  lng: number;
  accuracy?: number | null;
  /** 上次判定：1 在内 / 0 在外 / null 未判定 */
  prevInFence: number | null;
  /** 是否已建立过初始状态 */
  fenceInitialized: boolean;
  bufferM: number;
  accuracyGateM: number;
}

export interface FenceEvalResult {
  /** 本点是否真正参与了判定（false：无围栏 / 精度不足 → 该点 in_fence 存 NULL） */
  judged: boolean;
  /** 判定结果：1 在内 / 0 在外；judged=false 时为 null */
  inFence: number | null;
  /** 状态翻转：'out' = 出界，'in' = 回界，null = 无翻转 */
  transition: 'out' | 'in' | null;
  /** 到围栏边界的有向距离（米，圆为 d-R；多边形为到边界距离，内为 0） */
  distanceM: number | null;
}

const NOT_JUDGED: FenceEvalResult = {
  judged: false,
  inFence: null,
  transition: null,
  distanceM: null,
};

/**
 * 围栏判定（DESIGN 6.4）：
 *  1) 精度门槛：acc > gate → 不参与判定（该点 in_fence=NULL），设备状态保持；
 *  2) 缓冲带：d > R+buffer 判外、d < R 判内，R~R+buffer 之间保持原状态；
 *  3) 仅状态翻转才产生 transition。
 */
export function evaluateFence(i: FenceEvalInput): FenceEvalResult {
  if (!i.fence) return NOT_JUDGED;

  // ① 精度门槛 —— 不参与判定，该点 in_fence 记为 NULL，但设备状态保持
  if (i.accuracy != null && Number.isFinite(i.accuracy) && i.accuracy > i.accuracyGateM) {
    return NOT_JUDGED;
  }

  const { bufferM } = i;
  // 缓冲带内保持原状态：仍然"判定"为沿用值（便于地图展示），但不产生翻转
  const keepPrev = (distanceM: number): FenceEvalResult => ({
    judged: i.prevInFence != null,
    inFence: i.prevInFence,
    transition: null,
    distanceM,
  });

  let inside: boolean;
  let distM: number;

  if (i.fence.type === 'circle') {
    if (i.fence.center_lat == null || i.fence.center_lng == null || i.fence.radius_m == null) {
      return NOT_JUDGED;
    }
    distM = haversineMeters(i.lat, i.lng, i.fence.center_lat, i.fence.center_lng);
    inside = distM <= i.fence.radius_m;
    // ② 缓冲带
    if (i.fenceInitialized && i.prevInFence != null) {
      if (distM > i.fence.radius_m + bufferM) inside = false;
      else if (distM <= i.fence.radius_m) inside = true;
      else return keepPrev(distM - i.fence.radius_m);
    }
  } else {
    const polygon = parsePolygon(i.fence.polygon_json);
    if (polygon.length < 3) return NOT_JUDGED;
    const d = distanceToPolygonMeters(i.lat, i.lng, polygon);
    inside = d === 0;
    distM = inside ? 0 : d;
    if (i.fenceInitialized && i.prevInFence != null) {
      if (d > bufferM) inside = false;
      else if (d === 0) inside = true;
      else return keepPrev(d);
    }
  }

  const inFence = inside ? 1 : 0;

  // ③ 状态翻转（首次判定不产生 transition，由调用方决定是否"立即告警"）
  let transition: 'out' | 'in' | null = null;
  if (i.fenceInitialized && i.prevInFence != null && i.prevInFence !== inFence) {
    transition = inFence === 0 ? 'out' : 'in';
  }

  return {
    judged: true,
    inFence,
    transition,
    distanceM:
      i.fence.type === 'circle' && i.fence.radius_m != null ? distM - i.fence.radius_m : distM,
  };
}

export function parsePolygon(json: string | null): number[][] {
  if (!json) return [];
  try {
    const arr = JSON.parse(json);
    if (!Array.isArray(arr)) return [];
    return arr.filter(
      (p) => Array.isArray(p) && p.length >= 2 && Number.isFinite(p[0]) && Number.isFinite(p[1]),
    ) as number[][];
  } catch {
    return [];
  }
}

/** 经纬度合法性 */
export function isValidLatLng(lat: unknown, lng: unknown): boolean {
  return (
    typeof lat === 'number' &&
    typeof lng === 'number' &&
    Number.isFinite(lat) &&
    Number.isFinite(lng) &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180 &&
    !(lat === 0 && lng === 0)
  );
}
