-- Offline SVG atlas. No network requests, external assets or executable savegame data.
local network = require "telecom_network"
local M = {}
local palette = {
    NRA = "#409fff", NRO = "#b46ade", ANTENNA = "#e59927",
    tech_2g = "#cf9510", tech_3g = "#16877f", tech_3gp = "#318eca",
    tech_4g = "#5f991f", tech_4gp = "#a98924", tech_5g = "#e36451", tech_5gp = "#c95098",
}

function M.escape(value)
    return tostring(value or ""):gsub("[%z\1-\8\11\12\14-\31]", "")
        :gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        :gsub('"', "&quot;"):gsub("'", "&#39;")
end

function M.number(value)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Invalid map number")
    return (string.format("%.3f", value):gsub(",", "."):gsub("%.?0+$", ""))
end

local function entityId(kind, id)
    assert(type(id) == "number" and id >= 0 and id % 1 == 0, "Invalid entity id")
    return kind .. "-" .. string.format("%.0f", id)
end

local css = [=[
*{box-sizing:border-box} :root{font-family:system-ui,sans-serif;color:#243846;background:#f4f2e9}
body{margin:0} button,input,select{font:inherit} button,select{border:1px solid #bfcbc9;border-radius:4px;background:#fff;color:inherit;padding:7px 10px} button{cursor:pointer} button:hover{background:#edf3ef} button:focus-visible,select:focus-visible,input:focus-visible{outline:3px solid #c77e26;outline-offset:2px} .details{max-height:230px;overflow:auto}
header{height:60px;display:flex;align-items:center;justify-content:space-between;padding:0 24px;background:#203746;color:#fff;gap:16px} header strong{letter-spacing:.16em;font-size:13px} header span{font:12px monospace;color:#bed0d8}
.layout{display:grid;grid-template-columns:300px minmax(0,1fr);height:calc(100vh - 60px);height:calc(100svh - 60px)} aside{overflow:auto;border-right:1px solid #ced5cc;padding:24px;background:#faf9f3} h1{font:32px Georgia,serif;margin:0 0 12px;line-height:1.1} h2{font-size:16px;margin:0 0 10px;overflow-wrap:anywhere} p{font-size:12px;line-height:1.6;color:#576975} .eyebrow{font:11px monospace;letter-spacing:.15em;color:#9b641c;margin-bottom:10px}
.metrics{display:flex;gap:20px;border-block:1px solid #dbe0d5;padding:14px 0;margin:18px 0} .metrics strong{font:24px Georgia,serif;display:block} .metrics small{font-size:11px;color:#687980} select{width:100%;margin:5px 0 12px} .details{border-left:3px solid #c28339;padding:12px;background:#f1f0e7;margin:10px 0 18px;font-size:12px} .details[hidden]{display:none} .details p{margin:6px 0;overflow-wrap:anywhere} .service{border-top:1px solid #d4dccf;padding-top:8px;margin-top:8px} .muted{color:#70818a}
fieldset{border:0;border-top:1px solid #dbe0d5;padding:14px 0 4px;margin:16px 0 0} legend{font:11px monospace;letter-spacing:.12em;padding:0 8px 0 0;color:#61717b} label.filter{display:flex;align-items:center;gap:9px;margin:9px 0;font-size:13px;cursor:pointer} label.filter input{accent-color:#34556b} .tech-grid{display:grid;grid-template-columns:1fr 1fr} i.swatch{display:inline-block;flex:0 0 10px;width:10px;height:10px;background:var(--color);border-radius:50%} i.NRA{border-radius:0} i.NRO{border-radius:0;clip-path:polygon(50% 0,100% 100%,0 100%)} input[type=range]{width:100%;accent-color:#34556b} .note{font-size:11px;color:#6b797f} a{color:#34556b}
main{min-width:0;display:flex;flex-direction:column;overflow:hidden} .toolbar{display:flex;align-items:center;gap:6px;padding:12px 16px;flex-wrap:wrap;border-bottom:1px solid #cbd5d1;background:#f4f2e9} #view-status{margin-left:auto;font:11px monospace;color:#596d79} #map-frame{position:relative;flex:1;min-height:250px;overflow:hidden;background:#dce5e1} #map{display:block;width:100%;height:100%;touch-action:none;cursor:grab} #map.dragging{cursor:grabbing} .coverage{fill-opacity:.18;stroke-width:1.2;pointer-events:none} .entity{cursor:pointer;outline:none} .selection-halo{display:none;fill:none;stroke:#172d3e;stroke-width:2} .entity.is-selected .selection-halo,.entity:focus .selection-halo{display:inline} .symbol{stroke:#fff;stroke-width:1.6} .town-name{font:11px system-ui,sans-serif;fill:#243746;paint-order:stroke;stroke:#faf9f3;stroke-width:3px;stroke-linejoin:round} .entity.is-hidden,.coverage.is-hidden{display:none} .without-names .town-name{display:none} #scale{position:absolute;bottom:16px;left:20px;padding:7px 10px;background:#faf9f3dd;border-radius:3px;font:11px monospace;pointer-events:none} #scale-bar{border:solid #2d4553;border-width:0 1px 2px;height:6px;margin-bottom:4px} .north{position:absolute;right:18px;top:18px;color:#213d4e;font:14px monospace;pointer-events:none} .north:before{content:'\25b2';display:block;text-align:center}
noscript{display:block;padding:10px;background:#fff0b5} [hidden]{display:none!important}
@media(max-width:760px){header{padding:0 14px}header span{font-size:10px}.layout{display:flex;flex-direction:column;height:auto}main{order:0;height:66vh;min-height:360px}aside{order:1;overflow:visible;border-right:0;border-top:1px solid #cbd5d1;padding:20px}.tech-grid{grid-template-columns:repeat(4,1fr)}#view-status{width:100%;margin-left:0}}
]=]

local script = [=[
(() => {
  'use strict';
  const svg = document.getElementById('map');
  const frame = document.getElementById('map-frame');
  const full = {x:svg.viewBox.baseVal.x,y:svg.viewBox.baseVal.y,w:svg.viewBox.baseVal.width,h:svg.viewBox.baseVal.height};
  let box = {...full}, selected = null, drag = null, dragged = false;
  const entities = Array.from(svg.querySelectorAll('.entity'));
  const areas = Array.from(svg.querySelectorAll('.coverage'));
  const chooser = document.getElementById('choose');
  const only = document.getElementById('only-selected');
  const filters = Object.fromEntries(Array.from(document.querySelectorAll('[data-filter]'), input => [input.dataset.filter, input]));
  const enabled = key => !filters[key] || filters[key].checked;
  const unitsPerPixel = () => Math.max(box.w / Math.max(1,frame.clientWidth), box.h / Math.max(1,frame.clientHeight));
  function applyView() {
    const cx = box.x + box.w/2, cy = box.y + box.h/2;
    box.x = Math.max(full.x, Math.min(full.x + full.w - box.w, cx - box.w/2));
    box.y = Math.max(full.y, Math.min(full.y + full.h - box.h, cy - box.h/2));
    svg.setAttribute('viewBox', `${box.x} ${box.y} ${box.w} ${box.h}`);
    const unit = unitsPerPixel();
    svg.querySelectorAll('.marker-shape').forEach(shape => shape.setAttribute('transform', `scale(${unit})`));
    const base = 10 ** Math.floor(Math.log10(100 * unit));
    const distance = [5,2,1].map(n => n*base).find(n => n/unit <= 130) || base;
    document.getElementById('scale-bar').style.width = `${distance/unit}px`;
    document.getElementById('scale-value').textContent = distance >= 1000 ? `${+(distance/1000).toFixed(2)} km` : `${+distance.toFixed(1)} m`;
    document.getElementById('view-status').textContent = `Zoom ${(full.w/box.w).toFixed(1)}x`;
  }
  function worldPoint(event) {
    const matrix = svg.getScreenCTM();
    if (!matrix) return {x:box.x+box.w/2,y:box.y+box.h/2};
    const point = svg.createSVGPoint(); point.x = event.clientX; point.y = event.clientY;
    return point.matrixTransform(matrix.inverse());
  }
  function zoom(factor, anchor) {
    anchor ||= {x:box.x+box.w/2,y:box.y+box.h/2};
    const width = Math.max(full.w/64, Math.min(full.w, box.w/factor));
    const ratio = width/box.w;
    box = {x:anchor.x-(anchor.x-box.x)*ratio,y:anchor.y-(anchor.y-box.y)*ratio,w:width,h:box.h*ratio};
    applyView();
  }
  function select(id) {
    selected = document.getElementById(id);
    if (selected && !selected.classList.contains('entity')) selected = null;
    entities.forEach(entity => entity.classList.toggle('is-selected', entity === selected));
    document.querySelectorAll('.details').forEach(detail => detail.hidden = !selected || detail.id !== `detail-${selected.id}`);
    document.getElementById('selection-hint').hidden = !!selected;
    document.getElementById('centre-selected').disabled = !selected;
    chooser.value = selected ? selected.id : '';
    applyFilters();
  }
  function applyFilters() {
    let count = 0;
    entities.forEach(entity => {
      const show = enabled(`kind:${entity.dataset.kind}`);
      entity.classList.toggle('is-hidden', !show);
      entity.setAttribute('tabindex', show ? '0' : '-1');
      if (show && entity.dataset.kind !== 'TOWN') count++;
    });
    areas.forEach(area => area.classList.toggle('is-hidden',
      !enabled(`kind:${area.dataset.kind}`) || !enabled(`tech:${area.dataset.tech}`) ||
      (only.checked && (!selected || area.dataset.node !== selected.id))));
    ['terrain','roads','rails'].forEach(id => {const layer = document.getElementById(id); if(layer) layer.style.display = enabled(`layer:${id}`) ? '' : 'none';});
    svg.classList.toggle('without-names', !enabled('layer:names'));
    document.getElementById('visible-count').textContent = `${count} equipement(s) visible(s)`;
  }
  Object.values(filters).forEach(input => input.addEventListener('change', applyFilters));
  only.addEventListener('change', applyFilters);
  document.getElementById('opacity').addEventListener('input', event => areas.forEach(area => area.style.fillOpacity = Number(event.target.value)/100));
  chooser.addEventListener('change', () => select(chooser.value));
  document.getElementById('zoom-in').addEventListener('click', () => zoom(1.5));
  document.getElementById('zoom-out').addEventListener('click', () => zoom(1/1.5));
  document.getElementById('fit').addEventListener('click', () => {box={...full};applyView();});
  document.getElementById('centre-selected').addEventListener('click', () => {
    if(!selected) return;
    const width = Math.min(box.w,full.w/4), height=width*full.h/full.w;
    box={x:Number(selected.dataset.x)-width/2,y:-Number(selected.dataset.y)-height/2,w:width,h:height};applyView();
  });
  svg.addEventListener('wheel', event => {event.preventDefault();zoom(event.deltaY<0?1.2:1/1.2,worldPoint(event));},{passive:false});
  svg.addEventListener('pointerdown', event => {
    if(event.button!==0 || drag)return;
    drag={id:event.pointerId,x:event.clientX,y:event.clientY,box:{...box},unit:unitsPerPixel()};dragged=false;
    svg.setPointerCapture(event.pointerId);svg.classList.add('dragging');
  });
  svg.addEventListener('pointermove', event => {
    if(!drag || event.pointerId!==drag.id)return;
    const dx=event.clientX-drag.x,dy=event.clientY-drag.y;
    if(Math.abs(dx)+Math.abs(dy)>4)dragged=true;
    if(dragged){box={...drag.box,x:drag.box.x-dx*drag.unit,y:drag.box.y-dy*drag.unit};applyView();}
  });
  svg.addEventListener('pointerup', event => {
    if(!drag || event.pointerId!==drag.id)return;
    if(!dragged){const hit=document.elementFromPoint(event.clientX,event.clientY)?.closest('.entity');select(hit?.id||'');}
    svg.releasePointerCapture(event.pointerId);drag=null;svg.classList.remove('dragging');
  });
  svg.addEventListener('pointercancel', () => {drag=null;svg.classList.remove('dragging');});
  svg.addEventListener('keydown', event => {
    const entity=event.target.closest('.entity');
    if(entity && (event.key==='Enter'||event.key===' ')){event.preventDefault();select(entity.id);}
    if(event.key==='Escape')select('');
  });
  window.addEventListener('resize',applyView);
  applyView();applyFilters();
})();
]=]

local function checkbox(key, text, color, shape)
    local swatch = color and ('<i class="swatch ' .. (shape or '') .. '" style="--color:' .. color .. '"></i>') or ''
    return '<label class="filter"><input type="checkbox" data-filter="' .. M.escape(key) .. '" checked>' .. swatch .. M.escape(text) .. '</label>'
end

function M.prefix(snapshot)
    local out, n, e, b = {}, M.number, M.escape, snapshot.bounds
    local function add(text) out[#out + 1] = text end
    add('<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Telecom | Atlas de couverture</title><style>' .. css .. '</style></head><body>')
    add('<header><strong>TELECOM / ATLAS</strong><span>TRANSPORT FEVER 2 / INSTANTANE HORS LIGNE</span></header><noscript>JavaScript local permet le zoom et les filtres. La carte ci-dessous reste visible sans JavaScript.</noscript><div class="layout"><aside>')
    add('<div class="eyebrow">ANNEE ' .. n(snapshot.year) .. '</div><h1>Carte de<br>couverture.</h1><p>Une lecture du territoire, des infrastructures et de leurs portees.</p>')
    add('<div class="metrics"><div><strong>' .. #snapshot.nodes .. '</strong><small>equipements</small></div><div><strong>' .. n(snapshot.coveredTowns) .. '/' .. #snapshot.towns .. '</strong><small>villes couvertes</small></div></div>')
    add('<label for="choose">Localiser un element</label><select id="choose"><option value="">Selectionner...</option>')
    for _, group in ipairs({ { snapshot.nodes, "node" }, { snapshot.towns, "town" } }) do
        for _, item in ipairs(group[1]) do
            add('<option value="' .. entityId(group[2], item.id) .. '">' .. e(item.name) .. ' (#' .. n(item.id) .. ')</option>')
        end
    end
    add('</select><p id="selection-hint">Cliquez sur un symbole ou utilisez la liste. Les antennes inactives restent visibles en gris.</p>')
    local townNames = {}
    for _, town in ipairs(snapshot.towns) do townNames[town.id] = town.name end
    for _, node in ipairs(snapshot.nodes) do
        add('<section class="details" id="detail-' .. entityId("node", node.id) .. '" hidden><h2>' .. e(node.name) .. '</h2><p>' .. e(node.kind) .. ' / #' .. n(node.id) .. '<br>X ' .. n(node.x) .. ' m / Y ' .. n(node.y) .. ' m</p>')
        for _, service in ipairs(node.services) do
            local state = service.active and "actif" or service.configured and ("disponible en " .. n(service.year)) or "desactive"
            add('<div class="service"><strong>' .. e(service.name) .. '</strong> / ' .. n(service.radius) .. ' m / ' .. state)
            local names = {}
            for _, id in ipairs(service.townIds) do names[#names + 1] = e(townNames[id] or tostring(id)) end
            if service.active then add('<p>Villes : ' .. (#names > 0 and table.concat(names, ', ') or 'aucune') .. '</p>') end
            add('</div>')
        end
        add('</section>')
    end
    for _, town in ipairs(snapshot.towns) do
        local coverage = snapshot.coverage[town.id]
        add('<section class="details" id="detail-' .. entityId("town", town.id) .. '" hidden><h2>' .. e(town.name) .. '</h2><p>Contributions calculees :<br>Fixe ' .. n(100 * coverage.fixedBonus) .. '% / Mobile ' .. n(100 * coverage.mobileBonus) .. '%</p></section>')
    end
    add('<fieldset><legend>INFRASTRUCTURES</legend>')
    add(checkbox('kind:NRA', 'NRA / cuivre', palette.NRA, 'NRA'))
    add(checkbox('kind:NRO', 'NRO / fibre', palette.NRO, 'NRO'))
    add(checkbox('kind:ANTENNA', 'Antennes', palette.ANTENNA))
    add(checkbox('kind:TOWN', 'Villes', '#637b77'))
    add('<p id="visible-count" class="note"></p></fieldset><fieldset><legend>TECHNOLOGIES MOBILES</legend><div class="tech-grid">')
    for _, tech in ipairs(network.techs) do add(checkbox('tech:' .. tech.key, tech.name, palette[tech.key])) end
    add('</div></fieldset><fieldset><legend>COUVERTURE</legend><label class="filter"><input id="only-selected" type="checkbox">Equipement selectionne uniquement</label><label for="opacity" class="note">Opacite des zones</label><input id="opacity" type="range" min="0" max="60" value="18"></fieldset>')
    add('<fieldset><legend>FOND DE CARTE</legend>')
    for _, layer in ipairs({ { 'terrain', 'Relief et eau' }, { 'roads', 'Routes' }, { 'rails', 'Rails' }, { 'names', 'Noms des villes' } }) do add(checkbox('layer:' .. layer[1], layer[2])) end
    add('</fieldset><p class="note">Portee theorique circulaire, sans effet du relief. Les statistiques globales ne dependent pas des filtres. Un nouvel export est necessaire apres modification de la partie.</p>')
    if snapshot.boundsEstimated then add('<p class="note">Attention : limites du territoire estimees.</p>') end
    add('<p class="note">Principe inspire de <a href="https://github.com/AaditJha/Tpf2MapExporter" rel="noreferrer">Cartograph, Aadit Jha</a>. Aucun service externe requis.</p></aside><main>')
    add('<div class="toolbar"><button id="zoom-in" aria-label="Zoom avant">+</button><button id="zoom-out" aria-label="Zoom arriere">-</button><button id="fit">Carte entiere</button><button id="centre-selected" disabled>Centrer selection</button><span id="view-status"></span></div><div id="map-frame">')
    add('<svg id="map" xmlns="http://www.w3.org/2000/svg" viewBox="' .. n(b.minX) .. ' ' .. n(-b.maxY) .. ' ' .. n(b.maxX-b.minX) .. ' ' .. n(b.maxY-b.minY) .. '" aria-label="Carte de couverture telecom">')
    add('<defs><clipPath id="world-bounds"><rect x="' .. n(b.minX) .. '" y="' .. n(-b.maxY) .. '" width="' .. n(b.maxX-b.minX) .. '" height="' .. n(b.maxY-b.minY) .. '"/></clipPath></defs><g id="geography" clip-path="url(#world-bounds)">')
    return table.concat(out)
end

function M.suffix(snapshot)
    local out, n, e = { '</g><g id="coverage" clip-path="url(#world-bounds)">' }, M.number, M.escape
    local function add(text) out[#out + 1] = text end
    for _, node in ipairs(snapshot.nodes) do
        for _, service in ipairs(node.services) do
            if service.active then
                local color = palette[service.key] or palette[node.kind]
                add('<circle class="coverage" data-node="' .. entityId('node', node.id) .. '" data-kind="' .. e(node.kind) .. '" data-tech="' .. e(service.key) .. '" cx="' .. n(node.x) .. '" cy="' .. n(-node.y) .. '" r="' .. n(service.radius) .. '" fill="' .. color .. '" stroke="' .. color .. '" vector-effect="non-scaling-stroke"/>')
            end
        end
    end
    add('</g><g id="entities">')
    local unit = math.max(snapshot.bounds.maxX-snapshot.bounds.minX, snapshot.bounds.maxY-snapshot.bounds.minY) / 900
    local function startMarker(item, kind, prefix, color)
        add('<g class="entity" id="' .. entityId(prefix, item.id) .. '" data-kind="' .. kind .. '" data-x="' .. n(item.x) .. '" data-y="' .. n(item.y) .. '" transform="translate(' .. n(item.x) .. ' ' .. n(-item.y) .. ')" tabindex="0" role="button" aria-label="' .. e(item.name) .. '"><title>' .. e(item.name) .. ' / #' .. n(item.id) .. '</title><g class="marker-shape" transform="scale(' .. n(unit) .. ')"><circle class="selection-halo" r="11"/><g class="symbol" fill="' .. color .. '">')
    end
    for _, node in ipairs(snapshot.nodes) do
        local active = false
        for _, service in ipairs(node.services) do active = active or service.active end
        startMarker(node, node.kind, 'node', active and palette[node.kind] or '#879196')
        if node.kind == 'NRA' then add('<rect x="-5" y="-5" width="10" height="10"/>')
        elseif node.kind == 'NRO' then add('<path d="M0 -7 L7 6 L-7 6 Z"/>')
        else add('<circle r="5.5"/>') end
        add('</g></g></g>')
    end
    for _, town in ipairs(snapshot.towns) do
        local c = snapshot.coverage[town.id]
        startMarker(town, 'TOWN', 'town', (c.hasFixed or c.hasMobile) and '#2b8161' or '#63727a')
        add('<path d="M-5 -1H-1V-5H1V-1H5V1H1V5H-1V1H-5Z"/></g><text class="town-name" x="10" y="4">' .. e(town.name) .. '</text></g></g>')
    end
    add('</g></svg><div id="scale"><div id="scale-bar"></div><span id="scale-value"></span></div><div class="north">N</div></div></main></div><script>' .. script .. '</script></body></html>')
    return table.concat(out)
end

return M
