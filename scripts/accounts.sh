#!/bin/bash
# SuperTask™ Account Manager
# Manages multiple Claude Code accounts via CLAUDE_CONFIG_DIR isolation.
# Each account gets its own config directory with symlinked settings.

ACCOUNTS_DIR="$HOME/.claude/plugins/autoloop/accounts"
ACCOUNTS_FILE="$ACCOUNTS_DIR/accounts.json"
CONFIG_BASE="$HOME/.claude-supertask"
DEFAULT_CONFIG="$HOME/.claude"

mkdir -p "$ACCOUNTS_DIR"

# ─── HELPERS ───

_get_claude_bin() {
    # Find claude binary
    if command -v claude &>/dev/null; then
        echo "claude"
    elif [ -x "$HOME/.local/bin/claude" ]; then
        echo "$HOME/.local/bin/claude"
    else
        echo ""
    fi
}

_check_auth() {
    # Check if a config dir has valid credentials. Returns JSON with email + plan.
    local config_dir="$1"
    local claude_bin
    claude_bin=$(_get_claude_bin)
    [ -z "$claude_bin" ] && return 1

    CLAUDECODE= CLAUDE_CONFIG_DIR="$config_dir" "$claude_bin" auth status --json 2>/dev/null
}

_is_logged_in() {
    # Returns 0 if logged in, 1 if not
    local config_dir="$1"
    local status
    status=$(_check_auth "$config_dir")
    echo "$status" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('loggedIn') else 1)" 2>/dev/null
}

_get_email() {
    local config_dir="$1"
    local status
    status=$(_check_auth "$config_dir")
    echo "$status" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('email','unknown'))" 2>/dev/null
}

_get_plan() {
    local config_dir="$1"
    local status
    status=$(_check_auth "$config_dir")
    echo "$status" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('subscriptionType','unknown'))" 2>/dev/null
}

# ─── ACCOUNT STORAGE ───

_init_accounts_file() {
    if [ ! -f "$ACCOUNTS_FILE" ]; then
        echo '[]' > "$ACCOUNTS_FILE"
    fi
}

_read_accounts() {
    _init_accounts_file
    cat "$ACCOUNTS_FILE"
}

_save_accounts() {
    local json="$1"
    echo "$json" > "$ACCOUNTS_FILE"
}

_add_account_to_file() {
    local slot="$1"
    local email="$2"
    local plan="$3"
    local config_dir="$4"
    local label="$5"

    _init_accounts_file
    python3 -c "
import json, sys
accounts = json.load(open('$ACCOUNTS_FILE'))
# Remove existing entry for this slot
accounts = [a for a in accounts if a.get('slot') != $slot]
accounts.append({
    'slot': $slot,
    'email': '$email',
    'plan': '$plan',
    'config_dir': '$config_dir',
    'label': '$label'
})
accounts.sort(key=lambda a: a['slot'])
json.dump(accounts, open('$ACCOUNTS_FILE', 'w'), indent=2)
"
}

_remove_account_from_file() {
    local slot="$1"
    python3 -c "
import json
accounts = json.load(open('$ACCOUNTS_FILE'))
accounts = [a for a in accounts if a.get('slot') != $slot]
json.dump(accounts, open('$ACCOUNTS_FILE', 'w'), indent=2)
"
}

# ─── CORE OPERATIONS ───

add_account() {
    # Find next available slot (1-10)
    local slot="$1"
    if [ -z "$slot" ]; then
        slot=$(python3 -c "
import json
accounts = json.load(open('$ACCOUNTS_FILE')) if __import__('os').path.exists('$ACCOUNTS_FILE') else []
used = {a['slot'] for a in accounts}
for i in range(1, 11):
    if i not in used:
        print(i)
        break
")
    fi

    local config_dir="${CONFIG_BASE}-${slot}"

    # Create config directory
    mkdir -p "$config_dir"

    # Symlink shared settings
    ln -sf "$DEFAULT_CONFIG/settings.json" "$config_dir/settings.json" 2>/dev/null
    ln -sf "$DEFAULT_CONFIG/settings.local.json" "$config_dir/settings.local.json" 2>/dev/null

    # Run claude auth login in a visible terminal
    local claude_bin
    claude_bin=$(_get_claude_bin)
    if [ -z "$claude_bin" ]; then
        echo "ERROR: claude binary not found"
        return 1
    fi

    # Launch login in a terminal window and wait for it
    gnome-terminal --title="SuperTask™ — Login Account $slot" \
        --geometry=80x24 \
        -- bash -c "
echo '═══════════════════════════════════════════'
echo '  SuperTask™ — Account $slot Login'
echo '═══════════════════════════════════════════'
echo ''
echo 'Your browser will open. Sign in with the'
echo 'account you want to use for Account $slot.'
echo ''
CLAUDECODE= CLAUDE_CONFIG_DIR='$config_dir' '$claude_bin' auth login
echo ''
echo '─────────────────────────────────────────'
if CLAUDECODE= CLAUDE_CONFIG_DIR='$config_dir' '$claude_bin' auth status --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get(\"loggedIn\") else 1)' 2>/dev/null; then
    EMAIL=\$(CLAUDECODE= CLAUDE_CONFIG_DIR='$config_dir' '$claude_bin' auth status --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(\"email\",\"unknown\"))' 2>/dev/null)
    echo \"Login successful: \$EMAIL\"
    echo 'LOGIN_OK' > /tmp/supertask-login-$slot.status
else
    echo 'Login failed or cancelled.'
    echo 'LOGIN_FAIL' > /tmp/supertask-login-$slot.status
fi
echo ''
echo 'This window will close in 3 seconds...'
sleep 3
" &
    local TERM_PID=$!

    # Return the slot number for the caller to wait on
    echo "$slot"
}

verify_account() {
    local slot="$1"
    local config_dir="${CONFIG_BASE}-${slot}"

    # Special case: slot 0 or "default" = default ~/.claude
    if [ "$slot" = "0" ] || [ "$slot" = "default" ]; then
        config_dir="$DEFAULT_CONFIG"
    fi

    if ! _is_logged_in "$config_dir"; then
        return 1
    fi

    local email plan
    email=$(_get_email "$config_dir")
    plan=$(_get_plan "$config_dir")

    echo "$email|$plan|$config_dir"
    return 0
}

list_accounts() {
    # Returns accounts as pipe-separated lines: slot|email|plan|config_dir|label|logged_in
    _init_accounts_file

    # Always include the default account as slot 0
    local default_email default_plan default_logged_in="false"
    if _is_logged_in "$DEFAULT_CONFIG"; then
        default_email=$(_get_email "$DEFAULT_CONFIG")
        default_plan=$(_get_plan "$DEFAULT_CONFIG")
        default_logged_in="true"
    else
        default_email="(not logged in)"
        default_plan=""
    fi
    echo "0|$default_email|$default_plan|$DEFAULT_CONFIG|Default|$default_logged_in"

    # List configured accounts
    python3 -c "
import json, os, subprocess, sys

accounts_file = '$ACCOUNTS_FILE'
if not os.path.exists(accounts_file):
    sys.exit(0)

accounts = json.load(open(accounts_file))
for a in sorted(accounts, key=lambda x: x['slot']):
    slot = a['slot']
    config_dir = a['config_dir']
    label = a.get('label', f'Account {slot}')
    email = a.get('email', 'unknown')
    plan = a.get('plan', 'unknown')

    # Check if still logged in
    logged_in = 'unknown'
    try:
        result = subprocess.run(
            ['claude', 'auth', 'status', '--json'],
            capture_output=True, text=True, timeout=10,
            env={**os.environ, 'CLAUDECODE': '', 'CLAUDE_CONFIG_DIR': config_dir}
        )
        data = json.loads(result.stdout)
        if data.get('loggedIn'):
            logged_in = 'true'
            email = data.get('email', email)
            plan = data.get('subscriptionType', plan)
        else:
            logged_in = 'false'
    except:
        pass

    print(f'{slot}|{email}|{plan}|{config_dir}|{label}|{logged_in}')
" 2>/dev/null
}

get_config_dir_for_slot() {
    local slot="$1"
    if [ "$slot" = "0" ] || [ "$slot" = "default" ]; then
        echo "$DEFAULT_CONFIG"
        return 0
    fi
    echo "${CONFIG_BASE}-${slot}"
}

# Build zenity combo values string from configured accounts
# Format: "email1 (plan)|email2 (plan)|+ Add Account..."
build_account_combo() {
    local combo_values=""
    local accounts_info

    accounts_info=$(list_accounts 2>/dev/null)

    while IFS='|' read -r slot email plan config_dir label logged_in; do
        [ -z "$slot" ] && continue
        if [ "$logged_in" = "true" ]; then
            local display="$email ($plan)"
            if [ -n "$combo_values" ]; then
                combo_values="${combo_values}|${display}"
            else
                combo_values="$display"
            fi
        fi
    done <<< "$accounts_info"

    # Always add the "Add Account" option at the end
    if [ -n "$combo_values" ]; then
        combo_values="${combo_values}|+ Add Account..."
    else
        combo_values="+ Add Account..."
    fi

    echo "$combo_values"
}

# Look up config dir from a display string like "alex@purge.com (max)"
resolve_account_selection() {
    local selection="$1"
    local email_part="${selection%% (*}"  # Strip " (plan)" suffix

    local accounts_info
    accounts_info=$(list_accounts 2>/dev/null)

    while IFS='|' read -r slot email plan config_dir label logged_in; do
        if [ "$email" = "$email_part" ]; then
            echo "$config_dir"
            return 0
        fi
    done <<< "$accounts_info"

    echo ""
    return 1
}

# Get display label for a config dir (for monitor)
get_account_label() {
    local target_dir="$1"
    local accounts_info
    accounts_info=$(list_accounts 2>/dev/null)

    while IFS='|' read -r slot email plan config_dir label logged_in; do
        if [ "$config_dir" = "$target_dir" ]; then
            echo "$email ($plan)"
            return 0
        fi
    done <<< "$accounts_info"

    echo "Unknown account"
    return 1
}

# ─── CLI INTERFACE ───

case "${1:-}" in
    add)
        add_account "${2:-}"
        ;;
    verify)
        verify_account "${2:-0}"
        ;;
    list)
        list_accounts
        ;;
    combo)
        build_account_combo
        ;;
    resolve)
        resolve_account_selection "$2"
        ;;
    label)
        get_account_label "$2"
        ;;
    config-dir)
        get_config_dir_for_slot "${2:-0}"
        ;;
    *)
        echo "Usage: accounts.sh {add|verify|list|combo|resolve|label|config-dir} [args]"
        ;;
esac
