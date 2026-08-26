#!/usr/bin/env node
/*
 * Annuaire VoxelMage - OPTIONNEL.
 *
 * Le jeu fonctionne sans lui : sur un reseau local les parties sont trouvees
 * par broadcast UDP, et sur Internet le "code direct" de 8 caracteres contient
 * deja l'adresse de l'hote.
 *
 * Ce petit service ajoute deux choses :
 *   - une liste publique de parties mise a jour en temps reel ;
 *   - la resolution des codes courts (6 caracteres) hors reseau local.
 *
 * Aucune dependance : Node >= 18 suffit.  node directory/server.js
 */
const http = require("http");

const PORT = process.env.PORT || 8080;
const TTL_MS = 60 * 1000;          // une partie disparait apres 60 s sans signe de vie
const MAX_ROOMS = 500;

/** code -> { name, code, ip, port, direct, players, max, seen } */
const rooms = new Map();

function prune() {
  const now = Date.now();
  for (const [code, r] of rooms) if (now - r.seen > TTL_MS) rooms.delete(code);
}

function clientIp(req) {
  const fwd = req.headers["x-forwarded-for"];
  if (fwd) return String(fwd).split(",")[0].trim();
  return (req.socket.remoteAddress || "").replace(/^::ffff:/, "");
}

function send(res, code, body) {
  const data = JSON.stringify(body);
  res.writeHead(code, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Content-Length": Buffer.byteLength(data),
  });
  res.end(data);
}

function readJson(req) {
  return new Promise((resolve) => {
    let raw = "";
    req.on("data", (c) => {
      raw += c;
      if (raw.length > 8192) req.destroy();
    });
    req.on("end", () => {
      try { resolve(JSON.parse(raw || "{}")); } catch { resolve({}); }
    });
  });
}

const server = http.createServer(async (req, res) => {
  prune();
  const url = new URL(req.url, "http://localhost");

  if (req.method === "OPTIONS") return send(res, 204, {});

  // Liste publique
  if (req.method === "GET" && url.pathname === "/servers") {
    return send(res, 200, [...rooms.values()].map((r) => ({
      name: r.name, code: r.code, ip: r.ip, port: r.port,
      direct: r.direct, players: r.players, max: r.max,
    })));
  }

  // Resolution d'un code court
  if (req.method === "GET" && url.pathname === "/resolve") {
    const code = String(url.searchParams.get("code") || "").toUpperCase();
    const r = rooms.get(code);
    if (!r) return send(res, 404, { error: "code inconnu" });
    return send(res, 200, { ip: r.ip, port: r.port, name: r.name });
  }

  // L'hote annonce (ou rafraichit) sa partie
  if (req.method === "POST" && url.pathname === "/announce") {
    const b = await readJson(req);
    const code = String(b.code || "").toUpperCase();
    if (!/^[0-9A-HJKMNP-TV-Z]{6}$/.test(code)) {
      return send(res, 400, { error: "code invalide" });
    }
    if (!rooms.has(code) && rooms.size >= MAX_ROOMS) {
      return send(res, 503, { error: "annuaire plein" });
    }
    rooms.set(code, {
      code,
      name: String(b.name || "Partie").slice(0, 48),
      ip: clientIp(req),
      port: Math.min(65535, Math.max(1, parseInt(b.port, 10) || 24565)),
      direct: String(b.direct || "").slice(0, 16),
      players: parseInt(b.players, 10) || 1,
      max: parseInt(b.max, 10) || 16,
      seen: Date.now(),
    });
    return send(res, 200, { ok: true, ip: clientIp(req) });
  }

  // L'hote ferme sa partie
  if (req.method === "POST" && url.pathname === "/close") {
    const b = await readJson(req);
    rooms.delete(String(b.code || "").toUpperCase());
    return send(res, 200, { ok: true });
  }

  if (url.pathname === "/" || url.pathname === "/health") {
    return send(res, 200, { service: "voxelmage-directory", rooms: rooms.size });
  }
  send(res, 404, { error: "not found" });
});

server.listen(PORT, () => console.log(`Annuaire VoxelMage sur le port ${PORT}`));
