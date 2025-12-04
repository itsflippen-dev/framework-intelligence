#!/usr/bin/env python3
"""
Comprehensive DevContainer and Configuration Validation Script
Validates configurations against framework intelligence patterns.
"""

import json
import os
import sys
import re
from pathlib import Path
from typing import Dict, List, Tuple, Any, Optional

# Colors for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

# Required fields for DevContainer
REQUIRED_DEVCONTAINER_FIELDS = ["name", "image"]


def load_framework_intelligence(project_root: Path) -> Dict:
    """Load framework intelligence from .framework-intelligence.json"""
    intelligence_file = project_root / ".framework-intelligence.json"

    if not intelligence_file.exists():
        print(f"{Colors.YELLOW}Warning: Framework intelligence file not found at {intelligence_file}{Colors.NC}")
        print(f"{Colors.YELLOW}Run ./scripts/sync-framework-intelligence.sh to download{Colors.NC}")
        return {}

    try:
        with open(intelligence_file, 'r', encoding='utf-8') as f:
            intelligence = json.load(f)
            print(f"{Colors.GREEN}Loaded framework intelligence v{intelligence.get('version', 'unknown')}{Colors.NC}")
            return intelligence
    except json.JSONDecodeError as e:
        print(f"{Colors.RED}Error: Invalid JSON in framework intelligence file: {e}{Colors.NC}")
        return {}
    except Exception as e:
        print(f"{Colors.RED}Error loading framework intelligence: {e}{Colors.NC}")
        return {}


def validate_json_file(file_path: Path) -> Tuple[bool, str, Optional[Dict]]:
    """Validate JSON syntax and return parsed content."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = json.load(f)
        return True, "", content
    except json.JSONDecodeError as e:
        return False, f"Invalid JSON: {e}", None
    except Exception as e:
        return False, f"Error reading file: {e}", None


def check_deprecated_patterns(content: str, file_path: Path, intelligence: Dict) -> List[str]:
    """Check content for deprecated patterns from framework intelligence."""
    errors = []

    if not intelligence or "intelligence" not in intelligence:
        return errors

    # Flatten all deprecated patterns from all categories
    all_deprecated = []

    def extract_deprecated(data: Dict, category_path: str = ""):
        if isinstance(data, dict):
            if "deprecatedPatterns" in data:
                for pattern_name, pattern_info in data["deprecatedPatterns"].items():
                    if isinstance(pattern_info, dict):
                        all_deprecated.append({
                            "name": pattern_name,
                            "category": category_path,
                            **pattern_info
                        })
            for key, value in data.items():
                if key != "deprecatedPatterns":
                    new_path = f"{category_path}.{key}" if category_path else key
                    extract_deprecated(value, new_path)

    extract_deprecated(intelligence.get("intelligence", {}))

    # Check content against deprecated patterns
    for deprecated in all_deprecated:
        pattern = deprecated.get("pattern", "")
        if not pattern:
            continue

        # Convert pattern to a searchable form
        search_patterns = [pattern]

        # Add common variations
        if "checkOnSave\": true" in pattern:
            search_patterns.append('"checkOnSave": true')
            search_patterns.append("'checkOnSave': true")

        for search in search_patterns:
            if search in content:
                severity = deprecated.get("severity", "warning").upper()
                replacement = deprecated.get("replacement", "See documentation")
                reason = deprecated.get("reason", "")

                error_msg = f"[{severity}] Deprecated pattern found: {deprecated['name']}"
                if reason:
                    error_msg += f"\n    Reason: {reason}"
                error_msg += f"\n    Found: {search[:80]}..."
                error_msg += f"\n    Replace with: {replacement}"

                errors.append(error_msg)
                break

    return errors


def validate_devcontainer_structure(config: Dict, file_path: Path, intelligence: Dict) -> List[str]:
    """Validate DevContainer structure and required fields."""
    errors = []

    # Check required fields
    for field in REQUIRED_DEVCONTAINER_FIELDS:
        if field not in config:
            errors.append(f"Missing required field: '{field}'")

    # Validate 'name' field
    if "name" in config:
        if not isinstance(config["name"], str) or not config["name"].strip():
            errors.append("Field 'name' must be a non-empty string")

    # Validate 'image' field
    if "image" in config:
        image = config["image"]
        if not isinstance(image, str) or not image.strip():
            errors.append("Field 'image' must be a non-empty string")
        elif ":" not in image and "/" not in image:
            errors.append(f"Field 'image' appears to be invalid Docker image format: {image}")

    # Validate 'customizations' if present
    if "customizations" in config:
        customizations = config["customizations"]
        if not isinstance(customizations, dict):
            errors.append("Field 'customizations' must be a dictionary")
        else:
            # Validate VS Code settings
            if "vscode" in customizations:
                vscode_errors = validate_vscode_settings(
                    customizations["vscode"],
                    intelligence
                )
                errors.extend(vscode_errors)

    return errors


def validate_vscode_settings(vscode_config: Dict, intelligence: Dict) -> List[str]:
    """Validate VS Code settings against framework intelligence."""
    errors = []

    if not isinstance(vscode_config, dict):
        return ["vscode customization must be a dictionary"]

    settings = vscode_config.get("settings", {})
    if not isinstance(settings, dict):
        return ["vscode.settings must be a dictionary"]

    # Check rust-analyzer settings
    if "rust-analyzer.checkOnSave" in settings:
        check_on_save = settings["rust-analyzer.checkOnSave"]

        # Boolean is deprecated
        if isinstance(check_on_save, bool):
            errors.append(
                f"[ERROR] DEPRECATED: rust-analyzer.checkOnSave as boolean\n"
                f"    Found: \"rust-analyzer.checkOnSave\": {str(check_on_save).lower()}\n"
                f"    Replace with: \"rust-analyzer.checkOnSave\": {{ \"enable\": true, \"command\": \"clippy\" }}\n"
                f"    Reason: Boolean syntax deprecated since 2023-06-01"
            )

    # Check for deprecated ESLint config references
    extensions = vscode_config.get("extensions", [])
    if isinstance(extensions, list):
        # Check if using eslint but might have old config
        if "dbaeumer.vscode-eslint" in extensions:
            # This is fine, just a note that flat config should be used
            pass

    return errors


def validate_tailwind_config(config_path: Path, intelligence: Dict) -> List[str]:
    """Validate Tailwind CSS configuration."""
    errors = []

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Check for Tailwind 3 patterns in Tailwind 4 world
        if "module.exports" in content and "theme:" in content:
            errors.append(
                f"[WARNING] Tailwind 3 configuration detected\n"
                f"    Consider migrating to Tailwind 4 CSS-first config\n"
                f"    Use @theme {{ }} directive in CSS instead of JS config"
            )

        if "purge:" in content:
            errors.append(
                f"[ERROR] Deprecated 'purge' option found\n"
                f"    Replace with: content: ['./src/**/*.{{js,jsx,ts,tsx}}']"
            )

    except Exception as e:
        errors.append(f"Error reading Tailwind config: {e}")

    return errors


def validate_eslint_config(config_path: Path, intelligence: Dict) -> List[str]:
    """Validate ESLint configuration."""
    errors = []

    filename = config_path.name

    # Check for legacy config files
    legacy_files = ['.eslintrc', '.eslintrc.js', '.eslintrc.json', '.eslintrc.yaml', '.eslintrc.yml']
    if filename in legacy_files:
        errors.append(
            f"[WARNING] Legacy ESLint config format detected: {filename}\n"
            f"    ESLint 9+ uses flat config format\n"
            f"    Migrate to: eslint.config.js or eslint.config.mjs"
        )

    return errors


def find_config_files(root_dir: Path) -> Dict[str, List[Path]]:
    """Find all configuration files to validate."""
    configs = {
        "devcontainer": [],
        "tailwind": [],
        "eslint": [],
        "package": [],
        "tsconfig": []
    }

    # DevContainer files
    patterns = [
        root_dir.rglob(".devcontainer/devcontainer.json"),
        root_dir.rglob("**/devcontainer.json"),
        root_dir.rglob("tools/devcontainer/*.json"),
    ]
    for pattern in patterns:
        for file in pattern:
            if "node_modules" not in str(file):
                configs["devcontainer"].append(file)

    # Tailwind config
    for pattern in ["tailwind.config.js", "tailwind.config.ts", "tailwind.config.mjs"]:
        for file in root_dir.rglob(pattern):
            if "node_modules" not in str(file):
                configs["tailwind"].append(file)

    # ESLint config
    eslint_patterns = [".eslintrc*", "eslint.config.*"]
    for pattern in eslint_patterns:
        for file in root_dir.glob(pattern):
            configs["eslint"].append(file)

    # Remove duplicates
    for key in configs:
        configs[key] = sorted(set(configs[key]))

    return configs


def main():
    """Main validation function."""
    script_dir = Path(__file__).parent
    project_root = script_dir.parent

    print(f"\n{Colors.BLUE}{'=' * 60}{Colors.NC}")
    print(f"{Colors.BLUE}  Framework Intelligence Configuration Validator{Colors.NC}")
    print(f"{Colors.BLUE}{'=' * 60}{Colors.NC}\n")

    # Load framework intelligence
    intelligence = load_framework_intelligence(project_root)

    print(f"\n{Colors.CYAN}Scanning: {project_root}{Colors.NC}\n")

    # Find all config files
    config_files = find_config_files(project_root)

    total_errors = 0
    total_warnings = 0
    total_validated = 0

    # Validate DevContainers
    if config_files["devcontainer"]:
        print(f"\n{Colors.CYAN}DevContainer Files ({len(config_files['devcontainer'])}){Colors.NC}")
        print("-" * 40)

        for devcontainer_file in config_files["devcontainer"]:
            try:
                rel_path = devcontainer_file.relative_to(project_root)
            except ValueError:
                rel_path = devcontainer_file

            print(f"\n{Colors.BLUE}{rel_path}{Colors.NC}")

            # Validate JSON syntax
            is_valid, json_error, config = validate_json_file(devcontainer_file)
            if not is_valid:
                print(f"  {Colors.RED}Invalid JSON: {json_error}{Colors.NC}")
                total_errors += 1
                continue

            # Validate structure
            structure_errors = validate_devcontainer_structure(config, devcontainer_file, intelligence)

            # Check for deprecated patterns in raw content
            with open(devcontainer_file, 'r', encoding='utf-8') as f:
                raw_content = f.read()
            deprecated_errors = check_deprecated_patterns(raw_content, devcontainer_file, intelligence)

            all_errors = structure_errors + deprecated_errors

            if all_errors:
                for error in all_errors:
                    if "[ERROR]" in error:
                        print(f"  {Colors.RED}{error}{Colors.NC}")
                        total_errors += 1
                    elif "[WARNING]" in error:
                        print(f"  {Colors.YELLOW}{error}{Colors.NC}")
                        total_warnings += 1
                    else:
                        print(f"  {Colors.RED}{error}{Colors.NC}")
                        total_errors += 1
            else:
                print(f"  {Colors.GREEN}Valid{Colors.NC}")
                total_validated += 1

    # Validate Tailwind configs
    if config_files["tailwind"]:
        print(f"\n{Colors.CYAN}Tailwind CSS Configs ({len(config_files['tailwind'])}){Colors.NC}")
        print("-" * 40)

        for tailwind_file in config_files["tailwind"]:
            try:
                rel_path = tailwind_file.relative_to(project_root)
            except ValueError:
                rel_path = tailwind_file

            print(f"\n{Colors.BLUE}{rel_path}{Colors.NC}")

            errors = validate_tailwind_config(tailwind_file, intelligence)
            if errors:
                for error in errors:
                    if "[ERROR]" in error:
                        print(f"  {Colors.RED}{error}{Colors.NC}")
                        total_errors += 1
                    else:
                        print(f"  {Colors.YELLOW}{error}{Colors.NC}")
                        total_warnings += 1
            else:
                print(f"  {Colors.GREEN}Valid{Colors.NC}")
                total_validated += 1

    # Validate ESLint configs
    if config_files["eslint"]:
        print(f"\n{Colors.CYAN}ESLint Configs ({len(config_files['eslint'])}){Colors.NC}")
        print("-" * 40)

        for eslint_file in config_files["eslint"]:
            print(f"\n{Colors.BLUE}{eslint_file.name}{Colors.NC}")

            errors = validate_eslint_config(eslint_file, intelligence)
            if errors:
                for error in errors:
                    if "[ERROR]" in error:
                        print(f"  {Colors.RED}{error}{Colors.NC}")
                        total_errors += 1
                    else:
                        print(f"  {Colors.YELLOW}{error}{Colors.NC}")
                        total_warnings += 1
            else:
                print(f"  {Colors.GREEN}Valid{Colors.NC}")
                total_validated += 1

    # Summary
    print(f"\n{Colors.BLUE}{'=' * 60}{Colors.NC}")
    print(f"{Colors.BLUE}  Validation Summary{Colors.NC}")
    print(f"{Colors.BLUE}{'=' * 60}{Colors.NC}")
    print(f"  {Colors.GREEN}Valid:{Colors.NC} {total_validated}")
    print(f"  {Colors.YELLOW}Warnings:{Colors.NC} {total_warnings}")
    print(f"  {Colors.RED}Errors:{Colors.NC} {total_errors}")
    print()

    if total_errors == 0:
        print(f"{Colors.GREEN}All configurations are valid!{Colors.NC}\n")
        sys.exit(0)
    else:
        print(f"{Colors.RED}{total_errors} error(s) found. Please fix before committing.{Colors.NC}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
