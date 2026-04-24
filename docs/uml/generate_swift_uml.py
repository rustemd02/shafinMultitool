#!/usr/bin/env python3
"""Generate a lightweight UML class diagram from Swift source files.

The script intentionally uses a pragmatic parser based on line scanning.
It handles the common declaration shapes used in the SceneGeneratorModule:
top-level and nested `class` / `struct` / `enum` / `protocol` types,
stored/computed properties, enum cases, nesting, protocol conformance,
and associations inferred from property types.

Output formats:
  - Mermaid class diagram (`--format mermaid`, default)
  - PlantUML (`--format plantuml`)
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict, deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


TYPE_RE = re.compile(
    r"^\s*"
    r"(?:(?:public|private|fileprivate|internal|open|final|indirect|actor|static|"
    r"class|lazy|override|required|convenience|mutating|nonmutating|isolated|"
    r"nonisolated)\s+)*"
    r"(class|struct|enum|protocol)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)"
    r"(?:\s*<[^>{}]+>)?"
    r"(?:\s*:\s*([^{]+))?"
    r"\s*\{"
)

PROPERTY_RE = re.compile(
    r"^\s*"
    r"(?:(?:@[\w.]+(?:\([^)]*\))?\s*)*)"
    r"(?:(?:public|private|fileprivate|internal|open|final|static|class|lazy|weak|"
    r"unowned|override|required|convenience|mutating|nonmutating|isolated|"
    r"nonisolated|private\(set\)|public\(set\)|internal\(set\)|fileprivate\(set\))\s+)*"
    r"(?:let|var)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)"
    r"\s*:\s*"
    r"(.+?)"
    r"(?=\s*(?:=|\{|\Z))"
)

ENUM_CASE_RE = re.compile(r"^\s*case\s+(.+)$")
IDENTIFIER_RE = re.compile(r"[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*")
COMMENT_RE = re.compile(r"//.*$")


@dataclass
class PropertyDecl:
    name: str
    type_name: str


@dataclass
class TypeDecl:
    kind: str
    name: str
    full_name: str
    alias: str
    file_path: Path
    line: int
    parent_full_name: str | None = None
    inherits: list[str] = field(default_factory=list)
    properties: list[PropertyDecl] = field(default_factory=list)
    enum_cases: list[str] = field(default_factory=list)

    @property
    def display_name(self) -> str:
        return self.full_name


@dataclass(frozen=True)
class Edge:
    source: str
    target: str
    kind: str
    label: str = ""
    source_mult: str = ""
    target_mult: str = ""


@dataclass
class ParseContext:
    full_name: str
    body_depth: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate Mermaid or PlantUML class diagrams from Swift files."
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="Swift files and/or directories to scan.",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Where to write the generated diagram source.",
    )
    parser.add_argument(
        "--format",
        choices=("mermaid", "plantuml"),
        default="mermaid",
        help="Diagram source format.",
    )
    parser.add_argument(
        "--focus",
        nargs="+",
        default=[],
        help="Type names to center the graph around (short or full names).",
    )
    parser.add_argument(
        "--neighbor-depth",
        type=int,
        default=None,
        help="Keep only nodes within N undirected relation hops from --focus types.",
    )
    parser.add_argument(
        "--hide-properties",
        action="store_true",
        help="Show only types and relations, without members.",
    )
    return parser.parse_args()


def strip_comments(line: str) -> str:
    return COMMENT_RE.sub("", line)


def collect_swift_files(inputs: Iterable[str]) -> list[Path]:
    files: list[Path] = []
    for raw in inputs:
        path = Path(raw)
        if path.is_dir():
            files.extend(sorted(path.rglob("*.swift")))
        elif path.is_file() and path.suffix == ".swift":
            files.append(path)
        else:
            raise FileNotFoundError(f"Swift path not found: {path}")
    unique_files: dict[Path, None] = {}
    for file_path in files:
        unique_files[file_path.resolve()] = None
    return sorted(unique_files.keys())


def split_inheritance(raw: str | None) -> list[str]:
    if not raw:
        return []
    return [part.strip() for part in raw.split(",") if part.strip()]


def clean_type_expr(raw: str) -> str:
    cleaned = raw.strip()
    cleaned = cleaned.replace("some ", "")
    cleaned = cleaned.replace("any ", "")
    return cleaned


def parse_enum_cases(raw: str) -> list[str]:
    match = ENUM_CASE_RE.match(raw)
    if not match:
        return []
    payload = match.group(1).strip()
    cases: list[str] = []
    for part in payload.split(","):
        case_name = part.strip()
        if not case_name:
            continue
        case_name = case_name.split("=", 1)[0].strip()
        case_name = case_name.split("(", 1)[0].strip()
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", case_name):
            cases.append(case_name)
    return cases


def parse_swift_file(path: Path) -> list[TypeDecl]:
    types: list[TypeDecl] = []
    stack: list[ParseContext] = []
    brace_depth = 0

    lines = path.read_text(encoding="utf-8").splitlines()
    for line_number, line in enumerate(lines, start=1):
        code = strip_comments(line)
        current_body_depth = stack[-1].body_depth if stack else 0
        at_type_scope = (not stack and brace_depth == 0) or (
            stack and brace_depth == current_body_depth
        )

        type_match = TYPE_RE.match(code) if at_type_scope else None
        if type_match:
            kind, name, inherits_raw = type_match.groups()
            parent_full_name = stack[-1].full_name if stack else None
            full_name = f"{parent_full_name}.{name}" if parent_full_name else name
            alias = full_name.replace(".", "_")
            decl = TypeDecl(
                kind=kind,
                name=name,
                full_name=full_name,
                alias=alias,
                file_path=path,
                line=line_number,
                parent_full_name=parent_full_name,
                inherits=split_inheritance(inherits_raw),
            )
            types.append(decl)
            stack.append(ParseContext(full_name=full_name, body_depth=brace_depth + 1))

        elif stack and brace_depth == stack[-1].body_depth:
            current_type = next(t for t in reversed(types) if t.full_name == stack[-1].full_name)
            property_match = PROPERTY_RE.match(code)
            if property_match:
                prop_name, type_name = property_match.groups()
                current_type.properties.append(
                    PropertyDecl(name=prop_name, type_name=clean_type_expr(type_name))
                )
            elif current_type.kind == "enum":
                current_type.enum_cases.extend(parse_enum_cases(code))

        brace_depth += code.count("{") - code.count("}")
        while stack and brace_depth < stack[-1].body_depth:
            stack.pop()

    return types


def build_lookup(types: list[TypeDecl]) -> tuple[dict[str, TypeDecl], dict[str, list[str]]]:
    by_full_name = {type_decl.full_name: type_decl for type_decl in types}
    by_short_name: dict[str, list[str]] = defaultdict(list)
    for type_decl in types:
        by_short_name[type_decl.name].append(type_decl.full_name)
    return by_full_name, by_short_name


def resolve_type_name(
    candidate: str,
    owner: TypeDecl,
    by_full_name: dict[str, TypeDecl],
    by_short_name: dict[str, list[str]],
) -> str | None:
    candidate = candidate.strip()
    if not candidate:
        return None
    if candidate in by_full_name:
        return candidate

    owner_parts = owner.full_name.split(".")
    for depth in range(len(owner_parts), 0, -1):
        contextual_name = ".".join(owner_parts[:depth] + [candidate])
        if contextual_name in by_full_name:
            return contextual_name

    short_matches = by_short_name.get(candidate, [])
    if len(short_matches) == 1:
        return short_matches[0]
    return None


def extract_referenced_types(
    type_expr: str,
    owner: TypeDecl,
    by_full_name: dict[str, TypeDecl],
    by_short_name: dict[str, list[str]],
) -> list[str]:
    candidates = IDENTIFIER_RE.findall(type_expr)
    resolved: list[str] = []
    seen: set[str] = set()
    for candidate in candidates:
        target = resolve_type_name(candidate, owner, by_full_name, by_short_name)
        if target and target != owner.full_name and target not in seen:
            resolved.append(target)
            seen.add(target)
    return resolved


def multiplicity_for(type_expr: str) -> str:
    expr = type_expr.replace(" ", "")
    if expr.endswith("?") or expr.startswith("Optional<"):
        return "0..1"
    if (
        expr.startswith("[")
        or "Array<" in expr
        or "Set<" in expr
        or "Dictionary<" in expr
        or ":" in expr and expr.startswith("[")
    ):
        return "*"
    return "1"


def build_edges(types: list[TypeDecl]) -> list[Edge]:
    by_full_name, by_short_name = build_lookup(types)
    edges: list[Edge] = []
    seen: set[tuple[str, str, str, str, str, str]] = set()

    def add(edge: Edge) -> None:
        key = (
            edge.source,
            edge.target,
            edge.kind,
            edge.label,
            edge.source_mult,
            edge.target_mult,
        )
        if key not in seen:
            seen.add(key)
            edges.append(edge)

    for type_decl in types:
        if type_decl.parent_full_name:
            add(
                Edge(
                    source=type_decl.parent_full_name,
                    target=type_decl.full_name,
                    kind="nesting",
                    label="contains",
                    source_mult="1",
                    target_mult="*",
                )
            )

        for inherited in type_decl.inherits:
            inherited_name = inherited.split("<", 1)[0].strip()
            target = resolve_type_name(inherited_name, type_decl, by_full_name, by_short_name)
            if not target:
                continue
            relation_kind = "realization" if by_full_name[target].kind == "protocol" else "inheritance"
            add(Edge(source=type_decl.full_name, target=target, kind=relation_kind))

        for prop in type_decl.properties:
            targets = extract_referenced_types(prop.type_name, type_decl, by_full_name, by_short_name)
            for target in targets:
                add(
                    Edge(
                        source=type_decl.full_name,
                        target=target,
                        kind="association",
                        label=prop.name,
                        source_mult="1",
                        target_mult=multiplicity_for(prop.type_name),
                    )
                )

    return edges


def resolve_focus_names(
    focus: list[str],
    by_full_name: dict[str, TypeDecl],
    by_short_name: dict[str, list[str]],
) -> set[str]:
    resolved: set[str] = set()
    missing: list[str] = []

    for raw_name in focus:
        if raw_name in by_full_name:
            resolved.add(raw_name)
            continue
        short_matches = by_short_name.get(raw_name, [])
        if len(short_matches) == 1:
            resolved.add(short_matches[0])
            continue
        missing.append(raw_name)

    if missing:
        missing_list = ", ".join(missing)
        raise ValueError(f"Could not uniquely resolve focus types: {missing_list}")
    return resolved


def filter_graph(
    types: list[TypeDecl],
    edges: list[Edge],
    focus_names: list[str],
    neighbor_depth: int | None,
) -> tuple[list[TypeDecl], list[Edge]]:
    if not focus_names:
        return types, edges

    by_full_name, by_short_name = build_lookup(types)
    focus = resolve_focus_names(focus_names, by_full_name, by_short_name)
    if neighbor_depth is None:
        selected_names = focus
    else:
        adjacency: dict[str, set[str]] = defaultdict(set)
        for edge in edges:
            adjacency[edge.source].add(edge.target)
            adjacency[edge.target].add(edge.source)

        selected_names = set(focus)
        queue = deque((name, 0) for name in focus)
        while queue:
            node, depth = queue.popleft()
            if depth >= neighbor_depth:
                continue
            for neighbor in adjacency.get(node, set()):
                if neighbor in selected_names:
                    continue
                selected_names.add(neighbor)
                queue.append((neighbor, depth + 1))

    filtered_types = [type_decl for type_decl in types if type_decl.full_name in selected_names]
    filtered_names = {type_decl.full_name for type_decl in filtered_types}
    filtered_edges = [
        edge
        for edge in edges
        if edge.source in filtered_names and edge.target in filtered_names
    ]
    return filtered_types, filtered_edges


def relation_line_mermaid(edge: Edge, aliases: dict[str, str]) -> str:
    source = aliases[edge.source]
    target = aliases[edge.target]
    label = f" : {edge.label}" if edge.label else ""
    mult_prefix = f'"{edge.source_mult}" ' if edge.source_mult else ""
    mult_suffix = f' "{edge.target_mult}"' if edge.target_mult else ""

    if edge.kind == "nesting":
        connector = "*--"
    elif edge.kind == "association":
        connector = "-->"
    elif edge.kind == "inheritance":
        connector = "--|>"
        mult_prefix = ""
        mult_suffix = ""
    elif edge.kind == "realization":
        connector = "..|>"
        mult_prefix = ""
        mult_suffix = ""
    else:
        connector = "-->"

    return f"    {source} {mult_prefix}{connector}{mult_suffix} {target}{label}"


def render_mermaid(types: list[TypeDecl], edges: list[Edge], hide_properties: bool) -> str:
    lines = ["classDiagram"]

    aliases = {type_decl.full_name: type_decl.alias for type_decl in types}
    for type_decl in sorted(types, key=lambda item: (str(item.file_path), item.line, item.full_name)):
        lines.append(f'    class {type_decl.alias}["{type_decl.display_name}"]')
        lines.append(f"    class {type_decl.alias} {{")
        lines.append(f"        <<{type_decl.kind}>>")
        if not hide_properties:
            for prop in type_decl.properties:
                lines.append(f"        +{prop.name}: {prop.type_name}")
            if type_decl.kind == "enum":
                for case_name in type_decl.enum_cases:
                    lines.append(f"        +{case_name}")
        lines.append("    }")

    for edge in sorted(edges, key=lambda item: (item.source, item.target, item.kind, item.label)):
        lines.append(relation_line_mermaid(edge, aliases))

    return "\n".join(lines) + "\n"


def escape_plantuml(text: str) -> str:
    return text.replace('"', '\\"')


def relation_line_plantuml(edge: Edge, aliases: dict[str, str]) -> str:
    source = aliases[edge.source]
    target = aliases[edge.target]
    label = f" : {edge.label}" if edge.label else ""
    source_mult = f'"{edge.source_mult}" ' if edge.source_mult else ""
    target_mult = f' "{edge.target_mult}"' if edge.target_mult else ""

    if edge.kind == "nesting":
        connector = "*--"
    elif edge.kind == "association":
        connector = "-->"
    elif edge.kind == "inheritance":
        connector = "--|>"
        source_mult = ""
        target_mult = ""
    elif edge.kind == "realization":
        connector = "..|>"
        source_mult = ""
        target_mult = ""
    else:
        connector = "-->"
    return f"  {source} {source_mult}{connector}{target_mult} {target}{label}"


def render_plantuml(types: list[TypeDecl], edges: list[Edge], hide_properties: bool) -> str:
    lines = [
        "@startuml",
        "hide empty members",
        "skinparam classAttributeIconSize 0",
    ]

    aliases = {type_decl.full_name: type_decl.alias for type_decl in types}
    keyword_for_kind = {
        "class": "class",
        "struct": "class",
        "enum": "enum",
        "protocol": "interface",
    }

    for type_decl in sorted(types, key=lambda item: (str(item.file_path), item.line, item.full_name)):
        keyword = keyword_for_kind[type_decl.kind]
        lines.append(
            f'  {keyword} "{escape_plantuml(type_decl.display_name)}" as {type_decl.alias} {{'
        )
        if type_decl.kind == "struct":
            lines.append("    <<struct>>")
        if not hide_properties:
            for prop in type_decl.properties:
                lines.append(f"    +{prop.name}: {prop.type_name}")
            if type_decl.kind == "enum":
                for case_name in type_decl.enum_cases:
                    lines.append(f"    {case_name}")
        lines.append("  }")

    for edge in sorted(edges, key=lambda item: (item.source, item.target, item.kind, item.label)):
        lines.append(relation_line_plantuml(edge, aliases))

    lines.append("@enduml")
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()

    try:
        files = collect_swift_files(args.inputs)
    except FileNotFoundError as error:
        print(error, file=sys.stderr)
        return 1

    if not files:
        print("No Swift files matched the provided inputs.", file=sys.stderr)
        return 1

    types: list[TypeDecl] = []
    for file_path in files:
        types.extend(parse_swift_file(file_path))

    if not types:
        print("No Swift types were found in the provided inputs.", file=sys.stderr)
        return 1

    edges = build_edges(types)

    try:
        filtered_types, filtered_edges = filter_graph(
            types=types,
            edges=edges,
            focus_names=args.focus,
            neighbor_depth=args.neighbor_depth,
        )
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1

    if args.format == "plantuml":
        diagram = render_plantuml(filtered_types, filtered_edges, args.hide_properties)
    else:
        diagram = render_mermaid(filtered_types, filtered_edges, args.hide_properties)

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(diagram, encoding="utf-8")
    else:
        print(diagram, end="")

    print(
        f"Generated {args.format} diagram for {len(filtered_types)} types "
        f"from {len(files)} Swift files.",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
