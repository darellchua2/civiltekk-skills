# resolve_python / check_user_scripts_path (#673): functional-probe resolution
# (an MS Store-style python3 stub must be rejected), probe order, the py -3
# launcher form, and the per-OS scripts-dir PATH warning.
# Fake interpreters live in a PATH-sandboxed dir that SHADOWS the real ones
# (sandbox prepended, real PATH kept — uname/tr etc. still resolve).

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SANDBOX="$(mktemp -d)"
    FAKE_USER_BASE="$(mktemp -d)"
}

teardown() {
    rm -rf "$SANDBOX" "$FAKE_USER_BASE"
}

# $1=name $2=probe-exit-code $3=launcher arg ("", or "-3" for py)
fake_one() {
    cat > "$SANDBOX/$1" <<EOF
#!/usr/bin/env bash
if [ -n "$3" ] && [ "\$1" = "$3" ]; then shift; fi
if [ "\$1" = "-c" ]; then exit $2; fi
if [ "\$1" = "-m" ] && [ "\$2" = "site" ]; then echo "$FAKE_USER_BASE"; exit 0; fi
exit 1
EOF
    chmod +x "$SANDBOX/$1"
}

# All three fakes; per-candidate probe exit codes control the resolution.
fake_pythons() { # $1=python3 rc $2=python rc $3=py rc
    fake_one python3 "$1" ""
    fake_one python "$2" ""
    fake_one py "$3" "-3"
}

snip() {
    bash -c "cd '$REPO' && source deploy/setup.sh >/dev/null 2>&1; trap - ERR; PATH='$SANDBOX':\$PATH; export PATH; $1"
}

# ── resolve_python ───────────────────────────────────────────────────────────

@test "resolve: working python wins over a broken python3 stub" {
    fake_pythons 1 0 1
    run snip 'resolve_python; echo "bin=$PYTHON_BIN"'
    [ "$status" -eq 0 ]
    [ "$output" = "bin=python" ]
}

@test "resolve: working python3 is preferred first" {
    fake_pythons 0 0 0
    run snip 'resolve_python; echo "bin=$PYTHON_BIN"'
    [ "$status" -eq 0 ]
    [ "$output" = "bin=python3" ]
}

@test "resolve: py launcher keeps its -3 arg" {
    fake_pythons 1 1 0
    run snip 'resolve_python; echo "bin=$PYTHON_BIN"'
    [ "$status" -eq 0 ]
    [ "$output" = "bin=py -3" ]
}

@test "resolve: broken python3 stub is skipped, not fatal" {
    fake_pythons 1 0 1
    run snip 'resolve_python >/dev/null; echo "bin=$PYTHON_BIN"'
    [ "$status" -eq 0 ]
    [ "$output" = "bin=python" ]
}

@test "resolve: nothing works -> empty PYTHON_BIN + per-OS hint" {
    fake_pythons 1 1 1
    run snip 'resolve_python; rc=$?; echo "rc=$rc bin=$PYTHON_BIN"'
    [[ "$output" == *"No working Python found"* ]]
    [[ "$output" == *"rc=1 bin="* ]]
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*|Windows*) [[ "$output" == *"Microsoft Store alias stub"* ]] ;;
        *) [[ "$output" != *"Microsoft Store"* ]] ;;
    esac
}

@test "resolve: PYTHON_BIN actually executes (pip-style -m call shape)" {
    fake_pythons 1 0 1
    run snip 'resolve_python >/dev/null; $PYTHON_BIN -c "import sys"; echo "exec-ok"'
    [ "$status" -eq 0 ]
    [ "$output" = "exec-ok" ]
}

# ── check_user_scripts_path ──────────────────────────────────────────────────

@test "scripts-path: warns with the exact dir when it is off PATH" {
    fake_pythons 1 0 1
    # Hermetic HOME: the unix branch tests $HOME/.local/bin, and GitHub
    # runners pre-add ~/.local/bin to PATH — a fresh fake HOME keeps the
    # expected dir off PATH on every host.
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*|Windows*) EXPECT="$FAKE_USER_BASE/Scripts" ;;
        *) EXPECT="$FAKE_USER_BASE/.local/bin" ;;
    esac
    run snip "HOME='$FAKE_USER_BASE'; export HOME; resolve_python >/dev/null 2>&1; check_user_scripts_path"
    [ "$status" -eq 1 ]
    [[ "$output" == *"$EXPECT is not on your PATH"* ]]
}

@test "scripts-path: silent (rc 0) when the dir is on PATH" {
    fake_pythons 1 0 1
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*|Windows*) ADD="$FAKE_USER_BASE/Scripts" ;;
        *) ADD="$FAKE_USER_BASE/.local/bin" ;;
    esac
    run snip "HOME='$FAKE_USER_BASE'; export HOME; resolve_python >/dev/null 2>&1; PATH=\"\$PATH:$ADD\"; check_user_scripts_path"
    [ "$status" -eq 0 ]
}

@test "scripts-path: never mutates PATH (warn-only, no setx/export writes)" {
    run bash -c "sed -n '/^check_user_scripts_path() {/,/^}/p' '$REPO/deploy/setup.sh'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"setx"* ]]
    [[ "$output" != *"export PATH"* ]]
}
