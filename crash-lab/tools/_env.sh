# Sourced by the other tools. Resolves the project root and the Godot binary.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
# JAVA_TOOL_OPTIONS (proxy/CI images) makes the JVM print a banner on stderr; harmless.
run_godot() { "$GODOT" --headless --path "$PROJECT_DIR" "$@"; }
