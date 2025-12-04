#!/bin/bash
# Framework Intelligence Query Tool
# Query framework information from the intelligence cache

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INTELLIGENCE_FILE="$PROJECT_ROOT/.framework-intelligence.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${NC}"
    echo "Install with: brew install jq"
    exit 1
fi

# Check for intelligence file
if [[ ! -f "$INTELLIGENCE_FILE" ]]; then
    echo -e "${RED}Error: Intelligence file not found at $INTELLIGENCE_FILE${NC}"
    echo "Run: ./scripts/sync-framework-intelligence.sh"
    exit 1
fi

show_help() {
    echo "Framework Intelligence Query Tool"
    echo ""
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  search <term>       Search for frameworks matching term"
    echo "  info <framework>    Show detailed info for a framework"
    echo "  category <name>     List all frameworks in a category"
    echo "  categories          List all categories"
    echo "  patterns <fw>       Show current patterns for a framework"
    echo "  deprecated <fw>     Show deprecated patterns for a framework"
    echo "  version <fw>        Show current version of a framework"
    echo "  stats               Show intelligence statistics"
    echo ""
    echo "Examples:"
    echo "  $0 search react"
    echo "  $0 info nextjs"
    echo "  $0 category frontend"
    echo "  $0 patterns tailwindcss"
}

search_frameworks() {
    local term="$1"
    echo -e "${CYAN}Searching for: ${GREEN}$term${NC}"
    echo ""

    jq -r --arg term "$term" '
        .intelligence | to_entries[] |
        .key as $category |
        .value | to_entries[] |
        select(.key | ascii_downcase | contains($term | ascii_downcase)) |
        "\(.key) (\($category)) - v\(.value.currentVersion // "unknown")"
    ' "$INTELLIGENCE_FILE" | while read line; do
        echo -e "  ${GREEN}$line${NC}"
    done
}

show_info() {
    local fw="$1"

    # Find the framework in any category
    local result=$(jq -r --arg fw "$fw" '
        .intelligence | to_entries[] |
        .key as $category |
        .value | to_entries[] |
        select(.key | ascii_downcase == ($fw | ascii_downcase)) |
        {
            name: .key,
            category: $category,
            data: .value
        }
    ' "$INTELLIGENCE_FILE")

    if [[ -z "$result" || "$result" == "null" ]]; then
        echo -e "${RED}Framework not found: $fw${NC}"
        exit 1
    fi

    local name=$(echo "$result" | jq -r '.name')
    local category=$(echo "$result" | jq -r '.category')
    local version=$(echo "$result" | jq -r '.data.currentVersion // "unknown"')
    local ecosystem=$(echo "$result" | jq -r '.data.ecosystem // "unknown"')
    local pm=$(echo "$result" | jq -r '.data.packageManager // "unknown"')

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  $name${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "  Category:        ${GREEN}$category${NC}"
    echo -e "  Current Version: ${GREEN}$version${NC}"
    echo -e "  Ecosystem:       ${GREEN}$ecosystem${NC}"
    echo -e "  Package Manager: ${GREEN}$pm${NC}"

    # Config files
    local configs=$(echo "$result" | jq -r '.data.configFiles // [] | join(", ")')
    if [[ -n "$configs" && "$configs" != "" ]]; then
        echo -e "  Config Files:    ${CYAN}$configs${NC}"
    fi

    # Current patterns count
    local pattern_count=$(echo "$result" | jq -r '.data.currentPatterns | length // 0')
    if [[ "$pattern_count" -gt 0 ]]; then
        echo ""
        echo -e "${CYAN}Current Patterns ($pattern_count):${NC}"
        echo "$result" | jq -r '.data.currentPatterns | to_entries[] | "  - \(.key): \(.value.description // .value.pattern)"'
    fi

    # Deprecated patterns count
    local dep_count=$(echo "$result" | jq -r '.data.deprecatedPatterns | length // 0')
    if [[ "$dep_count" -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Deprecated Patterns ($dep_count):${NC}"
        echo "$result" | jq -r '.data.deprecatedPatterns | to_entries[] | "  - \(.key): \(.value.reason // .value.pattern)"'
    fi
}

list_category() {
    local category="$1"

    local result=$(jq -r --arg cat "$category" '
        .intelligence[$cat] // empty
    ' "$INTELLIGENCE_FILE")

    if [[ -z "$result" || "$result" == "null" ]]; then
        echo -e "${RED}Category not found: $category${NC}"
        echo ""
        echo "Available categories:"
        jq -r '.intelligence | keys[]' "$INTELLIGENCE_FILE"
        exit 1
    fi

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Category: $category${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    jq -r --arg cat "$category" '
        .intelligence[$cat] | to_entries[] |
        "  \(.key): v\(.value.currentVersion // "unknown")"
    ' "$INTELLIGENCE_FILE" | sort
}

list_categories() {
    echo -e "${CYAN}Available Categories:${NC}"
    echo ""
    jq -r '.intelligence | to_entries[] | "  \(.key) (\(.value | length) frameworks)"' "$INTELLIGENCE_FILE" | sort
}

show_patterns() {
    local fw="$1"

    local result=$(jq -r --arg fw "$fw" '
        .intelligence | to_entries[] |
        .value | to_entries[] |
        select(.key | ascii_downcase == ($fw | ascii_downcase)) |
        .value.currentPatterns // {}
    ' "$INTELLIGENCE_FILE")

    if [[ -z "$result" || "$result" == "null" || "$result" == "{}" ]]; then
        echo -e "${YELLOW}No current patterns found for: $fw${NC}"
        exit 0
    fi

    echo -e "${CYAN}Current Patterns for $fw:${NC}"
    echo ""
    echo "$result" | jq -r 'to_entries[] | "[\(.key)]\n  Pattern: \(.value.pattern)\n  Description: \(.value.description // "N/A")\n"'
}

show_deprecated() {
    local fw="$1"

    local result=$(jq -r --arg fw "$fw" '
        .intelligence | to_entries[] |
        .value | to_entries[] |
        select(.key | ascii_downcase == ($fw | ascii_downcase)) |
        .value.deprecatedPatterns // {}
    ' "$INTELLIGENCE_FILE")

    if [[ -z "$result" || "$result" == "null" || "$result" == "{}" ]]; then
        echo -e "${GREEN}No deprecated patterns found for: $fw${NC}"
        exit 0
    fi

    echo -e "${YELLOW}Deprecated Patterns for $fw:${NC}"
    echo ""
    echo "$result" | jq -r 'to_entries[] | "[\(.key)] - \(.value.severity // "warning")\n  Pattern: \(.value.pattern)\n  Replacement: \(.value.replacement // "N/A")\n  Reason: \(.value.reason // "N/A")\n"'
}

show_version() {
    local fw="$1"

    local version=$(jq -r --arg fw "$fw" '
        .intelligence | to_entries[] |
        .value | to_entries[] |
        select(.key | ascii_downcase == ($fw | ascii_downcase)) |
        .value.currentVersion // "unknown"
    ' "$INTELLIGENCE_FILE")

    if [[ -z "$version" || "$version" == "unknown" ]]; then
        echo -e "${RED}Framework not found: $fw${NC}"
        exit 1
    fi

    echo "$version"
}

show_stats() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Framework Intelligence Statistics${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    local version=$(jq -r '.version' "$INTELLIGENCE_FILE")
    local updated=$(jq -r '.lastUpdated' "$INTELLIGENCE_FILE")
    local categories=$(jq -r '.intelligence | keys | length' "$INTELLIGENCE_FILE")
    local frameworks=$(jq -r '[.intelligence | to_entries[] | .value | to_entries | length] | add' "$INTELLIGENCE_FILE")

    echo -e "  Version:      ${GREEN}$version${NC}"
    echo -e "  Last Updated: ${GREEN}$updated${NC}"
    echo -e "  Categories:   ${GREEN}$categories${NC}"
    echo -e "  Frameworks:   ${GREEN}$frameworks${NC}"
    echo ""

    echo -e "${CYAN}Frameworks per Category:${NC}"
    jq -r '.intelligence | to_entries | sort_by(.value | length) | reverse[] | "  \(.key): \(.value | length)"' "$INTELLIGENCE_FILE"
}

# Main
case "${1:-}" in
    search)
        [[ -z "${2:-}" ]] && { echo -e "${RED}Usage: $0 search <term>${NC}"; exit 1; }
        search_frameworks "$2"
        ;;
    info)
        [[ -z "${2:-}" ]] && { echo -e "${RED}Usage: $0 info <framework>${NC}"; exit 1; }
        show_info "$2"
        ;;
    category)
        [[ -z "${2:-}" ]] && { echo -e "${RED}Usage: $0 category <name>${NC}"; exit 1; }
        list_category "$2"
        ;;
    categories)
        list_categories
        ;;
    patterns)
        [[ -z "${2:-}" ]] && { echo -e "${RED}Usage: $0 patterns <framework>${NC}"; exit 1; }
        show_patterns "$2"
        ;;
    deprecated)
        [[ -z "${2:-}" ]] && { echo -e "${RED}Usage: $0 deprecated <framework>${NC}"; exit 1; }
        show_deprecated "$2"
        ;;
    version)
        [[ -z "${2:-}" ]] && { echo -e "${RED}Usage: $0 version <framework>${NC}"; exit 1; }
        show_version "$2"
        ;;
    stats)
        show_stats
        ;;
    -h|--help|"")
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac
