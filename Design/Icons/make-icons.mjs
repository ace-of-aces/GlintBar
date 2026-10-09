#!/usr/bin/env node
/**
 * Glint's icon, Eclipse: a black bar in front of a bright light, like the moon across the
 * sun. The glint is the diamond ring, the single bead of light just before totality.
 *
 * Writes four drawings next to this script:
 *   app.svg            1024x1024 macOS app icon (continuous-corner body on the 824pt grid)
 *   menubar.svg        22x16pt template image, Glint bar showing
 *   menubar-off.svg    22x16pt template image, app controls showing
 *   touchbar.svg       32x22pt Control Strip glyph at rest; the "sweep" group is the light
 *                      that runs along the bar's top edge when the glint plays
 *
 * The app uses app.svg through scripts/make-app-icon.sh. The menu bar and Control Strip
 * glyphs are drawn in code from the same geometry (Sources/Glint/Icons/EclipseGlyph.swift).
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

/** A horizontal streak: sharp at x0 and x1, t thick (half) at xm. */
function taper(x0, x1, xm, y, t) {
    return (
        `M${f(x0)},${f(y)} Q${f(xm - (xm - x0) * 0.35)},${f(y - t)} ${f(xm)},${f(y - t)} ` +
        `Q${f(xm + (x1 - xm) * 0.35)},${f(y - t)} ${f(x1)},${f(y)} ` +
        `Q${f(xm + (x1 - xm) * 0.35)},${f(y + t)} ${f(xm)},${f(y + t)} ` +
        `Q${f(xm - (xm - x0) * 0.35)},${f(y + t)} ${f(x0)},${f(y)}Z`
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

// --------------------------------------------------------------------------- app icon

function eclipseApp() {
    const p = "ec-";
    const [x, y, w, h] = [232, 427, 560, 170];
    const r = h / 2;
    const [acx, acy] = [x + w - r, y + r];
    // The diamond sits on the rim where the bar's right end starts to curve.
    const angle = -52 * (Math.PI / 180);
    const dx = acx + (r + 4) * Math.cos(angle);
    const dy = acy + (r + 4) * Math.sin(angle);
    const grow = (d, attrs) => capsule(x - d, y - d, w + 2 * d, h + 2 * d, attrs);

    const defs = `
<radialGradient id="${p}bg" cx="512" cy="512" r="620" gradientUnits="userSpaceOnUse">
<stop offset="0" stop-color="#211D18"/><stop offset=".55" stop-color="#0D0B09"/><stop offset="1" stop-color="#040404"/>
</radialGradient>
<linearGradient id="${p}sheen" x1="0" y1="${y}" x2="0" y2="${y + h}" gradientUnits="userSpaceOnUse">
<stop offset="0" stop-color="#fff" stop-opacity=".09"/><stop offset=".35" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#fff" stop-opacity=".03"/>
</linearGradient>
<radialGradient id="${p}halo" cx="${dx}" cy="${dy}" r="210" gradientUnits="userSpaceOnUse">
<stop offset="0" stop-color="#fff"/><stop offset=".12" stop-color="#FFF6E4" stop-opacity=".9"/><stop offset=".4" stop-color="#F4D9A6" stop-opacity=".25"/><stop offset="1" stop-color="#F4D9A6" stop-opacity="0"/>
</radialGradient>
<linearGradient id="${p}streamer" x1="0" y1="0" x2="1" y2="0">
<stop offset="0" stop-color="#F4D9A6" stop-opacity="0"/><stop offset=".5" stop-color="#FFF1D6" stop-opacity=".7"/><stop offset="1" stop-color="#F4D9A6" stop-opacity="0"/>
</linearGradient>
${blur(p + "b60", 60, "-40%", "180%")}${blur(p + "b18", 18, "-30%", "160%")}${blur(p + "b4", 4)}${blur(p + "b1", 1.2)}${blur(p + "b6", 6)}
`;
    const body = `
<rect width="1024" height="1024" fill="url(#${p}bg)"/>
${grow(110, { fill: "#E9C98E", opacity: ".26", filter: `url(#${p}b60)` })}
${grow(30, { fill: "#FFE9C4", opacity: ".5", filter: `url(#${p}b18)` })}
<rect x="${x - 150}" y="${acy - 3}" width="${w + 300}" height="6" fill="url(#${p}streamer)" filter="url(#${p}b4)"/>
${grow(8, { fill: "#FFF3DE", opacity: ".9", filter: `url(#${p}b4)` })}
${grow(4, { fill: "#FFFAF0", filter: `url(#${p}b1)` })}
${capsule(x, y, w, h, { fill: "#050505" })}
${capsule(x, y, w, h, { fill: `url(#${p}sheen)` })}
<circle cx="${dx}" cy="${dy}" r="210" fill="url(#${p}halo)"/>
<path d="${sparkle(dx, dy, 190, 150, 0.2)}" fill="#FFF1D6" opacity=".6" filter="url(#${p}b6)"/>
<path d="${sparkle(dx, dy, 176, 140, 0.17)}" fill="#fff"/>
<path d="${sparkle(dx, dy, 46, 46, 0.2)}" fill="#fff" transform="rotate(45 ${dx.toFixed(1)} ${dy.toFixed(1)})"/>
`;
    return app(p, defs, body, 0.7);
}

// --------------------------------------------------------------------------- menu bar

function eclipseMenubar() {
    const star = sparkle(18.3, 4.3, 3.5, 3.5, 0.3);
    const ring = '<rect x="2.25" y="3.75" width="17.5" height="8.5" rx="4.25" fill="none" stroke="#000" stroke-width="1.2"';
    const core = capsule(4.8, 6.3, 12.4, 3.4, { fill: "#000" });
    const on = menubar(
        `<mask id="ecm"><rect width="22" height="16" fill="#fff"/><path d="${star}" fill="#000" stroke="#000" stroke-width="2.4" stroke-linejoin="round"/></mask>`,
        `${ring} mask="url(#ecm)"/>
${core}
<path d="${star}" fill="#000"/>`,
    );
    const off = menubar("", `${ring}/>
${core}`);
    return [on, off];
}

// --------------------------------------------------------------------------- Touch Bar

function eclipseTouchbar() {
    const [tx, ty, tw, th] = [2.5, 6, 24.5, 10.5];
    const tr = th / 2;
    const angle = -50 * (Math.PI / 180);
    const tdx = tx + tw - tr + (tr + 0.2) * Math.cos(angle);
    const tdy = ty + tr + (tr + 0.2) * Math.sin(angle);
    const defs =
        blur("ectb", 1.6, "-40%", "180%") +
        blur("ectb2", 0.45) +
        `<radialGradient id="ecth" cx="${tdx.toFixed(2)}" cy="${tdy.toFixed(2)}" r="5.6" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff"/><stop offset=".25" stop-color="#FFF3DC" stop-opacity=".45"/><stop offset="1" stop-color="#F4D9A6" stop-opacity="0"/></radialGradient>`;
    const base = `${capsule(tx - 0.6, ty - 0.6, tw + 1.2, th + 1.2, { fill: "none", stroke: "#F2D29C", "stroke-width": "1.6", opacity: ".7", filter: "url(#ectb)" })}
${capsule(tx, ty, tw, th, { fill: "#000", stroke: "#FFF6E6", "stroke-width": "1.1" })}`;
    const sweep = `<path d="${taper(tx + tr - 1, tx + tr + 6, tx + tr + 3.5, ty, 0.95)}" fill="#fff" filter="url(#ectb2)"/>`;
    const diamond = `<circle cx="${tdx.toFixed(2)}" cy="${tdy.toFixed(2)}" r="5.6" fill="url(#ecth)"/>
<path d="${sparkle(tdx, tdy, 5, 4.4, 0.24)}" fill="#fff"/>`;
    return touchbar(defs, `<g class="base">${base}</g>
<g class="sweep" opacity="0">${sweep}</g>
<g class="diamond">${diamond}</g>`);
}

// --------------------------------------------------------------------------- output

const [on, off] = eclipseMenubar();
const files = { "app.svg": eclipseApp(), "menubar.svg": on, "menubar-off.svg": off, "touchbar.svg": eclipseTouchbar() };
mkdirSync(OUT, { recursive: true });
for (const [name, svg] of Object.entries(files)) writeFileSync(join(OUT, name), svg);
console.log("wrote", Object.keys(files).join(", "), "to", OUT);
