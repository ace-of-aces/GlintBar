#!/usr/bin/env node
/**
 * Glint's icon, Lens: a clear glass lens on a slider track, bending the bar beneath it.
 *
 * Writes four drawings next to this script:
 *   app.svg            1024x1024 macOS app icon (continuous-corner body on the 824pt grid)
 *   menubar.svg        22x16pt template image, Glint bar showing
 *   menubar-off.svg    22x16pt template image, app controls showing
 *   touchbar.svg       32x22pt Control Strip glyph at rest; the "sweep" group is the highlight
 *                      that runs around the rim when the glint plays
 *
 * The app uses app.svg through scripts/make-app-icon.sh. The menu bar and Control Strip
 * glyphs are drawn in code from the same geometry (Sources/Glint/Icons/LensGlyph.swift).
 *
 * Usage: node Design/Icons/make-icons.mjs
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const OUT = process.argv[2] ?? dirname(fileURLToPath(import.meta.url));

// --------------------------------------------------------------------------- shared geometry

// Control points of one continuous corner, in units of the corner radius
// (the same curve UIKit uses for icon masks).
const CORNER = [
    ["L", [1.52866471, 0]],
    ["C", [1.08849323, 0], [0.86840689, 0], [0.66993427, 0.065496]],
    ["L", [0.63149399, 0.074911]],
    ["C", [0.37282392, 0.16905899], [0.16906013, 0.37282401], [0.07491176, 0.63149399]],
    ["C", [0, 0.86840701], [0, 1.08849299], [0, 1.52866483]],
];

function continuousRect(x, y, w, h, r) {
    // (corner point, x direction into the rect, y direction into the rect)
    const corners = [[[x + w, y], -1, 1], [[x + w, y + h], -1, -1], [[x, y + h], 1, -1], [[x, y], 1, 1]];
    let d = `M${(x + 1.52866483 * r).toFixed(2)},${y.toFixed(2)}`;
    corners.forEach(([[cx, cy], sx, sy], i) => {
        const swap = i % 2 === 1; // walk the bottom-right and top-left corners from the vertical edge
        for (const [command, ...points] of CORNER) {
            const pts = points.map(([u, v]) => {
                const [a, b] = swap ? [v, u] : [u, v];
                return `${(cx + sx * a * r).toFixed(2)},${(cy + sy * b * r).toFixed(2)}`;
            });
            d += ` ${command}` + pts.join(" ");
        }
    });
    return d + "Z";
}

const SQ = continuousRect(100, 100, 824, 824, 185.4);

const f = (v) => v.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");

/** Four-point star with concave sides. k sets the waist, w how round it is. */
function sparkle(cx, cy, rx, ry = rx, k = 0.3, w = 0.22) {
    const c = Math.min(rx, ry) * k;
    const a = c * w;
    return (
        `M${f(cx)},${f(cy - ry)} ` +
        `C${f(cx + a)},${f(cy - c)} ${f(cx + c)},${f(cy - a)} ${f(cx + rx)},${f(cy)} ` +
        `C${f(cx + c)},${f(cy + a)} ${f(cx + a)},${f(cy + c)} ${f(cx)},${f(cy + ry)} ` +
        `C${f(cx - a)},${f(cy + c)} ${f(cx - c)},${f(cy + a)} ${f(cx - rx)},${f(cy)} ` +
        `C${f(cx - c)},${f(cy - a)} ${f(cx - a)},${f(cy - c)} ${f(cx)},${f(cy - ry)}Z`
    );
}

function capsule(x, y, w, h, attrs) {
    const extra = Object.entries(attrs).map(([k, v]) => `${k}="${v}"`).join(" ");
    return `<rect x="${f(x)}" y="${f(y)}" width="${f(w)}" height="${f(h)}" rx="${f(h / 2)}" ${extra}/>`;
}

function blur(id, sd, pad = "-60%", size = "220%") {
    return (
        `<filter id="${id}" x="${pad}" y="${pad}" width="${size}" height="${size}" ` +
        `color-interpolation-filters="sRGB"><feGaussianBlur stdDeviation="${sd}"/></filter>`
    );
}

function app(p, defs, body, rimStrength = 1.0) {
    const r = rimStrength;
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
<clipPath id="${p}sq"><path d="${SQ}"/></clipPath>
<linearGradient id="${p}rim" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="#fff" stop-opacity="${(0.6 * r).toFixed(2)}"/>
<stop offset=".3" stop-color="#fff" stop-opacity="${(0.1 * r).toFixed(2)}"/>
<stop offset=".72" stop-color="#fff" stop-opacity="${(0.03 * r).toFixed(2)}"/>
<stop offset="1" stop-color="#fff" stop-opacity="${(0.28 * r).toFixed(2)}"/>
</linearGradient>
${defs}
</defs>
<g clip-path="url(#${p}sq)">
${body}
<path d="${SQ}" fill="none" stroke="url(#${p}rim)" stroke-width="7"/>
</g>
</svg>
`;
}

function small(width, height, defs, body) {
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}">
<defs>${defs}</defs>
${body}
</svg>
`;
}

const menubar = (defs, body) => small(22, 16, defs, body);
const touchbar = (defs, body) => small(32, 22, defs, body);

// --------------------------------------------------------------------------- refraction

/**
 * A round glass lens. The middle magnifies evenly; toward the rim the glass bends
 * harder and harder, so lines bow out across the middle and curl back at the edge.
 */
class Refraction {
    constructor(cx, cy, R, mag = 1.25, edge = 0.08, n = 4) {
        Object.assign(this, { cx, cy, R, mag, edge, n });
        this.k = 1 + edge - 1 / mag;
    }

    sourceRadius(rho) {
        return rho / this.mag + this.k * rho ** this.n;
    }

    screenRadius(rs) {
        let lo = 0;
        let hi = 1;
        for (let i = 0; i < 40; i++) {
            const mid = (lo + hi) / 2;
            if (this.sourceRadius(mid) < rs) lo = mid;
            else hi = mid;
        }
        return (lo + hi) / 2;
    }

    point(x, y) {
        const dx = (x - this.cx) / this.R;
        const dy = (y - this.cy) / this.R;
        const r = Math.hypot(dx, dy);
        if (r < 1e-9) return [this.cx, this.cy];
        const limit = 1 + this.edge;
        const rho = r <= limit ? this.screenRadius(r) : 1 + (r - limit);
        return [this.cx + (dx / r) * rho * this.R, this.cy + (dy / r) * rho * this.R];
    }

    path(pts) {
        const q = pts.map(([x, y]) => this.point(x, y));
        return "M" + q.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" L") + "Z";
    }
}

function capsulePts(x, y, w, h, step = 3.0, arc = 32) {
    const r = h / 2;
    const n = Math.max(1, Math.trunc((w - 2 * r) / step));
    const pts = [];
    for (let i = 0; i <= n; i++) pts.push([x + r + ((w - 2 * r) * i) / n, y]);
    for (let i = 1; i < arc; i++) {
        const t = -Math.PI / 2 + (Math.PI * i) / arc;
        pts.push([x + w - r + r * Math.cos(t), y + r + r * Math.sin(t)]);
    }
    for (let i = 0; i <= n; i++) pts.push([x + w - r - ((w - 2 * r) * i) / n, y + h]);
    for (let i = 1; i < arc; i++) {
        const t = Math.PI / 2 + (Math.PI * i) / arc;
        pts.push([x + r + r * Math.cos(t), y + r + r * Math.sin(t)]);
    }
    return pts;
}

// --------------------------------------------------------------------------- app icon

const [CX, CY, R] = [592, 512, 204];
const [BX, BW, BH] = [136, 752, 150];
const BY = CY - BH / 2;
const [TX0, TX1, TH] = [214, 810, 16];

// Where the glint sits on the glass: inside the lens toward its upper right, over the bar.
const [GLINT_ANGLE, GLINT_RADIUS] = [-24, 0.52];

function lensApp() {
    const p = "ln-";
    const lens = new Refraction(CX, CY, R);

    const sceneFlat = `<rect width="1024" height="1024" fill="url(#${p}bg)"/>
${capsule(BX, BY, BW, BH, { fill: "#0B0B0F" })}
${capsule(BX, BY, BW, BH, { fill: `url(#${p}barGloss)` })}
${capsule(TX0, CY - TH / 2, TX1 - TX0, TH, { fill: "#fff", "fill-opacity": ".2" })}
${capsule(TX0, CY - TH / 2, CX - TX0, TH, { fill: `url(#${p}level)` })}`;

    // The bar's gloss follows the bar as the glass bends it, so it is drawn on the bent shape.
    const bar = lens.path(capsulePts(BX, BY, BW, BH));
    const bent = `<rect width="1024" height="1024" fill="url(#${p}bg)"/>
<path d="${bar}" fill="#0B0B0F"/>
<path d="${bar}" fill="url(#${p}barGloss)"/>
<path d="${lens.path(capsulePts(TX0, CY - TH / 2, TX1 - TX0, TH))}" fill="#fff" fill-opacity=".2"/>
<path d="${lens.path(capsulePts(TX0, CY - TH / 2, CX - TX0, TH))}" fill="#fff"/>`;

    const a = GLINT_ANGLE * (Math.PI / 180);
    const gx = CX + R * GLINT_RADIUS * Math.cos(a);
    const gy = CY + R * GLINT_RADIUS * Math.sin(a);
    const onGlass = `<circle cx="${f(gx)}" cy="${f(gy)}" r="60" fill="url(#${p}halo)"/>
<path d="${sparkle(gx, gy, 46, 46, 0.27)}" fill="#fff" opacity=".6" filter="url(#${p}b6)"/>
<path d="${sparkle(gx, gy, 40, 40, 0.25)}" fill="#fff"/>`;

    const defs = `
<linearGradient id="${p}bg" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#F8F9FB"/><stop offset=".6" stop-color="#E2E5EA"/><stop offset="1" stop-color="#C3C8D0"/>
</linearGradient>
<linearGradient id="${p}barGloss" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#fff" stop-opacity=".14"/><stop offset=".22" stop-color="#fff" stop-opacity="0"/><stop offset=".85" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#fff" stop-opacity=".08"/>
</linearGradient>
<linearGradient id="${p}level" x1="${TX0}" y1="0" x2="${CX}" y2="0" gradientUnits="userSpaceOnUse">
<stop offset="0" stop-color="#FFFFFF" stop-opacity=".75"/><stop offset="1" stop-color="#FFFFFF"/>
</linearGradient>
<clipPath id="${p}lensClip"><circle cx="${CX}" cy="${CY}" r="${R}"/></clipPath>
<radialGradient id="${p}edge" cx="${CX}" cy="${CY}" r="${R}" gradientUnits="userSpaceOnUse">
<stop offset=".74" stop-color="#0A1020" stop-opacity="0"/><stop offset=".93" stop-color="#0A1020" stop-opacity=".12"/><stop offset="1" stop-color="#0A1020" stop-opacity=".3"/>
</radialGradient>
<linearGradient id="${p}spec" x1="${CX - R}" y1="${CY - R}" x2="${CX + R * 0.2}" y2="${CY + R * 0.2}" gradientUnits="userSpaceOnUse">
<stop offset="0" stop-color="#fff" stop-opacity=".9"/><stop offset=".5" stop-color="#fff" stop-opacity=".08"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>
</linearGradient>
<linearGradient id="${p}rimG" x1="${CX - R}" y1="${CY - R}" x2="${CX + R}" y2="${CY + R}" gradientUnits="userSpaceOnUse">
<stop offset="0" stop-color="#fff"/><stop offset=".5" stop-color="#fff" stop-opacity=".18"/><stop offset="1" stop-color="#fff" stop-opacity=".75"/>
</linearGradient>
<radialGradient id="${p}halo" cx=".5" cy=".5" r=".5">
<stop offset="0" stop-color="#fff" stop-opacity=".55"/><stop offset=".45" stop-color="#fff" stop-opacity=".12"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>
</radialGradient>
<mask id="${p}crescent"><circle cx="${CX}" cy="${CY}" r="${R - 9}" fill="#fff"/><circle cx="${CX + 18}" cy="${CY + 22}" r="${R - 9}" fill="#000"/></mask>
<mask id="${p}crescentLow"><circle cx="${CX}" cy="${CY}" r="${R - 7}" fill="#fff"/><circle cx="${CX - 16}" cy="${CY - 20}" r="${R - 7}" fill="#000"/></mask>
${blur(p + "b24", 24)}${blur(p + "b3", 3)}${blur(p + "b6", 6)}
`;
    const body = `
${sceneFlat}
<ellipse cx="${CX + 8}" cy="${CY + 48}" rx="${R - 10}" ry="${R - 26}" fill="#1A2030" opacity=".34" filter="url(#${p}b24)"/>
<g clip-path="url(#${p}lensClip)">
${bent}
<circle cx="${CX}" cy="${CY}" r="${R}" fill="#fff" opacity=".04"/>
<circle cx="${CX}" cy="${CY}" r="${R}" fill="url(#${p}edge)"/>
<rect x="${CX - R}" y="${CY - R}" width="${2 * R}" height="${2 * R}" fill="url(#${p}spec)" mask="url(#${p}crescent)" opacity=".85"/>
<rect x="${CX - R}" y="${CY - R}" width="${2 * R}" height="${2 * R}" fill="#fff" mask="url(#${p}crescentLow)" opacity=".38" filter="url(#${p}b3)"/>
</g>
<circle cx="${CX}" cy="${CY}" r="${R + 0.5}" fill="none" stroke="#1A2030" stroke-opacity=".22" stroke-width="2"/>
<circle cx="${CX}" cy="${CY}" r="${R - 1.5}" fill="none" stroke="url(#${p}rimG)" stroke-width="3.5"/>
${onGlass}
`;
    return app(p, defs, body, 0.8);
}

// --------------------------------------------------------------------------- menu bar

/** A track seen through round glass: as thick as the track at the rim, swollen in the middle. */
function bulge(cx, cy, halfW, edgeH, midH) {
    const [x0, x1, ctrl] = [cx - halfW, cx + halfW, 2 * midH - edgeH];
    return (
        `M${f(x0)},${f(cy - edgeH)} Q${f(cx)},${f(cy - ctrl)} ${f(x1)},${f(cy - edgeH)} ` +
        `L${f(x1)},${f(cy + edgeH)} Q${f(cx)},${f(cy + ctrl)} ${f(x0)},${f(cy + edgeH)}Z`
    );
}

const [LX, LY, LR, LW] = [11.8, 8, 5.3, 1.3];
const INNER = LR - LW / 2;

function lensMenubar() {
    const star = sparkle(4.3, 3.1, 2.8, 2.8, 0.3);
    const defs = `<mask id="lnm"><rect width="22" height="16" fill="#fff"/><circle cx="${LX}" cy="${LY}" r="${INNER}" fill="#000"/></mask>`;
    const on = menubar(defs, `${capsule(1, 7, 20, 2, { fill: "#000", mask: "url(#lnm)" })}
<path d="${bulge(LX, LY, INNER + 0.3, 0.9, 1.35)}" fill="#000"/>
<circle cx="${LX}" cy="${LY}" r="${LR}" fill="none" stroke="#000" stroke-width="${LW}"/>
<path d="${star}" fill="#000"/>`);
    const off = menubar("", `${capsule(1, 7, 20, 2, { fill: "#000" })}
<circle cx="${LX}" cy="${LY}" r="${LR}" fill="#000"/>`);
    return [on, off];
}

// --------------------------------------------------------------------------- Touch Bar

const [TCX, TCY, TR] = [18, 11, 7.2];

function lensTouchbar() {
    const inner = TR - 0.6;
    let baseDefs = `<mask id="lntm"><rect width="32" height="22" fill="#fff"/><circle cx="${TCX}" cy="${TCY}" r="${inner}" fill="#000"/></mask>
<clipPath id="lntc"><circle cx="${TCX}" cy="${TCY}" r="${inner}"/></clipPath>
<linearGradient id="lntr" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff"/><stop offset=".55" stop-color="#fff" stop-opacity=".35"/><stop offset="1" stop-color="#fff" stop-opacity=".8"/></linearGradient>`;
    const swollenH = 1.4;
    const swollen = bulge(TCX, TCY, inner + 0.3, 0.9, swollenH);
    const base = `${capsule(1.5, 10, 29, 2, { fill: "#fff", "fill-opacity": ".35", mask: "url(#lntm)" })}
${capsule(1.5, 10, TCX - 1.5, 2, { fill: "#fff", mask: "url(#lntm)" })}
<g clip-path="url(#lntc)">
<path d="${swollen}" fill="#fff" fill-opacity=".35"/>
<g mask="url(#lntb-shape)"><rect x="${TCX - inner}" y="0" width="${inner - swollenH}" height="22" fill="#fff"/><circle cx="${TCX - swollenH}" cy="${TCY}" r="${swollenH}" fill="#fff"/></g>
</g>
<circle cx="${TCX}" cy="${TCY}" r="${TR}" fill="#fff" fill-opacity=".06" stroke="url(#lntr)" stroke-width="1.2"/>`;
    // The filled part of the swollen track ends at the knob's center in a round cap.
    baseDefs += `<mask id="lntb-shape"><path d="${swollen}" fill="#fff"/></mask>`;
    const sweep = `<circle cx="${TCX}" cy="${TCY}" r="${TR}" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" pathLength="100" stroke-dasharray="14 86" transform="rotate(-150 ${TCX} ${TCY})" filter="url(#lntb)"/>`;
    const star = `<path d="${sparkle(TCX - 4.4, TCY - 4.2, 2.9, 2.9, 0.28)}" fill="#fff"/>`;
    return touchbar(baseDefs + blur("lntb", 1), `<g class="base">${base}</g>
<g class="sweep" opacity="0">${sweep}</g>
<g class="star">${star}</g>`);
}

// --------------------------------------------------------------------------- output

const [on, off] = lensMenubar();
const files = { "app.svg": lensApp(), "menubar.svg": on, "menubar-off.svg": off, "touchbar.svg": lensTouchbar() };
mkdirSync(OUT, { recursive: true });
for (const [name, svg] of Object.entries(files)) writeFileSync(join(OUT, name), svg);
console.log("wrote", Object.keys(files).join(", "), "to", OUT);
