"""Compile authored development-map data into the project's Godot resources.

Geometry is authored in JSON, rasterized by Pillow, and connectivity is checked
by scipy.ndimage. This is a content adapter, not a runtime random-map generator
or a replacement for the project's navigation. No art assets are generated.
"""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import label


def native_rectangles(terrain, kind):
    """Encode matching row spans as the existing Rect2i stamp format."""
    active, result = {}, []
    height = terrain.shape[0]
    for y in range(height + 1):
        spans = []
        if y < height:
            values = np.flatnonzero(terrain[y] == kind)
            if len(values):
                groups = np.split(values, np.flatnonzero(np.diff(values) != 1) + 1)
                spans = [(int(g[0]), int(len(g))) for g in groups]
        present = set(spans)
        for key in list(active):
            if key not in present:
                result.append(active.pop(key))
        for x, width in spans:
            if (x, width) in active:
                active[x, width][3] += 1
            else:
                active[x, width] = [x, y, width, 1]
    return result


def compile_map(source, output, qa_dir):
    data = json.loads(source.read_text(encoding="utf-8"))
    width, height = data["dimensions"]
    image = Image.new("L", (width, height), 0)
    painter = ImageDraw.Draw(image)
    for key, value in (("rough_polygons", 1), ("obstacle_polygons", 2)):
        for polygon in data[key]:
            painter.polygon([tuple(point) for point in polygon], fill=value)
    terrain = np.array(image)
    bx, by = data["mainbrain"]["origin"]
    bw, bh = data["mainbrain"]["footprint"]
    if not np.all(terrain[by:by + bh, bx:bx + bw] == 0):
        raise ValueError("Mainbrain footprint is not entirely buildable")
    walk = terrain != 2
    walk[by:by + bh, bx:bx + bw] = False
    components, count = label(walk)
    px, py = data["probe_cell"]
    component = int(components[py, px])
    if not component or count != 1:
        raise ValueError(f"Expected one connected walkable area, got {count}")
    for site in data["resource_sites"]:
        x, y = site["cell"]
        if terrain[y, x] != 0 or components[y, x] != component:
            raise ValueError(f"Invalid resource site: {site['id']}")
        origins = []
        for dx, dy in ((-1, -1), (0, -1), (-1, 0), (0, 0)):
            mx, my = x + dx, y + dy
            overlaps_core = bx < mx + 2 and mx < bx + bw and by < my + 2 and my < by + bh
            if (0 <= mx < width - 1 and 0 <= my < height - 1
                    and np.all(terrain[my:my + 2, mx:mx + 2] == 0)
                    and not overlaps_core):
                origins.append([mx, my])
        if not origins:
            raise ValueError(f"No buildable 2x2 mining site: {site['id']}")
        site["suggested_mine_origin"] = origins[0]
    environment = []
    for site in data["development_sites"]:
        x, y = site["origin"]
        w, h = site["footprint"]
        if not np.all(terrain[y:y + h, x:x + w] == 0):
            raise ValueError(f"Development footprint is not buildable: {site['id']}")
        if not np.all(components[y:y + h, x:x + w] == component):
            raise ValueError(f"Unreachable development site: {site['id']}")
        if site.get("building"):
            area = terrain[y - 3:y + h + 3, x - 3:x + w + 3].copy()
            area[3:3 + h, 3:3 + w] = 255
            is_wind = site["building"] == "wind"
            score = float(np.sum(area == 1) + np.sum(area == 0) * .5) if is_wind else int(np.sum(area == 0))
            if score < site["minimum_score"]:
                raise ValueError(f"Insufficient environment score: {site['id']} = {score}")
            environment.append({"id": site["id"], "score": score,
                                "base_power": min(18 if is_wind else 20, int(score // 2))})
    for point in list(data["gates"].values()) + list(data["edge_routes"].values()):
        x, y = point
        if components[y, x] != component:
            raise ValueError(f"Unreachable gate or edge route: {point}")
    obstacles = native_rectangles(terrain, 2)
    rough = native_rectangles(terrain, 1)
    compiled = {"obstacle_rects": obstacles, "rough_rects": rough,
                "environment_sites": environment,
                "terrain_counts": {name: int(np.sum(terrain == value))
                                   for value, name in enumerate(("open", "rough", "obstacle"))}}
    # Only current runtime resource keys enter the native map. Fuel remains metadata.
    minerals = [site for site in data["resource_sites"] if site["runtime_kind"]]
    lines = [f'[gd_resource type="Resource" script_class="MechMapDefinition" load_steps={3 + len(minerals)} format=3]', "",
             '[ext_resource type="Script" path="res://content/map_definition.gd" id="1"]',
             '[ext_resource type="Script" path="res://content/mineral_definition.gd" id="2"]', ""]
    for site in minerals:
        x, y = site["cell"]
        lines += [f'[sub_resource type="Resource" id="{site["id"]}"]',
                  'script = ExtResource("2")', f'mineral_id = &"{site["id"]}"',
                  f'cell = Vector2i({x}, {y})', f'resource_kind = "{site["runtime_kind"]}"',
                  f'amount = {site["amount"]}', ""]
    def rectangles(values):
        return 'Array[Rect2i]([' + ', '.join('Rect2i(%d, %d, %d, %d)' % tuple(v) for v in values) + '])'
    def vector(values):
        return 'Vector2i(%d, %d)' % tuple(values)
    lines += ['[resource]', 'script = ExtResource("1")', f'map_id = &"{data["id"]}"',
              f'display_name = {json.dumps(data["name"], ensure_ascii=False)}',
              'dimensions = ' + vector(data["dimensions"]),
              f'wanderer_exclusion_radius = {float(data["wanderer_exclusion_radius"])}',
              'obstacle_rects = ' + rectangles(obstacles), 'rough_rects = ' + rectangles(rough),
              'rough_movement_weight = 2.0', 'mainbrain_origin = ' + vector([bx, by]),
              'mainbrain_footprint = ' + vector([bw, bh]), 'probe_cell = ' + vector(data["probe_cell"]),
              'main_gate = ' + vector(data["gates"]["north"]), 'flank = ' + vector(data["gates"]["east"]),
              'minerals = Array[ExtResource("2")]([' + ', '.join(f'SubResource("{s["id"]}")' for s in minerals) + '])', '']
    # Bundle uses an orthographic diagnostic projection. Native art remains isometric.
    scale = 4
    anchor_points = {**data["gates"], **{'edge_' + key: value for key, value in data["edge_routes"].items()}}
    anchor_points.update({site["id"]: site["suggested_mine_origin"] for site in data["resource_sites"]})
    anchor_points.update({site["id"]: site["origin"] for site in data["development_sites"]})
    anchors = {key: {"point": [(p[0] + .5) * scale, (p[1] + .5) * scale],
                     "approach": [(p[0] + .5) * scale, (p[1] + .5) * scale]}
               for key, p in anchor_points.items()}
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    bundle = {"schema": "generate2dmap.map_bundle.v2", "id": data["id"], "name": data["name"] + ' · navigation diagnostic',
              "art_source": "existing", "world": {"width": width * scale, "height": height * scale, "unit": "px"},
              "tile_size": scale, "layers": [{"name": "entities", "kind": "objects"}], "objects": [],
              "collision": {"actorRadius": .22 * scale, "ySquash": 1.0,
                            "rects": [[x * scale, y * scale, w * scale, h * scale] for x, y, w, h in obstacles + [[bx, by, bw, bh]]]},
              "nav": {"cell": 1}, "spawns": [{"id": "base", "x": (px + .5) * scale, "y": (py + .5) * scale}],
              "anchors": anchors, "provenance": {"tool": "billions-mech map content adapter", "version": "1.0",
                                                 "params": {"rasterizer": "Pillow.ImageDraw", "connectivity": "scipy.ndimage.label", "scale": scale},
                                                 "inputs": [{"path": "../../" + source.as_posix(), "sha256": source_hash}],
                                                 "route": "existing Godot renderer; collision/navigation data only",
                                                 "source": source.as_posix(), "source_sha256": source_hash, "no_new_art": True}}
    report = {"dimensions": data["dimensions"], "playable_cells": width * height,
              "walkable_components_with_core": count, "reachable_anchors": len(anchors),
              **compiled, "native_mineral_count": len(minerals), "fuel_reservations": sum(s["kind"] == 'fuel' for s in data["resource_sites"]),
              "source_sha256": source_hash}
    qa_dir.mkdir(parents=True, exist_ok=True)
    output.write_text('\n'.join(lines), encoding="utf-8")
    for filename, payload in (("map-bundle.json", bundle), ("layout-report.json", report)):
        (qa_dir / filename).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding="utf-8")
    print(json.dumps({"output": str(output), "dimensions": data["dimensions"], "components": count,
                      "anchors": len(anchors), "environment_sites": environment,
                      "terrain_counts": compiled["terrain_counts"]}, ensure_ascii=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("content/maps/development_basin_128.source.json"))
    parser.add_argument("--output", type=Path, default=Path("content/maps/development_basin_128.tres"))
    parser.add_argument("--qa-dir", type=Path, default=Path("validation/development-map-128"))
    args = parser.parse_args()
    compile_map(args.source, args.output, args.qa_dir)
