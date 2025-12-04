#!/bin/bash
# Framework Intelligence Sync Script
# Syncs framework intelligence from central repositories

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
NC='\033[0m' # No Color

# Configuration - Central repositories
REPOS=(
    "itsflippen-dev/framework-intelligence"
    "digital-1-group/framework-intelligence"
)
BRANCH="main"
INTELLIGENCE_PATH="intelligence/latest.json"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Framework Intelligence Sync${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to check if file needs update (older than 24 hours)
needs_update() {
    local local_file="$1"

    if [[ ! -f "$local_file" ]]; then
        echo -e "${YELLOW}No local intelligence file found${NC}"
        return 0
    fi

    # Get file modification time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local_modified=$(stat -f %m "$local_file" 2>/dev/null || echo "0")
    else
        local_modified=$(stat -c %Y "$local_file" 2>/dev/null || echo "0")
    fi

    local current_time=$(date +%s)
    local age_hours=$(( (current_time - local_modified) / 3600 ))

    echo -e "${CYAN}Intelligence file age: ${age_hours} hours${NC}"

    if [[ $age_hours -gt 24 ]]; then
        echo -e "${YELLOW}Intelligence file is older than 24 hours${NC}"
        return 0
    fi

    return 1
}

# Function to download intelligence file from a repo
download_from_repo() {
    local repo="$1"
    local output="$2"
    local temp_file=$(mktemp)

    local url="https://raw.githubusercontent.com/$repo/$BRANCH/$INTELLIGENCE_PATH"

    echo -e "${CYAN}Trying: $repo${NC}"

    if command -v curl &> /dev/null; then
        if curl -fsSL "$url" -o "$temp_file" 2>/dev/null; then
            # Validate JSON
            if command -v jq &> /dev/null; then
                if jq empty "$temp_file" 2>/dev/null; then
                    mv "$temp_file" "$output"
                    echo -e "${GREEN}Successfully downloaded from $repo${NC}"
                    return 0
                else
                    echo -e "${YELLOW}Invalid JSON from $repo${NC}"
                    rm -f "$temp_file"
                    return 1
                fi
            else
                # No jq, just check if file is not empty
                if [[ -s "$temp_file" ]]; then
                    mv "$temp_file" "$output"
                    echo -e "${GREEN}Downloaded from $repo (JSON not validated - jq not installed)${NC}"
                    return 0
                fi
            fi
        fi
    elif command -v wget &> /dev/null; then
        if wget -q "$url" -O "$temp_file" 2>/dev/null; then
            if [[ -s "$temp_file" ]]; then
                mv "$temp_file" "$output"
                echo -e "${GREEN}Downloaded from $repo${NC}"
                return 0
            fi
        fi
    fi

    rm -f "$temp_file"
    return 1
}

# Function to detect project frameworks
detect_frameworks() {
    local frameworks=()

    echo -e "${CYAN}Detecting project frameworks...${NC}"

    # Rust
    if [[ -f "$PROJECT_ROOT/Cargo.toml" ]]; then
        frameworks+=("rust")
        echo -e "  ${GREEN}Found: Rust${NC}"
    fi

    # JavaScript/TypeScript
    if [[ -f "$PROJECT_ROOT/package.json" ]]; then
        frameworks+=("javascript")
        echo -e "  ${GREEN}Found: JavaScript/TypeScript${NC}"

        # Check for specific frameworks
        if grep -q "\"next\"" "$PROJECT_ROOT/package.json" 2>/dev/null; then
            frameworks+=("nextjs")
            echo -e "  ${GREEN}Found: Next.js${NC}"
        fi
        if grep -q "\"react\"" "$PROJECT_ROOT/package.json" 2>/dev/null; then
            frameworks+=("react")
            echo -e "  ${GREEN}Found: React${NC}"
        fi
        if grep -q "\"vue\"" "$PROJECT_ROOT/package.json" 2>/dev/null; then
            frameworks+=("vue")
            echo -e "  ${GREEN}Found: Vue${NC}"
        fi
        if grep -q "\"svelte\"" "$PROJECT_ROOT/package.json" 2>/dev/null; then
            frameworks+=("svelte")
            echo -e "  ${GREEN}Found: Svelte${NC}"
        fi
        if grep -q "\"tailwindcss\"" "$PROJECT_ROOT/package.json" 2>/dev/null; then
            frameworks+=("tailwindcss")
            echo -e "  ${GREEN}Found: Tailwind CSS${NC}"
        fi
        if [[ -f "$PROJECT_ROOT/components.json" ]]; then
            frameworks+=("shadcn")
            echo -e "  ${GREEN}Found: shadcn/ui${NC}"
        fi
        if grep -q "\"prisma\"" "$PROJECT_ROOT/package.json" 2>/dev/null; then
            frameworks+=("prisma")
            echo -e "  ${GREEN}Found: Prisma${NC}"
        fi
    fi

    # Python
    if [[ -f "$PROJECT_ROOT/pyproject.toml" ]] || [[ -f "$PROJECT_ROOT/requirements.txt" ]]; then
        frameworks+=("python")
        echo -e "  ${GREEN}Found: Python${NC}"

        if grep -q "django" "$PROJECT_ROOT/requirements.txt" 2>/dev/null || grep -q "django" "$PROJECT_ROOT/pyproject.toml" 2>/dev/null; then
            frameworks+=("django")
            echo -e "  ${GREEN}Found: Django${NC}"
        fi
        if grep -q "fastapi" "$PROJECT_ROOT/requirements.txt" 2>/dev/null || grep -q "fastapi" "$PROJECT_ROOT/pyproject.toml" 2>/dev/null; then
            frameworks+=("fastapi")
            echo -e "  ${GREEN}Found: FastAPI${NC}"
        fi
    fi

    # Go
    if [[ -f "$PROJECT_ROOT/go.mod" ]]; then
        frameworks+=("go")
        echo -e "  ${GREEN}Found: Go${NC}"
    fi

    # Swift
    if [[ -f "$PROJECT_ROOT/Package.swift" ]]; then
        frameworks+=("swift")
        echo -e "  ${GREEN}Found: Swift${NC}"
    fi

    # Docker
    if [[ -f "$PROJECT_ROOT/Dockerfile" ]] || [[ -f "$PROJECT_ROOT/docker-compose.yml" ]] || [[ -f "$PROJECT_ROOT/compose.yaml" ]]; then
        frameworks+=("docker")
        echo -e "  ${GREEN}Found: Docker${NC}"
    fi

    # DevContainer
    if [[ -f "$PROJECT_ROOT/.devcontainer/devcontainer.json" ]]; then
        frameworks+=("devcontainer")
        echo -e "  ${GREEN}Found: DevContainer${NC}"
    fi

    if [[ ${#frameworks[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}No frameworks detected${NC}"
    fi

    echo "${frameworks[@]}"
}

# Function to show intelligence summary
show_summary() {
    if [[ ! -f "$INTELLIGENCE_FILE" ]]; then
        echo -e "${YELLOW}No intelligence file to summarize${NC}"
        return
    fi

    if command -v jq &> /dev/null; then
        echo ""
        echo -e "${CYAN}Intelligence Summary:${NC}"
        local version=$(jq -r '.version // "unknown"' "$INTELLIGENCE_FILE")
        local updated=$(jq -r '.lastUpdated // "unknown"' "$INTELLIGENCE_FILE")
        echo -e "  Version: ${GREEN}$version${NC}"
        echo -e "  Last Updated: ${GREEN}$updated${NC}"

        # Count frameworks
        local count=$(jq '[.intelligence | to_entries[] | .value | to_entries | length] | add' "$INTELLIGENCE_FILE" 2>/dev/null || echo "unknown")
        echo -e "  Frameworks: ${GREEN}$count${NC}"
    fi
}

# Function to push local intelligence to GitHub repos
push_to_repos() {
    local temp_dir=$(mktemp -d)

    echo -e "${CYAN}Pushing local intelligence to GitHub repositories...${NC}"

    for repo in "${REPOS[@]}"; do
        echo -e "${CYAN}Pushing to: $repo${NC}"

        local repo_dir="$temp_dir/$repo"

        # Clone repo
        if ! gh repo clone "$repo" "$repo_dir" 2>/dev/null; then
            echo -e "${YELLOW}Failed to clone $repo (may need gh auth)${NC}"
            continue
        fi

        # Create directory and copy file
        mkdir -p "$repo_dir/intelligence"
        cp "$INTELLIGENCE_FILE" "$repo_dir/intelligence/latest.json"

        # Commit and push
        cd "$repo_dir"
        git add intelligence/latest.json
        if git diff --cached --quiet; then
            echo -e "${GREEN}No changes to push for $repo${NC}"
        else
            git commit -m "Update framework intelligence to v$(jq -r '.version' intelligence/latest.json)

- $(jq '[.intelligence | to_entries[] | .value | to_entries | length] | add' intelligence/latest.json) frameworks
- $(jq '.intelligence | keys | length' intelligence/latest.json) categories

🤖 Generated with Framework Intelligence Sync"
            git push origin main
            echo -e "${GREEN}Successfully pushed to $repo${NC}"
        fi
        cd - > /dev/null
    done

    rm -rf "$temp_dir"
    echo -e "${GREEN}Push completed${NC}"
}

# Function to show diff with remote
show_diff() {
    echo -e "${CYAN}Comparing local vs remote intelligence...${NC}"

    local temp_file=$(mktemp)
    local repo="${REPOS[0]}"
    local url="https://raw.githubusercontent.com/$repo/$BRANCH/$INTELLIGENCE_PATH"

    if curl -fsSL "$url" -o "$temp_file" 2>/dev/null; then
        local local_ver=$(jq -r '.version' "$INTELLIGENCE_FILE")
        local remote_ver=$(jq -r '.version' "$temp_file")
        local local_count=$(jq '[.intelligence | to_entries[] | .value | to_entries | length] | add' "$INTELLIGENCE_FILE")
        local remote_count=$(jq '[.intelligence | to_entries[] | .value | to_entries | length] | add' "$temp_file")

        echo -e "  Local:  v${GREEN}$local_ver${NC} (${GREEN}$local_count${NC} frameworks)"
        echo -e "  Remote: v${YELLOW}$remote_ver${NC} (${YELLOW}$remote_count${NC} frameworks)"

        if [[ "$local_ver" != "$remote_ver" ]] || [[ "$local_count" != "$remote_count" ]]; then
            echo -e "${YELLOW}Local and remote differ - consider pushing${NC}"
        else
            echo -e "${GREEN}Local and remote are in sync${NC}"
        fi
    else
        echo -e "${YELLOW}Could not fetch remote for comparison${NC}"
    fi

    rm -f "$temp_file"
}

# Main execution
main() {
    local force_update=false
    local show_detect=false
    local push_mode=false
    local diff_mode=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force_update=true
                shift
                ;;
            -d|--detect)
                show_detect=true
                shift
                ;;
            -p|--push)
                push_mode=true
                shift
                ;;
            --diff)
                diff_mode=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  -f, --force    Force update regardless of file age"
                echo "  -d, --detect   Detect and show project frameworks"
                echo "  -p, --push     Push local intelligence to GitHub repos"
                echo "  --diff         Compare local vs remote versions"
                echo "  -h, --help     Show this help message"
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                exit 1
                ;;
        esac
    done

    # Detect frameworks if requested
    if [[ "$show_detect" == true ]]; then
        detect_frameworks
        echo ""
    fi

    # Push mode
    if [[ "$push_mode" == true ]]; then
        show_summary
        push_to_repos
        exit 0
    fi

    # Diff mode
    if [[ "$diff_mode" == true ]]; then
        show_diff
        exit 0
    fi

    # Check if update needed
    if [[ "$force_update" == true ]]; then
        echo -e "${YELLOW}Force update requested${NC}"
    elif ! needs_update "$INTELLIGENCE_FILE"; then
        echo -e "${GREEN}Intelligence file is up to date${NC}"
        show_summary
        echo ""
        echo -e "${GREEN}Sync completed successfully!${NC}"
        exit 0
    fi

    # Try to download from each repo
    echo ""
    echo -e "${CYAN}Attempting to sync from central repositories...${NC}"

    local success=false
    for repo in "${REPOS[@]}"; do
        if download_from_repo "$repo" "$INTELLIGENCE_FILE"; then
            success=true
            break
        fi
    done

    if [[ "$success" == false ]]; then
        echo ""
        echo -e "${YELLOW}Could not sync from remote repositories${NC}"

        if [[ -f "$INTELLIGENCE_FILE" ]]; then
            echo -e "${YELLOW}Using existing local intelligence file${NC}"
        else
            echo -e "${RED}No local intelligence file available${NC}"
            echo -e "${YELLOW}Please ensure at least one central repo is set up with intelligence data${NC}"
            exit 1
        fi
    fi

    show_summary

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Sync completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
}

main "$@"
