#!/bin/bash
# Generic suite/scenario dispatcher.

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SUITES_DIR="$ROOT_DIR/suites"
DOCKER_BIN=${DOCKER_BIN:-docker}
SHARDS=${SHARDS:-3}

usage() {
    cat <<'EOF'
Uso:
  make scenarios [<language>[/<library>]]
  make install <language>/<library>
  make install-all
  make test <language>/<library>[/<scenario>]
  make test-all [<language>[/<library>]]
  make lab <language>/<library>
EOF
}

suite_path() {
    local language=$1
    local library=$2
    printf '%s/%s/%s' "$SUITES_DIR" "$language" "$library"
}

service_name() {
    local language=$1
    local library=$2
    printf 'redis-lab-%s-%s' "$language" "$library"
}

split_target() {
    local target=${1:-}
    TARGET_LANGUAGE=
    TARGET_LIBRARY=
    TARGET_SCENARIO=

    IFS='/' read -r TARGET_LANGUAGE TARGET_LIBRARY TARGET_SCENARIO _ <<< "$target"
}

require_language() {
    local language=$1
    if [ -z "$language" ] || [ ! -d "$SUITES_DIR/$language" ]; then
        echo "Lenguaje no encontrado: ${language:-<vacio>}"
        echo ""
        list_languages
        exit 1
    fi
}

require_suite() {
    local language=$1
    local library=$2
    require_language "$language"

    if [ -z "$library" ] || [ ! -d "$(suite_path "$language" "$library")" ]; then
        echo "Libreria no encontrada: ${language}/${library:-<vacia>}"
        echo ""
        list_libraries "$language"
        exit 1
    fi
}

list_languages() {
    echo "Lenguajes disponibles:"
    if [ ! -d "$SUITES_DIR" ]; then
        echo "  (ninguno)"
        return
    fi

    find "$SUITES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '  %f\n' | sort
}

list_libraries() {
    local language=$1
    require_language "$language"

    echo "Librerias para ${language}:"
    find "$SUITES_DIR/$language" -mindepth 1 -maxdepth 1 -type d -printf '  %f\n' | sort
}

scenario_files() {
    local suite=$1
    find "$suite/scenarios" -maxdepth 1 -type f \
        \( -name '[0-9][0-9]-*.php' -o -name '[0-9][0-9]-*.mjs' -o -name '[0-9][0-9]-*.js' -o -name '[0-9][0-9]-*.sh' \) \
        -printf '%f\n' | sort -V
}

list_scenarios() {
    local language=$1
    local library=$2
    local suite

    require_suite "$language" "$library"
    suite=$(suite_path "$language" "$library")

    echo "Escenarios para ${language}/${library}:"
    scenario_files "$suite" | sed 's/^/  /'
}

list_all() {
    if [ ! -d "$SUITES_DIR" ]; then
        echo "No hay suites."
        return
    fi

    while IFS= read -r suite; do
        local rel
        rel=${suite#"$SUITES_DIR/"}
        echo "$rel"
        scenario_files "$suite" | sed 's/^/  /'
    done < <(find "$SUITES_DIR" -mindepth 2 -maxdepth 2 -type d | sort)
}

resolve_scenario() {
    local suite=$1
    local scenario=$2
    local found=()

    if [ -z "$scenario" ]; then
        echo "Falta escenario." >&2
        list_scenarios "$TARGET_LANGUAGE" "$TARGET_LIBRARY" >&2
        exit 1
    fi

    if [ -f "$suite/scenarios/$scenario" ]; then
        printf '%s/scenarios/%s' "$suite" "$scenario"
        return
    fi

    while IFS= read -r file; do
        found+=("$file")
    done < <(find "$suite/scenarios" -maxdepth 1 -type f \
        \( -name "${scenario}.*" -o -name "${scenario}-*" -o -name "${scenario}" \) | sort)

    if [ "${#found[@]}" -eq 0 ]; then
        echo "Escenario no encontrado: ${TARGET_LANGUAGE}/${TARGET_LIBRARY}/${scenario}" >&2
        echo "" >&2
        list_scenarios "$TARGET_LANGUAGE" "$TARGET_LIBRARY" >&2
        exit 1
    fi

    if [ "${#found[@]}" -gt 1 ]; then
        echo "Escenario ambiguo: $scenario" >&2
        printf '  %s\n' "${found[@]#$suite/scenarios/}" >&2
        exit 1
    fi

    printf '%s' "${found[0]}"
}

install_suite() {
    local language=$1
    local library=$2
    local suite service

    require_suite "$language" "$library"
    suite=$(suite_path "$language" "$library")
    service=$(service_name "$language" "$library")

    if [ -x "$suite/bin/install" ]; then
        "$DOCKER_BIN" exec "$service" bin/install
    elif [ -f "$suite/composer.json" ]; then
        "$DOCKER_BIN" exec "$service" composer install --no-interaction
    elif [ -f "$suite/package-lock.json" ]; then
        "$DOCKER_BIN" exec "$service" npm ci --no-audit --no-fund
    elif [ -f "$suite/package.json" ]; then
        "$DOCKER_BIN" exec "$service" npm install --no-audit --no-fund
    else
        echo "No hay instalador conocido para ${language}/${library}."
    fi
}

run_scenario() {
    local language=$1
    local library=$2
    local file=$3
    local suite service rel ext

    require_suite "$language" "$library"
    suite=$(suite_path "$language" "$library")
    service=$(service_name "$language" "$library")
    rel=${file#"$suite/"}
    ext=${file##*.}

    if [ -x "$suite/bin/run-scenario" ]; then
        "$DOCKER_BIN" exec -e SHARDS="$SHARDS" "$service" bin/run-scenario "$rel"
        return
    fi

    case "$ext" in
        php)
            "$DOCKER_BIN" exec -e SHARDS="$SHARDS" "$service" php "$rel"
            ;;
        mjs|js)
            "$DOCKER_BIN" exec -e SHARDS="$SHARDS" "$service" node "$rel"
            ;;
        sh)
            "$DOCKER_BIN" exec -e SHARDS="$SHARDS" "$service" sh "$rel"
            ;;
        *)
            echo "Extension no soportada para escenario: $rel"
            exit 1
            ;;
    esac
}

test_suite() {
    local language=$1
    local library=$2
    local scenario=${3:-}
    local suite file

    require_suite "$language" "$library"
    suite=$(suite_path "$language" "$library")

    if [ -n "$scenario" ]; then
        file=$(resolve_scenario "$suite" "$scenario")
        install_suite "$language" "$library"
        run_scenario "$language" "$library" "$file"
        return
    fi

    install_suite "$language" "$library"

    while IFS= read -r scenario_file; do
        echo ""
        echo ">>> ${language}/${library}/${scenario_file%.*}"
        run_scenario "$language" "$library" "$suite/scenarios/$scenario_file"
    done < <(scenario_files "$suite")
}

test_suites_in_language() {
    local scope_language=$1

    while IFS= read -r suite; do
        local rel language library
        rel=${suite#"$SUITES_DIR/"}
        language=${rel%%/*}
        library=${rel#*/}
        test_suite "$language" "$library"
    done < <(find "$SUITES_DIR/$scope_language" -mindepth 1 -maxdepth 1 -type d | sort)
}

test_all() {
    if [ -n "${TARGET_SCENARIO:-}" ]; then
        echo "test-all acepta como maximo <language>/<library>."
        echo "Para un escenario puntual usa make test <language>/<library>/<scenario>."
        exit 2
    fi

    if [ -z "${TARGET_LANGUAGE:-}" ]; then
        while IFS= read -r language_dir; do
            test_suites_in_language "${language_dir##*/}"
        done < <(find "$SUITES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
        return
    fi

    require_language "$TARGET_LANGUAGE"

    if [ -z "${TARGET_LIBRARY:-}" ]; then
        test_suites_in_language "$TARGET_LANGUAGE"
        return
    fi

    test_suite "$TARGET_LANGUAGE" "$TARGET_LIBRARY"
}

shell_suite() {
    local language=$1
    local library=$2
    local service

    require_suite "$language" "$library"
    service=$(service_name "$language" "$library")

    "$DOCKER_BIN" exec -e SHARDS="$SHARDS" -it "$service" sh -lc 'if command -v bash >/dev/null 2>&1; then exec bash; else exec sh; fi'
}

command=${1:-help}
target=${2:-}
split_target "$target"

case "$command" in
    help)
        usage
        ;;
    scenarios)
        if [ -z "$target" ]; then
            list_all
        elif [ -n "${TARGET_LIBRARY:-}" ]; then
            list_scenarios "$TARGET_LANGUAGE" "$TARGET_LIBRARY"
        else
            list_libraries "$TARGET_LANGUAGE"
        fi
        ;;
    install)
        install_suite "$TARGET_LANGUAGE" "$TARGET_LIBRARY"
        ;;
    install-all)
        while IFS= read -r suite; do
            rel=${suite#"$SUITES_DIR/"}
            install_suite "${rel%%/*}" "${rel#*/}"
        done < <(find "$SUITES_DIR" -mindepth 2 -maxdepth 2 -type d | sort)
        ;;
    test)
        test_suite "$TARGET_LANGUAGE" "$TARGET_LIBRARY" "${TARGET_SCENARIO:-}"
        ;;
    test-all)
        test_all
        ;;
    shell)
        shell_suite "$TARGET_LANGUAGE" "$TARGET_LIBRARY"
        ;;
    *)
        usage
        exit 1
        ;;
esac
