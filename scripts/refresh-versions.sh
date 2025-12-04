#!/usr/bin/env bash
# Framework Intelligence Version Refresh Script
# Fetches latest stable versions from package registries
# Requires: bash 4.0+, curl, jq (optional)

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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Framework Version Refresh${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check for required tools
check_requirements() {
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}Error: curl is required${NC}"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Warning: jq not installed. Install with: brew install jq${NC}"
        echo -e "${YELLOW}Some features will be limited without jq${NC}"
        HAS_JQ=false
    else
        HAS_JQ=true
    fi
}

# Fetch latest npm package version
get_npm_version() {
    local package="$1"
    local version=""

    if [[ "$HAS_JQ" == true ]]; then
        version=$(curl -s "https://registry.npmjs.org/$package/latest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)
    else
        version=$(curl -s "https://registry.npmjs.org/$package/latest" 2>/dev/null | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi

    if [[ -n "$version" && "$version" != "null" ]]; then
        echo "$version"
    fi
}

# Fetch latest PyPI package version
get_pypi_version() {
    local package="$1"
    local version=""

    if [[ "$HAS_JQ" == true ]]; then
        version=$(curl -s "https://pypi.org/pypi/$package/json" 2>/dev/null | jq -r '.info.version // empty' 2>/dev/null)
    fi

    if [[ -n "$version" && "$version" != "null" ]]; then
        echo "$version"
    fi
}

# Fetch latest crates.io package version
get_crates_version() {
    local crate="$1"
    local version=""

    if [[ "$HAS_JQ" == true ]]; then
        version=$(curl -s "https://crates.io/api/v1/crates/$crate" 2>/dev/null | jq -r '.crate.max_stable_version // .crate.max_version // empty' 2>/dev/null)
    fi

    if [[ -n "$version" && "$version" != "null" ]]; then
        echo "$version"
    fi
}

# Refresh npm packages
refresh_npm() {
    echo -e "${CYAN}Checking npm packages...${NC}"

    # Core packages to check
    local packages=(
        "react"
        "next"
        "vue"
        "svelte"
        "tailwindcss"
        "framer-motion"
        "zustand"
        "jotai"
        "express"
        "fastify"
        "hono"
        "prisma"
        "drizzle-orm"
        "vite"
        "esbuild"
        "eslint"
        "prettier"
        "vitest"
        "playwright"
        "openai"
        "ai"
    )

    for package in "${packages[@]}"; do
        local version=$(get_npm_version "$package")
        if [[ -n "$version" ]]; then
            echo -e "  ${GREEN}$package${NC}: $version"
        else
            echo -e "  ${YELLOW}$package${NC}: (unable to fetch)"
        fi
    done
}

# Refresh PyPI packages
refresh_pypi() {
    echo -e "\n${CYAN}Checking PyPI packages...${NC}"

    local packages=(
        "django"
        "fastapi"
        "flask"
        "sqlalchemy"
        "pytest"
        "langchain"
    )

    for package in "${packages[@]}"; do
        local version=$(get_pypi_version "$package")
        if [[ -n "$version" ]]; then
            echo -e "  ${GREEN}$package${NC}: $version"
        else
            echo -e "  ${YELLOW}$package${NC}: (unable to fetch)"
        fi
    done
}

# Refresh crates.io packages
refresh_crates() {
    echo -e "\n${CYAN}Checking crates.io packages...${NC}"

    local crates=(
        "actix-web"
        "axum"
        "diesel"
        "tokio"
        "serde"
    )

    for crate in "${crates[@]}"; do
        local version=$(get_crates_version "$crate")
        if [[ -n "$version" ]]; then
            echo -e "  ${GREEN}$crate${NC}: $version"
        else
            echo -e "  ${YELLOW}$crate${NC}: (unable to fetch)"
        fi
    done
}

# Update the intelligence file timestamp
update_timestamp() {
    if [[ -f "$INTELLIGENCE_FILE" ]] && [[ "$HAS_JQ" == true ]]; then
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local temp_file=$(mktemp)

        if jq --arg ts "$timestamp" '.validation.lastChecked = $ts' "$INTELLIGENCE_FILE" > "$temp_file" 2>/dev/null; then
            mv "$temp_file" "$INTELLIGENCE_FILE"
            echo -e "\n${GREEN}Updated intelligence file timestamp${NC}"
        else
            rm -f "$temp_file"
        fi
    fi
}

# Main execution
main() {
    local update_file=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--update)
                update_file=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  -u, --update   Update the intelligence file timestamp"
                echo "  -h, --help     Show this help message"
                echo ""
                echo "This script fetches latest versions from:"
                echo "  - npm registry"
                echo "  - PyPI"
                echo "  - crates.io"
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                exit 1
                ;;
        esac
    done

    check_requirements

    refresh_npm
    refresh_pypi
    refresh_crates

    if [[ "$update_file" == true ]]; then
        update_timestamp
    fi

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Version refresh completed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${CYAN}Note: Manual review recommended before updating${NC}"
    echo -e "${CYAN}version numbers in .framework-intelligence.json${NC}"
}

main "$@"
