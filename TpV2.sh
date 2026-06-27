#!/data/data/com.termux/files/usr/bin/bash

RAW_URL="https://raw.githubusercontent.com/Kolandone/v2raycollector/refs/heads/main/proxy.txt"

TOP_COUNT=10
MAX_JOBS=12
TCP_TIMEOUT=3
PING_TIMEOUT=2
SHOW_PING_INFO="no"   

WORKDIR="$PREFIX/tmp/mtproto_tcp_$$"

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RED="\033[1;31m"
MAGENTA="\033[1;35m"
BLUE="\033[1;34m"
RESET="\033[0m"

print_green()   { echo -e "${GREEN}$1${RESET}"; }
print_yellow()  { echo -e "${YELLOW}$1${RESET}"; }
print_cyan()    { echo -e "${CYAN}$1${RESET}"; }
print_red()     { echo -e "${RED}$1${RESET}"; }
print_magenta() { echo -e "${MAGENTA}$1${RESET}"; }
print_blue()    { echo -e "${BLUE}$1${RESET}"; }

cleanup() {
    rm -rf "$WORKDIR" 2>/dev/null
}
trap cleanup EXIT

banner() {
    clear
    echo -e "${MAGENTA}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║                  MTProto Proxy Finder v2        ║"
    echo "║                    TELEGRAM : KOLANDJS1         ║"
    echo "║                     GITHUB : KOLANDONE          ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

check_dependencies() {
    local update_done=false

    install_missing() {
        local cmd="$1"
        local pkg="$2"
        
        if ! command -v "$cmd" >/dev/null 2>&1; then
            if [ "$update_done" = false ]; then
                print_yellow "🔄 Updating Termux package lists..."
                pkg update -y -o Dpkg::Options::="--force-confold" >/dev/null 2>&1
                update_done=true
            fi
            print_cyan "📥 Installing $pkg..."
            pkg install "$pkg" -y -o Dpkg::Options::="--force-confold" >/dev/null 2>&1
        fi
    }

    install_missing "curl" "curl"
    install_missing "awk" "gawk"
    install_missing "sed" "sed"
    install_missing "grep" "grep"
    install_missing "timeout" "coreutils"
    install_missing "cut" "coreutils"
    install_missing "sort" "coreutils"
    install_missing "date" "coreutils"

    if [[ "$SHOW_PING_INFO" == "yes" ]]; then
        install_missing "ping" "iputils"
    fi

    if ! command -v termux-open-url >/dev/null 2>&1; then
        if [ "$update_done" = false ]; then
            pkg update -y -o Dpkg::Options::="--force-confold" >/dev/null 2>&1
            update_done=true
        fi
        print_cyan "📥 Installing termux-api..."
        pkg install termux-api -y -o Dpkg::Options::="--force-confold" >/dev/null 2>&1
    fi
}

download_mtproto_proxies() {
    curl -sL "$RAW_URL"
}

url_decode() {
    local data="${1//+/ }"
    printf '%b' "${data//%/\\x}"
}

extract_proxy_data() {
    local line="$1"
    local server="" port="" secret=""

    line="$(echo "$line" | tr -d '\r')"
    [[ -z "$line" ]] && return

    if [[ "$line" =~ server=([^&]+) ]]; then
        server="$(url_decode "${BASH_REMATCH[1]}")"
    fi
    if [[ "$line" =~ port=([^&]+) ]]; then
        port="$(url_decode "${BASH_REMATCH[1]}")"
    fi
    if [[ "$line" =~ secret=([^&]+) ]]; then
        secret="$(url_decode "${BASH_REMATCH[1]}")"
    fi

    if [[ -n "$server" && -n "$port" && -n "$secret" ]]; then
        echo "$server|$port|$secret"
        return
    fi

    if [[ "$line" =~ ^([^:]+):([0-9]+):(.+)$ ]]; then
        server="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
        secret="${BASH_REMATCH[3]}"
        echo "$server|$port|$secret"
        return
    fi
}

make_tg_link() {
    echo "tg://proxy?server=${1}&port=${2}&secret=${3}"
}

make_https_link() {
    echo "https://t.me/proxy?server=${1}&port=${2}&secret=${3}"
}

get_ping_info() {
    local host="$1"
    local out
    out=$(ping -c 1 -W "$PING_TIMEOUT" "$host" 2>/dev/null | sed -nE 's/.*time=([0-9.]+).*/\1/p' | head -n1)
    [[ -n "$out" ]] && echo "$out" || echo "-"
}

tcp_latency_ms() {
    local host="$1"
    local port="$2"
    local total_diff=0
    local count=3
    local start end diff

    for ((i=1; i<=count; i++)); do
        start=$(date +%s%3N 2>/dev/null)
        if [[ -z "$start" || ! "$start" =~ ^[0-9]+$ ]]; then
            start=$(( $(date +%s) * 1000 ))
        fi

        if timeout "$TCP_TIMEOUT" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
            end=$(date +%s%3N 2>/dev/null)
            if [[ -z "$end" || ! "$end" =~ ^[0-9]+$ ]]; then
                end=$(( $(date +%s) * 1000 ))
            fi
            diff=$((end - start))
            [[ "$diff" -lt 0 ]] && diff=0
            exec 3<&- 2>/dev/null
            exec 3>&- 2>/dev/null
            
            total_diff=$((total_diff + diff))
            sleep 0.05 
        else
            echo "999999"
            return
        fi
    done

    echo $(( total_diff / count ))
}

wait_for_slot() {
    while true; do
        if [[ $(jobs -rp | wc -l) -lt "$MAX_JOBS" ]]; then
            break
        fi
        sleep 0.1
    done
}

check_one_proxy() {
    local proxy="$1"
    local parsed server port secret tcp_ms ping_ms tg_link https_link

    parsed=$(extract_proxy_data "$proxy")
    [[ -z "$parsed" ]] && return

    server=$(echo "$parsed" | cut -d'|' -f1)
    port=$(echo "$parsed" | cut -d'|' -f2)
    secret=$(echo "$parsed" | cut -d'|' -f3)

    [[ -z "$server" || -z "$port" || -z "$secret" ]] && return

    tcp_ms=$(tcp_latency_ms "$server" "$port")
    
    if [[ "$tcp_ms" == "999999" ]]; then
        print_red "BAD  $server:$port"
        return
    fi

    if [[ "$SHOW_PING_INFO" == "yes" ]]; then
        ping_ms=$(get_ping_info "$server")
    else
        ping_ms="-"
    fi

    tg_link=$(make_tg_link "$server" "$port" "$secret")
    https_link=$(make_https_link "$server" "$port" "$secret")

    echo "${tcp_ms}|${ping_ms}|${server}|${port}|${secret}|${tg_link}|${https_link}" >> "$WORKDIR/results.txt"
    print_green "OK   $server:$port   Avg TCP: ${tcp_ms}ms"
}

save_outputs() {
    local sorted_file="$1"
    awk -F'|' '{print $7}' "$sorted_file" > best_mtproto_https_links.txt
    awk -F'|' '{print $6}' "$sorted_file" > best_mtproto_tg_links.txt
    cp "$sorted_file" best_mtproto_full_results.txt
}

show_results() {
    local sorted_file="$1"
    local count=1

    echo
    print_cyan "╔════════════════════════════════════════════════════╗"
    print_cyan "║      Best MTProto Proxies (Sorted by Avg TCP)      ║"
    print_cyan "╚════════════════════════════════════════════════════╝"
    echo

    while IFS='|' read -r tcp_ms ping_ms server port secret tg_link https_link; do
        [[ -z "$server" ]] && continue

        print_green "[$count] Avg TCP Latency: ${tcp_ms} ms"
        if [[ "$SHOW_PING_INFO" == "yes" ]]; then
            echo -e "${BLUE}Ping   :${RESET} $ping_ms ms"
        fi
        echo -e "${YELLOW}Server :${RESET} $server"
        echo -e "${YELLOW}Port   :${RESET} $port"
        echo -e "${YELLOW}Secret :${RESET} $secret"
        echo -e "${CYAN}Link   :${RESET} $https_link"
        echo "----------------------------------------------------"
        ((count++))
    done < "$sorted_file"
}

interactive_open() {
    local sorted_file="$1"
    local lines total choice selected tg_link https_link

    mapfile -t lines < "$sorted_file"
    total="${#lines[@]}"
    [[ "$total" -eq 0 ]] && return

    echo
    print_blue "Options:"
    echo "  [number] Open selected proxy in Telegram"
    echo "  a        Open best proxy"
    echo "  q        Quit"
    echo
    read -rp "Your choice: " choice

    if [[ "$choice" == "q" || -z "$choice" ]]; then
        return
    fi

    if [[ "$choice" == "a" ]]; then
        selected="${lines[0]}"
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= total )); then
        selected="${lines[$((choice - 1))]}"
    else
        print_red "Invalid choice."
        return
    fi

    tg_link=$(echo "$selected" | awk -F'|' '{print $6}')
    https_link=$(echo "$selected" | awk -F'|' '{print $7}')

    echo
    print_green "Selected proxy link:"
    echo "$https_link"
    echo

    if command -v termux-open-url >/dev/null 2>&1; then
        print_yellow "Opening in Telegram..."
        termux-open-url "$tg_link" 2>/dev/null || termux-open-url "$https_link" 2>/dev/null
    else
        print_red "termux-open-url not found."
        print_yellow "You can copy and open the link above manually."
    fi
}

main() {
    mkdir -p "$WORKDIR"
    : > "$WORKDIR/results.txt"

    banner
    check_dependencies

    print_yellow "Downloading MTProto proxies..."
    local proxies
    proxies=$(download_mtproto_proxies)

    if [[ -z "$proxies" ]]; then
        print_red "Failed to download proxies or list is empty."
        exit 1
    fi

    local total_raw
    total_raw=$(echo "$proxies" | sed '/^\s*$/d' | wc -l)
    print_magenta "Total raw lines: $total_raw"
    print_yellow "Checking TCP latency in parallel (3x checks)..."
    echo

    while IFS= read -r proxy; do
        [[ -z "$proxy" ]] && continue
        wait_for_slot
        check_one_proxy "$proxy" &
    done <<< "$proxies"

    wait

    if [[ ! -s "$WORKDIR/results.txt" ]]; then
        echo
        print_red "No stable MTProto proxies found."
        exit 1
    fi

    sort -n -t'|' -k1,1 "$WORKDIR/results.txt" | head -n "$TOP_COUNT" > "$WORKDIR/sorted.txt"

    local working_count
    working_count=$(wc -l < "$WORKDIR/results.txt")

    echo
    print_magenta "Stable proxies found: $working_count"
    print_magenta "Top shown: $TOP_COUNT"

    save_outputs "$WORKDIR/sorted.txt"
    show_results "$WORKDIR/sorted.txt"

    echo
    print_blue "Saved files in current directory:"
    echo "  best_mtproto_https_links.txt"
    echo "  best_mtproto_tg_links.txt"
    echo "  best_mtproto_full_results.txt"

    interactive_open "$WORKDIR/sorted.txt"
}

main
